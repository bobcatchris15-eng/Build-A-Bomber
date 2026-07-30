extends SceneTree
# Scratch: windowed screenshots for the comic-book/cel-shaded UNIT treatment
# (Chris, 2026-07-29: "make the units have a slight cartoonish / comic book
# look, against the more serious landscapes ... heavy lines and saturated
# colors, almost cel-shaded"). Three captures:
#   1. toon_bands sweep     - pick the band count (2 = hard comic, 4 = soft cel)
#   2. ink_width sweep      - pick the outline weight
#   3. units_on_terrain     - the actual point of the treatment: cartoon units
#                             sitting on a PHOTOREAL matte ground plane, lit by
#                             a warm key light matching the Flow lighting
#                             reference (bleached hot sun, hard shadow).
# The band/ink sweeps are the two knobs worth eyeballing before committing
# defaults; everything else in the shader is a secondary trim.
#
# Must run WITHOUT --headless (needs a real framebuffer to screenshot).
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_toon_units.gd

const BlueprintManager = preload("res://scripts/blueprint_manager.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")

const OUT_DIR = "res://progress_captures/2026-07-29/toon_units"

# Warm hard key + cool low ambient, matching the Flow reference plate's
# midday-sun/dust-haze read rather than the neutral studio setup the older
# capture scripts use - the toon bands respond strongly to key direction and
# ambient level, so judging them under a neutral grey studio light would give
# a misleading result.
func _make_world(ground: bool) -> Node3D:
	var world = Node3D.new()
	root.add_child(world)
	current_scene = world

	var light = DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-48, -34, 0)
	light.light_energy = 1.5
	light.light_color = Color(1.0, 0.95, 0.84)
	light.shadow_enabled = true

	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.74, 0.76, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.60, 0.72)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	world.add_child(env_node)

	if ground:
		# Deliberately a plain matte StandardMaterial3D, i.e. still PBR - the
		# whole treatment depends on the ground NOT being toon-shaded, so this
		# capture is only meaningful if the floor stays photoreal.
		var floor_mesh = MeshInstance3D.new()
		var plane = PlaneMesh.new()
		plane.size = Vector2(120, 120)
		floor_mesh.mesh = plane
		var gm = StandardMaterial3D.new()
		gm.albedo_color = Color(0.46, 0.42, 0.30)
		gm.roughness = 0.95
		gm.metallic = 0.0
		floor_mesh.material_override = gm
		world.add_child(floor_mesh)
		floor_mesh.position = Vector3(0, -0.05, 0)

	return world

func _spawn(bp_manager, world: Node3D, faction: String, pos: Vector3) -> Node3D:
	var parent = Node3D.new()
	world.add_child(parent)
	bp_manager.reconstruct_vehicle({
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "armor_thickness": 1.0,
		"faction": faction, "modules": [],
	}, parent, false)
	parent.global_position = pos
	return parent

# Walks every ShaderMaterial under a spawned vehicle and overrides one toon
# uniform, so a single capture can show the same hull at several settings.
func _set_param(node: Node, param: String, value) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for surf in range(mi.get_surface_override_material_count()):
			var m = mi.get_surface_override_material(surf)
			if m is ShaderMaterial:
				m.set_shader_parameter(param, value)
		if mi.material_override is ShaderMaterial:
			mi.material_override.set_shader_parameter(param, value)
	for child in node.get_children():
		_set_param(child, param, value)

func _label(parent: Node3D, text: String) -> void:
	var l = Label3D.new()
	l.text = text
	l.font_size = 26
	l.outline_size = 8
	l.position = Vector3(0, 2.3, 0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(l)

func _sweep(param: String, values: Array, filename: String) -> void:
	var world = _make_world(false)
	var cam = Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 5.5, 15), Vector3(0, 0.8, 0), Vector3.UP)
	var bp = BlueprintManager.new()
	world.add_child(bp)

	var spacing = 4.0
	var start_x = -spacing * (values.size() - 1) / 2.0
	for i in range(values.size()):
		var unit = _spawn(bp, world, "industrialists", Vector3(start_x + i * spacing, 0, 0))
		_set_param(unit, param, values[i])
		_label(unit, "%s = %s" % [param, str(values[i])])

	for _i in range(8): await process_frame
	root.get_texture().get_image().save_png("%s/%s" % [OUT_DIR, filename])
	print("[CAPTURE] saved %s" % filename)
	world.queue_free()
	await process_frame

func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	await _sweep("toon_bands", [2.0, 3.0, 4.0, 6.0], "toon_bands_sweep.png")
	await _sweep("ink_width", [0.15, 0.32, 0.55, 0.8], "ink_width_sweep.png")

	# --- The actual test: cartoon units on a photoreal matte ground ---
	var world = _make_world(true)
	var cam = Camera3D.new()
	world.add_child(cam)
	# Roughly the RTS camera's working angle/height rather than a hero shot -
	# this look has to hold up at the distance the game is actually played at.
	cam.look_at_from_position(Vector3(0, 12, 20), Vector3(0, 0, -2), Vector3.UP)
	var bp = BlueprintManager.new()
	world.add_child(bp)

	var factions = ["industrialists", "technocrats", "crimson_concordat", "dune_runners"]
	var spacing = 5.0
	var start_x = -spacing * (factions.size() - 1) / 2.0
	for i in range(factions.size()):
		_spawn(bp, world, factions[i], Vector3(start_x + i * spacing, 0, 0))

	for _i in range(8): await process_frame
	root.get_texture().get_image().save_png("%s/units_on_terrain.png" % OUT_DIR)
	print("[CAPTURE] saved units_on_terrain.png")
	world.queue_free()
	await process_frame

	quit(0)
