extends SceneTree
# Scratch: windowed screenshots proving the shared decal/stencil atlas -
# hazard stripes + stencil serial + mascot icon actually appear and differ
# by faction. Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_decals.gd

const BlueprintManager = preload("res://scripts/blueprint_manager.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")

func _make_world() -> Node3D:
	var world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var light = DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-55, -20, 0)
	light.light_energy = 1.3
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.1, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.35, 0.37)
	env.ambient_light_energy = 0.8
	env_node.environment = env
	world.add_child(env_node)
	return world

func _init():
	DirAccess.make_dir_recursive_absolute("res://progress_captures/2026-07-13/decals")

	# --- All 10 factions, top-down-ish view so the roof mascot + side serial are visible ---
	var world = _make_world()
	var cam = Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 12, 16), Vector3(0, 0.5, 0), Vector3.UP)
	var bp = BlueprintManager.new()
	world.add_child(bp)
	var ids = FactionCatalog.get_ids()
	var spacing = 4.2
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
		bp.reconstruct_vehicle(blueprint_data, parent, false)
		parent.global_position = Vector3(start_x + i * spacing, 0, 0)
	for i in range(6): await process_frame
	var img = root.get_texture().get_image()
	img.save_png("res://progress_captures/2026-07-13/decals/all_10_factions_topdown.png")
	print("[CAPTURE] saved all_10_factions_topdown.png")
	world.queue_free()
	await process_frame

	# --- Close-up on one hull's mascot + serial, per a few representative factions ---
	for fac in ["industrialists", "glacier_syndicate", "crimson_concordat", "ledger_combine"]:
		var world2 = _make_world()
		var cam2 = Camera3D.new()
		world2.add_child(cam2)
		cam2.look_at_from_position(Vector3(3.5, 3.2, 4.5), Vector3(0, 0.6, 0.5), Vector3.UP)
		var bp2 = BlueprintManager.new()
		world2.add_child(bp2)
		var blueprint_data2 = {
			"version": 1.0, "hull_type": "medium_hull",
			"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
			"armor_material": "hardened_steel", "armor_thickness": 1.0,
			"faction": fac, "modules": [],
		}
		var parent2 = Node3D.new()
		world2.add_child(parent2)
		bp2.reconstruct_vehicle(blueprint_data2, parent2, false)
		for i in range(6): await process_frame
		var img2 = root.get_texture().get_image()
		img2.save_png("res://progress_captures/2026-07-13/decals/closeup_%s.png" % fac)
		print("[CAPTURE] saved closeup_", fac, ".png")
		world2.queue_free()
		await process_frame

	quit(0)
