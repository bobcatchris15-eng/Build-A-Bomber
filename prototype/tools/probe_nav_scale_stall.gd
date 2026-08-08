extends SceneTree
# Standalone repro for the 2026-08-08 playtest report: "units just sit in one
# spot and go in a circle" at world_scale=4.0. Deliberately NOT a test_*.gd
# suite - avoids run_tests.gd/SUITE_FILES entirely so it can run independent
# of whatever else is mid-edit in the test tree.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_nav_scale_stall.gd

const UnitScript = preload("res://scripts/battle/units/unit.gd")
const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const OrderScript = preload("res://scripts/battle/orders/order.gd")
const MapCatalogScript = preload("res://scripts/map_catalog.gd")


# Same design the earlier successful diagnostic run used (nav_agent valid=
# true, move_speed=12.0 there) - a harvester design specifically, not just
# "first non-defence design", since that grabbed a flying/fixed_wing design
# with no ground NavigationAgent3D at all (a different, unrelated code path).
func _find_ground_design(battle) -> Dictionary:
	for design in battle.roster:
		if battle.is_defence_design(design):
			continue
		for module in design.get("modules", []):
			if str(module.get("type_id", "")) == "resource_harvester":
				return design
	return {}


func _init():
	var packed = load("res://scenes/Battle.tscn")
	if packed == null:
		print("[FAIL] Battle.tscn did not load")
		quit(1)
		return
	var battle = packed.instantiate()
	battle.map_id = "open_plains"
	root.add_child(battle)

	var guard := 0
	while not battle.world_is_ready and guard < 3000:
		await process_frame
		guard += 1
	if not battle.world_is_ready:
		print("[FAIL] Battle never finished building open_plains")
		quit(1)
		return
	# Real navmesh sync wait, same reasoning as suite_base.gd's _await_nav_map.
	for _i in range(30):
		await process_frame

	var bp_manager = BlueprintManagerScript.new()
	root.add_child(bp_manager)
	var unit = UnitScript.new()
	root.add_child(unit)
	var blueprint := _find_ground_design(battle)
	if blueprint.is_empty():
		print("[FAIL] No non-defence design in roster")
		quit(1)
		return
	var ok: bool = unit.setup(blueprint, 0, bp_manager, battle)
	if not ok:
		print("[FAIL] unit failed to assemble")
		quit(1)
		return
	print("assembled: move_speed=", unit.move_speed, " nav_agent valid=", is_instance_valid(unit.nav_agent))
	if not is_instance_valid(unit.nav_agent):
		print("[FAIL] Design '", blueprint.get("name", "?"), "' has no nav_agent - wrong design picked, not the bug under investigation")
		quit(1)
		return

	var map_def = MapCatalogScript.get_map("open_plains")
	var player_spawn = MapCatalogScript.get_spawn(map_def, "player")
	var enemy_spawn = MapCatalogScript.get_spawn(map_def, "enemy")
	var start: Vector3 = player_spawn.harvester
	var destination: Vector3 = enemy_spawn.harvester
	print("REAL spawn positions: player.harvester=", start, " enemy.harvester=", destination)
	unit.global_position = start
	for _i in range(10):
		await process_frame
	print("pre-order: pos=", unit.global_position, " nav_agent.target_position=", unit.nav_agent.target_position, " next_corner=", unit.nav_agent.get_next_path_position(), " finished=", unit.nav_agent.is_navigation_finished())

	# Direct NavigationServer3D query, bypassing the agent entirely - if THIS
	# comes back empty/degenerate, the navmesh itself has no route between
	# these two points, independent of any agent/steering tuning.
	var ground_map: RID = battle.get_ground_nav_map()
	var direct_path = NavigationServer3D.map_get_path(ground_map, start, destination, true)
	print("DIRECT map_get_path: ", direct_path.size(), " points, last=",
		(direct_path[-1] if direct_path.size() > 0 else "N/A"),
		" map_get_iteration_id=", NavigationServer3D.map_get_iteration_id(ground_map))
	print("  closest_point(start)=", NavigationServer3D.map_get_closest_point(ground_map, start))
	print("  closest_point(destination)=", NavigationServer3D.map_get_closest_point(ground_map, destination))

	# ISOLATED agent, independent of unit.gd's own per-tick target_position
	# re-assignment logic entirely - a fresh NavigationAgent3D, parented to a
	# plain Node3D at `start`, target_position set EXACTLY ONCE, then polled
	# for many frames untouched. If THIS also never produces a real path,
	# the bug is in NavigationAgent3D's own recompute cycle at this map
	# scale, not in how unit.gd drives it.
	var probe_body := Node3D.new()
	root.add_child(probe_body)
	probe_body.global_position = start
	var probe_agent := NavigationAgent3D.new()
	probe_body.add_child(probe_agent)
	probe_agent.avoidance_enabled = false
	probe_agent.set_navigation_map(ground_map)
	for _i in range(5):
		await physics_frame
	probe_agent.target_position = destination
	for i in range(60):
		await physics_frame
		if i < 10 or i % 10 == 0:
			print("ISOLATED tick ", i, " next_corner=", probe_agent.get_next_path_position(),
				" finished=", probe_agent.is_navigation_finished(),
				" nav_path_size=", probe_agent.get_current_navigation_path().size())
	probe_body.queue_free()

	unit.current_order = OrderScript.move(destination)
	print("order issued: current_order.position=", unit.current_order.position)

	# Extended to 3600 ticks (60s) - is this a hard deadlock or just very
	# slow convergence? 8s of near-zero progress doesn't distinguish them.
	for i in range(3600):
		await physics_frame
		if i < 40 or i % 300 == 0:
			print("tick ", i, " pos=", unit.global_position, " vel=", unit.velocity,
				" yaw=", unit.rotation.y,
				" next_corner=", unit.nav_agent.get_next_path_position(),
				" target_position=", unit.nav_agent.target_position,
				" finished=", unit.nav_agent.is_navigation_finished(),
				" dist_to_dest=", Vector3(unit.global_position.x, 0, unit.global_position.z).distance_to(destination))

	var final_distance = Vector3(unit.global_position.x, 0.0, unit.global_position.z).distance_to(destination)
	var initial_distance = start.distance_to(destination)
	print("RESULT: initial_distance=", initial_distance, " final_distance=", final_distance,
		" progress=", initial_distance - final_distance)

	quit(0)
