extends SceneTree
# Scratch: windowed screenshot proving the faction visual identity system -
# the SAME hull mesh (medium_hull, hardened_steel) rendered once per
# faction, side by side, so the only difference visible is the shader's
# paint color + wear level. Must run WITHOUT --headless (dummy renderer
# doesn't rasterize).
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_faction_materials.gd

const BlueprintManager = preload("res://scripts/blueprint_manager.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")

func _init():
	var world = Node3D.new()
	root.add_child(world)
	current_scene = world

	var cam = Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 5, 13), Vector3(0, 1, 0), Vector3.UP)

	var light = DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 1.2

	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.09, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.3, 0.32)
	env.ambient_light_energy = 0.6
	env_node.environment = env
	world.add_child(env_node)

	var bp_manager = BlueprintManager.new()
	world.add_child(bp_manager)

	var ids = FactionCatalog.get_ids()
	var showcase = ["industrialists", "technocrats", "scavengers", "zealots", "cybernetics"]
	var spacing = 4.5
	var start_x = -spacing * (showcase.size() - 1) / 2.0

	for i in range(showcase.size()):
		var fac = showcase[i]
		var blueprint_data = {
			"version": 1.0, "hull_type": "medium_hull",
			"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
			"armor_material": "hardened_steel", "armor_thickness": 1.0,
			"faction": fac,
			"modules": [],
		}
		var parent = Node3D.new()
		world.add_child(parent)
		var hull = bp_manager.reconstruct_vehicle(blueprint_data, parent, false)
		parent.global_position = Vector3(start_x + i * spacing, 0, 0)

		var label = Label3D.new()
		label.text = FactionCatalog.get_faction_name(fac)
		label.font_size = 32
		label.position = Vector3(0, 2.2, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		parent.add_child(label)

	for i in range(6):
		await process_frame

	DirAccess.make_dir_recursive_absolute("res://progress_captures/2026-07-13/faction_visuals")
	var img = root.get_texture().get_image()
	img.save_png("res://progress_captures/2026-07-13/faction_visuals/hull_faction_lineup.png")
	print("[CAPTURE] saved hull_faction_lineup.png")
	quit(0)
