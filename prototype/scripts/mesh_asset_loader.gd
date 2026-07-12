# MeshAssetLoader (use via preload, e.g. const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd"))
# Loads authored .glb assets (built by tools/blender/build_meshes.py) and
# hands back a plain Mesh resource, so calling code can keep treating it
# exactly like a procedurally-built CylinderMesh/BoxMesh (assign to
# MeshInstance3D.mesh, then position/rotate/scale/material_override as
# before). Falls back to null if no authored asset exists yet, so
# visual_builder.gd / module_placer.gd can gracefully keep using the
# procedural path for anything not yet upgraded.

static var _cache: Dictionary = {}

static func get_part_mesh(part_name: String) -> Mesh:
	return _load_and_cache("res://assets/models/parts/%s.glb" % part_name)

static func get_hull_mesh(hull_type_id: String) -> Mesh:
	return _load_and_cache("res://assets/models/hulls/%s.glb" % hull_type_id)

static func _load_and_cache(path: String) -> Mesh:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		_cache[path] = null
		return null
	var packed_scene = load(path) as PackedScene
	if not packed_scene:
		_cache[path] = null
		return null
	var instance = packed_scene.instantiate()
	var mesh_inst = _find_first_mesh_instance(instance)
	var mesh: Mesh = mesh_inst.mesh if mesh_inst else null
	instance.free()
	_cache[path] = mesh
	return mesh

static func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found = _find_first_mesh_instance(child)
		if found:
			return found
	return null
