extends SceneTree
# How each locomotion type sits on a reference hull: total vehicle width as a
# multiple of the hull's own, and where the lowest geometry lands relative to
# the ground plane the hull lift is supposed to put it on.
const ModuleCatalog = preload("res://scripts/module_catalog.gd")

func _init() -> void:
	await process_frame
	var hs: Vector3 = ModuleCatalog.REFERENCE_HULL_SIZE
	var ids: Array = []
	for t in ModuleCatalog.get_catalog():
		if ModuleCatalog.get_catalog()[t].get("category", "") == "locomotion":
			ids.append(t)
	ids.sort()
	print("type                 width/hull  span_z/hull  lowest_y  (0.00 = touching ground)")
	for type_id in ids:
		var hull := StaticBody3D.new()
		hull.name = "Hull"
		var mi := MeshInstance3D.new()
		mi.name = "MeshInstance3D"
		var bx := BoxMesh.new(); bx.size = hs; mi.mesh = bx
		hull.add_child(mi)
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
		var b := AABB()
		var seen := false
		for m in hull.find_children("*", "MeshInstance3D", true, false):
			if m.mesh == null: continue
			var xf: Transform3D = m.global_transform
			var part: AABB = xf * m.mesh.get_aabb()
			b = part if not seen else b.merge(part)
			seen = true
		print("%-20s %6.2fx      %6.2fx     %+.3f" % [
			type_id, b.size.x / hs.x, b.size.z / hs.z, b.position.y])
		pl.free(); hull.free()
		await process_frame
	quit()
