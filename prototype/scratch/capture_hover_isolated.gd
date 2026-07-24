extends SceneTree
# Isolated hover_engine module capture (no hull) - checks the new
# concentric-ring redesign (three nested hover_ring instances, outer/mid/
# inner) renders sensibly before wiring it up further.
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_hover_isolated.gd --path .

func _init():
	var out_dir = "res://progress_captures/debug/hover_engine"
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
	VisualBuilder.build_visual("hover_engine", module, Vector3(1.2, 0.3, 1.2), Color.DEEP_SKY_BLUE, {"emv_level": 1.0, "mount_reach_x": -1.4, "mount_reach_y": 0.4, "mount_reach_z": -0.8})
	for i in range(4): await process_frame

	var marker = MeshInstance3D.new()
	var marker_sphere = SphereMesh.new()
	marker_sphere.radius = 0.08
	marker_sphere.height = 0.16
	marker.mesh = marker_sphere
	marker.position = module.position + Vector3(-1.4, 0.4, -0.8)
	var marker_mat = StandardMaterial3D.new()
	marker_mat.albedo_color = Color.ORANGE
	marker.material_override = marker_mat
	world.add_child(marker)

	var cam = Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.position = Vector3(1.6, 1.1, 1.4)
	cam.look_at(Vector3(-0.5, 0.25, -0.3), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/hover_default.png" % out_dir)
	print("[CAPTURE] hover_default saved")

	cam.position = Vector3(0.1, 2.4, 0.1)
	cam.look_at(Vector3(0, 0.15, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/hover_top.png" % out_dir)
	print("[CAPTURE] hover_top saved")

	# High Electron Megavoltage - rings should be visibly fatter (thicker
	# tube), same diameters.
	VisualBuilder.build_visual("hover_engine", module, Vector3(1.2, 0.3, 1.2), Color.DEEP_SKY_BLUE, {"emv_level": 2.5})
	for i in range(4): await process_frame
	cam.position = Vector3(2.2, 1.4, 2.2)
	cam.look_at(Vector3(0, 0.15, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/hover_high_emv.png" % out_dir)
	print("[CAPTURE] hover_high_emv saved")

	quit(0)
