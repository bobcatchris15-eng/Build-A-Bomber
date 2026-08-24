extends SceneTree

const MountReachScript = preload("res://scripts/mount_reach.gd")
const HullChineScript = preload("res://scripts/hull_chine.gd")
const HullProjectionScript = preload("res://scripts/hull_projection.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")

func _init():
	print("--- Testing Pinned Corners Track Geometry ---")
	
	var hull_path = "res://assets/models/hulls/brenntal_medium_a.glb"
	var glb: PackedScene = load(hull_path)
	var hull = glb.instantiate()

	MountReachScript.clear_cache()
	MountReachScript.cache_hull(hull)
	
	var mesh_inst = MountReachScript._find_mesh_instance(hull)
	var aabb = mesh_inst.get_aabb()
	var profile = HullChineScript.build(mesh_inst)
	var frame = HullChineScript.mount_frame(profile, 0.0, 1.0)
	
	# Pinned to front and rear corners of visible hull mesh skin
	var station_z = aabb.position.z + aabb.size.z * 0.5 # mid-point
	var front_corner_z = aabb.position.z
	var rear_corner_z = aabb.position.z + aabb.size.z
	
	var front_z = front_corner_z - station_z # -size.z / 2
	var rear_z = rear_corner_z - station_z   # +size.z / 2
	var span = rear_z - front_z             # size.z
	
	var belt_scale = span / (VisualBuilder.BELT_HALF_SPAN * 2.0)
	var sprocket_radius = VisualBuilder.BELT_DRIVE_RADIUS * belt_scale
	var sprocket_scale = sprocket_radius / 0.4
	var sprocket_width = 0.3 * sprocket_scale
	var loop_center_y = -sprocket_radius
	var w = sprocket_radius * 1.05
	
	# Station placed at hull's widest point
	var hull_widest_x = aabb.size.x * 0.5
	var station_x = hull_widest_x + 0.02
	var station_y = float(frame["position"].y)
	
	print("Hull AABB: ", aabb)
	print("Station: (%.2f, %.2f, %.2f)" % [station_x, station_y, station_z])
	print("Front sprocket pinned at z=%.2f (hull front corner is %.2f)" % [front_z, front_corner_z])
	print("Rear sprocket pinned at z=%.2f (hull rear corner is %.2f)" % [rear_z, rear_corner_z])
	print("Belt span: %.2f, belt_scale: %.3f, sprocket_radius: %.3f" % [span, belt_scale, sprocket_radius])
	
	var station = Vector3(station_x, station_y, station_z)
	
	# Test front sprocket reach from inboard face of trapezoid gearbox
	var bottom_target_front = Vector3(-sprocket_width - w, loop_center_y, front_z)
	var shaft_angle = deg_to_rad(40.0)
	var dir_front = Vector3(-sin(shaft_angle), cos(shaft_angle), 0.55).normalized()
	var solved_front = MountReachScript.solve(null, station, bottom_target_front, dir_front, -1.0)
	print("Front sprocket reach solved: %.3f" % solved_front)
	
	# Test rear sprocket reach from inboard face of trapezoid gearbox
	var bottom_target_rear = Vector3(-sprocket_width - w, loop_center_y, rear_z)
	var dir_rear = Vector3(-sin(shaft_angle), cos(shaft_angle), -0.55).normalized()
	var solved_rear = MountReachScript.solve(null, station, bottom_target_rear, dir_rear, -1.0)
	print("Rear sprocket reach solved: %.3f" % solved_rear)
	
	# Test road wheels
	var wheel_span = span * 0.60
	var wheel_radius_target = VisualBuilder.BELT_ROAD_RADIUS * belt_scale
	var roller_y = loop_center_y - VisualBuilder.BELT_ROAD_DROP * belt_scale
	for i in range(5):
		var z = -wheel_span * 0.5 + (wheel_span * float(i) / 4.0)
		var bottom_wheel = Vector3(-0.3 * (wheel_radius_target / 0.45) - wheel_radius_target * 0.5, roller_y + wheel_radius_target * 0.35, z)
		var dir_wheel = Vector3(-sin(shaft_angle), cos(shaft_angle), 0.0).normalized()
		var solved_wheel = MountReachScript.solve(null, station, bottom_wheel, dir_wheel, -1.0)
		print("Wheel %d (z=%.2f) reach solved: %.3f" % [i, z, solved_wheel])

	hull.free()
	quit(0)
