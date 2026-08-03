extends SceneTree
const VB = preload("res://scripts/visual_builder.gd")
const MC = preload("res://scripts/module_catalog.gd")
const MAL = preload("res://scripts/mesh_asset_loader.gd")
func _init():
	print("--- does _part(type_id) resolve? ---")
	for id in ["armor_plating","slat_armor","spaced_composite","ablative_foam"]:
		print("  %-20s -> %s" % [id, "FOUND" if MAL.get_part_mesh(id) != null else "MISSING"])
	print("--- what actually gets built ---")
	for id in ["armor_plating","slat_armor","spaced_composite","ablative_foam"]:
		var d = MC.get_module_data(id)
		var n = Node3D.new(); root.add_child(n)
		VB.build_visual(id, n, d.size, d.color, {})
		var meshes = n.find_children("*", "MeshInstance3D", true, false)
		var tris = 0
		for m in meshes:
			if m.mesh: tris += m.mesh.get_faces().size() / 3
		print("  %-20s meshes=%d tris=%d" % [id, meshes.size(), tris])
		n.free()
	quit()
