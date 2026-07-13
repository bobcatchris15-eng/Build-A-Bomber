extends SceneTree
# Scratch: windowed screenshots proving the v2 faction visual identity
# system (VISUAL_ART_DIRECTION.md model) - all 10 factions' identical
# medium_hull mesh side by side, plus a stretch-invariance check (a
# stretched hull should show MORE brush/panel-line repetitions, not a
# smeared/enlarged pattern). Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_faction_materials.gd

const BlueprintManager = preload("res://scripts/blueprint_manager.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")

func _make_world() -> Node3D:
	var world = Node3D.new()
	root.add_child(world)
	current_scene = world
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
	return world

func _init():
	DirAccess.make_dir_recursive_absolute("res://progress_captures/2026-07-13/faction_visuals_v2")

	# --- All 10 factions, one row ---
	var world = _make_world()
	var cam = Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 4, 9), Vector3(0, 1, 0), Vector3.UP)

	var bp_manager = BlueprintManager.new()
	world.add_child(bp_manager)

	var ids = FactionCatalog.get_ids()
	var spacing = 3.4
	var start_x = -spacing * (ids.size() - 1) / 2.0

	for i in range(ids.size()):
		var fac = ids[i]
		var blueprint_data = {
			"version": 1.0, "hull_type": "medium_hull",
			"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
			"armor_material": "hardened_steel", "armor_thickness": 1.0,
			"faction": fac,
			"modules": [],
		}
		var parent = Node3D.new()
		world.add_child(parent)
		bp_manager.reconstruct_vehicle(blueprint_data, parent, false)
		parent.global_position = Vector3(start_x + i * spacing, 0, 0)

		var label = Label3D.new()
		label.text = FactionCatalog.get_faction_name(fac)
		label.font_size = 28
		label.position = Vector3(0, 2.0, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		parent.add_child(label)

	for i in range(6): await process_frame
	var img = root.get_texture().get_image()
	img.save_png("res://progress_captures/2026-07-13/faction_visuals_v2/hull_faction_lineup_v2.png")
	print("[CAPTURE] saved hull_faction_lineup_v2.png")
	world.queue_free()
	await process_frame

	# --- Stretch invariance: same faction, 1x vs 3x length hull_scale.z ---
	var world2 = _make_world()
	var cam2 = Camera3D.new()
	world2.add_child(cam2)
	cam2.look_at_from_position(Vector3(0, 6, 20), Vector3(0, 1, 0), Vector3.UP)
	var bp_manager2 = BlueprintManager.new()
	world2.add_child(bp_manager2)

	var normal_bp = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "armor_thickness": 1.0,
		"faction": "industrialists", "modules": [],
	}
	var stretched_bp = normal_bp.duplicate(true)
	stretched_bp["hull_scale"] = {"x": 1.0, "y": 1.0, "z": 3.0}

	var p1 = Node3D.new()
	world2.add_child(p1)
	bp_manager2.reconstruct_vehicle(normal_bp, p1, false)
	p1.global_position = Vector3(-4, 0, 0)
	var p2 = Node3D.new()
	world2.add_child(p2)
	bp_manager2.reconstruct_vehicle(stretched_bp, p2, false)
	p2.global_position = Vector3(4, 0, 0)

	for i in range(6): await process_frame
	var img2 = root.get_texture().get_image()
	img2.save_png("res://progress_captures/2026-07-13/faction_visuals_v2/stretch_invariance.png")
	print("[CAPTURE] saved stretch_invariance.png")
	world2.queue_free()
	await process_frame

	quit(0)
