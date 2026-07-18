extends SceneTree
# Scratch: diagnostic-only. Follow-up to diagnose_glossiness.gd's flat-swatch
# test, which was inconclusive for terrain (a small 2.6-unit un-tiled quad at
# a fixed angle may simply not catch a stray specular/Fresnel glint the way
# a large, many-times-tiled ground plane viewed at the real RTS camera's
# raking angle would). Builds a full-size (160-unit) grassland ground plane
# - same call skirmish.gd makes - under the exact Skirmish.tscn Environment/
# light/camera transform (not a look_at_from_position approximation), so
# this is as close to "what a player actually sees" as a scratch script gets.
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/diagnose_glossiness_wide.gd

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")
const HullMaterialBuilder = preload("res://scripts/hull_material_builder.gd")

const OUT_DIR = "res://progress_captures/2026-07-17/glossiness_diagnosis"

func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

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

	# Real 160x160 grassland Ground plane, same material call skirmish.gd
	# makes (build_ground_material), same size as lake_crossing's default map.
	var ground = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(160, 1, 160)
	ground.mesh = box
	ground.material_override = TerrainBuilder.build_ground_material(Color(0.2, 0.26, 0.21), Vector2(160, 160))
	world.add_child(ground)
	ground.position = Vector3(0, -0.5, 0)

	# A real hull, same call blueprint_manager.gd/module_placer.gd make -
	# hardened_steel armor on industrialists (the default faction), sitting
	# on the grass so hull-vs-terrain glossiness is visible in the SAME shot.
	var hull = MeshInstance3D.new()
	var hull_box = BoxMesh.new()
	hull_box.size = Vector3(4, 1.5, 8)
	hull.mesh = hull_box
	hull.material_override = HullMaterialBuilder.build_hull_material("hardened_steel", "industrialists")
	world.add_child(hull)
	hull.position = Vector3(-6, 1.0, 10)

	# Skirmish.tscn's raw Camera3D transform (position (0,26,52), basis
	# columns (1,0,0)/(0,.707,.707)/(0,-.707,.707)) turns out to point AWAY
	# from the ground when taken at face value (confirmed empirically - a
	# first attempt using it verbatim rendered nothing but sky). Whatever
	# the RTSCam script does at runtime to actually frame the battlefield,
	# it isn't just "use this transform as authored" - so use the same
	# real-world distance/height via look_at_from_position instead, which
	# is what every other capture script in this session already does
	# successfully.
	var cam = Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 26, 40), Vector3(0, 0, 0), Vector3.UP)

	for i in range(6): await process_frame
	var img = root.get_texture().get_image()
	img.save_png(OUT_DIR + "/wide_ground_plus_hull_real_camera.png")
	print("[CAPTURE] saved wide_ground_plus_hull_real_camera.png")

	# Closer product-shot angle on the same hull+ground - matching the
	# camera distance/pitch capture_faction_materials.gd used for the
	# faction lineup screenshot (which clearly showed a blown-out specular
	# streak on every hull), so this is an apples-to-apples look at whether
	# the same streak reproduces here, now with grass visible underneath.
	cam.look_at_from_position(Vector3(-6, 8, 22), Vector3(-6, 1, 10), Vector3.UP)
	for i in range(6): await process_frame
	var img2 = root.get_texture().get_image()
	img2.save_png(OUT_DIR + "/close_hull_on_grass_real_camera.png")
	print("[CAPTURE] saved close_hull_on_grass_real_camera.png")

	# EXACT same camera position/target as capture_faction_materials.gd's
	# faction lineup shot (the one that originally revealed a blown-out
	# diagonal specular streak on every hull top, before the 2026-07-17
	# hardened_steel roughness fix - see DECISIONS_NEEDED.md) - relative to
	# this hull's position, so this is the truest apples-to-apples spot-
	# check for a regression of that specific artifact.
	cam.look_at_from_position(Vector3(-6, 7, 18), Vector3(-6, 1, 10), Vector3.UP)
	for i in range(6): await process_frame
	var img3 = root.get_texture().get_image()
	img3.save_png(OUT_DIR + "/hull_streak_repro.png")
	print("[CAPTURE] saved hull_streak_repro.png")

	quit(0)
