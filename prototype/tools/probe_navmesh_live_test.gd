extends SceneTree

func _init():
	print("--- Starting probe_navmesh_live_test ---")
	var packed = load("res://scenes/Battle.tscn")
	if packed == null:
		print("[FAIL] Battle.tscn did not load")
		quit(1)
		return
	var battle = packed.instantiate()
	root.add_child(battle)

	for _i in range(10):
		await process_frame

	var site := Vector3(10, 0, 70)
	site.y = battle.terrain_height_at(site)
	print("[OK] site is %s" % site)

	var g_map: RID = battle.ground_nav_map
	for _i in range(10):
		await physics_frame

	var p_before: Vector3 = NavigationServer3D.map_get_closest_point(g_map, site)
	print("[INFO] before placement: closest nav point = %s, dist = %.3f" % [p_before, Vector2(p_before.x - site.x, p_before.z - site.z).length()])

	# Place structure
	var s: Structure = battle._place_structure("power_plant", 0, site)
	print("[OK] placed structure: %s, in tree=%s, footprint=%s" % [s.kind, s.is_inside_tree(), s.footprint])

	print("[INFO] _nav_rebake_pending before dirty: %s" % battle._nav_rebake_pending)
	battle._mark_navmesh_dirty(true)
	print("[INFO] _nav_rebake_pending after dirty: %s" % battle._nav_rebake_pending)

	# Wait for rebake
	print("[INFO] Waiting up to 100 frames for rebake...")
	for f in range(100):
		await physics_frame
		if not battle._nav_rebake_pending:
			print("[OK] _nav_rebake_pending cleared at frame %d" % f)
			break
	if battle._nav_rebake_pending:
		print("[FAIL] _nav_rebake_pending STILL TRUE after 100 frames!")

	# Wait 10 more frames for NavigationServer3D map iteration sync
	for f in range(10):
		await physics_frame

	var p_after: Vector3 = NavigationServer3D.map_get_closest_point(g_map, site)
	var dist_after: float = Vector2(p_after.x - site.x, p_after.z - site.z).length()
	print("[INFO] after placement & rebake: closest nav point = %s, dist = %.3f" % [p_after, dist_after])

	# Check path through the building
	var west := Vector3(site.x - 20, site.y, site.z)
	var east := Vector3(site.x + 20, site.y, site.z)
	var path := NavigationServer3D.map_get_path(g_map, west, east, true)
	print("[INFO] path points count: %d" % path.size())
	for i in range(path.size()):
		print("  path[%d] = %s" % [i, path[i]])

	var worst_d := INF
	for p in path:
		var d: float = Vector2(p.x - site.x, p.z - site.z).length()
		worst_d = minf(worst_d, d)
	print("[INFO] closest path distance to building center: %.3f" % worst_d)

	battle.queue_free()
	await process_frame
	quit(0)
