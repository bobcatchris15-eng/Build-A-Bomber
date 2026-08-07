extends SceneTree
# Does the battlefield finish actually land on a spawned unit?
#
# It only touches per-instance overrides - writing through a mesh-resource
# material would leak the battle finish into the Design Lab - so it is entirely
# possible for it to run, report nothing, and change no pixels. This counts the
# materials it reached and reads a roughness_bias back off one.

func _init():
	var battle = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	while not battle.world_is_ready:
		await process_frame
	for _i in range(30):
		await process_frame

	var kinds := {}
	var shiny: Array = []
	var checked := 0
	for u in battle.get_tree().get_nodes_in_group("units"):
		for m in _mats(u):
			checked += 1
			_audit(m, "unit", shiny, kinds)
	for st in battle.get_tree().get_nodes_in_group("structures"):
		for m in _mats(st):
			checked += 1
			_audit(m, "structure", shiny, kinds)

	print("  materials audited: %d" % checked)
	for k in kinds:
		print("    %-46s x%d" % [k, kinds[k]])
	print("  STILL SHINY (roughness < %.2f or metallic > %.2f or spec > %.2f): %d"
		% [FLOOR, CEILING, SPEC, shiny.size()])
	for entry in shiny.slice(0, 10):
		print("    %s" % entry)
	print("PASS" if shiny.is_empty() else "FAIL - %d material(s) escaped the finish" % shiny.size())
	quit(0 if shiny.is_empty() else 1)

const FLOOR := 0.82
const CEILING := 0.12
const SPEC := 0.15

# Reads back what is actually on the material. The previous version of this probe
# only looked for a shader parameter and so reported 62 of 64 materials as
# untouched when they had in fact been handled through the StandardMaterial3D
# path - the check has to cover every path the finish takes, or it grades its own
# blind spot.
func _audit(m: Material, owner: String, shiny: Array, kinds: Dictionary) -> void:
	var key: String = m.get_class()
	if m is ShaderMaterial and m.shader != null:
		key = "ShaderMaterial(%s)" % m.shader.resource_path.get_file()
	kinds[key] = kinds.get(key, 0) + 1
	if m is StandardMaterial3D:
		if m.roughness < FLOOR - 0.001 or m.metallic > CEILING + 0.001 				or m.metallic_specular > SPEC + 0.001:
			shiny.append("%s %s rough=%.2f metal=%.2f spec=%.2f"
				% [owner, key, m.roughness, m.metallic, m.metallic_specular])
		return
	if m is ShaderMaterial and m.shader != null:
		var r = m.get_shader_parameter("roughness")
		var mt = m.get_shader_parameter("metallic")
		var ts = m.get_shader_parameter("toon_specular_strength")
		if (r != null and float(r) < FLOOR - 0.001) 				or (mt != null and float(mt) > CEILING + 0.001) 				or (ts != null and float(ts) > 0.11):
			shiny.append("%s %s rough=%s metal=%s toon=%s" % [owner, key, r, mt, ts])

func _mats(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		if node.material_override != null:
			out.append(node.material_override)
		for i in range(node.get_surface_override_material_count()):
			if node.get_surface_override_material(i) != null:
				out.append(node.get_surface_override_material(i))
	for c in node.get_children():
		out.append_array(_mats(c))
	return out

func _resource_mats(node: Node) -> int:
	var n := 0
	if node is MeshInstance3D and node.mesh != null and node.material_override == null:
		n += node.mesh.get_surface_count()
	for c in node.get_children():
		n += _resource_mats(c)
	return n
