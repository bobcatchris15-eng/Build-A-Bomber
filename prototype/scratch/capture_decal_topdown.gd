extends SceneTree
const BlueprintManager = preload("res://scripts/blueprint_manager.gd")
func _init():
	var world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var light = DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-30, 60, 0)
	light.light_energy = 0.9
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.1, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.42)
	env.ambient_light_energy = 1.1
	env_node.environment = env
	world.add_child(env_node)
	var cam = Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.2, 1.4), Vector3(0, 0.5, 0.9), Vector3(0,0,-1))
	var bp = BlueprintManager.new()
	world.add_child(bp)
	var blueprint_data = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "armor_thickness": 1.0,
		"faction": "industrialists", "modules": [],
	}
	var parent = Node3D.new()
	world.add_child(parent)
	bp.reconstruct_vehicle(blueprint_data, parent, false)
	for i in range(6): await process_frame
	DirAccess.make_dir_recursive_absolute("res://progress_captures/2026-07-13/decals")
	var img = root.get_texture().get_image()
	img.save_png("res://progress_captures/2026-07-13/decals/roof_mascot_topdown.png")
	print("[CAPTURE] saved roof_mascot_topdown.png")
	quit(0)
