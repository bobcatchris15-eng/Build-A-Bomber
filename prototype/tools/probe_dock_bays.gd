extends SceneTree
# Are the refinery's derived dock bays actually on walkable navmesh? Bays
# buried in the building's own navmesh hole is a bug this codebase has
# already had twice (see building_catalog.gd dock_bays_for).
func _init():
	var packed = load("res://scenes/Battle.tscn")
	var battle = packed.instantiate()
	battle.map_id = "open_plains"
	root.add_child(battle)
	var guard := 0
	while not battle.world_is_ready and guard < 3000:
		await process_frame
		guard += 1
	for _i in range(30):
		await process_frame
	var ground_map: RID = battle.get_ground_nav_map()
	for s in get_nodes_in_group("structures"):
		if not is_instance_valid(s) or s.kind != "refinery":
			continue
		print("refinery team=", s.team, " footprint=", s.footprint, " bays=", s.bay_count())
		for i in range(s.bay_count()):
			var p: Vector3 = s.bay_position(i)
			var c = NavigationServer3D.map_get_closest_point(ground_map, p)
			var off = Vector3(c.x, 0, c.z).distance_to(Vector3(p.x, 0, p.z))
			print("   bay ", i, " @", p, " closest=", c, " OFFSET=", off,
				("  <<< OFF-MESH" if off > 1.0 else "  ok"))
	quit(0)
