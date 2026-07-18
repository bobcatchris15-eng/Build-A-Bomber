extends SceneTree
# Scratch: verifies the widened armor/structural contrast + new cel-shaded
# ink border (2026-07-17, Chris's follow-up on the armor/structural split)
# read clearly at REAL gameplay camera distance, not just in a close product
# shot - part of why the split read weak before may have been distance/
# lighting, per Chris's own ask. Uses a real multi-surface hull via
# BlueprintManager.reconstruct_vehicle() (the actual Design Lab/battlefield
# code path, so both the material split AND the ink border are the real
# thing, not a simplified stand-in) sitting on a real full-size grassland
# ground plane, under the same Environment/light this project's other
# gameplay-distance diagnostics use.
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_contrast_gameplay_distance.gd

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")
const BlueprintManager = preload("res://scripts/blueprint_manager.gd")

const OUT_DIR = "res://progress_captures/2026-07-17/contrast_and_ink_edges"

func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR + "/AFTER")

	var world = Node3D.new()
	root.add_child(world)
	current_scene = world

	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_horizon_color = Color(0.64625, 0.65575, 0.67075, 1)
	sky_mat.ground_horizon_color = Color(0.64625, 0.65575, 0.67075, 1)
	var sky = Sky.new()
	sky.sky_material = sky_mat
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var env_node = WorldEnvironment.new()
	env_node.environment = env
	world.add_child(env_node)

	var light = DirectionalLight3D.new()
	world.add_child(light)
	light.transform = Transform3D(Vector3(-0.866025, -0.433013, 0.25), Vector3(0, 0.5, 0.866025), Vector3(-0.5, 0.75, -0.433013), Vector3(0, 20, 0))
	light.shadow_enabled = true

	var ground = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(160, 1, 160)
	ground.mesh = box
	ground.material_override = TerrainBuilder.build_ground_material(Color(0.2, 0.26, 0.21), Vector2(160, 160))
	world.add_child(ground)
	ground.position = Vector3(0, -0.5, 0)

	var bp_manager = BlueprintManager.new()
	world.add_child(bp_manager)
	var parent = Node3D.new()
	world.add_child(parent)
	bp_manager.reconstruct_vehicle({
		"version": 1.0, "hull_type": "heavy_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "armor_thickness": 1.0,
		"faction": "industrialists", "modules": [],
	}, parent, false)
	parent.position = Vector3(-6, 0, 10)

	# Real RTS-ish battlefield distance (same order of magnitude as
	# Skirmish.tscn's own Camera3D position, per diagnose_glossiness_wide.gd's
	# own precedent) but close enough to still tell one hull's finish apart
	# from another at a glance.
	var cam = Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(-2, 14, 26), Vector3(-6, 1, 10), Vector3.UP)

	for i in range(6): await process_frame
	root.get_texture().get_image().save_png(OUT_DIR + "/AFTER/gameplay_distance_heavy_hull.png")
	print("[CAPTURE] saved gameplay_distance_heavy_hull.png")

	# A closer-but-still-real "mid-zoom" distance, the range a player
	# actually spends most of a match at (fully zoomed-out battlefield
	# overview vs. this session's earlier close product shots are two
	# extremes - this is the middle ground).
	cam.look_at_from_position(Vector3(-6, 5, 18), Vector3(-6, 1, 10), Vector3.UP)
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png(OUT_DIR + "/AFTER/mid_distance_heavy_hull.png")
	print("[CAPTURE] saved mid_distance_heavy_hull.png")

	# A genuine close-up that still frames the WHOLE hull length (front
	# armor arc through rear structural body in one shot) - the earlier
	# close-up pass happened to crop in tight enough that a single frame
	# showed almost entirely one material or the other, which is why a
	# fresh look at that pair alone wasn't conclusive. This is the
	# decisive close shot: same hull, same materials, framed so both
	# regions and the ink border between them are unambiguous at once.
	cam.look_at_from_position(Vector3(-1, 4.5, 15), Vector3(-6, 0.5, 10), Vector3.UP)
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png(OUT_DIR + "/AFTER/close_full_length_heavy_hull.png")
	print("[CAPTURE] saved close_full_length_heavy_hull.png")

	quit(0)
