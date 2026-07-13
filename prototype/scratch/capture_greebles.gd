extends SceneTree
# Scratch: windowed screenshots proving the alpha-cutout greeble system -
# the 5 treated factions' distinctive silhouette-extending details, plus a
# row of untreated factions confirming they stay clean. Must run WITHOUT
# --headless (dummy renderer doesn't rasterize).
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_greebles.gd

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
	env.ambient_light_color = Color(0.32, 0.32, 0.34)
	env.ambient_light_energy = 0.7
	env_node.environment = env
	world.add_child(env_node)
	return world

func _spawn_row(world: Node3D, bp_manager: Node, ids: Array, spacing: float) -> void:
	var start_x = -spacing * (ids.size() - 1) / 2.0
	for i in range(ids.size()):
		var fac = ids[i]
		var blueprint_data = {
			"version": 1.0, "hull_type": "medium_hull",
			"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
			"armor_material": "hardened_steel", "armor_thickness": 1.0,
			"faction": fac, "modules": [],
		}
		var parent = Node3D.new()
		world.add_child(parent)
		bp_manager.reconstruct_vehicle(blueprint_data, parent, false)
		parent.global_position = Vector3(start_x + i * spacing, 0, 0)
		var label = Label3D.new()
		label.text = FactionCatalog.get_faction_name(fac)
		label.font_size = 30
		label.position = Vector3(0, 3.2, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		parent.add_child(label)

func _init():
	DirAccess.make_dir_recursive_absolute("res://progress_captures/2026-07-13/greebles")

	# --- Row 1: the 5 treated factions ---
	var world1 = _make_world()
	var cam1 = Camera3D.new()
	world1.add_child(cam1)
	cam1.look_at_from_position(Vector3(0, 5, 15), Vector3(0, 1.2, 0), Vector3.UP)
	var bp1 = BlueprintManager.new()
	world1.add_child(bp1)
	_spawn_row(world1, bp1, ["salvage_union", "bayou_irregulars", "crimson_concordat", "aerodrome_cartel", "dune_runners"], 5.5)
	for i in range(6): await process_frame
	var img1 = root.get_texture().get_image()
	img1.save_png("res://progress_captures/2026-07-13/greebles/treated_factions.png")
	print("[CAPTURE] saved treated_factions.png")
	world1.queue_free()
	await process_frame

	# --- Row 2: untreated factions, confirming they stay clean ---
	var world2 = _make_world()
	var cam2 = Camera3D.new()
	world2.add_child(cam2)
	cam2.look_at_from_position(Vector3(0, 5, 15), Vector3(0, 1.2, 0), Vector3.UP)
	var bp2 = BlueprintManager.new()
	world2.add_child(bp2)
	_spawn_row(world2, bp2, ["industrialists", "technocrats", "expansionists", "glacier_syndicate", "ledger_combine"], 5.5)
	for i in range(6): await process_frame
	var img2 = root.get_texture().get_image()
	img2.save_png("res://progress_captures/2026-07-13/greebles/untreated_factions.png")
	print("[CAPTURE] saved untreated_factions.png")
	world2.queue_free()
	await process_frame

	# --- Close-ups of each treated faction, one at a time ---
	var closeups = ["salvage_union", "bayou_irregulars", "crimson_concordat", "aerodrome_cartel", "dune_runners"]
	for fac in closeups:
		var world3 = _make_world()
		var cam3 = Camera3D.new()
		world3.add_child(cam3)
		cam3.look_at_from_position(Vector3(4, 3.5, 6), Vector3(0, 1.0, 0), Vector3.UP)
		var bp3 = BlueprintManager.new()
		world3.add_child(bp3)
		var blueprint_data = {
			"version": 1.0, "hull_type": "medium_hull",
			"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
			"armor_material": "hardened_steel", "armor_thickness": 1.0,
			"faction": fac, "modules": [],
		}
		var parent = Node3D.new()
		world3.add_child(parent)
		bp3.reconstruct_vehicle(blueprint_data, parent, false)
		for i in range(6): await process_frame
		var img3 = root.get_texture().get_image()
		img3.save_png("res://progress_captures/2026-07-13/greebles/closeup_%s.png" % fac)
		print("[CAPTURE] saved closeup_", fac, ".png")
		world3.queue_free()
		await process_frame

	quit(0)
