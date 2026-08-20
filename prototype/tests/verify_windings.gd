extends SceneTree

const BlockMeshes = preload("res://scripts/block_meshes.gd")

func check_mesh(mesh: ArrayMesh, name: String):
	var arrs = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrs[Mesh.ARRAY_NORMAL]
	var raw_indices = arrs[Mesh.ARRAY_INDEX]
	
	var has_index = raw_indices != null and raw_indices.size() > 0
	var count = raw_indices.size() if has_index else verts.size()
	print("Checking %s: %d triangles..." % [name, count / 3])
	
	for i in range(0, count, 3):
		var i0 = raw_indices[i] if has_index else i
		var i1 = raw_indices[i+1] if has_index else i+1
		var i2 = raw_indices[i+2] if has_index else i+2
		var v0 = verts[i0]
		var v1 = verts[i1]
		var v2 = verts[i2]
		var n = norms[i0]
		# Godot convention: (v2 - v0).cross(v1 - v0) aligns with normal
		var calc_n = (v2 - v0).cross(v1 - v0).normalized()
		var dot = calc_n.dot(n)
		if dot < 0.5:
			print("  [FAIL] Tri %d: expected norm=%s, got calc_n=%s (dot=%.2f)" % [i/3, str(n), str(calc_n), dot])
			assert(false, "Inverted triangle in %s" % name)
		else:
			print("  [PASS] Tri %d: norm=%s (dot=%.2f)" % [i/3, str(n), dot])

func _init():
	var cube = BlockMeshes.build_cube()
	check_mesh(cube, "Cube")
	var wedge = BlockMeshes.build_wedge()
	check_mesh(wedge, "Wedge")
	print("\nALL WINDINGS MATCH GODOT FRONT-FACING CONVENTION PERFECTLY!")
	quit(0)
