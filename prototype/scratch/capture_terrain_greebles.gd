extends SceneTree
# Scratch: windowed screenshots verifying the new procedural terrain
# textures (tools/generate_terrain_textures.gd) and ground-clutter greebles
# (scripts/terrain_greebles.gd) actually render for each of the 5
# locomotor-differentiated terrain types. Must run WITHOUT --headless (a
# real GPU viewport is needed to read back rendered pixels).
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_terrain_greebles.gd
#
# Light direction copied from scenes/skirmish.tscn's DirectionalLight3D (the
# same "sun" the baked terrain textures' own directional-shading pass
# assumes). Camera uses a plain look_at_from_position() elevated ~45 degrees
# over a single 18x18 zone, rather than reverse-engineering the real
# RTSCam script's runtime pan/zoom transform - close enough to the real
# in-game angle to judge texture/greeble legibility, without depending on
# a controller script this scratch scene never instantiates.

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")

const OUT_DIR = "res://progress_captures/2026-07-17/terrain_textures_greebles"

func _make_world(ground_color: Color) -> Node3D:
	var world = Node3D.new()
	root.add_child(world)
	current_scene = world

	var light = DirectionalLight3D.new()
	world.add_child(light)
	light.transform = Transform3D(Vector3(-0.866025, -0.433013, 0.25), Vector3(0, 0.5, 0.866025), Vector3(-0.5, 0.75, -0.433013), Vector3(0, 20, 0))
	light.shadow_enabled = true

	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.09, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.35, 0.38)
	env.ambient_light_energy = 0.5
	env_node.environment = env
	world.add_child(env_node)

	var ground = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var mat = StandardMaterial3D.new()
	mat.albedo_color = ground_color
	ground.material_override = mat
	world.add_child(ground)

	var cam = Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 13, 13), Vector3(0, 0, 0), Vector3.UP)
	return world

func _capture(name: String, world: Node3D):
	for i in range(6): await process_frame
	var img = root.get_texture().get_image()
	img.save_png(OUT_DIR + "/" + name + ".png")
	print("[CAPTURE] saved ", name, ".png")
	world.queue_free()

func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var surface_types = [
		{"type": "marsh", "ground_color": Color(0.28, 0.26, 0.16)},
		{"type": "rocky", "ground_color": Color(0.28, 0.26, 0.16)},
		{"type": "snow_mud", "ground_color": Color(0.28, 0.26, 0.16)},
		{"type": "sand", "ground_color": Color(0.28, 0.26, 0.16)},
	]
	for entry in surface_types:
		var world = _make_world(entry.ground_color)
		var map_def = {
			"map_half_extents": 70.0,
			"surface_zones": [
				{"center": Vector3(0, 0, 0), "half_extents": Vector2(9, 9), "surface_type": entry.type},
			],
		}
		TerrainBuilder.spawn_visuals(map_def, world)
		await _capture("terrain_" + entry.type, world)
		await process_frame

	# Shallow water: needs the underlying water_areas rect too, since
	# _spawn_shallow_water_marker draws its marker ON TOP of the main water
	# plane, not standalone.
	var water_world = _make_world(Color(0.26, 0.28, 0.22))
	var water_map_def = {
		"map_half_extents": 80.0,
		"water_areas": [
			{"center": Vector3(0, 0, 0), "half_extents": Vector2(12, 12)},
		],
		"shallow_water_areas": [
			{"center": Vector3(0, 0, 0), "half_extents": Vector2(9, 9)},
		],
	}
	TerrainBuilder.spawn_visuals(water_map_def, water_world)
	await _capture("terrain_shallow_water", water_world)

	quit(0)
