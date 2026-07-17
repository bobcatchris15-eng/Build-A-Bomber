extends SceneTree
# UI Polish Pass verification: Design Lab with styled sidebars (Parts Catalog + Blueprint Stats)
# Captures the C&C-inspired chrome, panel borders, and color-coded stat labels
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script prototype/scratch/capture_ui_sidebars.gd

func _init():
	print("[INIT] UI Sidebars capture script starting")
	var out_dir = "res://progress_captures/2026-07-17_ui_pass"
	print("[INIT] Creating output directory: ", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("[INIT] Output directory ready")

	print("[LOAD] Loading MainLab.tscn")
	var scene_res = load("res://scenes/MainLab.tscn")
	if not scene_res:
		print("[ERROR] Failed to load MainLab.tscn")
		quit(1)
	var scene = scene_res.instantiate()
	print("[LOAD] Instantiated scene, adding to root")
	root.add_child(scene)
	root.size = Vector2i(1280, 800)
	print("[LOAD] Waiting for render frames")
	for i in range(8): await process_frame
	print("[LOAD] Scene loaded and ready")

	var cam = root.get_camera_3d()

	# Default view showing both sidebars with a hull
	scene.clear_hull()
	await process_frame
	scene._place_hull_from_ui("medium_hull")
	for i in range(4): await process_frame

	if cam and "_distance" in cam:
		cam._distance = 11.0
		cam.position.z = 11.0
		cam.get_parent().rotation.y = deg_to_rad(-30.0)
		cam.get_parent().rotation.x = deg_to_rad(-15.0)
		await process_frame

	root.get_texture().get_image().save_png("%s/design_lab_ui_sidebars_full.png" % out_dir)
	print("[CAPTURE] Design Lab UI sidebars (full view) saved")

	# Closer view focused on left sidebar (Parts Catalog)
	if cam and "_distance" in cam:
		cam._distance = 8.0
		cam.position.z = 8.0
		cam.position.x = -3.0
		cam.get_parent().rotation.y = deg_to_rad(-20.0)
		cam.get_parent().rotation.x = deg_to_rad(-10.0)
		await process_frame

	root.get_texture().get_image().save_png("%s/parts_catalog_panel_detail.png" % out_dir)
	print("[CAPTURE] Parts Catalog panel (detail) saved")

	# Reset and close to show right sidebar (Blueprint Stats)
	if cam and "_distance" in cam:
		cam._distance = 8.0
		cam.position.z = 8.0
		cam.position.x = 3.0
		cam.get_parent().rotation.y = deg_to_rad(-160.0)
		cam.get_parent().rotation.x = deg_to_rad(-10.0)
		await process_frame

	root.get_texture().get_image().save_png("%s/blueprint_stats_panel_detail.png" % out_dir)
	print("[CAPTURE] Blueprint Stats panel (detail) saved")

	quit(0)
