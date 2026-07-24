extends SceneTree
# Isolated fixed_wing_engine module capture (no hull) - checks the new
# pylon-mounted, radially-distributed redesign (aerofoil pylon, turbine
# core stretch) renders sensibly.
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_fixed_wing_isolated.gd --path .

func _init():
	var out_dir = "res://progress_captures/debug/fixed_wing_engine"
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

	var marker = MeshInstance3D.new()
	var marker_sphere = SphereMesh.new()
	marker_sphere.radius = 0.08
	marker_sphere.height = 0.16
	marker.mesh = marker_sphere
	marker.position = Vector3(0, 0, 0)
	var marker_mat = StandardMaterial3D.new()
	marker_mat.albedo_color = Color.ORANGE
	marker.material_override = marker_mat
	world.add_child(marker)

	var VisualBuilder = load("res://scripts/visual_builder.gd")
	var module = Node3D.new()
	world.add_child(module)
	module.position = Vector3(2.6, 0, 0)
	VisualBuilder.build_visual("fixed_wing_engine", module, Vector3(1.0, 0.5, 1.5), Color.SLATE_GRAY, {"turbine_compression": 1.0, "afterburner": false, "mount_reach_x": -2.6, "mount_reach_y": 0.0, "mount_reach_z": 0.0})
	for i in range(4): await process_frame

	var cam = Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.position = Vector3(3.5, 1.6, 3.0)
	cam.look_at(Vector3(1.3, 0, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/fw_default.png" % out_dir)
	print("[CAPTURE] fw_default saved")

	# High turbine compression - core segment should stretch out the back.
	VisualBuilder.build_visual("fixed_wing_engine", module, Vector3(1.0, 0.5, 1.5), Color.SLATE_GRAY, {"turbine_compression": 2.0, "afterburner": true, "mount_reach_x": -2.6, "mount_reach_y": 0.0, "mount_reach_z": 0.0})
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/fw_compressed.png" % out_dir)
	print("[CAPTURE] fw_compressed saved")

	# Radial spread test - 5 engines around an ellipse, matching module_placer.gd's formula.
	for c in module.get_children():
		c.queue_free()
	for i in range(6): await process_frame
	var count = 5
	var x_radius = 3.0
	var z_radius = 1.5
	for i in range(count):
		var angle = i * TAU / float(count)
		var p = Vector3(cos(angle) * x_radius, 0, sin(angle) * z_radius)
		var reach = -p
		var m2 = Node3D.new()
		world.add_child(m2)
		m2.position = p
		VisualBuilder.build_visual("fixed_wing_engine", m2, Vector3(1.0, 0.5, 1.5), Color.SLATE_GRAY, {"turbine_compression": 1.0, "afterburner": false, "mount_reach_x": reach.x, "mount_reach_y": reach.y, "mount_reach_z": reach.z})
	for i in range(4): await process_frame
	cam.position = Vector3(0, 6.0, 0.01)
	cam.look_at(Vector3(0, 0, 0), Vector3.FORWARD)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/fw_radial_top.png" % out_dir)
	print("[CAPTURE] fw_radial_top saved")

	quit(0)
