extends SceneTree
# Scratch: windowed screenshots validating Tier 2 (waist-inset + deck-line
# step) on medium_hull - bare hull silhouette, a close-up on the waist band,
# a close-up on the rear deck-line step, and a weapon-mounted shot to
# directly check the pintle-top mount still sits correctly against the new
# deck-line geometry (not floating/clipping). Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_medium_hull_tier2.gd

const BlueprintManager = preload("res://scripts/blueprint_manager.gd")

func _make_world() -> Node3D:
	var world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var light = DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-50, -35, 0)
	light.light_energy = 1.2
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.09, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.36, 0.38)
	env.ambient_light_energy = 0.9
	env_node.environment = env
	world.add_child(env_node)
	return world

func _build(modules: Array, cam_pos: Vector3, cam_look: Vector3, fname: String, out_dir: String) -> void:
	var w = _make_world()
	var c = Camera3D.new()
	w.add_child(c)
	c.look_at_from_position(cam_pos, cam_look, Vector3.UP)
	var b = BlueprintManager.new()
	w.add_child(b)
	var p = Node3D.new()
	w.add_child(p)
	b.reconstruct_vehicle({
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "armor_thickness": 1.0,
		"faction": "industrialists", "modules": modules,
	}, p, false)
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png("%s/%s" % [out_dir, fname])
	print("[CAPTURE] saved ", fname)
	w.queue_free()
	await process_frame

func _init():
	var out_dir = "res://progress_captures/2026-07-13/medium_hull_tier2"
	DirAccess.make_dir_recursive_absolute(out_dir)

	await _build([], Vector3(6, 3.5, 7), Vector3(0, 0.7, 0), "bare_hull_3q.png", out_dir)
	await _build([], Vector3(5, 2, -6), Vector3(0, 0.4, -2.5), "waist_side_closeup.png", out_dir)
	await _build([], Vector3(3, 2, 5), Vector3(0, 0.6, 2.2), "deck_line_rear_closeup.png", out_dir)

	# Weapon at the showcase's usual forward-center position - the exact
	# spot most likely to interact with the new geometry.
	await _build([
		{"type_id": "basic_cannon", "name": "Cannon", "position": {"x": 0, "y": 0.9, "z": 0.5}, "rotation": {"x": 0, "y": 0, "z": 0}, "scale": {"x": 1, "y": 1, "z": 1}, "tweaks": {}, "mount_style": "pintle_top", "mount_normal": {"x": 0, "y": 1, "z": 0}},
	], Vector3(5, 3, 4), Vector3(0, 0.9, 0.5), "with_weapon_mount.png", out_dir)

	# A rear-mounted weapon specifically ON the new deck-line step
	await _build([
		{"type_id": "basic_cannon", "name": "RearCannon", "position": {"x": 0, "y": 0.9, "z": 2.2}, "rotation": {"x": 0, "y": 0, "z": 0}, "scale": {"x": 1, "y": 1, "z": 1}, "tweaks": {}, "mount_style": "pintle_top", "mount_normal": {"x": 0, "y": 1, "z": 0}},
	], Vector3(5, 3, 5), Vector3(0, 0.9, 2.2), "with_rear_weapon_on_deckline.png", out_dir)

	quit(0)
