extends SceneTree
# WHICH SUBSYSTEM OWNS THE PER-UNIT COST.
#
# probe_perf_scaling.gd found the shape and the size. The shape is good news:
# per-unit cost FLATTENS at ~2410 us from 8 units on, so scaling is LINEAR -
# there is no quadratic every-unit-sees-every-unit blowup to hunt.
#
# The size is the bug. 2.4 MILLISECONDS of CPU per unit per physics frame,
# measured HEADLESS - no renderer, no draw calls, no shadows. A 16 ms frame
# budget is therefore spent by SEVEN units before anything is drawn at all,
# which is exactly the match size Chris was playing.
#
# So the question is no longer "is it the GPU" (it is not) but "which
# _physics_process". This turns each candidate off in isolation and re-times.
# Disabling rather than instrumenting on purpose: wrapping every suspect in
# Time.get_ticks_usec() perturbs the thing being measured and misses time
# spent in engine calls those scripts make (raycasts, navigation queries),
# which is precisely where this kind of cost usually hides.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_perf_attribution.gd

const UNIT_COUNT := 16
const SETTLE_FRAMES := 90
const MEASURE_FRAMES := 240

var _battle = null


func _init():
	await process_frame

	_battle = preload("res://scenes/Battle.tscn").instantiate()
	root.add_child(_battle)
	var guard := 0
	while not _battle.world_is_ready and guard < 3000:
		await process_frame
		guard += 1
	if not _battle.world_is_ready:
		print("[FAIL] Battle never built its world")
		quit(1)
		return

	var design: Dictionary = {}
	for d in _battle.roster:
		if str(d.get("name", "")) == "Bulwark MBT":
			design = d
			break
	if design.is_empty() and _battle.roster.size() > 0:
		design = _battle.roster[0]

	for i in range(UNIT_COUNT):
		var ang := TAU * float(i) / float(UNIT_COUNT)
		_battle.spawn_unit(design, _battle.PLAYER_TEAM,
			Vector3(cos(ang), 0.0, sin(ang)) * (20.0 + float(i)))
		await process_frame

	print("=== PER-SUBSYSTEM ATTRIBUTION (%d units, headless) ===" % UNIT_COUNT)

	var baseline := await _time_frames()
	print("%-28s %10.2f ms  %s" % ["everything on", baseline, ""])

	for probe in [
			{"label": "auto_weapon off", "script": "res://scripts/auto_weapon.gd"},
			{"label": "unit movement off", "script": "res://scripts/battle/units/unit.gd"},
		]:
		var touched := _set_processing_by_script(probe.script, false)
		var t := await _time_frames()
		print("%-28s %10.2f ms  (-%.1f%%, %d nodes)"
			% [probe.label, t, (1.0 - t / maxf(0.01, baseline)) * 100.0, touched])
		_set_processing_by_script(probe.script, true)

	# The director owns vision, the neighbour grid and the AI commander, all on
	# one tick - so this is a coarse bucket, worth splitting only if it lands.
	if _battle.has_method("set_physics_process"):
		_battle.set_physics_process(false)
		var t := await _time_frames()
		print("%-28s %10.2f ms  (-%.1f%%)"
			% ["director tick off", t, (1.0 - t / maxf(0.01, baseline)) * 100.0])
		_battle.set_physics_process(true)

	print("")
	print("Biggest drop is the owner. Budget at 60 fps is 16.67 ms TOTAL,")
	print("and this measurement has no renderer in it at all.")

	_battle.queue_free()
	await process_frame
	quit(0)


func _time_frames() -> float:
	for _i in range(SETTLE_FRAMES):
		await physics_frame
	var t0 := Time.get_ticks_usec()
	for _i in range(MEASURE_FRAMES):
		await physics_frame
	return (float(Time.get_ticks_usec() - t0) / float(MEASURE_FRAMES)) / 1000.0


func _set_processing_by_script(script_path: String, enabled: bool) -> int:
	var n := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.append(c)
		var s = node.get_script()
		if s != null and s.resource_path == script_path:
			node.set_physics_process(enabled)
			n += 1
	return n
