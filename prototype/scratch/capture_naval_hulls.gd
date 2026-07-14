extends SceneTree
# Scratch: windowed screenshots validating Tier 1 polish on the naval hull
# family - real V-deadrise cross-section, sheer, and (for heavy_cruiser)
# topside flare, viewed bow-on so the cross-section actually reads. Must
# run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_naval_hulls.gd

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
	var out_dir = "res://progress_captures/2026-07-13/naval_hulls"
	DirAccess.make_dir_recursive_absolute(out_dir)

	# 3/4 side views - overall silhouette, sheer, bevel
	await _shot("naval_hull", Vector3(6, 3, 8), Vector3(0, 0.5, 0), "naval_hull_3q.png", out_dir)
	await _shot("small_boat_hull", Vector3(4, 2.5, 5), Vector3(0, 0.3, 0), "small_boat_hull_3q.png", out_dir)
	await _shot("heavy_cruiser_hull", Vector3(8, 3.5, 10), Vector3(0, 0.6, 0), "heavy_cruiser_hull_3q.png", out_dir)

	# Bow-on views (low, from just off the bow) - where the V-deadrise
	# cross-section and any topside flare actually reads
	await _shot("naval_hull", Vector3(1.5, 0.8, -8), Vector3(0, -0.3, 2), "naval_hull_bowon.png", out_dir)
	await _shot("small_boat_hull", Vector3(1.0, 0.6, -4.5), Vector3(0, -0.2, 1), "small_boat_hull_bowon.png", out_dir)
	await _shot("heavy_cruiser_hull", Vector3(1.8, 1.0, -9), Vector3(0, -0.3, 2), "heavy_cruiser_hull_bowon.png", out_dir)

	quit(0)
