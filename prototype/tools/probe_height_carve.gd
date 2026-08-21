extends SceneTree

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")
const MapCatalog = preload("res://scripts/map_catalog.gd")

func _init():
	print("--- Testing heightmap navmesh carving with real height ---")
	var map_def = MapCatalog.get_map("lake_crossing")
	var site := Vector3(0, 0, 70)
	var ground_y = TerrainBuilder.terrain_height_at(map_def, site)
	print("Ground Y at (0, 70) on lake_crossing = %.3f" % ground_y)

	var hole: Dictionary = {
		"center": Vector3(site.x, ground_y, site.z),
		"half_extents": Vector2(4.5, 4.5),
	}

	# Build navmeshes with the hole
	var nav = TerrainBuilder.build_navmeshes(map_def, [hole])
	var g_map: RID = nav.ground_map

	NavigationServer3D.map_force_update(g_map)
	for _i in range(5):
		await physics_frame

	# Check closest nav point to building center
	var p_bldg = NavigationServer3D.map_get_closest_point(g_map, Vector3(site.x, ground_y, site.z))
	print("Closest nav point to building center: %s (distance from site XZ: %.3f)" % [
		p_bldg, Vector2(p_bldg.x - site.x, p_bldg.z - site.z).length()
	])

	# Check path from (0, ground_y, 90) to (0, ground_y, 40)
	var start := Vector3(0, TerrainBuilder.terrain_height_at(map_def, Vector3(0, 0, 90)), 90)
	var dest := Vector3(0, TerrainBuilder.terrain_height_at(map_def, Vector3(0, 0, 40)), 40)
	var path := NavigationServer3D.map_get_path(g_map, start, dest, true)
	print("Path from %s to %s:" % [start, dest])
	print("  Points count = %d" % path.size())
	for i in range(path.size()):
		print("  path[%d] = %s" % [i, path[i]])

	var worst_d := INF
	for p in path:
		var d = Vector2(p.x - site.x, p.z - site.z).length()
		worst_d = minf(worst_d, d)
	print("Closest approach to building center XZ = %.3f (building half-footprint=4.5)" % worst_d)

	for r in nav.ground_regions + nav.amphibious_regions + [nav.water_region, nav.deep_water_region, nav.ground_map, nav.water_map, nav.amphibious_map, nav.deep_water_map]:
		if r.is_valid():
			NavigationServer3D.free_rid(r)
	quit(0)
