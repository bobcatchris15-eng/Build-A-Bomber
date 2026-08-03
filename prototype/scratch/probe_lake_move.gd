extends SceneTree
# Scratch: replicates test_unit_order_move_actually_navigates_around_the_lake's
# EXACT fixture (one tracked_treads module at local y=-0.4, 140 manual ticks)
# and prints why it now covers only ~4.25 units when it needs 5.
#
# The failure is deterministic across retries, so it is a real regression rather
# than the project's known shared-process flake - and a Skirmish ROSTER unit
# moves 56 units in the same scene, so it is something about this fixture
# specifically.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_lake_move.gd --path .

const BattleUnitScript = preload("res://scripts/battle_unit.gd")

func _init():
	var skirmish = load("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await process_frame
	await process_frame

	var bp = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "tracked_treads", "settings": {"width": 1.0}},
		"modules": [
			{"type_id": "tracked_treads", "name": "Tracked Treads", "position": {"x": 0.0, "y": -0.4, "z": 0.0}, "rotation": {"x": 0.0, "y": 0.0, "z": 0.0}, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "yaw_offset": 0.0, "tweaks": {}}
		]
	}
	var unit = CharacterBody3D.new()
	unit.set_script(BattleUnitScript)
	skirmish.add_child(unit)
	unit.global_position = Vector3(0, 0.5, 0)
	unit.setup(bp, 0, skirmish.bp_manager)

	print("move_speed   = %.3f" % unit.move_speed)
	print("weight       = %.1f" % unit.total_weight)
	print("capacity     = %.1f" % unit.weight_capacity)
	print("load_ratio   = %.3f  overloaded=%s" % [unit.load_ratio, unit.is_overloaded])
	print("top_speed    = %.3f" % unit.top_speed)
	print("terrain mult = %.3f" % unit.terrain_speed_multiplier)
	print("hull lift    = %.3f" % unit.hull_node.position.y)
	for c in unit.get_children():
		if c is CollisionShape3D:
			var desc := str(c.shape)
			var bottom := NAN
			if c.shape is BoxShape3D:
				bottom = c.position.y - (c.shape as BoxShape3D).size.y * 0.5 * c.scale.y
			print("collider %-24s pos.y %6.3f  bottom %6.3f  %s" % [c.name, c.position.y, bottom, desc])

	var lake_center: Vector3 = Vector3(27, 0, 0)
	var lake_span: float = 15.0
	if not skirmish.current_map.get("water_blobs", []).is_empty():
		var blob = skirmish.current_map.water_blobs[0]
		lake_center = blob.center
		lake_span = blob.get("radius", 10.0)

	var start_pos: Vector3 = unit.global_position
	unit.order_move(Vector3(lake_center.x + lake_span * 2.5, 0.5, lake_center.z))
	print("")
	print("target = %s" % str(Vector3(lake_center.x + lake_span * 2.5, 0.5, lake_center.z)))

	for i in range(140):
		unit._physics_process(1.0 / 60.0)
		unit.move_and_slide()
		if i % 20 == 0 or i == 139:
			print("  tick %3d  pos %-30s moved %6.2f  vel %-28s tmult %.2f  spd %.2f" % [
				i, str(unit.global_position), start_pos.distance_to(unit.global_position),
				str(unit.velocity), unit.terrain_speed_multiplier, unit.move_speed])
	print("")
	print("TOTAL MOVED %.3f   (test needs >= 5.0)" % start_pos.distance_to(unit.global_position))
	quit(0)
