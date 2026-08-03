extends SceneTree
const AG = preload("res://scripts/armor_greebles.gd")
func _init():
	# Does the ellipsoid actually contain the hull's eight corners?
	for size in [Vector3(4,1.4,6), Vector3(2,1,3), Vector3(6,2.5,9)]:
		var hull = Node3D.new(); root.add_child(hull)
		var mi = MeshInstance3D.new(); var bm = BoxMesh.new(); bm.size = size
		mi.mesh = bm; hull.add_child(mi)
		AG.apply(hull, "energy_shielding", size)
		var b = hull.get_node("ArmorGreebles").get_node_or_null("EnergyShield")
		var worst = 0.0
		for sx in [-1.0,1.0]:
			for sy in [-1.0,1.0]:
				for sz in [-1.0,1.0]:
					var c = Vector3(sx*size.x*0.5, sy*size.y*0.5, sz*size.z*0.5) - b.position
					var v = Vector3(c.x/b.scale.x, c.y/b.scale.y, c.z/b.scale.z)
					worst = maxf(worst, v.length_squared())
		print("hull %s -> worst corner %.3f  %s" % [str(size), worst, "CONTAINED" if worst <= 1.0 else "POKES THROUGH"])
		hull.free()
	quit()
