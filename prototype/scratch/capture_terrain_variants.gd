extends SceneTree
# Scratch: windowed screenshots proving the terrain variant work actually
# changes what's on screen (Chris, 2026-07-29: "a broader range of terrain
# ones each one can sample from instead of being one tiled again and again.
# at RTS scale, large differentiation will be more important than seam
# matching on terrain maps and buildings").
#
# Two captures, deliberately paired - a single "after" shot proves nothing
# without the "before" beside it, and the whole claim here is comparative:
#   1. ground_single_vs_blended.png - one big ground plane at RTS camera
#      height, rendered twice: left half with variant_count forced to 1 (the
#      old behaviour, one tile repeated), right half with the full blend.
#   2. surface_variant_grid.png     - every surface type that got Flow
#      variants, each shown as its 4 variants side by side, so it's obvious
#      whether the derived variants (rotate + tonal shift) actually read as
#      different ground or just as the same plate twice.
#
# Capture 2 is the honest check on the weakest part of this pass: variants
# 2 and 3 are re-mixes of variant 1's source plate, not new source art. If
# they don't read as distinct here, the answer is more Flow plates, not more
# re-mixing.
#
# Must run WITHOUT --headless (needs a real framebuffer to screenshot).
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_terrain_variants.gd

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")

const OUT_DIR = "res://progress_captures/2026-07-30/terrain_variants"
const SURFACES = ["grassland", "marsh", "snow_mud", "sand", "rocky", "gravel", "forest"]

func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_report_variants()
	await _capture_ground_comparison()
	await _capture_variant_grid()
	print("Captures written to ", OUT_DIR)
	quit(0)

# Print what the discovery actually found before rendering anything - if this
# says 1 variant for everything, the PNGs weren't imported and both captures
# below would be identical for reasons that have nothing to do with the
# shader.
func _report_variants() -> void:
	print("--- terrain variants discovered ---")
	for s in SURFACES:
		var v = TerrainBuilder._get_terrain_variants(s)
		print("  %-12s %d  %s" % [s, v.size(), str(v)])

func _make_world() -> Node3D:
	var world = Node3D.new()
	root.add_child(world)
	current_scene = world

	var light = DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-48, -34, 0)
	light.light_energy = 1.4
	light.light_color = Color(1.0, 0.97, 0.9)
	light.shadow_enabled = true

	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.78, 0.80, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.64, 0.72)
	env.ambient_light_energy = 0.7
	env_node.environment = env
	world.add_child(env_node)
	return world

# Ground plane with world-position UVs baked in, matching what
# build_ground_visual_mesh() produces - the shader's noise is driven by UV, so
# feeding it a default 0..1 PlaneMesh UV would sample one blend value across
# the whole plane and show nothing.
func _ground_plane(size: float) -> MeshInstance3D:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var res := 24
	var step := size / float(res)
	for row in range(res):
		for col in range(res):
			var x0 := -size * 0.5 + col * step
			var z0 := -size * 0.5 + row * step
			var corners = [
				Vector3(x0, 0, z0), Vector3(x0 + step, 0, z0),
				Vector3(x0 + step, 0, z0 + step), Vector3(x0, 0, z0 + step)]
			for idx in [0, 1, 2, 0, 2, 3]:
				var v: Vector3 = corners[idx]
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(v.x, v.z) / 6.0)
				st.add_vertex(v)
	st.generate_tangents()
	var mi = MeshInstance3D.new()
	mi.mesh = st.commit()
	return mi

func _capture_ground_comparison() -> void:
	var world = _make_world()

	# Left: forced to a single variant (old behaviour). Right: full blend.
	# Same shader in both cases, so the only difference between the halves is
	# variant_count - which is exactly the claim being tested.
	var single = _ground_plane(220.0)
	single.material_override = TerrainBuilder.build_blended_surface_material(
		"grassland", Color(0.72, 0.76, 0.7))
	(single.material_override as ShaderMaterial).set_shader_parameter("variant_count", 1)
	single.position = Vector3(-115, 0, 0)
	world.add_child(single)

	var blended = _ground_plane(220.0)
	blended.material_override = TerrainBuilder.build_blended_surface_material(
		"grassland", Color(0.72, 0.76, 0.7))
	blended.position = Vector3(115, 0, 0)
	world.add_child(blended)

	var cam = Camera3D.new()
	# Roughly the game's RTS framing: high, steeply angled, seeing a lot of
	# ground at once - which is the condition that makes tiling obvious.
	cam.fov = 60
	world.add_child(cam)
	# look_at_from_position rather than position + look_at: look_at needs a
	# valid global transform, and depending on when the node actually enters
	# the tree it can error out and silently leave the camera pointing down
	# -Z at the horizon - which produces a screenshot of the sky that looks
	# like the terrain failed rather than like the camera did.
	cam.look_at_from_position(Vector3(0, 120, 130), Vector3(0, 0, 0), Vector3.UP)

	await _shot("ground_single_vs_blended.png")
	world.queue_free()
	await process_frame

func _capture_variant_grid() -> void:
	var world = _make_world()
	var x := 0.0
	for s in SURFACES:
		var variants = TerrainBuilder._get_terrain_variants(s)
		var z := 0.0
		for v in variants:
			var quad = MeshInstance3D.new()
			var plane = PlaneMesh.new()
			plane.size = Vector2(10, 10)
			quad.mesh = plane
			var mat = StandardMaterial3D.new()
			var tex = TerrainBuilder._get_terrain_textures(s, v)
			mat.albedo_texture = tex.albedo
			mat.normal_enabled = true
			mat.normal_texture = tex.normal
			mat.roughness_texture = tex.roughness
			# Two repeats per swatch so each cell shows its own tiling
			# behaviour, not just one blown-up copy of the plate.
			mat.uv1_scale = Vector3(2, 2, 1)
			quad.material_override = mat
			quad.position = Vector3(x, 0, z)
			world.add_child(quad)
			z += 11.0
		x += 11.0

	var cam = Camera3D.new()
	world.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 58.0
	cam.position = Vector3(x * 0.5 - 5.5, 60, 16.5)
	cam.rotation_degrees = Vector3(-90, 0, 0)

	await _shot("surface_variant_grid.png")
	world.queue_free()
	await process_frame

func _shot(name: String) -> void:
	# Several frames, not one: the first frame after a scene swap can render
	# before textures/shaders have finished compiling, which produces a
	# convincing-looking but wrong screenshot.
	for i in range(6):
		await process_frame
	var img = root.get_texture().get_image()
	img.save_png(OUT_DIR + "/" + name)
	print("  wrote ", name)
