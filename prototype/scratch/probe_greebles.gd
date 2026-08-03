extends SceneTree
const AG = preload("res://scripts/armor_greebles.gd")
func _init():
	for mat in ["hardened_steel","reactive_armor","ablative_ceramic","energy_shielding"]:
		var hull = Node3D.new()
		root.add_child(hull)
		var mi = MeshInstance3D.new()
		var bm = BoxMesh.new(); bm.size = Vector3(4,1.4,6)
		mi.mesh = bm
		hull.add_child(mi)
		AG.apply(hull, mat, Vector3(4,1.4,6))
		var c = hull.get_node_or_null("ArmorGreebles")
		var n = 0; var shield = false
		if c:
			for ch in c.find_children("*", "MeshInstance3D", true, false):
				n += 1
				if ch.name == "EnergyShield": shield = true
		print("%-18s greebles=%3d shield=%s" % [mat, n, str(shield)])
		hull.free()
	quit()
