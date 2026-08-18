extends SceneTree
# Quick probe: load a hull GLB and print its AABB, then compare to expected.
# Run:
#   Godot_v4.7.1-stable_win64_console.exe --path prototype --script tools/probe_hull_aabb.gd -- --hull=tallow_medium_b

const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var hull_id: String = "tallow_medium_b"
	for a in args:
		if a.begins_with("--hull="):
			hull_id = a.substr("--hull=".length())
	var mesh: Mesh = MeshAssetLoader.get_hull_mesh(hull_id)
	if mesh == null:
		print("[FAIL] no mesh for ", hull_id); quit(1); return
	var aabb: AABB = mesh.get_aabb()
	print("HULL %s aabb=%s min=(%.2f, %.2f, %.2f) max=(%.2f, %.2f, %.2f)" % [
		hull_id, aabb.size,
		aabb.position.x, aabb.position.y, aabb.position.z,
		aabb.position.x + aabb.size.x, aabb.position.y + aabb.size.y, aabb.position.z + aabb.size.z,
	])
	# Count vertices in each Y bucket
	var y_buckets := {}
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for v in verts:
		var bucket: int = int(v.y * 10.0)  # 0.1 unit buckets
		y_buckets[bucket] = y_buckets.get(bucket, 0) + 1
	print("Y BUCKETS (0.1 unit, y*10 -> count):")
	var keys = y_buckets.keys()
	keys.sort()
	for k in keys:
		print("  y=%.1f count=%d" % [float(k)/10.0, y_buckets[k]])
	quit(0)

