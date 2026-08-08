extends SceneTree
# Is a factory's exit_position() - where a newly BUILT unit is spawned -
# actually on the navmesh? The auto-spawned harvester works and a
# factory-built one spins in place, which points at the spawn point rather
# than at steering.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_factory_exit.gd

const MapCatalogScript = preload("res://scripts/map_catalog.gd")
const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")


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
	print("map_half_extents=", map_def.get("map_half_extents"),
		" nav_grid_cell=", TerrainBuilderScript._nav_grid_cell(map_def),
		" nav_cell_size=", TerrainBuilderScript._nav_cell_size(map_def),
		" HOLE_SUBDIVISION_CELL=", TerrainBuilderScript.HOLE_SUBDIVISION_CELL)

	var ground_map: RID = battle.get_ground_nav_map()

	for s in get_nodes_in_group("structures"):
		if not is_instance_valid(s) or not s.has_method("exit_position"):
			continue
		var exit: Vector3 = s.exit_position()
		var closest = NavigationServer3D.map_get_closest_point(ground_map, exit)
		var flat = Vector3(closest.x, 0, closest.z)
		var off = flat.distance_to(Vector3(exit.x, 0, exit.z))
		print("  ", s.kind, " team=", s.team, " @", s.global_position,
			" footprint=", s.footprint,
			" exit=", exit, " closest=", closest,
			" OFFSET=", off, ("  <<< OFF-MESH" if off > 1.0 else ""))

		# Walk outward along the exit direction to find the real hole edge.
		var dir: Vector3 = exit - s.global_position
		dir.y = 0.0
		dir = dir.normalized()
		var edge := -1.0
		for step in range(1, 60):
			var d := step * 0.5
			var p: Vector3 = s.global_position + dir * d
			var c = NavigationServer3D.map_get_closest_point(ground_map, p)
			if Vector3(c.x, 0, c.z).distance_to(Vector3(p.x, 0, p.z)) < 0.75:
				edge = d
				break
		print("      hole edge along exit dir at ", edge,
			"  (exit is at ", (exit - s.global_position).length(), ")")

	quit(0)
