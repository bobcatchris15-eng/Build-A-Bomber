extends SceneTree
const VB = preload("res://scripts/visual_builder.gd")
const MC = preload("res://scripts/module_catalog.gd")

# Volume-weighted centroid of a built module, in module-local space.
# Each mesh contributes its own AABB volume as the weight, which is a decent
# proxy for mass on parts that are all roughly the same density steel.
func centroid(n: Node3D) -> Dictionary:
	var total := 0.0
	var acc := Vector3.ZERO
	var reach_fwd := 0.0
	var reach_aft := 0.0
	for m in n.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null: continue
		var a: AABB = m.mesh.get_aabb()
		var sc = m.global_transform.basis.get_scale()
		var vol = maxf(0.0001, a.size.x * sc.x) * maxf(0.0001, a.size.y * sc.y) * maxf(0.0001, a.size.z * sc.z)
		var c = m.global_transform * (a.position + a.size * 0.5)
		acc += c * vol
		total += vol
		var zmin = (m.global_transform * a.position).z
		var zmax = (m.global_transform * (a.position + a.size)).z
		reach_fwd = minf(reach_fwd, minf(zmin, zmax))
		reach_aft = maxf(reach_aft, maxf(zmin, zmax))
	return {"c": acc / maxf(0.0001, total), "fwd": reach_fwd, "aft": reach_aft}

func _init():
	var ids := []
	for id in MC.get_catalog().keys():
		if MC.get_module_data(id).get("category","") == "weapon":
			ids.append(id)
	ids.sort()
	print("%-24s %8s %8s %8s   %s" % ["weapon", "cog.z", "fwd", "aft", "balance"])
	for id in ids:
		var d = MC.get_module_data(id)
		var n = Node3D.new()
		root.add_child(n)
		VB.build_visual(id, n, d.size, d.color, {})
		var r = centroid(n)
		var span = r.aft - r.fwd
		# Normalised: 0 = balanced on the mount, -1 = all mass at the muzzle.
		var bal = (r.c.z - 0.0) / maxf(0.001, span * 0.5)
		var flag = ""
		if absf(bal) > 0.45: flag = "  <-- NOSE-HEAVY" if bal < 0.0 else "  <-- TAIL-HEAVY"
		print("%-24s %8.3f %8.3f %8.3f   %+.2f%s" % [id, r.c.z, r.fwd, r.aft, bal, flag])
		n.free()
	quit()
