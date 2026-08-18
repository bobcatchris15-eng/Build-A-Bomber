extends SceneTree
# Print a part mesh's local AABB so we can see what the GLB actually contains.
# Run: --path prototype --script tools/probe_part_aabb.gd -- --part=missile_pod_missile

const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var part: String = "missile_pod_missile"
	for a in args:
		if a.begins_with("--part="):
			part = a.substr("--part=".length())
	var mesh: Mesh = MeshAssetLoader.get_part_mesh(part)
	if mesh == null:
		print("[FAIL] no mesh for ", part); quit(1); return
	var aabb: AABB = mesh.get_aabb()
	print("PART %s aabb=%s min=(%.3f, %.3f, %.3f) max=(%.3f, %.3f, %.3f)" % [
		part, aabb.size,
		aabb.position.x, aabb.position.y, aabb.position.z,
		aabb.position.x + aabb.size.x, aabb.position.y + aabb.size.y, aabb.position.z + aabb.size.z,
	])
	quit(0)
