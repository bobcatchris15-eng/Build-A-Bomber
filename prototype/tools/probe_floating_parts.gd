extends SceneTree
# Detects "floating" parts in modular weapon assemblies.
#
# A part is flagged when two meshes in the same module's visual tree are stacked
# (X/Z projections overlap) and the Y-gap between them is larger than a sane
# tolerance for that module's overall size. The 6 guided-missile launchers
# (hvm / sam / loitering / arm / bunker_buster / cruise_missile) and the
# sensor_beacon_launcher are the known-floating cases - this probe is to
# catch any others, not just those.
#
# Build pattern matches module_placer.gd:898-901 and part_thumbnail.gd:236-240:
# fresh Node3D, hand it to VisualBuilder.build_visual, walk the tree.
#
# Run:
#   Godot_v4.7.1-stable_win64_console.exe --path prototype --script tools/probe_floating_parts.gd

const VisualBuilder = preload("res://scripts/visual_builder.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")

# Two stacked meshes are considered "floating" when the Y gap between them
# is larger than this fraction of the LARGER mesh's height. 8% reads as a
# visible disconnection in screenshots at typical RTS camera distances.
const RELATIVE_GAP_THRESHOLD := 0.08
# Absolute minimum - sub-2cm gaps aren't worth reporting even on tiny modules.
const ABSOLUTE_GAP_THRESHOLD := 0.02
# X/Z overlap must be at least this fraction of the smaller mesh's footprint
# for the pair to count as "stacked" (otherwise they're side-by-side, not
# stacked, and the gap is just air between them).
const XZ_OVERLAP_THRESHOLD := 0.30


func _init() -> void:
	# Every weapon type_id. The catalog's "category" == "weapon" filter
	# matches the same set the visual builder cares about. Pulling from
	# the catalog directly keeps this list in sync as new weapons land.
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
		print("[OK] no floating parts detected across %d weapon types" % type_ids.size())
		quit(0)
		return

	print("[FAIL] %d floating-part finding(s) across %d weapon types:" % [findings.size(), type_ids.size()])
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
	# Force the engine to register the new node tree before we ask for AABBs.
	await process_frame

	var meshes: Array = _collect_meshes(parent)
	if meshes.size() < 2:
		parent.queue_free()
		return []

	var aabbs: Array = []
	for m in meshes:
		aabbs.append(_world_aabb(m))

	# Module's overall Y extent gives the "larger mesh's height" reference for
	# the relative-gap threshold.
	var module_aabb: AABB = _total_aabb(aabbs)
	var absolute_tolerance: float = maxf(ABSOLUTE_GAP_THRESHOLD, module_aabb.size.y * RELATIVE_GAP_THRESHOLD)

	var findings: Array = []
	for i in range(meshes.size()):
		for j in range(meshes.size()):
			if i == j:
				continue
			var a: AABB = aabbs[i]
			var b: AABB = aabbs[j]
			var overlap: float = _xz_overlap_fraction(a, b)
			if overlap < XZ_OVERLAP_THRESHOLD:
				continue
			# The lower box's top and the upper box's bottom.
			var a_below_b: bool = (a.position.y + a.size.y) <= b.position.y
			var b_below_a: bool = (b.position.y + b.size.y) <= a.position.y
			if not a_below_b and not b_below_a:
				continue  # AABBs intersect in Y already - not a gap.
			var gap: float
			var lower_top: float
			var upper_bottom: float
			if a_below_b:
				lower_top = a.position.y + a.size.y
				upper_bottom = b.position.y
			else:
				lower_top = b.position.y + b.size.y
				upper_bottom = a.position.y
			gap = upper_bottom - lower_top
			if gap < absolute_tolerance:
				continue
			var lower_label: String = _label(meshes[i if a_below_b else j])
			var upper_label: String = _label(meshes[j if a_below_b else i])
			findings.append({
				"type_id": type_id,
				"summary": "gap=%.3f between '%s' (top y=%.3f) and '%s' (bottom y=%.3f), xz overlap=%.2f" % [
					gap, lower_label, lower_top, upper_label, upper_bottom, overlap,
				],
				"gap": gap,
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
	# mi.get_aabb() returns the mesh's local-space AABB. To get the world
	# AABB we transform all 8 corners by the instance's global transform and
	# take the envelope - tight AABB even when the mesh is rotated.
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


func _xz_overlap_fraction(a: AABB, b: AABB) -> float:
	var ax_range: float = _overlap_1d(a.position.x, a.position.x + a.size.x, b.position.x, b.position.x + b.size.x)
	var az_range: float = _overlap_1d(a.position.z, a.position.z + a.size.z, b.position.z, b.position.z + b.size.z)
	if ax_range <= 0.0 or az_range <= 0.0:
		return 0.0
	var a_w: float = maxf(a.size.x, 0.001)
	var a_d: float = maxf(a.size.z, 0.001)
	var b_w: float = maxf(b.size.x, 0.001)
	var b_d: float = maxf(b.size.z, 0.001)
	var x_frac: float = ax_range / minf(a_w, b_w)
	var z_frac: float = az_range / minf(a_d, b_d)
	return sqrt(x_frac * z_frac)


func _overlap_1d(lo1: float, hi1: float, lo2: float, hi2: float) -> float:
	return maxf(0.0, minf(hi1, hi2) - maxf(lo1, lo2))


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
