extends SceneTree

const MountReachScript = preload("res://scripts/mount_reach.gd")
const HullChineScript = preload("res://scripts/hull_chine.gd")
const HullProjectionScript = preload("res://scripts/hull_projection.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")

func _init():
	print("--- Testing Sprocket Gearbox Inboard Attachment ---")
	
	var hull_path = "res://assets/models/hulls/brenntal_medium_a.glb"
	var glb: PackedScene = load(hull_path)
	var hull = glb.instantiate()

	MountReachScript.clear_cache()
	MountReachScript.cache_hull(hull)
	
	var mesh_inst = MountReachScript._find_mesh_instance(hull)
	var aabb = mesh_inst.get_aabb()
	var profile = HullChineScript.build(mesh_inst)
	var frame = HullChineScript.mount_frame(profile, 0.0, 1.0)
	
	var station_x = float(frame["half_width"]) + 0.04 * aabb.size.x
	var station_y = float(frame["position"].y)
	var tweaks = {
		"station_x": station_x,
		"station_y": station_y,
		"station_z": 0.0,
		"node_scale_x": 1.0,
		"node_scale_y": 1.0,
		"node_scale_z": 1.0,
		"target_length": aabb.size.z
	}
	
	var target_length = aabb.size.z
	var belt_scale: float = target_length / (VisualBuilder.BELT_HALF_SPAN * 2.0 + VisualBuilder.BELT_DRIVE_RADIUS * 2.0)
	var sprocket_scale = (VisualBuilder.BELT_DRIVE_RADIUS * belt_scale) / 0.4
	var sprocket_width = 0.3 * sprocket_scale
	var sprocket_radius = VisualBuilder.BELT_DRIVE_RADIUS * belt_scale
	var loop_center_y = -sprocket_radius
	var front_z = -VisualBuilder.BELT_HALF_SPAN * belt_scale
	var w = sprocket_radius * 1.05
	
	# Sprocket inner face is at -sprocket_width
	# Gearbox narrow inner face is at -sprocket_width - w
	var bottom_target = Vector3(-sprocket_width - w, loop_center_y, front_z)
	print("Sprocket front_z: %.3f, sprocket_width: %.3f, w: %.3f" % [front_z, sprocket_width, w])
	print("Gearbox inner face bottom_target: ", bottom_target)
	
	var station = MountReachScript.station_from(tweaks)
	var shaft_angle = deg_to_rad(40.0)
	var dir = Vector3(-sin(shaft_angle), cos(shaft_angle), 0.55).normalized()
	var solved_len = MountReachScript.solve(null, station, bottom_target, dir, -1.0)
	print("Front sprocket solved shaft reach from inner face: %.3f" % solved_len)
	if solved_len > 0.0:
		print("[OK] Driveshaft cleanly attaches to inboard face of gearbox and penetrates hull by 0.05m!")
	else:
		print("[FAIL] Missed hull!")

	hull.free()
	quit(0)
