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

# How much of a frame a section must account for before it is named as the cause.
const DOMINANCE_SHARE := 0.5


static func reset() -> void:
	_frame.clear()
	_totals.clear()
	_frames.clear()
	_frame_start = Time.get_ticks_usec()


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

	_frames.append([total_ms, dominant, float(dominant_us) / 1000.0])
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
	var over_33 := 0
	var over_100 := 0
	for t in times:
		sum += t
		if t > 33.0:
			over_33 += 1
		if t > 100.0:
			over_100 += 1
	return {
		"frames": times.size(),
		"mean": sum / float(times.size()),
		"p50": times[int(float(times.size()) * 0.50)],
		"p95": times[int(float(times.size()) * 0.95)],
		"p99": times[int(float(times.size()) * 0.99)],
		"worst": times[times.size() - 1],
		"over_33ms": over_33,
		"over_100ms": over_100,
	}


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
static func hitch_blame(threshold_ms: float = 33.0) -> Array:
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
