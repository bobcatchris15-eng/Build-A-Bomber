extends SceneTree
# Isolated + on-hull screw_drive capture - checks the fore-aft orientation
# fix, the fore/aft gearbox housings, drum_diameter/helix_depth tweaks, and
# a manually-posed spin (battle_unit.gd drives this live in battle).
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_screw_drive.gd --path .

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
	var out_dir = "res://progress_captures/debug/screw_drive"
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

	var hull = _make_hull("medium_hull", Vector3(4.0, 1.0, 6.0))
	world.add_child(hull)
	var ModulePlacerScript = load("res://scripts/module_placer.gd")
	var placer = Node3D.new()
	placer.set_script(ModulePlacerScript)
	placer.hull = hull
	world.add_child(placer)
	for i in range(2): await process_frame
	placer.update_locomotion("screw_drive", {"drum_diameter": 1.0, "helix_depth": 1.0})
	for i in range(4): await process_frame

	cam.position = Vector3(6.0, 3.0, 6.0)
	cam.look_at(Vector3(0, -0.5, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/screw_on_hull_perspective.png" % out_dir)
	print("[CAPTURE] screw_on_hull_perspective saved")

	cam.position = Vector3(0, 6.0, 0.01)
	cam.look_at(Vector3(0, 0, 0), Vector3.FORWARD)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/screw_on_hull_top.png" % out_dir)
	print("[CAPTURE] screw_on_hull_top saved")

	cam.position = Vector3(3.5, 0.5, 0.0)
	cam.look_at(Vector3(0, -0.5, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/screw_side.png" % out_dir)
	print("[CAPTURE] screw_side saved")

	# Close-up on the REAL on-hull corner mount (gearbox + diagonal brace
	# reaching up to the hull's actual corner) - the hull is
	# Vector3(4.0,1.0,6.0), so the aft-right corner is roughly at
	# (2.0, 0.5-worth-of-height-above-center, 3.0) in world space, and the
	# gearbox/drum end sits further out/down from there.
	cam.position = Vector3(3.6, 0.0, 3.6)
	cam.look_at(Vector3(2.3, -0.5, 3.0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/screw_corner_closeup.png" % out_dir)
	print("[CAPTURE] screw_corner_closeup saved")

	cam.position = Vector3(4.5, -0.2, 4.5)
	cam.look_at(Vector3(2.6, -0.9, 3.0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/screw_corner_closeup2.png" % out_dir)
	print("[CAPTURE] screw_corner_closeup2 saved")

	# Isolated close-up: standard vs shallow vs deep helix depth, and
	# thin vs thick drum_diameter, side by side.
	var VisualBuilder = load("res://scripts/visual_builder.gd")
	var labels = ["shallow", "standard", "deep", "thin_diam", "thick_diam"]
	var tweaks_list = [
		{"drum_diameter": 1.0, "helix_depth": 0.5, "drum_length": 2.5},
		{"drum_diameter": 1.0, "helix_depth": 1.0, "drum_length": 2.5},
		{"drum_diameter": 1.0, "helix_depth": 1.5, "drum_length": 2.5},
		{"drum_diameter": 0.6, "helix_depth": 1.0, "drum_length": 2.5},
		{"drum_diameter": 1.6, "helix_depth": 1.0, "drum_length": 2.5},
	]
	for i in range(labels.size()):
		var m = Node3D.new()
		world.add_child(m)
		m.position = Vector3(0, 2.0 + i * 1.2, -6)
		VisualBuilder.build_visual("screw_drive", m, Vector3(0.8, 0.8, 3.0), Color(0.32, 0.3, 0.24), tweaks_list[i])
	for i in range(4): await process_frame

	cam.position = Vector3(3.0, 3.6, -6.0)
	cam.look_at(Vector3(0, 3.6, -6), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/screw_variants.png" % out_dir)
	print("[CAPTURE] screw_variants saved")

	# Close-up on one end (standard variant, drum_length=2.5, gearbox at
	# 0.65*drum_length=1.625) to clearly check the gearbox housing against
	# the tapered shaft cap.
	cam.position = Vector3(1.5, 2.3, -6.0 + 1.625)
	cam.look_at(Vector3(0, 2.0, -6.0 + 1.625), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/screw_gearbox_closeup.png" % out_dir)
	print("[CAPTURE] screw_gearbox_closeup saved")

	# Manually pose ScrewSpin to confirm it rotates the drum+helix as a
	# rigid unit while the gearboxes stay put (battle_unit.gd drives this
	# live via rotate_z(6.0*delta) mid-battle).
	var drum_module = null
	for c in hull.get_children():
		if c.has_meta("module_data") and c.get_meta("module_data").type_id == "screw_drive":
			drum_module = c
			break
	if drum_module:
		var spin_node = drum_module.get_node_or_null("ScrewSpin")
		if spin_node:
			spin_node.rotation.z = 1.2
	for i in range(4): await process_frame
	cam.position = Vector3(3.5, 0.5, 0.0)
	cam.look_at(Vector3(0, -0.5, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/screw_spin_posed.png" % out_dir)
	print("[CAPTURE] screw_spin_posed saved")

	quit(0)
