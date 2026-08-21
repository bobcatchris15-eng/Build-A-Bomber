extends SceneTree

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")
const MapCatalog = preload("res://scripts/map_catalog.gd")

func _init():
	var map_def = MapCatalog.get_map("lake_crossing")
	var site := Vector3(0, 0, 70)
	var ground_y = TerrainBuilder.terrain_height_at(map_def, site)
	print("Ground Y at (0, 70) = %.3f" % ground_y)

	var tile_rects = TerrainBuilder._nav_tile_rects(map_def)
	var tile_cell_size = TerrainBuilder._nav_tile_cell_size(map_def)
	var ground_verts = TerrainBuilder._build_ground_faces(map_def, [])
	var ground_buckets = TerrainBuilder._bucket_verts_by_tile(ground_verts, map_def, tile_rects)

	print("Total ground_verts: %d" % ground_verts.size())
	for i in range(tile_rects.size()):
		if tile_rects[i].x0 <= 0 and tile_rects[i].x1 >= 0 and tile_rects[i].z0 <= 70 and tile_rects[i].z1 >= 70:
			print("Tile %d covers (0, 70): %s" % [i, tile_rects[i]])
			print("  Bucket %d verts count: %d" % [i, ground_buckets[i].size()])
			var nm = TerrainBuilder._bake_nav_mesh(ground_buckets[i], tile_cell_size)
			print("  Baked navmesh polygon count: %d" % nm.get_polygon_count())
			var min_v = Vector3(INF, INF, INF)
			var max_v = Vector3(-INF, -INF, -INF)
			var nm_verts = nm.get_vertices()
			for v in nm_verts:
				min_v.x = minf(min_v.x, v.x)
				min_v.y = minf(min_v.y, v.y)
				min_v.z = minf(min_v.z, v.z)
				max_v.x = maxf(max_v.x, v.x)
				max_v.y = maxf(max_v.y, v.y)
				max_v.z = maxf(max_v.z, v.z)
			print("  Navmesh AABB: min=%s max=%s" % [min_v, max_v])

	quit(0)
