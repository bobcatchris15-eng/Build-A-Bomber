extends SceneTree
# Scratch: diagnostic-only, NOT a fix. Chris flagged the whole game looking
# too shiny/glossy (grass AND hull materials both) and asked for a real
# diagnosis before touching any individual material: replicate the exact
# Environment/Sky/DirectionalLight3D every real gameplay scene uses
# (Skirmish.tscn/MainLab.tscn/Battlefield.tscn all share the identical
# sub-resource pattern - background_mode=Sky with a bright grey
# ProceduralSkyMaterial, tonemap_mode=Filmic, no explicit ambient_light_
# source/reflected_light_source override so both default to BG/sky), then
# render StandardMaterial3D swatches at KNOWN roughness values under that
# exact setup - if even roughness=1.0 (maximally rough, should be
# perfectly matte with zero specular) shows a visible sheen, the
# environment/lighting is the root cause; if only low-roughness swatches
# look glossy and 1.0 looks properly flat, the individual materials
# themselves are the problem.
# Must run WITHOUT --headless (needs a real GPU viewport for pixel readback).
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/diagnose_glossiness.gd

const OUT_DIR = "res://progress_captures/2026-07-17/glossiness_diagnosis"

func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var world = Node3D.new()
	root.add_child(world)
	current_scene = world

	# Exact copy of Skirmish.tscn's Environment sub-resource.
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
	print("[DIAG] ambient_light_source=", env.ambient_light_source, " reflected_light_source=", env.reflected_light_source, " ambient_light_energy=", env.ambient_light_energy, " ssr_enabled=", env.ssr_enabled, " glow_enabled=", env.glow_enabled)

	# Exact copy of Skirmish.tscn's DirectionalLight3D transform.
	var light = DirectionalLight3D.new()
	world.add_child(light)
	light.transform = Transform3D(Vector3(-0.866025, -0.433013, 0.25), Vector3(0, 0.5, 0.866025), Vector3(-0.5, 0.75, -0.433013), Vector3(0, 20, 0))
	light.shadow_enabled = true
	print("[DIAG] light_energy=", light.light_energy, " light_specular=", light.light_specular, " light_indirect_energy=", light.light_indirect_energy)

	# 6 flat swatches in a row: pure-dielectric roughness sweep (0.0/0.5/1.0
	# at metallic=0, isolating roughness's own effect), hardened_steel's
	# real armor PBR values (metallic=0.8/roughness=0.2 - hull_material_
	# builder.gd's ARMOR_PBR), and the real baked grassland texture two ways
	# (as authored, and forced to roughness=1.0 to see if even that removes
	# the sheen).
	var grass_tex = load("res://assets/textures/terrain/grassland_albedo.png")
	var grass_rough_tex = load("res://assets/textures/terrain/grassland_roughness.png")

	var swatches = [
		{"label": "rough_0.0", "roughness": 0.0, "metallic": 0.0},
		{"label": "rough_0.5", "roughness": 0.5, "metallic": 0.0},
		{"label": "rough_1.0", "roughness": 1.0, "metallic": 0.0},
		{"label": "hardened_steel(m0.8 r0.2)", "roughness": 0.2, "metallic": 0.8},
		{"label": "grassland_as_authored", "roughness": 1.0, "roughness_tex": grass_rough_tex, "albedo_tex": grass_tex},
		{"label": "grassland_forced_r1.0", "roughness": 1.0, "roughness_tex": null, "albedo_tex": grass_tex},
	]

	var spacing = 3.2
	var start_x = -spacing * (swatches.size() - 1) / 2.0
	for i in range(swatches.size()):
		var s = swatches[i]
		var mesh_inst = MeshInstance3D.new()
		var plane = PlaneMesh.new()
		plane.size = Vector2(2.6, 2.6)
		mesh_inst.mesh = plane
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.6, 0.6) if not s.has("albedo_tex") else Color.WHITE
		mat.metallic = s.get("metallic", 0.0)
		mat.roughness = s.roughness
		if s.get("albedo_tex"):
			mat.albedo_texture = s.albedo_tex
		if s.has("roughness_tex") and s.roughness_tex:
			mat.roughness_texture = s.roughness_tex
		mesh_inst.material_override = mat
		world.add_child(mesh_inst)
		mesh_inst.global_position = Vector3(start_x + i * spacing, 0, 0)

		var label = Label3D.new()
		label.text = s.label
		label.font_size = 20
		label.position = Vector3(0, 1.6, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mesh_inst.add_child(label)

	var cam = Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 9, 11), Vector3(0, 0, 0), Vector3.UP)

	for i in range(6): await process_frame
	var img = root.get_texture().get_image()
	img.save_png(OUT_DIR + "/roughness_sweep_current_lighting.png")
	print("[CAPTURE] saved roughness_sweep_current_lighting.png")

	quit(0)
