extends SceneTree
# Close-up single-hull capture per faction to actually judge the new
# Flow-sourced textures, unlike capture_faction_materials.gd's distant
# 10-in-a-row lineup shot. Must run WITHOUT --headless.

const BlueprintManager = preload("res://scripts/blueprint_manager.gd")

func _make_world() -> Node3D:
	var world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var light = DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 1.4
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.11, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.35, 0.38)
	env.ambient_light_energy = 0.7
	env_node.environment = env
	world.add_child(env_node)
	return world

func _init():
	DirAccess.make_dir_recursive_absolute("res://progress_captures/2026-07-26_flow_textures")
	var factions = ["ledger_combine", "industrialists", "technocrats", "salvage_union"]
	for faction in factions:
		var world = _make_world()
		var cam = Camera3D.new()
		world.add_child(cam)
		cam.look_at_from_position(Vector3(0, 2.0, 4.5), Vector3(0, 1.0, 0), Vector3.UP)
		var bp_manager = BlueprintManager.new()
		world.add_child(bp_manager)
		var blueprint_data = {
			"version": 1.0, "hull_type": "medium_hull",
			"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
			"armor_material": "hardened_steel", "armor_thickness": 1.0,
			"faction": faction, "modules": [],
		}
		var parent = Node3D.new()
		world.add_child(parent)
		bp_manager.reconstruct_vehicle(blueprint_data, parent, false)

		for i in range(6): await process_frame
		var img = root.get_texture().get_image()
		img.save_png("res://progress_captures/2026-07-26_flow_textures/" + faction + "_closeup.png")
		print("[CAPTURE] saved ", faction, "_closeup.png")
		world.queue_free()
		await process_frame
	quit(0)
