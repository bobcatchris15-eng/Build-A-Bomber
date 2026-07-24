extends SceneTree
# Isolated ornithopter_wing module capture (no hull) - checks the
# dragonfly-style fore/hind wing pair rebuild (longer/narrower wings, two
# named flap pivots per node beating in opposition).
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_ornithopter_wing_isolated.gd --path .

func _init():
	var out_dir = "res://progress_captures/debug/ornithopter_wing"
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
	VisualBuilder.build_visual("ornithopter_wing", module, Vector3(2.0, 0.2, 1.0), Color(0.42, 0.32, 0.22), {"wingspan": 1.0, "wing_sweep": 1.0})
	for i in range(4): await process_frame

	var cam = Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.position = Vector3(0.5, 3.2, 0.1)
	cam.look_at(Vector3(1.2, 0, 0), Vector3.FORWARD)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/ow_top.png" % out_dir)
	print("[CAPTURE] ow_top saved")

	cam.position = Vector3(1.5, 1.8, 3.2)
	cam.look_at(Vector3(1.2, 0, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/ow_perspective.png" % out_dir)
	print("[CAPTURE] ow_perspective saved")

	# Manually pose the two pivots to the extremes (opposite directions) -
	# same effect battle_unit.gd's sin(t)/-sin(t) drive produces mid-flap,
	# without needing a live physics tick.
	var fore = module.get_node("WingPivotFore")
	var hind = module.get_node("WingPivotHind")
	fore.rotation.x = 0.35
	hind.rotation.x = -0.35
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/ow_flap_opposed.png" % out_dir)
	print("[CAPTURE] ow_flap_opposed saved")

	# Real on-hull placement via module_placer.gd (left/right mirrored
	# pair, same path the Design Lab uses) - top-down, so the full
	# left+right wing silhouette against the hull is visible at once.
	module.queue_free()
	for i in range(2): await process_frame

	var hull = StaticBody3D.new()
	hull.name = "Hull"
	var col = CollisionShape3D.new()
	var col_box = BoxShape3D.new()
	col_box.size = Vector3(4.0, 1.0, 6.0)
	col.shape = col_box
	col.name = "CollisionShape3D"
	hull.add_child(col)
	hull.set_meta("base_hull_size", Vector3(4.0, 1.0, 6.0))
	hull.set_meta("hull_scale", Vector3(1, 1, 1))
	hull.set_meta("type_id", "medium_hull")
	world.add_child(hull)
	for i in range(2): await process_frame

	var ModulePlacerScript = load("res://scripts/module_placer.gd")
	var placer = Node3D.new()
	placer.set_script(ModulePlacerScript)
	placer.hull = hull
	world.add_child(placer)
	for i in range(2): await process_frame

	placer.update_locomotion("ornithopter_wing", {"wingspan": 1.0, "wing_sweep": 1.0})
	for i in range(4): await process_frame

	cam.position = Vector3(0, 8.0, 0.01)
	cam.look_at(Vector3(0, 0, 0), Vector3.FORWARD)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/ow_on_hull_top.png" % out_dir)
	print("[CAPTURE] ow_on_hull_top saved")

	cam.position = Vector3(6.0, 3.0, 5.0)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/ow_on_hull_perspective.png" % out_dir)
	print("[CAPTURE] ow_on_hull_perspective saved")

	quit(0)
