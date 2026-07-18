extends SceneTree
# Scratch: windowed screenshots verifying the hull armor/structural material
# split (2026-07-17, Approach A multi-region rollout - see DECISIONS_NEEDED.md)
# actually renders through the real spawn pipeline - BlueprintManager.
# reconstruct_vehicle(), same call the real Design Lab/battlefield make.
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_armor_split.gd

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

func _capture_hull(hull_type: String, fname: String, cam_pos: Vector3, cam_look: Vector3) -> void:
	var w = _make_world()
	var cam = Camera3D.new()
	w.add_child(cam)
	cam.look_at_from_position(cam_pos, cam_look, Vector3.UP)
	var bp_manager = BlueprintManager.new()
	w.add_child(bp_manager)
	var parent = Node3D.new()
	w.add_child(parent)
	bp_manager.reconstruct_vehicle({
		"version": 1.0, "hull_type": hull_type,
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "armor_thickness": 1.0,
		"faction": "industrialists", "modules": [],
	}, parent, false)
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png("res://progress_captures/2026-07-17/armor_split/%s" % fname)
	print("[CAPTURE] saved ", fname)
	w.queue_free()
	await process_frame

func _init():
	DirAccess.make_dir_recursive_absolute("res://progress_captures/2026-07-17/armor_split")
	await _capture_hull("light_hull", "light_hull_close.png", Vector3(1.8, 1.3, 2.3), Vector3(0, 0.4, 0))
	await _capture_hull("medium_hull", "medium_hull_close.png", Vector3(2.2, 1.6, 2.8), Vector3(0, 0.6, 0))
	await _capture_hull("heavy_hull", "heavy_hull_close.png", Vector3(3.2, 2.0, 3.8), Vector3(0, 0.7, 0))
	await _capture_hull("assault_hull", "assault_hull_close.png", Vector3(2.6, 1.7, 3.2), Vector3(0, 0.65, 0))
	await _capture_hull("sponson_hull", "sponson_hull_close.png", Vector3(3.2, 2.0, 3.6), Vector3(0, 0.7, 0))
	quit(0)
