extends SceneTree
const MAL = preload("res://scripts/mesh_asset_loader.gd")
func _init():
	for p in ["amr_breech", "amr_barrel", "amr_muzzle_brake", "amr_sensor_pod", "amr_mount"]:
		var m = MAL.get_part_mesh(p)
		if m == null:
			print(p, " MISSING"); continue
		var a = m.get_aabb()
		print("%-18s pos=(%.3f, %.3f, %.3f) size=(%.3f, %.3f, %.3f)  z: %.3f .. %.3f" % [
			p, a.position.x, a.position.y, a.position.z, a.size.x, a.size.y, a.size.z,
			a.position.z, a.position.z + a.size.z])
	quit()
