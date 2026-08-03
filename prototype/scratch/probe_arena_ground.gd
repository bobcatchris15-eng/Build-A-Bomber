extends SceneTree
# Scratch: does a vehicle in the TEST ARENA actually stand on its running gear?
#
# Chris, 2026-08-03: "the locomotors are currently falling through the ground in
# the test arena, leaving the vehicles sliding around on their belly." Three
# things have to be true afterwards:
#
#   1. the unit's ORIGIN settles on the arena floor - that origin IS the ground
#      contact point, by the invariant reconstruct_vehicle establishes;
#   2. the lowest locomotion GEOMETRY sits at the floor, not below it;
#   3. the hull's own underside is ABOVE the floor by a real ride height, which
#      is what "not sliding on its belly" means.
#
# Checks types the old lift formula special-cased (wheels, legs) AND ones it gave
# no ride height at all (tracked_treads, screw_drive) - the worse case.
#
# The design under test is built in a REAL MainLab and then run through
# serialize_hull(), because locomotion instances reach a battle as entries in the
# blueprint's `modules` array (serialize_hull walks every hull child carrying
# module_data). A hand-written dict with `"modules": []` has no running gear at
# all, which the first version of this probe did - it reported every lowest-gear
# measurement as nan and looked like a failure of the fix rather than of the
# fixture.
#
# DOES NOT WRITE user://blueprint.json. Battlefield.tscn boots its own vehicle
# from that path and it holds whatever design Chris last sent to the arena;
# clobbering it to inject a test design would destroy real work. This spawns an
# ADDITIONAL battle_unit under the Battlefield node instead, which exercises the
# identical path (reconstruct_vehicle's lift, battle_unit's ground snap, and
# battlefield.gd's terrain_height_at) because get_parent() is the same node.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_arena_ground.gd --path .

const BlueprintManager = preload("res://scripts/blueprint_manager.gd")
const BattleUnitScript = preload("res://scripts/battle_unit.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")

const CASES := [
	["wheels", {"wheel_size": 1.0, "num_axles": 4, "wheels_per_axle": 1}],
	["tracked_treads", {"tread_width": 1.0}],
	["legs", {"knee_height": 0.375, "count": 4}],
	["screw_drive", {"drum_diameter": 1.0, "helix_depth": 1.0}],
	["half_track", {}],
	["pontoon_wheels", {"pontoon_size": 1.0, "axle_count": 4}],
]

func _lowest_locomotion_y(hull: Node3D) -> float:
	var lowest := INF
	for child in hull.get_children():
		if not child.has_meta("module_data"):
			continue
		var d = child.get_meta("module_data")
		if d == null or d.category != "locomotion":
			continue
		var wb: AABB = VisualBuilder.measure_visual_bounds(child)
		if wb.size.length_squared() <= 0.0:
			continue
		lowest = minf(lowest, child.position.y + wb.position.y * child.scale.y)
	return lowest

func _init():
	# --- build each design for real in the Design Lab, and serialize it ---
	var lab = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	for _i in range(12):
		await process_frame
	var lab_bp = BlueprintManager.new()
	lab.add_child(lab_bp)

	var blueprints := {}
	var lab_lift := {}
	for case in CASES:
		var loco_id: String = case[0]
		if lab.get_node_or_null("Hull") == null and lab.has_method("_place_hull_from_ui"):
			lab._place_hull_from_ui("medium_hull")
			for _i in range(6):
				await process_frame
		lab.update_locomotion(loco_id, (case[1] as Dictionary).duplicate())
		for _i in range(8):
			await process_frame
		var lab_hull = lab.get_node_or_null("Hull")
		if lab_hull == null:
			print("  %-16s SKIP (lab built no hull)" % loco_id)
			continue
		blueprints[loco_id] = lab_bp.serialize_hull(lab_hull)
		# What the DESIGN LAB itself chose, so the battle spawn can be compared
		# against it - they are supposed to be identical now.
		lab_lift[loco_id] = lab_hull.position.y
	lab.queue_free()
	await process_frame

	# --- now spawn each into the real arena ---
	var scene = load("res://scenes/Battlefield.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for _i in range(30):
		await process_frame

	if not scene.has_method("terrain_height_at"):
		print("FAIL: Battlefield has no terrain_height_at() - the arena is still on the")
		print("      gravity/is_on_floor fallback, which rests the HULL on the ground.")
		quit(1)
		return
	var floor_y: float = scene.terrain_height_at(Vector3.ZERO)
	print("arena floor y = %.2f" % floor_y)
	print("")

	var bp_manager = BlueprintManager.new()
	scene.add_child(bp_manager)

	var all_ok := true
	for case in CASES:
		var loco_id: String = case[0]
		if not blueprints.has(loco_id):
			continue
		var unit = CharacterBody3D.new()
		unit.set_script(BattleUnitScript)
		scene.add_child(unit)
		unit.setup(blueprints[loco_id], 0, bp_manager)
		# Drop in from above so the settle is real, not just the spawn pose.
		unit.global_position = Vector3(0.0, floor_y + 3.0, 0.0)
		for _i in range(120):
			await process_frame

		if not is_instance_valid(unit) or not is_instance_valid(unit.hull_node):
			print("  %-16s SKIP (no hull built)" % loco_id)
			continue
		var hull: Node3D = unit.hull_node
		var origin_y: float = unit.global_position.y
		var lowest_local := _lowest_locomotion_y(hull)
		# hull.position.y MUST be included: _lowest_locomotion_y measures in the
		# HULL's local space, and the hull is a lifted child of the unit. The
		# first version of this check omitted it and reported every type as
		# "gear buried by exactly the lift" - which is arithmetically the same
		# statement as "the lift is correct", read wrong.
		var gear_world: float = origin_y + hull.position.y + lowest_local if lowest_local < INF else NAN
		var hull_half: float = ModuleCatalog.get_module_data("medium_hull").get("size", Vector3.ONE).y * 0.5
		var hull_underside: float = origin_y + hull.position.y - hull_half

		var problems: Array = []
		if absf(origin_y - floor_y) > 0.35:
			problems.append("origin not on floor")
		if lowest_local == INF:
			problems.append("NO LOCOMOTION GEOMETRY (fixture problem, not the fix)")
		elif gear_world < floor_y - 0.2:
			problems.append("gear BURIED %.2f below floor" % (floor_y - gear_world))
		elif gear_world > floor_y + 0.3:
			problems.append("gear FLOATING %.2f above floor" % (gear_world - floor_y))
		if hull_underside <= floor_y + 0.05:
			problems.append("hull ON ITS BELLY")
		# The whole point of sharing measure_visual_bounds(): the battle spawn
		# must sit at the same height the Design Lab previewed.
		if lab_lift.has(loco_id) and absf(hull.position.y - lab_lift[loco_id]) > 0.02:
			problems.append("lift %.2f != lab's %.2f" % [hull.position.y, lab_lift[loco_id]])
		if not problems.is_empty():
			all_ok = false

		print("  %-16s origin %6.2f  lowest gear %6.2f  hull underside %6.2f  lift %5.2f (lab %5.2f)  %s" % [
			loco_id, origin_y, gear_world, hull_underside, hull.position.y,
			lab_lift.get(loco_id, NAN),
			"ok" if problems.is_empty() else "<-- " + ", ".join(problems)])
		unit.queue_free()
		await process_frame

	print("")
	print("RESULT ", "all standing on their running gear, at the lab's own ride height" if all_ok else "SOME STILL WRONG")
	quit(0 if all_ok else 1)
