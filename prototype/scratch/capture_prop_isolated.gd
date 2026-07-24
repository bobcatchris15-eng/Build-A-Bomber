extends SceneTree
# Close isolated naval_propeller capture (no hull, no pylon distance) -
# checks the housing cone points fore-aft (local Z) and blades fan out
# distinctly around the hub.
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_prop_isolated.gd --path .

func _init():
	var out_dir = "res://progress_captures/debug/naval_buoyant_pylon"
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
	VisualBuilder.build_visual("naval_propeller", module, Vector3(0.5, 0.5, 0.8), Color.TEAL, {"blade_count": 4.0, "blade_pitch": 1.0, "mount_reach_x": 0.0, "mount_reach_y": 0.0, "mount_reach_z": 1.5})
	for i in range(4): await process_frame

	var cam = Camera3D.new()
	world.add_child(cam)
	cam.current = true
	# Side-on: X to the right, Z (fore-aft) into/out of the screen - if the
	# housing correctly points along Z, we should see it edge-on (foreshortened
	# cone), NOT a full cone profile spanning left-right.
	cam.position = Vector3(1.2, 0.3, 0.5)
	cam.look_at(Vector3(0, 0, 0.4), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/prop_side.png" % out_dir)
	print("[CAPTURE] prop_side saved")

	cam.position = Vector3(0.8, 0.7, 2.2)
	cam.look_at(Vector3(0, 0, 0.4), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/prop_perspective.png" % out_dir)
	print("[CAPTURE] prop_perspective saved")

	# Straight down the shaft (looking along -Z toward the hub from behind)
	cam.position = Vector3(0, 0, 2.0)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/prop_rear.png" % out_dir)
	print("[CAPTURE] prop_rear saved")

	quit(0)
