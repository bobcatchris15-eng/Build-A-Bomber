extends SceneTree
# Checks the REAL baked navmesh (post building placement, unlike probe_
# spawn_terrain.gd's map_def-only check) around a compact spawn cluster,
# to isolate why routing between real spawn points deadlocks even with the
# agent_max_climb fix applied.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_spawn_navmesh.gd

const MapCatalogScript = preload("res://scripts/map_catalog.gd")


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

	var map_def = MapCatalogScript.get_map("open_plains")
	var player_spawn = MapCatalogScript.get_spawn(map_def, "player")
	var ground_map: RID = battle.get_ground_nav_map()
	var harvester: Vector3 = player_spawn.harvester
	var hq: Vector3 = player_spawn.hq

	print("harvester=", harvester, " hq=", hq)

	# List real building StaticBody3D instances near the spawn cluster, so
	# we know their actual footprints, not just the authored spawn points.
	print("--- buildings in the tree near the spawn ---")
	for b in get_nodes_in_group("structures"):
		if not is_instance_valid(b):
			continue
		var d = b.global_position.distance_to(hq)
		if d < 60.0:
			print("  ", b.name, " @ ", b.global_position, " dist_to_hq=", d)

	# Closest point on navmesh at increasing distances FROM the harvester
	# spawn, in the direction of the destination (toward map centre/enemy),
	# to find exactly where local connectivity breaks.
	print("--- closest_point at increasing radii from harvester, toward map centre ---")
	var toward_centre := (Vector3.ZERO - harvester).normalized()
	for dist in [1.0, 2.0, 3.0, 5.0, 8.0, 12.0, 20.0, 30.0, 50.0, 80.0, 120.0]:
		var probe_point = harvester + toward_centre * dist
		var closest = NavigationServer3D.map_get_closest_point(ground_map, probe_point)
		var path = NavigationServer3D.map_get_path(ground_map, harvester, probe_point, true)
		var reached = not path.is_empty() and path[-1].distance_to(probe_point) < 3.0
		print("  dist=", dist, " probe=", probe_point, " closest_point=", closest,
			" path_len=", path.size(), " reached=", reached)

	quit(0)
