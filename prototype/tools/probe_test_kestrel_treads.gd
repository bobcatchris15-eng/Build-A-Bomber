extends SceneTree

const MountReachScript = preload("res://scripts/mount_reach.gd")
const HullChineScript = preload("res://scripts/hull_chine.gd")
const HullProjectionScript = preload("res://scripts/hull_projection.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")
const LocomotionMountScript = preload("res://scripts/locomotion_mount.gd")

const HULLS_DIR := "res://assets/models/hulls"

func _init():
	print("=== Testing Kestrel Hulls for Tracked Treads ===")
	
	var kestrels := [
		"kestrel_heavy_a.glb",
		"kestrel_light_a.glb",
		"kestrel_light_b.glb",
		"kestrel_light_c.glb",
		"kestrel_medium_a.glb",
		"kestrel_medium_b.glb",
		"kestrel_medium_c.glb",
		"kestrel_oddball_a.glb",
		"kestrel_oddball_b.glb",
		"kestrel_scout_a.glb",
		"kestrel_scout_b.glb",
		"kestrel_scout_c.glb",
		"kestrel_transport_a.glb",
		"kestrel_transport_b.glb",
	]
	
	for glb_name in kestrels:
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
		var station_z = 0.0
		
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
		
		var station = Vector3(station_x, station_y, station_z)
		var surface = MountReachScript.surface_for(null)
		
		print("\n--- %s ---" % glb_name)
		print("AABB: [P: %s, S: %s]" % [aabb.position, aabb.size])
		print("Station: %s" % station)
		print("Chine frame at z=0: pos=%s, normal=%s, belly_drop=%.3f, half_w=%.3f" % [frame["position"], frame["normal"], frame["belly_drop"], frame["half_width"]])
		
		# Test Front Sprocket
		var bottom_front = Vector3(-sprocket_width - w, loop_center_y, front_z)
		var front_hit_count = 0
		var front_candidates = [
			Vector3(-sin(deg_to_rad(40.0)), cos(deg_to_rad(40.0)), 0.55).normalized(),
			Vector3(-sin(deg_to_rad(30.0)), cos(deg_to_rad(30.0)), 0.80).normalized(),
			Vector3(-sin(deg_to_rad(20.0)), cos(deg_to_rad(20.0)), 1.05).normalized(),
			Vector3(-1.0, 0.0, 0.0), # straight inboard
			Vector3(-0.7, 0.7, 0.0).normalized(), # inboard up 45 deg
			Vector3(-0.5, 0.5, 0.7).normalized(),
			Vector3(-0.7, 0.3, 0.6).normalized(),
		]
		for c_dir in front_candidates:
			var l = MountReachScript.solve(null, station, bottom_front, c_dir, -1.0)
			if l > 0.0:
				print("  Front sprocket HIT with dir %s -> len=%.3f" % [c_dir, l])
				front_hit_count += 1
				break
		if front_hit_count == 0:
			print("  [FAIL] Front sprocket MISSED with all candidates!")
			
		# Test Rear Sprocket
		var bottom_rear = Vector3(-sprocket_width - w, loop_center_y, rear_z)
		var rear_hit_count = 0
		var rear_candidates = [
			Vector3(-sin(deg_to_rad(40.0)), cos(deg_to_rad(40.0)), -0.55).normalized(),
			Vector3(-sin(deg_to_rad(30.0)), cos(deg_to_rad(30.0)), -0.80).normalized(),
			Vector3(-sin(deg_to_rad(20.0)), cos(deg_to_rad(20.0)), -1.05).normalized(),
			Vector3(-1.0, 0.0, 0.0),
			Vector3(-0.7, 0.7, 0.0).normalized(),
			Vector3(-0.5, 0.5, -0.7).normalized(),
			Vector3(-0.7, 0.3, -0.6).normalized(),
		]
		for c_dir in rear_candidates:
			var l = MountReachScript.solve(null, station, bottom_rear, c_dir, -1.0)
			if l > 0.0:
				print("  Rear sprocket HIT with dir %s -> len=%.3f" % [c_dir, l])
				rear_hit_count += 1
				break
		if rear_hit_count == 0:
			print("  [FAIL] Rear sprocket MISSED with all candidates!")
			
		# Test Road Wheels
		var wheel_span = span * 0.58
		var wheel_radius_target = VisualBuilder.BELT_ROAD_RADIUS * belt_scale
		var roller_y = loop_center_y - VisualBuilder.BELT_ROAD_DROP * belt_scale
		var wheel_misses = 0
		for i in range(5):
			var z = -wheel_span * 0.5 + (wheel_span * float(i) / 4.0)
			var bottom_wheel = Vector3(-0.3 * (wheel_radius_target / 0.45) - wheel_radius_target * 0.4, roller_y + wheel_radius_target * 0.35, z)
			var w_candidates = [
				Vector3(-sin(deg_to_rad(40.0)), cos(deg_to_rad(40.0)), 0.0).normalized(),
				Vector3(-sin(deg_to_rad(40.0)), cos(deg_to_rad(40.0)), -signf(z) * 0.40).normalized(),
				Vector3(-sin(deg_to_rad(30.0)), cos(deg_to_rad(30.0)), -signf(z) * 0.75).normalized(),
				Vector3(-1.0, 0.0, 0.0), # straight inboard
				Vector3(-0.8, 0.6, 0.0).normalized(),
				Vector3(-0.6, 0.8, 0.0).normalized(),
				Vector3(-0.9, 0.3, 0.0).normalized(),
			]
			var w_hit = false
			for c_dir in w_candidates:
				var l = MountReachScript.solve(null, station, bottom_wheel, c_dir, -1.0)
				if l > 0.0:
					w_hit = true
					break
			if not w_hit:
				wheel_misses += 1
				print("  [FAIL] Wheel %d (z=%.2f) MISSED!" % [i, z])
		if wheel_misses == 0:
			print("  [OK] All 5 road wheels hit.")
		
		hull.free()
		
	quit(0)
