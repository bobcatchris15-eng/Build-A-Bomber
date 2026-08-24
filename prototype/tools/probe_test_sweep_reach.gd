extends SceneTree

const MountReachScript = preload("res://scripts/mount_reach.gd")
const HullChineScript = preload("res://scripts/hull_chine.gd")
const HullProjectionScript = preload("res://scripts/hull_projection.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")
const LocomotionMountScript = preload("res://scripts/locomotion_mount.gd")

const HULLS_DIR := "res://assets/models/hulls"

func _init():
	print("=== Testing Comprehensive Raycast Sweep on All 127 Hulls ===")
	
	var dir = DirAccess.open(HULLS_DIR)
	var files: Array[String] = []
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if fname.ends_with(".glb") and not fname.ends_with("_collision.glb"):
			files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	
	var total_wheels_tested = 0
	var total_wheels_hit = 0
	var total_sprockets_tested = 0
	var total_sprockets_hit = 0
	
	# Build candidate directions:
	# Elevations: 15, 30, 45, 60 deg up; 0 deg horizontal; -15 deg down-inboard
	# Azimuths: straight inboard (0), aft/fwd (+-0.3, +-0.6, +-0.9)
	var get_candidates = func(is_sprocket: bool, z_pos: float) -> Array[Vector3]:
		var list: Array[Vector3] = []
		var z_bias = 0.0
		if is_sprocket:
			z_bias = 0.6 if z_pos < 0.0 else -0.6
		elif absf(z_pos) > 0.1:
			z_bias = -signf(z_pos) * 0.35
			
		var elev_angles = [35.0, 45.0, 25.0, 55.0, 15.0, 0.0]
		var z_offsets = [z_bias, z_bias * 1.4, z_bias * 0.6, 0.0, -z_bias * 0.5]
		for el in elev_angles:
			var r_el = deg_to_rad(el)
			for zo in z_offsets:
				var v = Vector3(-cos(r_el), sin(r_el), zo).normalized()
				if not list.has(v):
					list.append(v)
		return list
	
	for glb_name in files:
		var path = "%s/%s" % [HULLS_DIR, glb_name]
		var glb: PackedScene = load(path)
		if not glb:
			continue
		var hull = glb.instantiate()
		var mesh_inst = MountReachScript._find_mesh_instance(hull)
		if not mesh_inst:
			hull.free()
			continue
			
		MountReachScript.clear_cache()
		MountReachScript.cache_hull(hull)
		
		var aabb = mesh_inst.get_aabb()
		var profile = HullChineScript.build(mesh_inst)
		var frame = HullChineScript.mount_frame(profile, 0.0, 1.0)
		
		var widest_x: float = float(frame.get("half_width", 0.0))
		if profile.has("aabb") and profile["aabb"] is AABB:
			widest_x = maxf(widest_x, (profile["aabb"] as AABB).size.x * 0.5)
		var station_x = widest_x + 0.02
		var station_y = float(frame["position"].y)
		var station = Vector3(station_x, station_y, 0.0)
		
		var target_length = aabb.size.z
		var front_z = -target_length * 0.5
		var rear_z = target_length * 0.5
		var span = target_length
		var belt_scale = span / (VisualBuilder.BELT_HALF_SPAN * 2.0)
		var sprocket_radius = VisualBuilder.BELT_DRIVE_RADIUS * belt_scale
		var sprocket_scale = sprocket_radius / 0.4
		var sprocket_width = 0.3 * sprocket_scale
		var loop_center_y = -sprocket_radius
		var w = sprocket_radius * 1.05
		
		# Test Front Sprocket
		total_sprockets_tested += 1
		var bottom_front = Vector3(-sprocket_width - w, loop_center_y, front_z)
		for c_dir in get_candidates.call(true, front_z):
			var l = MountReachScript.solve(null, station, bottom_front, c_dir, -1.0)
			if l > 0.0:
				total_sprockets_hit += 1
				break
				
		# Test Rear Sprocket
		total_sprockets_tested += 1
		var bottom_rear = Vector3(-sprocket_width - w, loop_center_y, rear_z)
		for c_dir in get_candidates.call(true, rear_z):
			var l = MountReachScript.solve(null, station, bottom_rear, c_dir, -1.0)
			if l > 0.0:
				total_sprockets_hit += 1
				break
				
		# Test Road Wheels
		var wheel_span = span * 0.58
		var wheel_radius_target = VisualBuilder.BELT_ROAD_RADIUS * belt_scale
		var roller_y = loop_center_y - VisualBuilder.BELT_ROAD_DROP * belt_scale
		for i in range(5):
			total_wheels_tested += 1
			var z = -wheel_span * 0.5 + (wheel_span * float(i) / 4.0)
			var bottom_wheel = Vector3(-0.3 * (wheel_radius_target / 0.45) - wheel_radius_target * 0.4, roller_y + wheel_radius_target * 0.35, z)
			for c_dir in get_candidates.call(false, z):
				var l = MountReachScript.solve(null, station, bottom_wheel, c_dir, -1.0)
				if l > 0.0:
					total_wheels_hit += 1
					break
					
		hull.free()
		
	print("Results across all %d hulls:" % files.size())
	print("  Sprockets hit: %d / %d (%.1f%%)" % [total_sprockets_hit, total_sprockets_tested, 100.0 * float(total_sprockets_hit) / float(total_sprockets_tested)])
	print("  Road wheels hit: %d / %d (%.1f%%)" % [total_wheels_hit, total_wheels_tested, 100.0 * float(total_wheels_hit) / float(total_wheels_tested)])
	quit(0)
