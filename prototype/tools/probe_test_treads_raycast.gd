extends SceneTree

const VisualBuilder = preload("res://scripts/visual_builder.gd")
const HullChineScript = preload("res://scripts/hull_chine.gd")
const HullProjectionScript = preload("res://scripts/hull_projection.gd")
const MountReachScript = preload("res://scripts/mount_reach.gd")

func _init():
	var hull_path = "res://assets/models/hulls/brenntal_medium_a.glb"
	var glb: PackedScene = load(hull_path)
	var inst = glb.instantiate()
	var mesh_inst: MeshInstance3D = null
	for child in inst.get_children():
		if child is MeshInstance3D:
			mesh_inst = child
			break
	if not mesh_inst:
		for sub in inst.find_children("*", "MeshInstance3D"):
			mesh_inst = sub
			break

	var profile = HullChineScript.build(mesh_inst)
	var frame = HullChineScript.mount_frame(profile, 0.0, 1.0)
	var aabb = mesh_inst.get_aabb()
	
	var target_length: float = aabb.size.z
	var belt_scale: float = target_length / (VisualBuilder.BELT_HALF_SPAN * 2.0 + VisualBuilder.BELT_DRIVE_RADIUS * 2.0)
	var sprocket_radius: float = VisualBuilder.BELT_DRIVE_RADIUS * belt_scale
	var loop_center_y: float = -sprocket_radius
	var front_z: float = -VisualBuilder.BELT_HALF_SPAN * belt_scale
	var rear_z: float = VisualBuilder.BELT_HALF_SPAN * belt_scale
	var wheel_radius_target: float = VisualBuilder.BELT_ROAD_RADIUS * belt_scale
	var roller_y: float = loop_center_y - VisualBuilder.BELT_ROAD_DROP * belt_scale
	var wheel_span: float = VisualBuilder.BELT_HALF_SPAN * 2.0 * belt_scale * 0.55
	
	# Station positioned at chine X with small clearance, chine Y
	var station_x = float(frame["half_width"]) + 0.04 * aabb.size.x
	var station_y = float(frame["position"].y)
	var station = Vector3(station_x, station_y, 0.0)
	
	var surface = HullProjectionScript.build_surface(mesh_inst)
	
	print("--- Testing Track Mount Solves ---")
	var test_points = [
		{"name": "Front Sprocket", "y": loop_center_y, "z": front_z, "r": sprocket_radius, "dir_z": 0.55},
		{"name": "Rear Sprocket", "y": loop_center_y, "z": rear_z, "r": sprocket_radius, "dir_z": -0.55},
		{"name": "Wheel 0", "y": roller_y, "z": -wheel_span * 0.5, "r": wheel_radius_target, "dir_z": 0.0},
		{"name": "Wheel 2 (mid)", "y": roller_y, "z": 0.0, "r": wheel_radius_target, "dir_z": 0.0},
		{"name": "Wheel 4", "y": roller_y, "z": wheel_span * 0.5, "r": wheel_radius_target, "dir_z": 0.0},
	]
	
	for pt in test_points:
		var r: float = pt["r"]
		var bottom_target = Vector3(-r * 0.40, pt["y"] + r * 0.35, pt["z"])
		var shaft_angle = deg_to_rad(40.0)
		var dir = Vector3(-sin(shaft_angle), cos(shaft_angle), pt["dir_z"]).normalized()
		var ray_from_hull = station + bottom_target
		var hit = HullProjectionScript.raycast(surface, ray_from_hull, dir)
		if hit.get("hit", false):
			var dist = ray_from_hull.distance_to(hit["position"])
			print("[OK] %s: HIT at dist=%.3f, pos=%s" % [pt["name"], dist, hit["position"]])
		else:
			print("[FAIL] %s: MISSED hull" % pt["name"])
			
	inst.free()
	quit(0)
