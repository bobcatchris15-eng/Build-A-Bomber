extends SceneTree
# Isolated legs module capture (no hull) - checks the new longitudinal
# ridges + bulkier faceted hip/ankle joints render sensibly.
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_legs_isolated.gd --path .

func _init():
	var out_dir = "res://progress_captures/debug/legs"
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

	var hull_stub = MeshInstance3D.new()
	var hull_box = BoxMesh.new()
	hull_box.size = Vector3(4.0, 1.0, 6.0)
	hull_stub.mesh = hull_box
	hull_stub.position = Vector3(0, 1.5, 0)
	var hull_mat = StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.3, 0.32, 0.28)
	hull_stub.material_override = hull_mat
	world.add_child(hull_stub)

	var VisualBuilder = load("res://scripts/visual_builder.gd")
	var module = Node3D.new()
	world.add_child(module)
	module.position = Vector3(2.0, 0, 0)
	VisualBuilder.build_visual("legs", module, Vector3(0.5, 1.5, 0.5), Color.DARK_RED, {"leg_length": 1.0, "foot_size": 1.0, "leg_stance_reach": 4.0 * 0.8, "leg_hull_centerline_y": 1.35})
	for i in range(4): await process_frame

	var cam = Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.position = Vector3(7.0, 3.0, 7.0)
	cam.look_at(Vector3(2.0, 0.8, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/legs_default.png" % out_dir)
	print("[CAPTURE] legs_default saved")

	VisualBuilder.build_visual("legs", module, Vector3(0.5, 1.5, 0.5), Color.DARK_RED, {"leg_length": 1.0, "foot_size": 1.0, "leg_stance_reach": 4.0 * 0.8, "leg_hull_centerline_y": 1.35, "knee_height": -0.5})
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/legs_knee_low.png" % out_dir)
	print("[CAPTURE] legs_knee_low saved")

	VisualBuilder.build_visual("legs", module, Vector3(0.5, 1.5, 0.5), Color.DARK_RED, {"leg_length": 1.0, "foot_size": 1.0, "leg_stance_reach": 4.0 * 0.8, "leg_hull_centerline_y": 1.35, "knee_height": 1.5})
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/legs_knee_high.png" % out_dir)
	print("[CAPTURE] legs_knee_high saved")

	cam.position = Vector3(0.6, 0.9, 1.6)
	cam.look_at(Vector3(0.35, 0.3, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/legs_ankle_closeup.png" % out_dir)
	print("[CAPTURE] legs_ankle_closeup saved")

	cam.position = Vector3(0.6, 1.7, 1.4)
	cam.look_at(Vector3(0.0, 1.3, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/legs_hip_closeup.png" % out_dir)
	print("[CAPTURE] legs_hip_closeup saved")

	quit(0)
