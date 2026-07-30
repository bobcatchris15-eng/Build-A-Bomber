extends SceneTree

func _init() -> void:
	print("=== Inspecting Baked Hull Facets ===")
	var hull_ids := ["medium_hull", "heavy_hull", "assault_hull"]
	for id in hull_ids:
		var path := "res://assets/models/hulls/%s.res" % id
		if not ResourceLoader.exists(path):
			printerr("Missing ", path)
			continue
		var mesh: ArrayMesh = load(path)
		var faces := mesh.get_faces()
		var tri_count := faces.size() / 3
		print("\n--- %s --- (%d triangles)" % [id, tri_count])

		var unique_normals := {}
		for i in range(tri_count):
			var p0 := faces[i * 3]
			var p1 := faces[i * 3 + 1]
			var p2 := faces[i * 3 + 2]
			var n := (p1 - p0).cross(p2 - p0)
			if n.length_squared() > 1e-8:
				n = n.normalized()
				# Round normal to 2 decimal places to count face orientations
				var key := Vector3(snapped(n.x, 0.05), snapped(n.y, 0.05), snapped(n.z, 0.05))
				unique_normals[key] = unique_normals.get(key, 0) + 1

		print("Unique face normal orientations (top 10):")
		var sorted_keys := unique_normals.keys()
		sorted_keys.sort_custom(func(a, b): return unique_normals[a] > unique_normals[b])
		for k in sorted_keys.slice(0, min(10, sorted_keys.size())):
			print("  Normal %s: %d triangles" % [k, unique_normals[k]])

	quit(0)
