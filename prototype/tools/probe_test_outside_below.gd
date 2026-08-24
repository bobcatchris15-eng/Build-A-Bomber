extends SceneTree

const MountReachScript = preload("res://scripts/mount_reach.gd")
const HullChineScript = preload("res://scripts/hull_chine.gd")
const HullProjectionScript = preload("res://scripts/hull_projection.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")
const LocomotionMountScript = preload("res://scripts/locomotion_mount.gd")

func _init():
	print("--- Testing Outside & Below Track Alignment ---")
	
	for hull_name in ["brenntal_medium_a.glb", "kestrel_heavy_a.glb", "kestrel_oddball_a.glb"]:
		var hull_path = "res://assets/models/hulls/" + hull_name
		var glb: PackedScene = load(hull_path)
		var hull = glb.instantiate()
		
		MountReachScript.clear_cache()
		MountReachScript.cache_hull(hull)
		
		var mesh_inst = MountReachScript._find_mesh_instance(hull)
		var aabb = mesh_inst.get_aabb()
		var profile = HullChineScript.build(mesh_inst)
		var frame = HullChineScript.mount_frame(profile, 0.0, 1.0)
		
		var target_length = aabb.size.z
		var front_z = -target_length * 0.5
		var rear_z = target_length * 0.5
		var span = target_length
		
		var belt_scale = span / (VisualBuilder.BELT_HALF_SPAN * 2.0)
		var sprocket_radius = VisualBuilder.BELT_DRIVE_RADIUS * belt_scale
		var sprocket_scale = (VisualBuilder.BELT_DRIVE_RADIUS * belt_scale) / 0.4
		var sprocket_width = 0.3 * sprocket_scale
		var loop_center_y = -sprocket_radius
		var w = sprocket_radius * 1.05
		
		# Outboard placement: entire track sits outside the widest point of hull
		var widest_x: float = float(frame.get("half_width", 0.0))
		if profile.has("aabb") and profile["aabb"] is AABB:
			widest_x = maxf(widest_x, (profile["aabb"] as AABB).size.x * 0.5)
		
		var station_x = widest_x + sprocket_width + 0.05
		var station_y = float(frame["position"].y)
		var station_z = aabb.position.z + aabb.size.z * 0.5
		var station = Vector3(station_x, station_y, station_z)
		
		print("\n--- %s ---" % hull_name)
		print("Hull Widest X: %.3f, Station X: %.3f (Track inner face: %.3f, outer: %.3f)" % [widest_x, station_x, station_x - sprocket_width, station_x])
		print("Front sprocket world Z: %.3f (Hull front corner: %.3f)" % [station_z + front_z, aabb.position.z])
		print("Rear sprocket world Z: %.3f (Hull rear corner: %.3f)" % [station_z + rear_z, aabb.position.z + aabb.size.z])
		print("Top of sprocket world Y: %.3f (Hull lower chine: %.3f)" % [station_y + loop_center_y + sprocket_radius, station_y])
		
		# Test Front Sprocket Reach
		var bottom_front = Vector3(-sprocket_width - w, loop_center_y, front_z)
		var front_solved = false
		var z_bias = 0.60
		var elev_angles = [35.0, 45.0, 25.0, 55.0, 15.0, 0.0]
		var z_offsets = [z_bias, z_bias * 1.4, z_bias * 0.6, 0.0, -z_bias * 0.5]
		for el in elev_angles:
			var r_el = deg_to_rad(el)
			for zo in z_offsets:
				var c_dir = Vector3(-cos(r_el), sin(r_el), zo).normalized()
				var l = MountReachScript.solve(null, station, bottom_front, c_dir, -1.0)
				if l > 0.0:
					print("  Front sprocket reach: %.3f (dir: %s)" % [l, c_dir])
					front_solved = true
					break
			if front_solved:
				break
		if not front_solved:
			print("  [FAIL] Front sprocket reach failed!")
			
		# Test Rear Sprocket Reach
		var bottom_rear = Vector3(-sprocket_width - w, loop_center_y, rear_z)
		var rear_solved = false
		var z_bias_rear = -0.60
		var z_offsets_rear = [z_bias_rear, z_bias_rear * 1.4, z_bias_rear * 0.6, 0.0, -z_bias_rear * 0.5]
		for el in elev_angles:
			var r_el = deg_to_rad(el)
			for zo in z_offsets_rear:
				var c_dir = Vector3(-cos(r_el), sin(r_el), zo).normalized()
				var l = MountReachScript.solve(null, station, bottom_rear, c_dir, -1.0)
				if l > 0.0:
					print("  Rear sprocket reach: %.3f (dir: %s)" % [l, c_dir])
					rear_solved = true
					break
			if rear_solved:
				break
		if not rear_solved:
			print("  [FAIL] Rear sprocket reach failed!")
			
		# Test Road Wheels
		var wheel_span = span * 0.58
		var wheel_radius_target = VisualBuilder.BELT_ROAD_RADIUS * belt_scale
		var roller_y = loop_center_y - VisualBuilder.BELT_ROAD_DROP * belt_scale
		var wheels_hit = 0
		for i in range(5):
			var z = -wheel_span * 0.5 + (wheel_span * float(i) / 4.0)
			var bottom_wheel = Vector3(-0.3 * (wheel_radius_target / 0.45) - wheel_radius_target * 0.4, roller_y + wheel_radius_target * 0.35, z)
			var w_bias = -signf(z) * 0.35 if absf(z) > 0.1 else 0.0
			var w_z_offsets = [w_bias, w_bias * 1.4, 0.0, -w_bias * 0.5]
			var w_solved = false
			for el in elev_angles:
				var r_el = deg_to_rad(el)
				for zo in w_z_offsets:
					var c_dir = Vector3(-cos(r_el), sin(r_el), zo).normalized()
					var l = MountReachScript.solve(null, station, bottom_wheel, c_dir, -1.0)
					if l > 0.0:
						wheels_hit += 1
						w_solved = true
						break
				if w_solved:
					break
		print("  Road wheels hit: %d / 5" % wheels_hit)
		
		hull.free()
		
	quit(0)
