extends SceneTree

# Compiles the fog shroud shader on a REAL renderer and reports any error.
#
# run_tests.gd is headless, and headless Godot uses the dummy rasterizer, which
# never compiles a shader - so a GLSL error in SHROUD_SHADER passes the entire
# test suite and only shows up as untextured fog in a playtest. This opens a
# small window for a few frames purely to make the driver compile it.
#
# Run (NOT headless - that is the whole point):
#   ./Godot_v4.7.1-stable_win64_console.exe --path . \
#       --script tools/probe_shroud_shader_compiles.gd

const VisionServiceScript = preload("res://scripts/battle/vision/vision_service.gd")

func _init() -> void:
	DisplayServer.window_set_size(Vector2i(128, 128))
	DisplayServer.window_set_position(Vector2i(8, 8))

	var world := Node3D.new()
	root.add_child(world)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	# look_at_from_position, not position-then-look_at: look_at() requires the
	# node to already be inside the tree AND positioned, and fails loudly
	# otherwise, leaving the camera pointing somewhere arbitrary.
	cam.look_at_from_position(Vector3(0, 12, 12), Vector3.ZERO, Vector3.UP)

	# Something opaque for the depth buffer, so the fragment path that reads
	# DEPTH_TEXTURE actually runs instead of discarding on every pixel.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.85, 0.85, 0.85)
	ground.material_override = ground_mat
	world.add_child(ground)

	# Light it. Without this the unlit ground is already nearly as dark as the
	# fog, and the clear-vs-fogged comparison below has almost no range to
	# measure across - which reads as "the fog did nothing" when it in fact
	# worked perfectly.
	var sun := DirectionalLight3D.new()
	world.add_child(sun)
	sun.look_at_from_position(Vector3(0, 20, 6), Vector3.ZERO, Vector3.UP)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.7)
	e.ambient_light_energy = 1.0
	env.environment = e
	world.add_child(env)

	# A stand-in for a tree / boulder / cliff face: something TALL. This is the
	# whole point of the change - the old shroud was a sheet lying on the
	# ground at 1.0 clearance, so anything taller than a metre punched through
	# it and stayed visible inside the fog. 8 units is well clear of any
	# sheet-based fog.
	var pillar := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3, 8, 3)
	pillar.mesh = box
	var pillar_mat := StandardMaterial3D.new()
	# Distinctly red so the sample point can be FOUND in the rendered frame
	# rather than computed. unproject_position() returns (0,0) here because the
	# root viewport has no size yet this early, and a hardcoded pixel silently
	# slides onto the ground if the framing is ever touched.
	pillar_mat.albedo_color = Color(0.9, 0.05, 0.05)
	pillar.material_override = pillar_mat
	world.add_child(pillar)
	pillar.position = Vector3(0, 4, 0)

	var vision = VisionServiceScript.new()
	vision.setup(null, 0, 40.0)
	var shroud: MeshInstance3D = vision.build_shroud()
	world.add_child(shroud)

	print("SHROUD_PROBE: instance=%s mesh=%s aabb=%s" % [
		shroud.name, shroud.mesh.get_class(), str(shroud.custom_aabb.size.x)])

	# Compiling is not drawing, so measure it - but measure it as an A/B rather
	# than against a fixed threshold. The framebuffer read back here is sRGB
	# encoded while fog_color is linear (sRGB(0.015) is about 0.14, not 0.015),
	# and it has been through tonemapping besides, so any absolute cutoff would
	# be a guess. Comparing the same pixel with the shroud hidden and shown
	# needs no such guess.
	shroud.visible = false
	for i in range(6):
		await process_frame
	var clear_luma := _sample_ground_luma()
	var pillar_px := _find_red_pixel()
	var clear_pillar := _sample_at(pillar_px)

	shroud.visible = true
	for i in range(6):
		await process_frame
	var fogged_luma := _sample_ground_luma()
	var fogged_pillar := _sample_at(pillar_px)

	print("SHROUD_PROBE: TALL OBJECT at %s luma clear=%.4f fogged=%.4f" % [
		str(pillar_px), clear_pillar, fogged_pillar])

	# No viewer was registered, so every cell is UNEXPLORED (alpha 1.0): the fog
	# is at full strength and should have REPLACED the ground colour outright.
	# So the strongest available check is not "darker" but "equal to fog_color"
	# - converted to sRGB, because that is the space get_image() reads back in.
	var expected := Color(
		_linear_to_srgb(0.015), _linear_to_srgb(0.015), _linear_to_srgb(0.02))
	var expected_luma: float = (expected.r + expected.g + expected.b) / 3.0
	print("SHROUD_PROBE: ground luma clear=%.4f fogged=%.4f expected_fog=%.4f" % [
		clear_luma, fogged_luma, expected_luma])

	if fogged_luma >= clear_luma * 0.5:
		print("SHROUD_PROBE: *** FOG DID NOT DRAW *** full-strength fog barely changed the ground")
		quit(1)
		return
	if absf(fogged_luma - expected_luma) > 0.02:
		print("SHROUD_PROBE: *** FOG DREW THE WRONG COLOUR *** expected ~%.4f" % expected_luma)
		quit(1)
		return
	# The requirement itself: an 8-unit-tall object must be fogged too. Under
	# the old ground-hugging sheet (1.0 clearance) this pixel was untouched,
	# which is exactly the "fog only covers the base ground" report.
	if pillar_px.x < 0.0:
		print("SHROUD_PROBE: *** PROBE BUG *** tall object was not framed (no red pixel found)")
		quit(1)
		return
	if absf(fogged_pillar - expected_luma) > 0.02:
		print("SHROUD_PROBE: *** TALL GEOMETRY NOT FOGGED *** expected ~%.4f, got %.4f" % [
			expected_luma, fogged_pillar])
		quit(1)
		return

	print("SHROUD_PROBE: fog covers world geometry at full strength, INCLUDING tall objects")
	quit(0)


func _linear_to_srgb(x: float) -> float:
	if x <= 0.0031308:
		return x * 12.92
	return 1.055 * pow(x, 1.0 / 2.4) - 0.055


func _sample_ground_luma() -> float:
	var img: Image = root.get_texture().get_image()
	return _sample_at(Vector2(img.get_width() / 2, int(img.get_height() * 0.65)))


# Locates the tall red pillar in the CLEAR frame. Returns (-1, -1) if it is
# not on screen at all, so a mis-framed probe reports itself instead of
# quietly sampling empty ground and declaring success.
func _find_red_pixel() -> Vector2:
	var img: Image = root.get_texture().get_image()
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.r > 0.4 and c.g < 0.3 and c.b < 0.3:
				return Vector2(x, y)
	return Vector2(-1, -1)


func _sample_at(px: Vector2) -> float:
	var img: Image = root.get_texture().get_image()
	var x: int = clampi(int(px.x), 0, img.get_width() - 1)
	var y: int = clampi(int(px.y), 0, img.get_height() - 1)
	var c: Color = img.get_pixel(x, y)
	return (c.r + c.g + c.b) / 3.0
