extends SceneTree

const OrderScript = preload("res://scripts/battle/orders/order.gd")

func _init():
	print("--- Starting probe_unit_building_collision ---")
	var packed = load("res://scenes/Battle.tscn")
	if packed == null:
		print("[FAIL] Battle.tscn did not load")
		quit(1)
		return
	var battle = packed.instantiate()
	root.add_child(battle)

	for _i in range(10):
		await process_frame

	# Player HQ is at (0, 0, 102).
	# Place a power plant right in front of the player base at (0, 0, 70).
	var building_site := Vector3(0, 0, 70)
	building_site.y = battle.terrain_height_at(building_site)
	var s: Structure = battle._place_structure("power_plant", 0, building_site)
	print("[OK] placed structure: %s at %s, footprint=%s" % [s.kind, s.global_position, s.footprint])

	battle._mark_navmesh_dirty(true)

	# Wait for rebake to complete
	for f in range(60):
		await physics_frame
		if not battle._nav_rebake_pending:
			print("[OK] rebake finished at frame %d" % f)
			break

	# Wait 10 more frames for sync
	for f in range(10):
		await physics_frame

	# Now get a unit and order it to drive through (0, 0, 70) to (0, 0, 40)
	var units: Array = battle.get_team_units(0)
	if units.is_empty():
		print("[FAIL] no units spawned")
		quit(1)
		return

	var unit: BattleUnit = units[0]
	unit.global_position = Vector3(0, battle.terrain_height_at(Vector3(0, 0, 90)), 90)
	print("[OK] unit placed at %s, move_speed=%.1f" % [unit.global_position, unit.move_speed])

	var target_pos := Vector3(0, battle.terrain_height_at(Vector3(0, 0, 40)), 40)
	unit.current_order = OrderScript.move(target_pos)
	print("[OK] ordered unit to %s" % target_pos)

	# Trace unit movement for 180 ticks (3 seconds)
	var min_dist_to_building := INF
	for t in range(180):
		await physics_frame
		var pos := unit.global_position
		var d := Vector2(pos.x - building_site.x, pos.z - building_site.z).length()
		min_dist_to_building = minf(min_dist_to_building, d)
		if t % 30 == 0:
			var nav_target = unit.nav_agent.target_position if unit.nav_agent else Vector3.ZERO
			var nav_next = unit.nav_agent.get_next_path_position() if unit.nav_agent else Vector3.ZERO
			print("t=%3d: pos=(%.2f, %.2f, %.2f) vel=(%.2f, %.2f) dist_to_bldg=%.2f nav_next=%s nav_target=%s" % [
				t, pos.x, pos.y, pos.z, unit.velocity.x, unit.velocity.z, d, nav_next, nav_target
			])

	print("[INFO] Minimum distance to building center reached: %.2f m (building half-footprint=%.2f)" % [min_dist_to_building, s.footprint.x * 0.5])
	
	battle.queue_free()
	await process_frame
	quit(0)
