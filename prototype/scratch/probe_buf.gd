extends SceneTree
const MAL = preload("res://scripts/mesh_asset_loader.gd")
func _init():
	for p in ["amr_buffer", "amr_sensor_pod", "amr_breech"]:
		var m = MAL.get_part_mesh(p)
		if m == null: print(p, " MISSING"); continue
		var a = m.get_aabb()
		print("%-16s z: %.3f .. %.3f   x: %.3f .. %.3f   y: %.3f .. %.3f" % [p,
			a.position.z, a.position.z+a.size.z, a.position.x, a.position.x+a.size.x,
			a.position.y, a.position.y+a.size.y])
	quit()
