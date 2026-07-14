extends SceneTree
# Scratch: close-up review of wear/grime/decal quality per faction, as part
# of the material/faction polish review pass - checking for anything that
# still reads as placeholder-ish rather than just confirming the mechanism
# works. Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_faction_polish_review.gd

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

func _shot(fac: String, fname: String, out_dir: String) -> void:
	var w = _make_world()
	var c = Camera3D.new()
	w.add_child(c)
	c.look_at_from_position(Vector3(3.2, 2.2, 3.5), Vector3(0, 0.6, 0), Vector3.UP)
	var b = BlueprintManager.new()
	w.add_child(b)
	var p = Node3D.new()
	w.add_child(p)
	b.reconstruct_vehicle({
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "armor_thickness": 1.0,
		"faction": fac, "modules": [],
	}, p, false)
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png("%s/%s" % [out_dir, fname])
	print("[CAPTURE] saved ", fname)
	w.queue_free()
	await process_frame

func _init():
	var out_dir = "res://progress_captures/2026-07-13/faction_polish_review"
	DirAccess.make_dir_recursive_absolute(out_dir)

	await _shot("industrialists", "industrialists_closeup.png", out_dir)
	await _shot("ledger_combine", "ledger_combine_closeup.png", out_dir)
	await _shot("glacier_syndicate", "glacier_syndicate_closeup.png", out_dir)
	await _shot("salvage_union", "salvage_union_closeup.png", out_dir)
	await _shot("crimson_concordat", "crimson_concordat_closeup.png", out_dir)

	quit(0)
