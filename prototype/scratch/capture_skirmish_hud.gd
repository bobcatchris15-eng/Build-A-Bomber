extends SceneTree
# UI Polish Pass verification: Skirmish HUD with styled bars (brushed aluminum theme)
# Captures the top info bar and bottom build queue bar with C&C-inspired styling
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64.exe --path prototype scratch/capture_skirmish_hud.tscn

func _init():
	var out_dir = "res://progress_captures/2026-07-17_ui_pass"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene = load("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 800)
	for i in range(8): await process_frame

	# Wait for Skirmish scene to fully initialize (camera, HUD, etc.)
	for i in range(4): await process_frame

	# Capture default Skirmish view showing top info bar and bottom build queue
	root.get_texture().get_image().save_png("%s/skirmish_hud_full.png" % out_dir)
	print("[CAPTURE] Skirmish HUD (full view with info and build bars) saved")

	# Try to get a zoomed view showing the UI more clearly if camera allows
	var cam = root.get_camera_3d()
	if cam and "_distance" in cam:
		cam._distance = 15.0
		cam.position.z = 15.0
		await process_frame

	root.get_texture().get_image().save_png("%s/skirmish_hud_battlefield_view.png" % out_dir)
	print("[CAPTURE] Skirmish HUD (battlefield view) saved")

	quit(0)
