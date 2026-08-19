class_name BattleProfiler
extends RefCounted
# Opt-in section timing for a live match.
#
# WHY NOT GODOT'S OWN PROFILER. It needs an editor debugger session attached, and
# the runs that matter here are long headless ones. It also reports per-function
# self time, which answers "what is expensive on average" - but a HITCH is a
# single frame, and an average is precisely the statistic that hides it. This
# records per-frame section totals so a spike can be attributed to a section
# rather than to a function that merely happens to be hot.
#
# COST WHEN DISABLED is one static bool read per call site. `enabled` is checked
# before Time.get_ticks_usec() is called, so an un-profiled build does not pay
# for the clock reads - which matters, because the measurement below is only
# meaningful if the instrumentation is not itself a significant part of it. That
# assumption is not taken on trust: profile_battle_run.gd runs the same match
# twice, once with this on and once off, and reports the difference.
#
# NOT THREAD SAFE and does not need to be: every instrumented section runs on the
# main thread inside _physics_process.

static var enabled: bool = false

# section -> accumulated usec for the CURRENT frame.
static var _frame: Dictionary = {}
# section -> {sum, max, count} across the whole run.
static var _totals: Dictionary = {}
# Per-frame [total_ms, dominant_section, dominant_ms], kept for every frame so
# percentiles are exact rather than sampled.
static var _frames: Array = []
static var _frame_start: int = 0

# The last frame's totals, written by end_frame() and read by BattleLogger
# to mirror per-section timings and hitch events to the structured log.
# Snapshot rather than live `_frame` so the read happens AFTER end_frame
# has cleared the dict.
static var last_frame_ms: float = 0.0
static var last_dominant: String = ""
static var last_dominant_ms: float = 0.0
static var last_sections: Dictionary = {}

# How much of a frame a section must account for before it is named as the cause.
const DOMINANCE_SHARE := 0.5

# SKIRMISH_PERF_TROUBLESHOOTING.md §10.5. The FIRST end_frame() after a reset()
# measures the interval from the reset to the first completed tick - which spans
# the deploy gate, the HQ-placement wait and the camera intro, none of which are
# compute. In the 2026-08-19T19-57-23 capture that came out as a 189 003 ms
# "frame" inside a 258 800 ms match, and it poisoned `worst` and `mean` in
# frame_stats while `p50` stayed at 13.9 ms. The old plan read that as a stall
# and it is an idle gap.
#
# So the first interval after every reset() is measured, used only to
# re-baseline `_frame_start`, and dropped. It is still surfaced - as
# `first_frame_ms` on the summary - because "how long between world-ready and
# the first tick" IS worth knowing; it just is not a frame time and must not sit
# in the same distribution as one.
static var _first_frame_pending: bool = true
static var first_frame_ms: float = 0.0


static func reset() -> void:
	_frame.clear()
	_totals.clear()
	_frames.clear()
	_frame_start = Time.get_ticks_usec()
	_first_frame_pending = true
	first_frame_ms = 0.0
	last_frame_ms = 0.0
	last_dominant = ""
	last_dominant_ms = 0.0
	last_sections.clear()


# Returns a token to hand back to stop(). Zero when disabled, which stop() reads
# as "do nothing" - so a call site never needs its own `if enabled` guard.
static func start() -> int:
	if not enabled:
		return 0
	return Time.get_ticks_usec()


static func stop(section: String, token: int) -> void:
	if token == 0:
		return
	var elapsed := Time.get_ticks_usec() - token
	_frame[section] = _frame.get(section, 0) + elapsed


# Called once per frame by the director, after everything it times.
static func end_frame() -> void:
	if not enabled:
		return
	var now := Time.get_ticks_usec()
	var total_ms := float(now - _frame_start) / 1000.0
	_frame_start = now

	# See _first_frame_pending above. Drop the reset-to-first-tick interval
	# rather than letting it into _frames. The per-section totals gathered
	# during it are still folded in below on the NEXT frame; only this one
	# bogus interval is discarded, and _frame is cleared so the sections it
	# holds do not double-count into the following frame.
	if _first_frame_pending:
		_first_frame_pending = false
		first_frame_ms = total_ms
		_frame.clear()
		last_frame_ms = 0.0
		last_dominant = ""
		last_dominant_ms = 0.0
		last_sections.clear()
		return

	var dominant := ""
	var dominant_us := 0
	for section in _frame:
		var us: int = _frame[section]
		if us > dominant_us:
			dominant_us = us
			dominant = section
		var row: Dictionary = _totals.get(section, {"sum": 0, "max": 0, "count": 0})
		row["sum"] += us
		row["max"] = maxi(row["max"], us)
		row["count"] += 1
		_totals[section] = row

	# DOMINANCE_SHARE GATE. hitch_blame() refuses to name a section as
	# the cause of a stall unless it accounts for at least DOMINANCE_SHARE
	# of the frame. end_frame() previously recorded the largest timed
	# section regardless, and match_director.log_hitch() read that raw -
	# so a 35.6 s frame with no instrumented work named `production`
	# (which itself totalled 0.0 ms across the match) as dominant. Same
	# rule, same field, same call site; the two readers have to agree or
	# the per-hitch log is fiction.
	#
	# The "<untimed>" string is the same one hitch_blame() emits in the
	# shared case, so downstream log readers can correlate on it
	# without a separate vocabulary.
	var named := ""
	var named_us := 0
	if dominant != "" and float(dominant_us) / 1000.0 >= total_ms * DOMINANCE_SHARE:
		named = dominant
		named_us = dominant_us
	else:
		named = "<untimed>"
		named_us = 0
	_frames.append([total_ms, named, float(named_us) / 1000.0])
	# Snapshot for BattleLogger to read. The mirror (per-section log lines
	# and hitch detection) lives in match_director.gd so the profiler
	# itself stays free of a logger dependency - the previous preload was
	# circular.
	last_frame_ms = total_ms
	last_dominant = named
	last_dominant_ms = float(named_us) / 1000.0
	last_sections = _frame.duplicate()
	_frame.clear()


static func frame_count() -> int:
	return _frames.size()


# Frame-time percentiles, in ms. The whole point of keeping every frame.
static func frame_stats() -> Dictionary:
	if _frames.is_empty():
		return {}
	var times: Array[float] = []
	for f in _frames:
		times.append(f[0])
	times.sort()
	var sum := 0.0
	# SKIRMISH_PERF_TROUBLESHOOTING.md §3.2. The 33 ms / 100 ms
	# hardcoded thresholds are meaningless at 30 Hz - a healthy tick
	# IS 33.3 ms. Derive from the current tick rate so 30 Hz Skirmish
	# and 60 Hz Test Range each get thresholds that match their own
	# frame budget. The legacy keys (over_33ms, over_100ms) are kept
	# so existing log readers don't break; over_3x_budget is the
	# signal that aligns with the engine's actual frame budget.
	var threshold := hitch_threshold_ms()
	var over_threshold := 0
	var over_33 := 0
	var over_100 := 0
	for t in times:
		sum += t
		if t > threshold:
			over_threshold += 1
		if t > 33.0:
			over_33 += 1
		if t > 100.0:
			over_100 += 1
	return {
		"frames": times.size(),
		# The discarded reset-to-first-tick interval, reported separately so it
		# is visible without contaminating the distribution. See §10.5.
		"first_frame_ms": first_frame_ms,
		"mean": sum / float(times.size()),
		"p50": times[int(float(times.size()) * 0.50)],
		"p95": times[int(float(times.size()) * 0.95)],
		"p99": times[int(float(times.size()) * 0.99)],
		"worst": times[times.size() - 1],
		"over_33ms": over_33,
		"over_100ms": over_100,
		"hitch_threshold_ms": threshold,
		"over_hitch_threshold": over_threshold,
	}


# SKIRMISH_PERF_TROUBLESHOOTING.md §3.2. A hitch is "a frame at least
# N times the engine's tick budget" - 100 ms at 30 Hz physics, 50 ms
# at 60 Hz. The old 33 ms / 100 ms hardcoded constants conflated
# normal 30 Hz ticks with real stalls (over_33ms counted every
# healthy tick in the 2026-08-19 log). This derives a sensible
# threshold from the current tick rate and is what the rest of the
# profiler keys off.
#
# 3x tick budget is "one missed frame plus a normal one" - the gap
# between "the engine is keeping up" and "a frame was dropped". The
# minimum of 50 ms protects against a 60 Hz match collapsing to 0.83
# ms, which would be silly.
static func hitch_threshold_ms() -> float:
	var tick_budget_ms := 1000.0 / float(Engine.physics_ticks_per_second)
	return maxf(50.0, tick_budget_ms * 3.0)


# section -> {total_ms, mean_ms, worst_ms, frames}, sorted by total descending.
static func sections() -> Array:
	var out: Array = []
	for section in _totals:
		var row: Dictionary = _totals[section]
		out.append({
			"section": section,
			"total_ms": float(row["sum"]) / 1000.0,
			"mean_ms": float(row["sum"]) / float(maxi(1, row["count"])) / 1000.0,
			"worst_ms": float(row["max"]) / 1000.0,
			"frames": row["count"],
		})
	out.sort_custom(func(a, b): return a["total_ms"] > b["total_ms"])
	return out


# Which section dominated the frames that hitched. This is the question the whole
# file exists to answer: a section can be cheap on average and still be the thing
# that stalls, and only the bad frames can say so.
#
# SKIRMISH_PERF_TROUBLESHOOTING.md §3.2. The default threshold is
# derived from the current tick rate (hitch_threshold_ms()), NOT a
# hardcoded 33 ms. Callers that want a specific threshold (e.g. the
# log's 100 ms "feels like a freeze" marker) can still pass one.
static func hitch_blame(threshold_ms: float = -1.0) -> Array:
	if threshold_ms < 0.0:
		threshold_ms = hitch_threshold_ms()
	var blame: Dictionary = {}
	var worst: Dictionary = {}
	for f in _frames:
		if f[0] < threshold_ms:
			continue
		# A section is only blamed if it actually accounts for the frame. Naming
		# the largest TIMED section regardless produced nonsense: a 3402ms frame
		# was credited to `production`, whose own worst measurement across the
		# whole run was 0.17ms. Below this share the honest answer is that the
		# cost was somewhere not instrumented, and saying so is what points at
		# the next place to look.
		var who: String = "<untimed>"
		if f[1] != "" and f[2] >= f[0] * DOMINANCE_SHARE:
			who = f[1]
		blame[who] = blame.get(who, 0) + 1
		worst[who] = maxf(worst.get(who, 0.0), f[0])
	var out: Array = []
	for who in blame:
		out.append({"section": who, "hitches": blame[who], "worst_ms": worst[who]})
	out.sort_custom(func(a, b): return a["hitches"] > b["hitches"])
	return out
