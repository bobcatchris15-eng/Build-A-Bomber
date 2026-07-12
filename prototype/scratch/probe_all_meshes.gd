extends SceneTree
# Loads every hull + part glb and reports its mesh AABB size, plus
# surface/vertex counts, so we can sanity-check the new geometry against
# module_catalog.gd's expected sizes without needing a real screenshot.

func _init():
	var expectations = {
		"light_hull": Vector3(3.0, 1.0, 4.0),
		"medium_hull": Vector3(4.0, 1.0, 6.0),
		"heavy_hull": Vector3(6.0, 1.5, 8.0),
		"interceptor_hull": Vector3(2.4, 0.8, 3.2),
		"assault_hull": Vector3(5.0, 1.3, 7.0),
		"pillbox_foundation": Vector3(3.0, 1.2, 3.0),
		"tower_foundation": Vector3(3.0, 4.0, 3.0),
	}
	print("--- HULLS ---")
	for hull_name in expectations:
		_check("res://assets/models/hulls/%s.glb" % hull_name, expectations[hull_name])

	print("--- PARTS (existence + basic sanity) ---")
	var dir = DirAccess.open("res://assets/models/parts")
	var ok_count = 0
	var fail_count = 0
	if dir:
		dir.list_dir_begin()
		var fname = dir.get_next()
		while fname != "":
			if fname.ends_with(".glb"):
				var mesh = _load_mesh("res://assets/models/parts/" + fname)
				if mesh:
					var aabb = mesh.get_aabb()
					if aabb.size.length() > 0.001:
						ok_count += 1
					else:
						print("  [WARN] Degenerate AABB: ", fname)
						fail_count += 1
				else:
					print("  [FAIL] Could not load: ", fname)
					fail_count += 1
			fname = dir.get_next()
		dir.list_dir_end()
	print("Parts OK: ", ok_count, " Failed: ", fail_count)
	quit(0 if fail_count == 0 else 1)

func _check(path: String, expected: Vector3):
	var mesh = _load_mesh(path)
	if not mesh:
		print("  [FAIL] Could not load ", path)
		return
	var aabb_size = mesh.get_aabb().size
	var diff = (aabb_size - expected).abs()
	var tol = 0.15
	var status = "OK" if (diff.x < tol and diff.y < tol and diff.z < tol) else "MISMATCH"
	print("  [%s] %s -> AABB %s (expected %s)" % [status, path.get_file(), aabb_size, expected])

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
