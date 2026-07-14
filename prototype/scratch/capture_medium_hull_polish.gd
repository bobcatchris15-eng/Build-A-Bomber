extends SceneTree
# Scratch: windowed screenshots validating the Geometric Polish Pass Tier 1
# change to medium_hull - tiered bevel + non-linear (nose-aggressive) taper
# on build_wedge_hull(). Must run WITHOUT --headless (dummy renderer
# doesn't rasterize).
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_medium_hull_polish.gd

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
	env.ambient_light_color = Color(0.32, 0.32, 0.34)
	env.ambient_light_energy = 0.75
	env_node.environment = env
	world.add_child(env_node)
	return world

func _init():
	var out_dir = "res://progress_captures/2026-07-13/medium_hull_polish"
	DirAccess.make_dir_recursive_absolute(out_dir)

	# --- Shot 1: bare hull, 3/4 angle - taper + bevel silhouette ---
	var world1 = _make_world()
	var cam1 = Camera3D.new()
	world1.add_child(cam1)
	cam1.look_at_from_position(Vector3(6, 3.5, 7), Vector3(0, 0.8, 0), Vector3.UP)
	var bp1 = BlueprintManager.new()
	world1.add_child(bp1)
	var parent1 = Node3D.new()
	world1.add_child(parent1)
	bp1.reconstruct_vehicle({
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "armor_thickness": 1.0,
		"faction": "industrialists", "modules": [],
	}, parent1, false)
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png("%s/bare_hull_3q.png" % out_dir)
	print("[CAPTURE] saved bare_hull_3q.png")
	world1.queue_free()
	await process_frame

	# --- Shot 2: top-down, close - inspect bevel edges directly ---
	var world2 = _make_world()
	var cam2 = Camera3D.new()
	world2.add_child(cam2)
	cam2.look_at_from_position(Vector3(0, 9, 0.5), Vector3(0, 0, 0), Vector3(0, 0, -1))
	var bp2 = BlueprintManager.new()
	world2.add_child(bp2)
	var parent2 = Node3D.new()
	world2.add_child(parent2)
	bp2.reconstruct_vehicle({
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "armor_thickness": 1.0,
		"faction": "industrialists", "modules": [],
	}, parent2, false)
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png("%s/bare_hull_top.png" % out_dir)
	print("[CAPTURE] saved bare_hull_top.png")
	world2.queue_free()
	await process_frame

	# --- Shot 3: nose close-up, low angle - the aggressive nose taper + bevel ---
	var world3 = _make_world()
	var cam3 = Camera3D.new()
	world3.add_child(cam3)
	cam3.look_at_from_position(Vector3(2.5, 1.3, -5.5), Vector3(0, 0.4, -3), Vector3.UP)
	var bp3 = BlueprintManager.new()
	world3.add_child(bp3)
	var parent3 = Node3D.new()
	world3.add_child(parent3)
	bp3.reconstruct_vehicle({
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "armor_thickness": 1.0,
		"faction": "industrialists", "modules": [],
	}, parent3, false)
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png("%s/nose_closeup.png" % out_dir)
	print("[CAPTURE] saved nose_closeup.png")
	world3.queue_free()
	await process_frame

	# --- Shot 4: with a pintle-mounted weapon - confirm mount still sits
	# flush against the new tapered/bevelled deck, not floating/clipping ---
	var world4 = _make_world()
	var cam4 = Camera3D.new()
	world4.add_child(cam4)
	cam4.look_at_from_position(Vector3(5, 4, 6), Vector3(0, 1.0, 0.5), Vector3.UP)
	var bp4 = BlueprintManager.new()
	world4.add_child(bp4)
	var parent4 = Node3D.new()
	world4.add_child(parent4)
	bp4.reconstruct_vehicle({
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "armor_thickness": 1.0,
		"faction": "industrialists",
		"modules": [
			{"type_id": "basic_cannon", "name": "Cannon", "position": {"x": 0, "y": 0.9, "z": 0.5}, "rotation": {"x": 0, "y": 0, "z": 0}, "scale": {"x": 1, "y": 1, "z": 1}, "tweaks": {}, "mount_style": "pintle_top", "mount_normal": {"x": 0, "y": 1, "z": 0}},
		],
	}, parent4, false)
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png("%s/with_weapon_mount.png" % out_dir)
	print("[CAPTURE] saved with_weapon_mount.png")
	world4.queue_free()
	await process_frame

	quit(0)
