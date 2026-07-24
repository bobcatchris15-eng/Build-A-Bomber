extends SceneTree
# Isolated naval_propeller / buoyant_envelope pylon-mount capture - checks
# the stern pylon rebuild (Chris's ask, 2026-07-24) actually clears the
# hull mesh instead of floating buried inside it.
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_naval_buoyant_pylon.gd --path .

func _make_hull(hull_type: String, size: Vector3) -> StaticBody3D:
	var hull = StaticBody3D.new()
	hull.name = "Hull"
	var col = CollisionShape3D.new()
	var col_box = BoxShape3D.new()
	col_box.size = size
	col.shape = col_box
	col.name = "CollisionShape3D"
	hull.add_child(col)
	hull.set_meta("base_hull_size", size)
	hull.set_meta("hull_scale", Vector3(1, 1, 1))
	hull.set_meta("type_id", hull_type)
	# Visible hull box so we can see whether the prop actually clears it.
	var vis = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	vis.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.42, 0.45)
	vis.material_override = mat
	hull.add_child(vis)
	return hull

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

	var cam = Camera3D.new()
	world.add_child(cam)
	cam.current = true

	var ModulePlacerScript = load("res://scripts/module_placer.gd")

	# --- naval_propeller on naval_hull-shaped box ---
	var hull1 = _make_hull("naval_hull", Vector3(3.5, 1.6, 9.0))
	world.add_child(hull1)
	hull1.position = Vector3(-4, 0, 0)
	var placer1 = Node3D.new()
	placer1.set_script(ModulePlacerScript)
	placer1.hull = hull1
	world.add_child(placer1)
	for i in range(2): await process_frame
	placer1.update_locomotion("naval_propeller", {"prop_count": 3, "blade_count": 4, "blade_pitch": 1.0})
	for i in range(4): await process_frame

	# --- buoyant_envelope on airship_hull-shaped box ---
	var hull2 = _make_hull("airship_hull", Vector3(4.0, 3.0, 9.5))
	world.add_child(hull2)
	hull2.position = Vector3(6, 0, 0)
	var placer2 = Node3D.new()
	placer2.set_script(ModulePlacerScript)
	placer2.hull = hull2
	world.add_child(placer2)
	for i in range(2): await process_frame
	placer2.update_locomotion("buoyant_envelope", {"prop_count": 2, "blade_count": 3, "blade_pitch": 1.0})
	for i in range(4): await process_frame

	cam.position = Vector3(1, 4.5, 14)
	cam.look_at(Vector3(1, 0, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/pylon_wide.png" % out_dir)
	print("[CAPTURE] pylon_wide saved")

	cam.position = Vector3(-4, 1.5, 8)
	cam.look_at(Vector3(-4, 0, -2), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/pylon_naval_stern.png" % out_dir)
	print("[CAPTURE] pylon_naval_stern saved")

	cam.position = Vector3(6, 2.0, 9)
	cam.look_at(Vector3(6, 0, -2), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/pylon_buoyant_stern.png" % out_dir)
	print("[CAPTURE] pylon_buoyant_stern saved")

	cam.position = Vector3(1, 10.0, 0.01)
	cam.look_at(Vector3(1, 0, 0), Vector3.FORWARD)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/pylon_top.png" % out_dir)
	print("[CAPTURE] pylon_top saved")

	quit(0)
