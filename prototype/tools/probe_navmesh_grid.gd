extends SceneTree
# Fine-grained map of navmesh connectivity around the harvester spawn -
# for each grid point, is map_get_closest_point() approximately AT the
# query point (on-mesh) or far from it (in a hole/gap)?
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_navmesh_grid.gd

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

	print("harvester=", harvester)
	print("grid centred on harvester, 2-unit steps, X range -20..+20, Z range -20..+20")
	print("# = closest_point > 1.5 units away (off-mesh/gap), . = on-mesh, H = harvester itself")
	for dz in range(-20, 21, 2):
		var row := ""
		for dx in range(-20, 21, 2):
			var p = Vector3(harvester.x + dx, 0, harvester.z + dz)
			if dx == 0 and dz == 0:
				row += "H"
				continue
			var closest = NavigationServer3D.map_get_closest_point(ground_map, p)
			var flat_closest = Vector3(closest.x, 0, closest.z)
			var off = flat_closest.distance_to(p) > 1.5
			row += ("#" if off else ".")
		print(row)

	quit(0)
