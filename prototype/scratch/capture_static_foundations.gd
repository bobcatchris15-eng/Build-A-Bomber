extends SceneTree
# Scratch: windowed screenshots validating Tier 1 polish on the 3 static
# foundation hulls (pillbox/tower/fortress-wall) - bevel treatment plus
# tower's new base skirt and the wall's tiling seam (two segments placed
# end-to-end, confirming preserve_axis kept the end-caps flat/matching).
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_static_foundations.gd

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

func _spawn(world, bp, hull_id, pos := Vector3.ZERO) -> void:
	var parent = Node3D.new()
	world.add_child(parent)
	bp.reconstruct_vehicle({
		"version": 1.0, "hull_type": hull_id,
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "armor_thickness": 1.0,
		"faction": "industrialists", "modules": [],
	}, parent, false)
	parent.global_position = pos

func _init():
	var out_dir = "res://progress_captures/2026-07-13/static_foundations"
	DirAccess.make_dir_recursive_absolute(out_dir)

	# --- Pillbox close-up ---
	var w1 = _make_world()
	var c1 = Camera3D.new()
	w1.add_child(c1)
	c1.look_at_from_position(Vector3(4, 3, 5), Vector3(0, 0.3, 0), Vector3.UP)
	var b1 = BlueprintManager.new()
	w1.add_child(b1)
	_spawn(w1, b1, "pillbox_foundation")
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png("%s/pillbox_closeup.png" % out_dir)
	print("[CAPTURE] saved pillbox_closeup.png")
	w1.queue_free()
	await process_frame

	# --- Tower close-up (base skirt visible) ---
	var w2 = _make_world()
	var c2 = Camera3D.new()
	w2.add_child(c2)
	c2.look_at_from_position(Vector3(6, 3, 7), Vector3(0, 1.5, 0), Vector3.UP)
	var b2 = BlueprintManager.new()
	w2.add_child(b2)
	_spawn(w2, b2, "tower_foundation")
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png("%s/tower_full.png" % out_dir)
	print("[CAPTURE] saved tower_full.png")
	w2.queue_free()
	await process_frame

	var w3 = _make_world()
	var c3 = Camera3D.new()
	w3.add_child(c3)
	c3.look_at_from_position(Vector3(3, 0.2, 3.5), Vector3(0, -1.5, 0), Vector3.UP)
	var b3 = BlueprintManager.new()
	w3.add_child(b3)
	_spawn(w3, b3, "tower_foundation")
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png("%s/tower_base_skirt.png" % out_dir)
	print("[CAPTURE] saved tower_base_skirt.png")
	w3.queue_free()
	await process_frame

	# --- Fortress wall: TWO segments placed end-to-end to verify tiling ---
	var w4 = _make_world()
	var c4 = Camera3D.new()
	w4.add_child(c4)
	c4.look_at_from_position(Vector3(2, 4, 12), Vector3(0, 0.5, 0), Vector3.UP)
	var b4 = BlueprintManager.new()
	w4.add_child(b4)
	_spawn(w4, b4, "fortress_wall_foundation", Vector3(-3.0, 0, 0))
	_spawn(w4, b4, "fortress_wall_foundation", Vector3(3.0, 0, 0))
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png("%s/wall_tiling_seam.png" % out_dir)
	print("[CAPTURE] saved wall_tiling_seam.png")
	w4.queue_free()
	await process_frame

	quit(0)
