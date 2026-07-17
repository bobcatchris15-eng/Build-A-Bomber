extends SceneTree
# Reusable single-hull verification capture: wide 3/4, side profile, and an
# extreme non-uniform hull_scale stretch test (2.5x/2.2x/0.35x, matching the
# medium_hull/light_hull/heavy_hull verification precedent). Pass the hull
# type_id and an output subfolder name as script args.
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_single_hull.gd -- <hull_type_id> <out_subdir>

func _init():
	var args = OS.get_cmdline_user_args()
	var hull_type = args[0] if args.size() > 0 else "assault_hull"
	var out_subdir = args[1] if args.size() > 1 else hull_type
	var out_dir = "res://progress_captures/2026-07-13/%s" % out_subdir
	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 800)
	for i in range(6): await process_frame

	var cam = root.get_camera_3d()

	scene.clear_hull()
	await process_frame
	scene._place_hull_from_ui(hull_type)
	for i in range(6): await process_frame
	if cam and "_distance" in cam:
		cam._distance = 11.0
		cam.position.z = 11.0
		cam.get_parent().rotation.y = deg_to_rad(-40.0)
		cam.get_parent().rotation.x = deg_to_rad(-10.0)
		await process_frame
	root.get_texture().get_image().save_png("%s/%s_wide34.png" % [out_dir, hull_type])
	print("[CAPTURE] ", hull_type, " wide34 saved")

	if cam and "_distance" in cam:
		cam.get_parent().rotation.y = deg_to_rad(-90.0)
		cam.get_parent().rotation.x = deg_to_rad(-6.0)
		await process_frame
	root.get_texture().get_image().save_png("%s/%s_side.png" % [out_dir, hull_type])
	print("[CAPTURE] ", hull_type, " side saved")

	var hull = scene.hull
	if hull:
		hull.set_meta("hull_scale", Vector3(2.5, 2.2, 0.35))
		scene.update_hull_appearance()
		await process_frame
		if cam and "_distance" in cam:
			cam.get_parent().rotation.y = deg_to_rad(-40.0)
			cam.get_parent().rotation.x = deg_to_rad(-10.0)
			cam._distance = 14.0
			cam.position.z = 14.0
			await process_frame
		root.get_texture().get_image().save_png("%s/%s_extreme_stretch.png" % [out_dir, hull_type])
		print("[CAPTURE] ", hull_type, " extreme_stretch saved")
	else:
		print("[WARN] could not find placed hull node for ", hull_type, " to stretch-test")

	quit(0)
