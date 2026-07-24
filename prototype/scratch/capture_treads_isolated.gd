extends SceneTree
# Isolated tracked_treads module capture (no hull), lit from a dedicated
# light - same approach used for the wheels driveshaft/gearbox debugging.
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_treads_isolated.gd --path .

func _init():
	var out_dir = "res://progress_captures/2026-07-23/tracked_treads"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var world = Node3D.new()
	root.add_child(world)
	root.size = Vector2i(1100, 800)

	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.55, 0.6)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.ambient_light_energy = 1.2
	env_node.environment = env
	world.add_child(env_node)

	var sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(35.0), 0)
	sun.light_energy = 1.4
	world.add_child(sun)
	var fill = DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-30.0), deg_to_rad(-120.0), 0)
	fill.light_energy = 0.6
	world.add_child(fill)

	var VisualBuilder = load("res://scripts/visual_builder.gd")
	var module = Node3D.new()
	world.add_child(module)
	VisualBuilder.build_visual("tracked_treads", module, Vector3(0.8, 0.6, 2.5), Color.DARK_OLIVE_GREEN, {"tread_width": 1.0, "drive_sprocket": true, "target_length": 6.0})
	for i in range(4): await process_frame

	var cam = Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.position = Vector3(5.0, 2.4, 5.0)
	cam.look_at(Vector3(0, 0.3, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/treads_isolated_default.png" % out_dir)
	print("[CAPTURE] treads isolated_default saved")

	cam.position = Vector3(0.1, 1.2, 7.0)
	cam.look_at(Vector3(0, 0.3, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/treads_isolated_side.png" % out_dir)
	print("[CAPTURE] treads isolated_side saved")

	# Close-up on one sprocket/loop junction - checks the loop now fully
	# covers the sprocket's width (Chris's ask) instead of the sprocket
	# poking out past a too-narrow belt.
	cam.position = Vector3(0.9, 0.6, 2.9)
	cam.look_at(Vector3(0.15, 0.3, 2.5), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/treads_isolated_sprocket_closeup.png" % out_dir)
	print("[CAPTURE] treads isolated_sprocket_closeup saved")

	quit(0)
