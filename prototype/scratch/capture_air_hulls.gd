extends SceneTree
# Scratch: windowed screenshots validating Tier 1 polish on the air hull
# family - bevel treatment, and for fuselage_hull specifically confirming
# the nose/body/tail weld+bevel actually smoothed the old topological seam
# rather than just relying on shade_smooth to hide it. Must run WITHOUT
# --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_air_hulls.gd

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
	env.ambient_light_color = Color(0.34, 0.34, 0.36)
	env.ambient_light_energy = 0.8
	env_node.environment = env
	world.add_child(env_node)
	return world

func _shot(hull_id: String, cam_pos: Vector3, cam_look: Vector3, fname: String, out_dir: String) -> void:
	var w = _make_world()
	var c = Camera3D.new()
	w.add_child(c)
	c.look_at_from_position(cam_pos, cam_look, Vector3.UP)
	var b = BlueprintManager.new()
	w.add_child(b)
	var p = Node3D.new()
	w.add_child(p)
	b.reconstruct_vehicle({
		"version": 1.0, "hull_type": hull_id,
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "armor_thickness": 1.0,
		"faction": "industrialists", "modules": [],
	}, p, false)
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png("%s/%s" % [out_dir, fname])
	print("[CAPTURE] saved ", fname)
	w.queue_free()
	await process_frame

func _init():
	var out_dir = "res://progress_captures/2026-07-13/air_hulls"
	DirAccess.make_dir_recursive_absolute(out_dir)

	await _shot("flying_wing_hull", Vector3(6, 3, 7), Vector3(0, 0.2, 0), "flying_wing_3q.png", out_dir)
	await _shot("fuselage_hull", Vector3(5, 2.5, 7), Vector3(0, 0.2, 0), "fuselage_3q.png", out_dir)
	await _shot("fuselage_hull", Vector3(1.5, 0.6, -5), Vector3(0, 0.1, 1), "fuselage_nose_closeup.png", out_dir)
	await _shot("airship_hull", Vector3(8, 3, 10), Vector3(0, 0.5, 0), "airship_3q.png", out_dir)

	quit(0)
