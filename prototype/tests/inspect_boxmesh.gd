extends SceneTree

func _init():
	var bm := BoxMesh.new()
	var arrs := bm.get_mesh_arrays()
	var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrs[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrs[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrs[Mesh.ARRAY_INDEX]
	
	print("BoxMesh has %d verts, %d indices" % [verts.size(), indices.size()])
	for i in range(0, indices.size(), 3):
		var i0 = indices[i]
		var i1 = indices[i+1]
		var i2 = indices[i+2]
		var v0 = verts[i0]
		var v1 = verts[i1]
		var v2 = verts[i2]
		var n = norms[i0]
		var calc_n = (v1 - v0).cross(v2 - v0).normalized()
		var dot = calc_n.dot(n)
		print("Tri %d: norm=%s, calc_norm=%s, dot=%.2f" % [i/3, str(n), str(calc_n), dot])
	quit(0)
