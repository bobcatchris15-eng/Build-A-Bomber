extends SceneTree
# Isolated wheel-module capture: spawns ONLY the wheels module geometry
# (no hull mesh) via VisualBuilder.build_visual() directly, lit from a
# dedicated light, to answer whether the driveshaft/gearbox geometry is
# actually present and correctly shaped, independent of hull occlusion or
# the hull's own dark underside shading.
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_wheel_isolated.gd

func _init():
	var out_dir = "res://progress_captures/2026-07-23/wheel_driveshaft"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var world = Node3D.new()
	root.add_child(world)
	root.size = Vector2i(1000, 800)

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
	VisualBuilder.build_visual("wheels", module, Vector3(0.6, 0.6, 0.6), Color.BLACK, {"wheel_size": 1.0, "wheels_per_axle": 1})
	for i in range(4): await process_frame

	var cam = Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.position = Vector3(1.2, 0.5, 1.2)
	cam.look_at(Vector3(0, -0.15, 0), Vector3.UP)
	for i in range(4): await process_frame

	root.get_texture().get_image().save_png("%s/wheels_isolated_module.png" % out_dir)
	print("[CAPTURE] wheels isolated_module saved")

	cam.position = Vector3(0.05, 0.6, 1.0)
	cam.look_at(Vector3(0, -0.1, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/wheels_isolated_module_front.png" % out_dir)
	print("[CAPTURE] wheels isolated_module_front saved")

	quit(0)
