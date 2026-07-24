extends SceneTree
# Full-vehicle tracked_treads capture, mirroring capture_wheel_driveshaft.gd's
# approach for wheels.
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_treads_hull.gd --path .

func _init():
	var out_dir = "res://progress_captures/2026-07-23/tracked_treads"
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

	scene.update_locomotion("tracked_treads", {"tread_width": 1.0, "drive_sprocket": true})
	for i in range(6): await process_frame

	if cam and "_distance" in cam:
		cam._distance = 6.0
		cam.position.z = 6.0
		cam.get_parent().rotation.y = deg_to_rad(-40.0)
		cam.get_parent().rotation.x = deg_to_rad(-10.0)
		await process_frame
	root.get_texture().get_image().save_png("%s/treads_hull_wide34.png" % out_dir)
	print("[CAPTURE] treads hull wide34 saved")

	if cam and "_distance" in cam:
		cam._distance = 3.0
		cam.position.z = 3.0
		cam.get_parent().rotation.y = deg_to_rad(-95.0)
		cam.get_parent().rotation.x = deg_to_rad(-8.0)
		await process_frame
	root.get_texture().get_image().save_png("%s/treads_hull_close.png" % out_dir)
	print("[CAPTURE] treads hull close saved")

	quit(0)
