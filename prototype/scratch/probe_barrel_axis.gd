extends SceneTree
# Verify build_barrel's authored orientation: the mesh should extend
# primarily along local Y (length ~1.0, base near y=0) with a small radius
# in X/Z, matching Godot's own CylinderMesh default axis convention that
# visual_builder.gd's runtime PI/2 X rotation expects.

func _init():
	var mesh = _load_mesh("res://assets/models/parts/barrel_standard.glb")
	if not mesh:
		print("[BARREL-PROBE] Could not load barrel_standard.glb")
		quit(1)
		return
	var aabb = mesh.get_aabb()
	print("[BARREL-PROBE] barrel_standard AABB position: ", aabb.position, " size: ", aabb.size)
	var is_y_length = aabb.size.y > aabb.size.x and aabb.size.y > aabb.size.z
	var base_near_origin = aabb.position.y < 0.05 and aabb.position.y > -0.05
	print("[BARREL-PROBE] Y is the long axis: ", is_y_length, " | base near y=0: ", base_near_origin)
	quit(0 if (is_y_length and base_near_origin) else 1)

func _load_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var packed = load(path)
	if packed == null:
		return null
	var inst = packed.instantiate()
	var mesh_inst = _find_mesh(inst)
	var mesh = mesh_inst.mesh if mesh_inst else null
	inst.free()
	return mesh

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var f = _find_mesh(child)
		if f: return f
	return null
