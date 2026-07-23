extends SceneTree
# Visual verification for the wheels running-gear redesign (driveshaft box +
# gearbox, replacing rg_mount_box for the "wheels" locomotion type).
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_wheel_driveshaft.gd

func _init():
	var out_dir = "res://progress_captures/2026-07-23/wheel_driveshaft"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 800)
	for i in range(6): await process_frame

	var cam = root.get_camera_3d()

	scene.clear_hull()
	await process_frame
	scene._place_hull_from_ui("medium_hull")
	for i in range(6): await process_frame

	scene.update_locomotion("wheels", {"wheel_size": 1.0, "num_axles": 4, "wheels_per_axle": 1})
	for i in range(6): await process_frame

	if cam and "_distance" in cam:
		cam._distance = 6.0
		cam.position.z = 6.0
		cam.get_parent().rotation.y = deg_to_rad(-90.0)
		cam.get_parent().rotation.x = deg_to_rad(-6.0)
		await process_frame
	root.get_texture().get_image().save_png("%s/wheels_side_eyelevel.png" % out_dir)
	print("[CAPTURE] wheels side_eyelevel saved")

	if cam and "_distance" in cam:
		cam._distance = 3.0
		cam.position.z = 3.0
		cam.get_parent().rotation.y = deg_to_rad(-95.0)
		cam.get_parent().rotation.x = deg_to_rad(-8.0)
		await process_frame
	root.get_texture().get_image().save_png("%s/wheels_axle_close_eyelevel.png" % out_dir)
	print("[CAPTURE] wheels axle_close_eyelevel saved")

	if cam and "_distance" in cam:
		cam._distance = 10.0
		cam.position.z = 10.0
		cam.get_parent().rotation.y = deg_to_rad(-40.0)
		cam.get_parent().rotation.x = deg_to_rad(-10.0)
		await process_frame
	root.get_texture().get_image().save_png("%s/wheels_wide34.png" % out_dir)
	print("[CAPTURE] wheels wide34 saved")

	scene.update_locomotion("wheels", {"wheel_size": 1.6, "num_axles": 4, "wheels_per_axle": 2})
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png("%s/wheels_big_cluster.png" % out_dir)
	print("[CAPTURE] wheels big_cluster saved")

	quit(0)
