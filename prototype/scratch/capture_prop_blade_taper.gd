extends SceneTree
# Scratch: windowed screenshots validating the propeller/ship_screw blade
# thinning taper (Section 3) - blades should now read wide at the hub,
# narrow at the tip, instead of constant-width slats. Must run WITHOUT
# --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_prop_blade_taper.gd

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

func _build(hull: String, modules: Array, cam_pos: Vector3, cam_look: Vector3, fname: String, out_dir: String) -> void:
	var w = _make_world()
	var c = Camera3D.new()
	w.add_child(c)
	c.look_at_from_position(cam_pos, cam_look, Vector3.UP)
	var b = BlueprintManager.new()
	w.add_child(b)
	var p = Node3D.new()
	w.add_child(p)
	b.reconstruct_vehicle({
		"version": 1.0, "hull_type": hull,
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
	var out_dir = "res://progress_captures/2026-07-13/prop_blade_taper"
	DirAccess.make_dir_recursive_absolute(out_dir)

	await _build("fuselage_hull", [
		{"type_id": "propeller_prop", "name": "Prop", "position": {"x": 0, "y": 0, "z": -3.2}, "rotation": {"x": 0, "y": 0, "z": 0}, "scale": {"x": 1, "y": 1, "z": 1}, "tweaks": {}},
	], Vector3(1.2, 0.3, -5.5), Vector3(0, 0, -3.2), "propeller_closeup.png", out_dir)

	await _build("naval_hull", [
		{"type_id": "ship_screw", "name": "Screw", "position": {"x": 0, "y": 0, "z": 0}, "rotation": {"x": 0, "y": 0, "z": 0}, "scale": {"x": 1, "y": 1, "z": 1}, "tweaks": {}},
	], Vector3(1.5, 0.2, 5.5), Vector3(0, -0.2, 4.5), "ship_screw_closeup.png", out_dir)

	quit(0)
