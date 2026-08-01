extends SceneTree
# Scratch: is test_c1_building_placed_after_unit_is_moving_forces_a_repath
# flaky because the TEST is fragile, or because the GAME genuinely fails to
# path around a building sometimes?
#
# The failure data says something real is going on: across runs of identical
# code the unit finished at x=2.31 on one attempt and x=-29.4 on another,
# against a required x>=10 and a start of x=-40. That is not noise around a
# threshold, that is "sometimes it travels most of the way and sometimes it
# barely moves at all".
#
# The suspicion about the harness: the test advances the unit by calling
# unit._physics_process(1/60) and move_and_slide() 900 times in a tight loop
# WITHOUT awaiting a single frame. NavigationServer3D syncs its maps on real
# physics steps, so in that loop a NavigationAgent3D can never receive an
# updated path - every one of those 900 iterations steers on whatever
# corridor happened to be cached when the loop started.
#
# So this runs the SAME scenario two ways, N times each:
#   manual  - exactly what the test does (900 manual ticks, no awaits)
#   real    - awaiting a real physics frame each tick, like the actual game
#
# If `real` is reliable and `manual` is not, the test is lying and the game
# is fine. If `real` is ALSO scattered, units really do fail to route around
# buildings sometimes and it is a live gameplay bug.
#
# Usage: ./godot.exe --headless --script scratch/probe_c1_repath_flake.gd --path .

const TRIALS := 6
const TICKS := 900
const START_X := -40.0
const GOAL_X := 40.0
const PASS_X := 10.0

func _init():
	print("=== C1 repath: manual-tick (as the test does) vs real physics frames ===")
	print("start x=%.0f  goal x=%.0f  test requires final x >= %.0f\n" % [START_X, GOAL_X, PASS_X])

	var manual := []
	for t in range(TRIALS):
		manual.append(await _trial(false))
	var real := []
	for t in range(TRIALS):
		real.append(await _trial(true))

	_report("manual ticks (test's method)", manual)
	_report("real physics frames (game)  ", real)
	quit(0)

func _trial(use_real_frames: bool) -> float:
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await process_frame
	await process_frame

	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var bp = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "tracked_treads", "settings": {"width": 1.0}},
		"modules": [{"type_id": "tracked_treads", "name": "Tracked Treads",
			"position": {"x": 0.0, "y": -0.4, "z": 0.0}, "rotation": {"x": 0.0, "y": 0.0, "z": 0.0},
			"scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "yaw_offset": 0.0, "tweaks": {}}]
	}
	var unit = CharacterBody3D.new()
	unit.set_script(BattleUnitScript)
	skirmish.add_child(unit)
	unit.global_position = Vector3(START_X, 0.5, 200)
	unit.setup(bp, skirmish.PLAYER_TEAM, skirmish.bp_manager)

	unit.order_move(Vector3(GOAL_X, 0.5, 200))
	for i in range(20):
		unit._physics_process(1.0 / 60.0)
		unit.move_and_slide()

	skirmish._spawn_prefab("heavy_manufactory", skirmish.ENEMY_TEAM, Vector3(0, 0, 200), skirmish.enemy_faction)
	for i in range(5):
		await process_frame

	if use_real_frames:
		# The unit's own _physics_process runs on its own here; just let the
		# engine tick, which is what happens in a real match.
		for i in range(TICKS):
			await physics_frame
	else:
		for i in range(TICKS):
			unit._physics_process(1.0 / 60.0)
			unit.move_and_slide()

	var final_x: float = unit.global_position.x
	skirmish.queue_free()
	await process_frame
	return final_x

func _report(label: String, xs: Array) -> void:
	var passes := 0
	var line := ""
	for x in xs:
		if x >= PASS_X:
			passes += 1
		line += "%8.1f" % x
	print("%s  pass %d/%d   final x:%s" % [label, passes, xs.size(), line])
