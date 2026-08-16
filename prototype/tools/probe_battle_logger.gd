extends SceneTree
# Smoke test for the BattleLogger wiring. Runs the same begin_match ->
# log_section -> log_hitch -> log_lifecycle -> end_match flow the live
# match triggers, and confirms the JSONL file the logger writes has the
# expected events and the in-memory summary is well-formed.
#
# Run: ./Godot_v4.7.1-stable_win64_console.exe --headless --script tools/probe_battle_logger.gd

const BattleLogger = preload("res://scripts/battle/battle_logger.gd")
const Profiler = preload("res://scripts/battle/battle_profiler.gd")


func _init():
	BattleLogger.enabled = true
	BattleLogger.begin_match("probe", {"map_id": "smoke"})
	Profiler.enabled = true
	Profiler.reset()
	# Simulate a frame: some sections, then end_frame.
	for section in ["neighbour_grid", "vision", "units", "weapons"]:
		var t := Profiler.start()
		OS.delay_msec(0)
		Profiler.stop(section, t)
	Profiler.end_frame()
	# Manually drive the mirror that match_director.gd's _physics_process
	# would do, since this script is a SceneTree and does not have a
	# scene.
	if BattleLogger.enabled:
		BattleLogger.begin_frame()
		for section_name in Profiler.last_sections:
			BattleLogger.log_section(section_name, Profiler.last_sections[section_name])
	# Lifecycle events.
	BattleLogger.unit_spawned("probe_unit", 0, "scout")
	BattleLogger.structure_built("refinery", 0)
	BattleLogger.unit_died("probe_unit", 0, "scout", "probe")
	BattleLogger.structure_died("refinery", 0)
	BattleLogger.beacon_fired("probe_unit", Vector3(10, 0, 10))
	BattleLogger.drone_launched("probe_unit", "scout", 2)
	BattleLogger.mine_dropped("probe_unit", Vector3(5, 0, 5))
	BattleLogger.smoke_popped("probe_unit", 8.0)
	# Dump-now returns a path.
	var dump_path := BattleLogger.dump_now("smoke")
	if dump_path.is_empty():
		print("[FAIL] dump_now returned empty")
		quit(1)
		return
	# Hitch log: stamp a large last_frame_ms and call log_hitch.
	Profiler.last_frame_ms = 250.0
	Profiler.last_dominant = "weapons"
	Profiler.last_dominant_ms = 200.0
	BattleLogger.log_hitch(250.0, "weapons", 200.0)
	BattleLogger.end_match()
	# Confirm the file exists and has the expected lines.
	var f := FileAccess.open(BattleLogger.log_path, FileAccess.READ)
	if f == null:
		print("[FAIL] could not reopen log file: %s" % BattleLogger.log_path)
		quit(1)
		return
	var contents := f.get_as_text()
	f.close()
	var required := ["MATCH_BEGIN", "MATCH_END", "section", "hitch",
			"unit_spawn", "unit_death", "structure_built", "structure_death",
			"beacon_fired", "drone_launched", "mine_dropped", "smoke_popped",
			"manual_dump", "profiler_summary"]
	for token in required:
		# JSON.stringify emits no whitespace between key/value pairs, so
		# the substring is `"event":"<name>"` rather than the more
		# natural `"event": "<name>"`.
		if not contents.contains('"event":"%s"' % token):
			print("[FAIL] log missing event: %s" % token)
			quit(1)
			return
	print("[PASS] log file has all %d event types. Path: %s"
		% [required.size(), ProjectSettings.globalize_path(BattleLogger.log_path)])
	quit(0)
