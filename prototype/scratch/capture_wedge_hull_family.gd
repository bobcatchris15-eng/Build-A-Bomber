extends SceneTree
# Scratch: windowed screenshot validating Tier 1 rollout across the full
# wedge-hull family (light/medium/heavy/interceptor/assault) - confirms
# each archetype reads distinctly per Section 2 (light=aggressive taper,
# heavy=minimal taper+chunky bevel, interceptor=extreme dart width+height
# taper+sharp bevel, assault=heavy-like bulk). Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_wedge_hull_family.gd

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

func _init():
	var out_dir = "res://progress_captures/2026-07-13/wedge_hull_family"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var hulls = ["light_hull", "medium_hull", "heavy_hull", "interceptor_hull", "assault_hull"]
	var world = _make_world()
	var cam = Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(4, 10, 26), Vector3(0, 0.5, 0), Vector3.UP)
	var bp = BlueprintManager.new()
	world.add_child(bp)

	var spacing = 6.5
	var start_x = -spacing * (hulls.size() - 1) / 2.0
	for i in range(hulls.size()):
		var parent = Node3D.new()
		world.add_child(parent)
		bp.reconstruct_vehicle({
			"version": 1.0, "hull_type": hulls[i],
			"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
			"armor_material": "hardened_steel", "armor_thickness": 1.0,
			"faction": "industrialists", "modules": [],
		}, parent, false)
		parent.global_position = Vector3(start_x + i * spacing, 0, 0)
		var label = Label3D.new()
		label.text = hulls[i]
		label.font_size = 26
		label.position = Vector3(0, 2.6, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		parent.add_child(label)

	for i in range(6): await process_frame
	root.get_texture().get_image().save_png("%s/all_five_row.png" % out_dir)
	print("[CAPTURE] saved all_five_row.png")
	world.queue_free()
	await process_frame

	# Individual 3/4 close-ups so each archetype's silhouette/bevel reads clearly
	for h in hulls:
		var w = _make_world()
		var c = Camera3D.new()
		w.add_child(c)
		c.look_at_from_position(Vector3(5, 3.5, 6.5), Vector3(0, 0.7, 0), Vector3.UP)
		var b = BlueprintManager.new()
		w.add_child(b)
		var p = Node3D.new()
		w.add_child(p)
		b.reconstruct_vehicle({
			"version": 1.0, "hull_type": h,
			"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
			"armor_material": "hardened_steel", "armor_thickness": 1.0,
			"faction": "industrialists", "modules": [],
		}, p, false)
		for i in range(6): await process_frame
		root.get_texture().get_image().save_png("%s/%s_closeup.png" % [out_dir, h])
		print("[CAPTURE] saved ", h, "_closeup.png")
		w.queue_free()
		await process_frame

	quit(0)
