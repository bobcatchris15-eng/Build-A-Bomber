extends SceneTree

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")

func _init():
	var map_def: Dictionary = {
		"map_half_extents": 320.0,
		"world_scale": 1.0,
		"obstacles": [],
		"water_areas": []
	}
	var hole: Dictionary = {
		"center": Vector3(10, 0, 70),
		"half_extents": Vector2(2.25 + 2.5, 2.1 + 2.5), # 4.75, 4.6
	}
	var tile_rects = TerrainBuilder._nav_tile_rects(map_def)
	var tiles = TerrainBuilder.tiles_overlapping_hole(map_def, hole)
	print("map tile_size = ", TerrainBuilder._nav_tile_size(map_def))
	print("total tile_rects = ", tile_rects.size())
	print("tiles overlapping hole = ", tiles)
	for t in tiles:
		print("  tile %d rect: %s" % [t, tile_rects[t]])

	var ground_verts = TerrainBuilder._build_ground_faces(map_def, [hole])
	print("ground_verts size = ", ground_verts.size())

	# Check triangles near (10, 70)
	var count_inside := 0
	var i := 0
	while i + 2 < ground_verts.size():
		var c = (ground_verts[i] + ground_verts[i+1] + ground_verts[i+2]) / 3.0
		if absf(c.x - 10.0) < 4.5 and absf(c.z - 70.0) < 4.5:
			count_inside += 1
			print("  Found triangle inside hole: centroid=%s" % c)
		i += 3
	print("Triangles inside hole in ground_verts = ", count_inside)

	var buckets = TerrainBuilder._bucket_verts_by_tile(ground_verts, map_def, tile_rects)
	for t in tiles:
		print("Bucket %d size = %d verts" % [t, buckets[t].size()])
		var b_inside := 0
		var bi := 0
		while bi + 2 < buckets[t].size():
			var c = (buckets[t][bi] + buckets[t][bi+1] + buckets[t][bi+2]) / 3.0
			if absf(c.x - 10.0) < 4.5 and absf(c.z - 70.0) < 4.5:
				b_inside += 1
			bi += 3
		print("Bucket %d triangles inside hole = %d" % [t, b_inside])

	quit(0)
