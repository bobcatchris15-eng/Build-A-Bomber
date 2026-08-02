extends SceneTree
# Volume-weighted centroid of a weapon's geometry along its own barrel axis,
# normalised against its front-to-back span. 0.0 = balanced on the trunnion,
# negative = mass biased forward of it (an emitter stuck on a post).
const VisualBuilder = preload("res://scripts/visual_builder.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")

func _init() -> void:
	await process_frame
	var ids: Array = OS.get_cmdline_user_args()
	if ids.is_empty():
		ids = ["heavy_laser", "pd_laser", "coilgun"]
	for type_id in ids:
		var probe := Node3D.new()
		root.add_child(probe)
		var d = ModuleCatalog.get_module_data(type_id)
		VisualBuilder.build_visual(type_id, probe, d.get("size", Vector3.ONE), d.color, {})
		await process_frame
		var acc := Vector3.ZERO
		var total := 0.0
		var min_z := INF
		var max_z := -INF
		for m in probe.find_children("*", "MeshInstance3D", true, false):
			if m.mesh == null: continue
			var a: AABB = m.mesh.get_aabb()
			var sc: Vector3 = m.global_transform.basis.get_scale()
			var vol: float = maxf(0.0001, a.size.x * sc.x) * maxf(0.0001, a.size.y * sc.y) * maxf(0.0001, a.size.z * sc.z)
			var c: Vector3 = m.global_transform * (a.position + a.size * 0.5)
			acc += c * vol
			total += vol
			for i in range(8):
				var corner: Vector3 = m.global_transform * (a.position + Vector3(
					a.size.x * float(i & 1), a.size.y * float((i >> 1) & 1), a.size.z * float((i >> 2) & 1)))
				min_z = minf(min_z, corner.z)
				max_z = maxf(max_z, corner.z)
		var centroid := acc / maxf(total, 0.0001)
		var span: float = maxf(max_z - min_z, 0.0001)
		print("%-18s balance=%+.3f  span=%.2f  z=[%.2f..%.2f]  volume=%.4f" % [
			type_id, -centroid.z / span, span, min_z, max_z, total])
		probe.free()
		await process_frame
	quit()
