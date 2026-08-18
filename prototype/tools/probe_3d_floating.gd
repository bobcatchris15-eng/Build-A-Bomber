extends SceneTree
# 3D AABB-distance floating-parts probe.
#
# The vertical-gap probe (probe_floating_parts.gd) only catches parts
# that are stacked in Y with XZ overlap. The two guided-launcher
# floating cases the user spotted - loitering_munition and
# sensor_beacon_launcher - have body and round at the same Y level but
# offset in X-Z (the body sits at the pivot and the canted tube
# projects forward+up, leaving the tube base hovering off-axis from the
# body's trunnion). The vertical probe sees Y overlap and skips them.
#
# This probe measures the 3D AABB distance (Euclidean distance between
# the closest points of two AABBs) and flags any pair whose distance
# exceeds a threshold tied to the module's overall size. Catches both
# vertical and X-Z offset gaps. The threshold is the same RELATIVE
# fraction as the vertical probe so the two probes are comparable.
#
# Known false positives the probe WILL flag and we accept:
#   * rotary_cannon barrel ring (top-bottom Y gap inside the ring,
#     centre filled by the clamp ring)
#   * tesla_coil mount vs toroid (housing column connects them in the
#     visual tree, but the probe checks raw AABBs)
#   * missile_pod mount vs row 1/2 missiles (missiles sit inside the
#     housing shell, which is connected to the mount via the brackets)
#
# Run:
#   Godot_v4.7.1-stable_win64_console.exe --path prototype --script tools/probe_3d_floating.gd

const VisualBuilder = preload("res://scripts/visual_builder.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")

const RELATIVE_GAP_THRESHOLD := 0.08
const ABSOLUTE_GAP_THRESHOLD := 0.02

func _init() -> void:
	var cat: Dictionary = ModuleCatalog.get_catalog()
	var type_ids: Array = []
	for type_id in cat.keys():
		if cat[type_id].get("category", "") == "weapon":
			type_ids.append(type_id)
	type_ids.sort()

	var findings: Array = []
	for type_id in type_ids:
		var result: Array = await _inspect(type_id)
		for f in result:
			findings.append(f)

	if findings.is_empty():
		print("[OK] no 3d-distance floating parts across %d weapon types" % type_ids.size())
		quit(0)
		return

	print("[FAIL] %d 3d-distance floating-part finding(s) across %d weapon types:" % [findings.size(), type_ids.size()])
	for f in findings:
		print("  %s: %s" % [f["type_id"], f["summary"]])
	quit(1)


func _inspect(type_id: String) -> Array:
	var cat: Dictionary = ModuleCatalog.get_catalog()
	var data: Dictionary = cat.get(type_id, {})
	var base_size: Vector3 = data.get("size", Vector3.ONE)
	var base_color: Color = data.get("color", Color.WHITE)
	var tweaks: Dictionary = {}

	var parent := Node3D.new()
	root.add_child(parent)
	VisualBuilder.build_visual(type_id, parent, base_size, base_color, tweaks)
	await process_frame

	var meshes: Array = _collect_meshes(parent)
	if meshes.size() < 2:
		parent.queue_free()
		return []

	var aabbs: Array = []
	for m in meshes:
		aabbs.append(_world_aabb(m))

	var module_aabb: AABB = _total_aabb(aabbs)
	var module_max: float = maxf(module_aabb.size.x, maxf(module_aabb.size.y, module_aabb.size.z))
	var threshold: float = maxf(ABSOLUTE_GAP_THRESHOLD, module_max * RELATIVE_GAP_THRESHOLD)

	var findings: Array = []
	for i in range(meshes.size()):
		for j in range(i + 1, meshes.size()):
			var a: AABB = aabbs[i]
			var b: AABB = aabbs[j]
			var dist: float = _aabb_distance(a, b)
			if dist < threshold:
				continue
			findings.append({
				"type_id": type_id,
				"summary": "dist=%.3f (threshold=%.3f) between '%s' aabb=(%.2f,%.2f,%.2f)+(%0.2f,%0.2f,%0.2f) and '%s' aabb=(%.2f,%.2f,%.2f)+(%0.2f,%0.2f,%0.2f)" % [
					dist, threshold,
					_label(meshes[i]), aabbs[i].position.x, aabbs[i].position.y, aabbs[i].position.z, aabbs[i].size.x, aabbs[i].size.y, aabbs[i].size.z,
					_label(meshes[j]), aabbs[j].position.x, aabbs[j].position.y, aabbs[j].position.z, aabbs[j].size.x, aabbs[j].size.y, aabbs[j].size.z,
				],
			})

	parent.queue_free()
	return findings


func _collect_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for c in node.get_children():
		out.append_array(_collect_meshes(c))
	return out


func _world_aabb(mi: MeshInstance3D) -> AABB:
	var local: AABB = mi.get_aabb()
	if local.size == Vector3.ZERO:
		return local
	var xf: Transform3D = mi.global_transform
	var corners: Array[Vector3] = []
	for cx in [local.position.x, local.position.x + local.size.x]:
		for cy in [local.position.y, local.position.y + local.size.y]:
			for cz in [local.position.z, local.position.z + local.size.z]:
				corners.append(xf * Vector3(cx, cy, cz))
	var lo: Vector3 = corners[0]
	var hi: Vector3 = corners[0]
	for c in corners:
		lo = Vector3(minf(lo.x, c.x), minf(lo.y, c.y), minf(lo.z, c.z))
		hi = Vector3(maxf(hi.x, c.x), maxf(hi.y, c.y), maxf(hi.z, c.z))
	return AABB(lo, hi - lo)


func _total_aabb(aabbs: Array) -> AABB:
	if aabbs.is_empty():
		return AABB()
	var lo: Vector3 = aabbs[0].position
	var hi: Vector3 = aabbs[0].position + aabbs[0].size
	for a in aabbs.slice(1):
		lo = Vector3(minf(lo.x, a.position.x), minf(lo.y, a.position.y), minf(lo.z, a.position.z))
		hi = Vector3(maxf(hi.x, a.position.x + a.size.x), maxf(hi.y, a.position.y + a.size.y), maxf(hi.z, a.position.z + a.size.z))
	return AABB(lo, hi - lo)


# Standard 3D AABB distance: 0 if the boxes overlap, otherwise the
# Euclidean distance between the closest points on each box. The
# per-axis gap is the unsigned distance between the closest faces.
func _aabb_distance(a: AABB, b: AABB) -> float:
	var dx: float = maxf(0.0, maxf(a.position.x, b.position.x) - minf(a.position.x + a.size.x, b.position.x + b.size.x))
	var dy: float = maxf(0.0, maxf(a.position.y, b.position.y) - minf(a.position.y + a.size.y, b.position.y + b.size.y))
	var dz: float = maxf(0.0, maxf(a.position.z, b.position.z) - minf(a.position.z + a.size.z, b.position.z + b.size.z))
	return sqrt(dx * dx + dy * dy + dz * dz)


func _label(node: Node) -> String:
	if node.name != "" and not node.name.begins_with("@"):
		return node.name
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_name: String = (node as MeshInstance3D).mesh.resource_name
		if mesh_name != "":
			return mesh_name
		var path: String = (node as MeshInstance3D).mesh.resource_path
		if path != "":
			return path.get_file().get_basename()
	return "<unnamed>"
