extends SceneTree
const MAL = preload("res://scripts/mesh_asset_loader.gd")
func _init():
	for p in ["autocannon_mount","autocannon_receiver","autocannon_barrel","autocannon_ammo_box"]:
		var m = MAL.get_part_mesh(p)
		if m == null: print(p," MISSING"); continue
		var a = m.get_aabb()
		print("%-22s z: %7.3f .. %7.3f   y: %6.3f .. %6.3f   x: %6.3f .. %6.3f  tris=%d" % [p,
			a.position.z, a.position.z+a.size.z, a.position.y, a.position.y+a.size.y,
			a.position.x, a.position.x+a.size.x, m.get_faces().size()/3])
	quit()
