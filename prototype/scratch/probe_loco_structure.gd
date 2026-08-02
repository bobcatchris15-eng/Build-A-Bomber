extends SceneTree
# Structural sanity check for mounted locomotion, per Chris's three failure
# modes: floating/disconnected pieces, unrealistic sizes, and infrastructure
# that is either too fragile or too bulky to be plausible.
#
# Done by measurement rather than by eye, because there are 17 types x 3 views
# and the interesting failures are small gaps that a screenshot hides behind
# whatever is in front of them.
#
#   ATTACH GAP   distance from the module's topmost geometry up to the hull's
#                underside. Anything above ~0.05 is running gear hanging in
#                space with nothing joining it to the vehicle.
#   SPLIT GAP    the largest empty span between adjacent sub-parts down the
#                module's own vertical axis. This is what catches a wheel that
#                is fine at the hub and fine at the rim but has nothing in
#                between - the "disconnected pieces" case.
#   BULK         module volume as a fraction of the hull's own. A locomotor
#                that is a third of the vehicle by volume reads as heavier than
#                the thing it is carrying.
#   SLENDER      thinnest cross-section anywhere in the load path, against the
#                span it is carrying. Low means spindly, high means a girder
#                where a strut belongs.

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")

const ATTACH_GAP_LIMIT := 0.05
const SPLIT_GAP_LIMIT := 0.18
const BULK_LIMIT := 0.28
const SLENDER_MIN := 0.045


func _part_boxes(module: Node3D) -> Array:
	var out: Array = []
	for m in module.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var walker: Node = m
		while walker != null and walker != module:
			if walker is Node3D:
				xf = walker.transform * xf
			walker = walker.get_parent()
		out.append(xf * m.mesh.get_aabb())
	return out


func _init() -> void:
	await process_frame
	var hs: Vector3 = ModuleCatalog.REFERENCE_HULL_SIZE
	var hull_vol: float = hs.x * hs.y * hs.z
	var ids: Array = []
	for t in ModuleCatalog.get_catalog():
		if ModuleCatalog.get_catalog()[t].get("category", "") == "locomotion":
			ids.append(t)
	ids.sort()

	print("type                 attach_gap  split_gap   bulk   slender   verdict")
	for type_id in ids:
		var hull := StaticBody3D.new()
		hull.name = "Hull"
		hull.set_meta("type_id", "medium_hull")
		var cs := CollisionShape3D.new(); cs.name = "CollisionShape3D"
		var cb := BoxShape3D.new(); cb.size = hs; cs.shape = cb
		hull.add_child(cs)
		root.add_child(hull)
		var pl := Node3D.new()
		pl.set_script(load("res://scripts/module_placer.gd"))
		pl.hull = hull
		root.add_child(pl)
		await process_frame
		pl.update_locomotion(type_id, {})
		await process_frame

		var hull_bottom: float = -hs.y * 0.5
		var worst_attach := 0.0
		var worst_split := 0.0
		var total_vol := 0.0
		var thinnest := 999.0
		var counted := 0

		for child in hull.get_children():
			if not child.has_meta("module_data"):
				continue
			var md = child.get_meta("module_data")
			if md == null or md.category != "locomotion":
				continue
			counted += 1
			var boxes: Array = _part_boxes(child)
			if boxes.is_empty():
				continue
			# ATTACH GAP - only meaningful for gear that hangs BELOW the hull.
			var top := -999.0
			for b in boxes:
				var bb: AABB = b
				top = maxf(top, child.position.y + (bb.position.y + bb.size.y) * child.scale.y)
			if child.position.y < hull_bottom:
				worst_attach = maxf(worst_attach, absf(hull_bottom - top))
			# SPLIT GAP - sort the sub-parts by vertical extent and look for a
			# span with nothing in it.
			var spans: Array = []
			for b in boxes:
				var bb2: AABB = b
				var lo: float = bb2.position.y * child.scale.y
				spans.append([lo, lo + bb2.size.y * child.scale.y])
				total_vol += bb2.size.x * bb2.size.y * bb2.size.z \
					* child.scale.x * child.scale.y * child.scale.z
				var cross: float = minf(bb2.size.x * child.scale.x, bb2.size.z * child.scale.z)
				if bb2.size.y * child.scale.y > 0.25:
					thinnest = minf(thinnest, cross)
			spans.sort_custom(func(a, b): return a[0] < b[0])
			var reach := -999.0
			for sp in spans:
				if reach > -998.0 and sp[0] - reach > worst_split:
					worst_split = sp[0] - reach
				reach = maxf(reach, sp[1])

		var bulk: float = total_vol / maxf(hull_vol, 0.0001)
		if thinnest > 998.0:
			thinnest = 0.0
		var flags: Array = []
		if worst_attach > ATTACH_GAP_LIMIT:
			flags.append("FLOATING")
		if worst_split > SPLIT_GAP_LIMIT:
			flags.append("DISCONNECTED")
		if bulk > BULK_LIMIT:
			flags.append("BULKY")
		if thinnest > 0.0 and thinnest < SLENDER_MIN:
			flags.append("FRAGILE")
		print("%-20s %8.3f   %8.3f  %6.3f  %7.3f   %s" % [
			type_id, worst_attach, worst_split, bulk, thinnest,
			"ok" if flags.is_empty() else ", ".join(flags)])

		pl.free()
		hull.free()
		await process_frame
	quit()
