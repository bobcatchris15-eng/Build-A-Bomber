extends SceneTree
# Reports the triangle count of every authored part mesh, heaviest first, so
# decimation effort goes where the triangles actually are rather than where the
# model looks complicated.

const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")

func _init() -> void:
	var dir := DirAccess.open("res://assets/models/parts")
	if dir == null:
		print("no parts dir")
		quit()
		return
	var rows := []
	var total := 0
	for f in dir.get_files():
		if not f.ends_with(".glb"):
			continue
		var id := f.get_basename()
		var mesh: Mesh = MeshAssetLoader.get_part_mesh(id)
		if mesh == null:
			rows.append([-1, id, Vector3.ZERO])
			continue
		var tris := mesh.get_faces().size() / 3
		total += tris
		rows.append([tris, id, mesh.get_aabb().size])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("part_id, tris, aabb")
	for r in rows:
		print("%-28s %6d   %s" % [r[1], r[0], str(r[2])])
	print("TOTAL %d tris across %d parts" % [total, rows.size()])
	quit()
