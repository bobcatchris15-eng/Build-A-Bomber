extends SceneTree
# Isolated helicopter_rotors pylon debug capture: places a plain box
# standing in for the hull at the origin, plus a rotor module positioned
# exactly the way module_placer.gd's update_locomotion() places one
# (x_offset = hull_size.x/2 + 1.2, y_offset = hull_size.y/2 + 0.3), so the
# pylon's hull_corner math can be checked against a known, exact target
# point (the hull box's own top-outer corner) without going through the
# full Design Lab hull-placement/collider pipeline.
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_rotor_pylon.gd --path .

func _init():
	var out_dir = "res://progress_captures/debug/rotor_pylon"
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

	var hull_size = Vector3(4.0, 1.0, 6.0)
	var hull_stub = MeshInstance3D.new()
	var hull_box = BoxMesh.new()
	hull_box.size = hull_size
	hull_stub.mesh = hull_box
	var hull_mat = StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.3, 0.32, 0.28)
	hull_stub.material_override = hull_mat
	world.add_child(hull_stub)

	var VisualBuilder = load("res://scripts/visual_builder.gd")
	var x_offset = hull_size.x / 2.0 + 1.2
	var y_offset = hull_size.y / 2.0 + 0.3

	for side in [-1.0, 1.0]:
		var module = Node3D.new()
		world.add_child(module)
		module.position = Vector3(x_offset * side, y_offset, 0)
		VisualBuilder.build_visual("helicopter_rotors", module, Vector3(4.0, 0.2, 4.0), Color.SILVER, {"blade_count": 4, "blade_length": 1.0, "duct": false, "mount_side": side, "mount_reach_x": x_offset, "mount_reach_y": y_offset})
	for i in range(4): await process_frame

	var cam = Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.position = Vector3(12.0, 5.0, 12.0)
	cam.look_at(Vector3(0, 0.5, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/rotor_pylon_wide.png" % out_dir)
	print("[CAPTURE] rotor_pylon_wide saved")

	cam.position = Vector3(6.5, 2.2, 2.0)
	cam.look_at(Vector3(3.2, 0.6, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/rotor_pylon_closeup.png" % out_dir)
	print("[CAPTURE] rotor_pylon_closeup saved")

	# Close-up on just the +1 side rotor's full pylon run, from its mount
	# point (3.2, 0.8, 0) all the way down to the hull's own center (0,0,0).
	cam.position = Vector3(4.5, 2.0, 3.0)
	cam.look_at(Vector3(1.6, 0.4, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/rotor_pylon_macro.png" % out_dir)
	print("[CAPTURE] rotor_pylon_macro saved")

	quit(0)
