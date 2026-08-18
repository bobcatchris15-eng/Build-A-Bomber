extends SceneTree
# Print a part mesh's vertex positions in Godot space to understand
# the coordinate conversion from Blender.
# Run: --path prototype --script tools/probe_housing_gd.gd -- --part=missile_pod_housing

const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var part: String = "missile_pod_housing"
	for a in args:
		if a.begins_with("--part="):
			part = a.substr("--part=".length())
	var mesh: Mesh = MeshAssetLoader.get_part_mesh(part)
	if mesh == null:
		print("[FAIL] no mesh for ", part); quit(1); return
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var xs: Array = []
	var ys: Array = []
	var zs: Array = []
	for v in vertices:
		xs.append(v.x)
		ys.append(v.y)
		zs.append(v.z)
	xs.sort()
	ys.sort()
	zs.sort()
	print("PART ", part, " vertex_count=", vertices.size())
	print("  X min=", xs[0], " max=", xs[xs.size() - 1])
	print("  Y min=", ys[0], " max=", ys[ys.size() - 1])
	print("  Z min=", zs[0], " max=", zs[zs.size() - 1])
	# Print 8 corner vertices
	if vertices.size() >= 8:
		print("  first 8 vertices:")
		for i in range(8):
			print("    v", i, " = ", vertices[i])
		# Find the 8 vertices with the maximum Y value
		var sorted_v: Array = []
		for v in vertices:
			sorted_v.append(v)
		sorted_v.sort_custom(func(a, b): return a.y > b.y)
		print("  top 8 by Y:")
		for i in range(min(8, sorted_v.size())):
			print("    y", i, " = ", sorted_v[i])
	quit(0)
