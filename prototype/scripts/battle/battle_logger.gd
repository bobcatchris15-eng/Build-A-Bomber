class_name BattleLogger
extends RefCounted

# Reached through preload, not through the `BattleProfiler` global class name,
# for the same reason profile_battle_run.gd cites (lines 24-27): the static
# flag set via one and read via the other did not agree during a previous
# investigation, and the harness and the game code now go through the same
# resource.
const BattleProfiler = preload("res://scripts/battle/battle_profiler.gd")
# Structured logger for live matches. Writes one event per line to a text file
# under user://logs/, so a playtest can be analysed after the match is over
# without anyone having to screenshot an F3 overlay frame by frame.
#
# WHY NOT JUST print() TO GODOT'S OWN LOG. The engine already writes
# user://godot_master<timestamp>.log when file_logging is on (see
# project.godot:[debug]). That log is the right place for engine errors, but
# for a perf investigation the things worth correlating - hitch frame, dominant
# section, unit count, projectile count, deployable spawns - want to land in
# ONE file with a known schema. Mixing them into the engine log would also
# mean a perf dump fights every other subsystem's prints for the same buffer.
#
# WHY NOT A BINARY FORMAT. JSONL is human-greppable, which matters because the
# first thing done with the log on a playtest report is `grep hitch battle.log`
# and look at what was on screen three lines before. A binary format would
# need a reader first, and the file is the report.
#
# COST WHEN DISABLED is one static-bool read per call site (matching
# battle_profiler.gd's posture). The hot path during a match is
# log_event("section"...) from BattleProfiler.end_frame() - ten calls per
# frame - and each of them returns immediately when enabled is false. The
# autoload flip below is a single static var, no per-call allocation.
#
# NOT THREAD SAFE and does not need to be: every event is enqueued from
# _physics_process or its callees on the main thread.

# Master switch. Flipped on by match_director._ready() so a Skirmish / Test
# Range / Operations run gets a log without the caller having to remember.
# Tools that want a control run can flip it off before the same match.
static var enabled: bool = false

# Where the log is being written this match. Empty when no match is live.
static var log_path: String = ""

# Lifecycle counters kept across the match. Read into the per-frame
# payload so the post-mortem can see what state the match was in when
# the worst frames landed.
static var _match_id: String = ""
static var _match_start_us: int = 0
static var _frame_counter: int = 0
static var _spawn_count: int = 0
static var _death_count: int = 0
static var _structure_count: int = 0
static var _structure_death_count: int = 0
static var _beacon_fire_count: int = 0
static var _drone_launch_count: int = 0
static var _mine_drop_count: int = 0
static var _smoke_pop_count: int = 0

# File handle. Single per match; flushed on a fixed cadence and on
# end_match so a crash still leaves a usable log.
static var _file: FileAccess = null
# Flush every N frames so a 5-minute match produces ~600 flushes, not the
# ~18000 a per-frame flush would. FileAccess buffers, so this is not
# catastrophic, but it shows up in the file as flush stalls during a hitch
# investigation.
const FLUSH_EVERY_FRAMES := 30

# Hitch threshold for the auto-snapshot. The perf_hud uses 33ms (one missed
# 30fps frame) and 50ms (two missed). Anything over 100ms is the kind of
# frame that a player would describe as "the game froze" and is what this
# whole exercise exists to find, so the threshold is set there.
const HITCH_THRESHOLD_MS := 100.0


# Open the log file and write the match header. Idempotent: a second call
# with the match still open closes and reopens, so the test harness can call
# it again after toggling enabled.
static func begin_match(match_id: String = "", context: Dictionary = {}) -> void:
	if not enabled:
		return
	if _file != null:
		end_match()
	if not _ensure_logs_dir():
		push_error("[BattleLogger] could not create user://logs/")
		enabled = false
		return
	var ts := Time.get_datetime_string_from_system(true).replace(":", "-")
	var safe_id := match_id.strip_edges().replace(" ", "_")
	if safe_id.is_empty():
		safe_id = "match"
	log_path = "user://logs/battle_%s_%s.log" % [ts, safe_id]
	_file = FileAccess.open(log_path, FileAccess.WRITE)
	if _file == null:
		push_error("[BattleLogger] open failed for %s (err %d)"
			% [log_path, FileAccess.get_open_error()])
		enabled = false
		return
	_match_id = safe_id
	_match_start_us = Time.get_ticks_usec()
	_frame_counter = 0
	_spawn_count = 0
	_death_count = 0
	_structure_count = 0
	_structure_death_count = 0
	_beacon_fire_count = 0
	_drone_launch_count = 0
	_mine_drop_count = 0
	_smoke_pop_count = 0
	# Header is a structured record the post-mortem can read first. Engine
	# settings dominate the frame-time baseline (per perf_hud.gd's own
	# header), so the match-time render config is the first thing the
	# reader wants.
	var header := {
		"engine_ticks_per_second": Engine.physics_ticks_per_second,
		"max_fps": Engine.max_fps,
		"time_scale": Engine.time_scale,
		"vsync": DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED,
		"viewport_size": _viewport_size(),
		"msaa_3d": _get_msaa_3d_label(),
	}
	for k in context:
		header[k] = context[k]
	_write_event("MATCH_BEGIN", header)
	_file.flush()
	print("[BattleLogger] logging to %s" % ProjectSettings.globalize_path(log_path))


# Write the closing summary, the profiler section breakdown, and the
# hitch blame. Called from match_director._exit_tree() so it fires whether
# the match ended normally, the user quit, or Godot crashed into a script
# error and tore the tree down.
static func end_match() -> void:
	if not enabled or _file == null:
		return
	var duration_ms := float(Time.get_ticks_usec() - _match_start_us) / 1000.0
	_write_event("MATCH_END", {
		"duration_ms": duration_ms,
		"frames": _frame_counter,
		"units_spawned": _spawn_count,
		"unit_deaths": _death_count,
		"structures_built": _structure_count,
		"structure_deaths": _structure_death_count,
		"beacons_fired": _beacon_fire_count,
		"drones_launched": _drone_launch_count,
		"mines_dropped": _mine_drop_count,
		"smoke_pops": _smoke_pop_count,
	})
	_dump_profiler_summary()
	_file.flush()
	_file.close()
	_file = null
	print("[BattleLogger] match closed: %d frames, %.1fs, log at %s"
		% [_frame_counter, duration_ms / 1000.0,
			ProjectSettings.globalize_path(log_path)])


# --- Per-frame helpers ------------------------------------------------------

# Called once per physics frame from match_director. Increments the counter,
# flushes on cadence, and writes a one-line frame record so the post-mortem
# has a timeline of every section timing.
static func begin_frame() -> void:
	if not enabled or _file == null:
		return
	_frame_counter += 1
	if _frame_counter % FLUSH_EVERY_FRAMES == 0:
		_file.flush()


# Write a per-section timing line. Called by BattleProfiler.end_frame() for
# every section the profiler recorded this frame. The dict-of-section-data
# pattern is the same one the offline harness prints; this just routes to
# a file so a live match can be post-mortem'd the same way.
static func log_section(section: String, us: int) -> void:
	if not enabled or _file == null:
		return
	_write_event("section", {"name": section, "us": us})


# A single frame exceeded HITCH_THRESHOLD_MS. The detail captured here is
# what the file gives you that an on-screen overlay cannot: the exact
# section that consumed the frame, the unit / structure / projectile counts
# at that moment, and the wall-clock time. A stutter report with this in
# the log has a single place to point at; without it, the report is
# memory plus a description of the screen.
static func log_hitch(frame_ms: float, dominant: String,
		dominant_ms: float, scene_snapshot: Dictionary = {}) -> void:
	if not enabled or _file == null:
		return
	var payload := {
		"frame_ms": frame_ms,
		"dominant": dominant,
		"dominant_ms": dominant_ms,
		"units_alive": _count_group("units"),
		"structures_alive": _count_group("structures"),
		"missiles_alive": _count_group("missiles"),
	}
	for k in scene_snapshot:
		payload[k] = scene_snapshot[k]
	_write_event("hitch", payload)


# --- Lifecycle events ------------------------------------------------------

# Spawn / death / structure events. All routed through one helper so the
# JSON record is identical and grep is unambiguous. The per-event counters
# (above) are not strictly required to read the log - every event line
# carries its own - but they let end_match() report totals before the
# per-event lines are read.
static func unit_spawned(unit_name: String, team: int, kind: String) -> void:
	if not enabled or _file == null:
		return
	_spawn_count += 1
	_write_event("unit_spawn", {"name": unit_name, "team": team, "kind": kind})


static func unit_died(unit_name: String, team: int, kind: String, cause: String) -> void:
	if not enabled or _file == null:
		return
	_death_count += 1
	_write_event("unit_death", {"name": unit_name, "team": team, "kind": kind, "cause": cause})


static func structure_built(kind: String, team: int) -> void:
	if not enabled or _file == null:
		return
	_structure_count += 1
	_write_event("structure_built", {"kind": kind, "team": team})


static func structure_died(kind: String, team: int) -> void:
	if not enabled or _file == null:
		return
	_structure_death_count += 1
	_write_event("structure_death", {"kind": kind, "team": team})


# --- Build-time and runtime instrumentation (SKIRMISH_PERF_TROUBLESHOOTING.md §10) ---
#
# WHY THESE ARE EVENTS AND NOT PROFILER SECTIONS. Everything that runs before
# `world_is_ready` is wiped by the `Profiler.reset()` the director does at the
# end of the build, so a section opened during the world build never reaches
# `sections()`. That is why `navmesh_boot_bake` records real time and then
# appears nowhere in the summary. Build-phase costs therefore have to be written
# straight to the log as their own event, at the moment they are measured.
#
# `build_step` answers §10.6: time-to-Ready is p50 15.7 s / max 83.6 s and
# essentially all of it is one phase ("Sculpting terrain mesh"), but 7 runs did
# the same map in ~3 s. Sub-step timings are what separate "the mesh build is
# slow" from "the navmesh wait is slow" from "something is being skipped".
static func log_build_step(step: String, ms: float, detail: Dictionary = {}) -> void:
	if not enabled or _file == null:
		return
	var payload := {"step": step, "ms": snappedf(ms, 0.001)}
	for k in detail:
		payload[k] = detail[k]
	_write_event("build_step", payload)


# §10.1. The rendered frame rate was only derivable by counting `render_frame`
# section entries and dividing by the match duration - which works, but means
# the single most important number in the log (4.53 fps) is not written
# anywhere in it. This states it directly, once a second, alongside the
# renderer counters that explain it.
static func log_perf_sample(detail: Dictionary) -> void:
	if not enabled or _file == null:
		return
	_write_event("perf_sample", detail)


# §10.2 support. `unit.move_and_slide` costs ~4 ms per unit per frame at 15
# units and scales superlinearly, which points at collision geometry. Godot's
# broadphase generates one pair PER SHAPE per interacting body, so the shape
# COUNT per unit is the number that predicts the cost - and it is not knowable
# from the blueprint alone, because it depends on which collider tier the hull
# resolved to. Logged once per spawn so a capture can be read as
# "N units x S shapes" instead of "N units".
static func log_unit_colliders(unit_name: String, team: int, detail: Dictionary) -> void:
	if not enabled or _file == null:
		return
	var payload := {"unit": unit_name, "team": team}
	for k in detail:
		payload[k] = detail[k]
	_write_event("unit_colliders", payload)


# §10.3. 107 synchronous Recast rebakes for 59 structures - roughly two per
# placement - at 272 ms mean. Whether that is "two placements each needing one"
# or "one placement triggering two" decides whether the fix is coalescing or
# de-duplication, and the trigger plus the affected-tile count is what tells
# them apart.
static func log_nav_rebake(reason: String, ms: float, detail: Dictionary = {}) -> void:
	if not enabled or _file == null:
		return
	var payload := {"reason": reason, "ms": snappedf(ms, 0.001)}
	for k in detail:
		payload[k] = detail[k]
	_write_event("nav_rebake", payload)


static func beacon_fired(unit_name: String, fog_point: Vector3) -> void:
	if not enabled or _file == null:
		return
	_beacon_fire_count += 1
	_write_event("beacon_fired", {
		"unit": unit_name,
		"x": fog_point.x, "y": fog_point.y, "z": fog_point.z,
	})


static func drone_launched(unit_name: String, drone_type: String, count: int) -> void:
	if not enabled or _file == null:
		return
	_drone_launch_count += count
	_write_event("drone_launched", {
		"unit": unit_name, "drone_type": drone_type, "count": count,
	})


static func mine_dropped(unit_name: String, position: Vector3) -> void:
	if not enabled or _file == null:
		return
	_mine_drop_count += 1
	_write_event("mine_dropped", {
		"unit": unit_name,
		"x": position.x, "y": position.y, "z": position.z,
	})


static func smoke_popped(unit_name: String, hp_pct: float) -> void:
	if not enabled or _file == null:
		return
	_smoke_pop_count += 1
	_write_event("smoke_popped", {"unit": unit_name, "hp_pct": hp_pct})


# --- Dump-now (F4) ---------------------------------------------------------

# The "I just saw a stutter, write it down NOW" hook. Writes the
# in-memory profiler state to a separate file under user://logs/ so the
# reading-the-overlay path does not depend on the user getting all the way
# to the end of the match. Also writes a `manual_dump` line into the
# running log so the on-disk record is consistent.
static func dump_now(label: String = "manual") -> String:
	if _file == null:
		return ""
	var path := "user://logs/dump_%s_%d.log" % [label, Time.get_ticks_msec()]
	var dump_file := FileAccess.open(path, FileAccess.WRITE)
	if dump_file == null:
		return ""
	dump_file.store_line("# manual dump: %s" % label)
	dump_file.store_line("# frame: %d, game time: %.2fs"
		% [_frame_counter, float(Time.get_ticks_usec() - _match_start_us) / 1_000_000.0])
	dump_file.store_line("")
	dump_file.store_line("## frame stats")
	var stats = _safe_call(BattleProfiler, "frame_stats", [])
	if typeof(stats) == TYPE_DICTIONARY and not stats.is_empty():
		for k in stats:
			dump_file.store_line("  %-10s %s" % [k, str(stats[k])])
	dump_file.store_line("")
	dump_file.store_line("## sections (sorted by total ms)")
	var sections = _safe_call(BattleProfiler, "sections", [])
	if typeof(sections) == TYPE_ARRAY:
		for row in sections:
			dump_file.store_line("  %-22s total %9.2f  mean %7.3f  worst %7.2f  frames %5d"
				% [row["section"], row["total_ms"], row["mean_ms"],
					row["worst_ms"], row["frames"]])
	dump_file.store_line("")
	dump_file.store_line("## hitch blame (>33ms)")
	var blame = _safe_call(BattleProfiler, "hitch_blame", [33.0])
	if typeof(blame) == TYPE_ARRAY:
		for row in blame:
			dump_file.store_line("  %-22s %5d hitch(es)  worst frame %.1f ms"
				% [row["section"], row["hitches"], row["worst_ms"]])
	dump_file.store_line("")
	dump_file.store_line("## performance monitors (one-shot snapshot)")
	for m in [Performance.TIME_PROCESS, Performance.TIME_PHYSICS_PROCESS,
			Performance.MEMORY_STATIC, Performance.OBJECT_NODE_COUNT,
			Performance.OBJECT_ORPHAN_NODE_COUNT, Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME,
			Performance.RENDER_TOTAL_OBJECTS_IN_FRAME, Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME,
			Performance.RENDER_VIDEO_MEM_USED]:
		dump_file.store_line("  %-40s %s" % [_perf_monitor_name(m), str(Performance.get_monitor(m))])
	dump_file.flush()
	dump_file.close()
	# Also record that we dumped in the main log so the timeline is consistent.
	_write_event("manual_dump", {"label": label, "path": path})
	_file.flush()
	return path


# --- Internals -------------------------------------------------------------

static func _ensure_logs_dir() -> bool:
	var d := DirAccess.open("user://")
	if d == null:
		return false
	if d.dir_exists("logs"):
		return true
	return d.make_dir("logs") == OK


static func _write_event(event: String, payload: Dictionary) -> void:
	if _file == null:
		return
	var record := {
		"t_us": Time.get_ticks_usec() - _match_start_us,
		"frame": _frame_counter,
		"event": event,
	}
	for k in payload:
		record[k] = payload[k]
	_file.store_line(JSON.stringify(record))


static func _dump_profiler_summary() -> void:
	if _file == null:
		return
	_write_event("profiler_summary", {
		"frame_stats": _safe_call(BattleProfiler, "frame_stats", []),
		"sections": _safe_call(BattleProfiler, "sections", []),
		"hitch_blame_33": _safe_call(BattleProfiler, "hitch_blame", [33.0]),
		"hitch_blame_100": _safe_call(BattleProfiler, "hitch_blame", [100.0]),
	})


# Safely call a static method on a preloaded class, swallowing any error.
# The logger never wants to itself be the cause of a script error in a
# playtest harness, so any failure returns the supplied default.
static func _safe_call(script, method: String, args: Array) -> Variant:
	if script == null:
		return null
	if not script.has_method(method):
		return null
	return script.callv(method, args)


static func _count_group(group: String) -> int:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0
	return tree.get_nodes_in_group(group).size()


static func _viewport_size() -> Array:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return [0, 0]
	var root := tree.root
	if root == null:
		return [0, 0]
	var size := root.get_visible_rect().size
	return [int(size.x), int(size.y)]


static func _get_msaa_3d_label() -> String:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return "n/a"
	var root := tree.root
	if root == null:
		return "n/a"
	var mode := int(root.msaa_3d)
	if mode < 4:
		return ["off", "2x", "4x", "8x"][mode]
	return "%dx" % (1 << mode)


static func _perf_monitor_name(monitor: int) -> String:
	# Performance monitors are integers; the names live in the enum on
	# the Performance singleton, but pulling them through Engine.get_singleton
	# is not portable, so a small hand-maintained table is the
	# clearest answer.
	match monitor:
		Performance.TIME_PROCESS: return "TIME_PROCESS"
		Performance.TIME_PHYSICS_PROCESS: return "TIME_PHYSICS_PROCESS"
		Performance.MEMORY_STATIC: return "MEMORY_STATIC"
		Performance.OBJECT_NODE_COUNT: return "OBJECT_NODE_COUNT"
		Performance.OBJECT_ORPHAN_NODE_COUNT: return "OBJECT_ORPHAN_NODE_COUNT"
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME: return "RENDER_TOTAL_DRAW_CALLS_IN_FRAME"
		Performance.RENDER_TOTAL_OBJECTS_IN_FRAME: return "RENDER_TOTAL_OBJECTS_IN_FRAME"
		Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME: return "RENDER_TOTAL_PRIMITIVES_IN_FRAME"
		Performance.RENDER_VIDEO_MEM_USED: return "RENDER_VIDEO_MEM_USED"
		_: return "monitor_%d" % monitor
