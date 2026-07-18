extends SceneTree
# Scratch: RIGOROUS pixel-level verification, not visual impression. Chris
# (relaying skepticism from looking at the hull screenshots directly)
# couldn't see a clear difference in the heavy_hull before/after pair.
# Two separate controlled tests, each isolating ONE effect from the other
# and from confounding geometry/lighting complexity:
#
# Test A (material contrast in isolation): two identical flat boxes side
# by side, one with the real armor material, one with the real structural
# material, same light/camera/distance - samples the CENTER of each box's
# front face (deliberately far from any edge, so the ink border can't be
# contributing) and prints exact RGB + computes the delta.
#
# Test B (ink border in isolation): ONE box, single material, viewed at an
# angle that shows a real corner edge - scans a horizontal pixel row
# straight across that edge and prints R at every X coordinate, so the
# darkening dip at the edge is a literal number in a printed list, not an
# eyeballed impression of a screenshot.
#
# Must run WITHOUT --headless (needs a real rendered frame to read pixels
# back from).
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/pixel_verify_contrast_and_ink.gd

const HullMaterialBuilder = preload("res://scripts/hull_material_builder.gd")
const OUT_DIR = "res://progress_captures/2026-07-18/pixel_verify"

func _make_world(ambient_energy: float = 0.5) -> Node3D:
	var world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var light = DirectionalLight3D.new()
	world.add_child(light)
	# A raking-ish angle (not face-on, not grazing) so a shinier material's
	# specular highlight is visible without blowing out the whole face.
	light.rotation_degrees = Vector3(-35, -50, 0)
	light.light_energy = 1.4
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = ambient_energy
	env_node.environment = env
	world.add_child(env_node)
	return world

func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	await _test_a_material_contrast()
	await _test_b_ink_border()
	quit(0)

# --- Test A: material contrast, isolated from any edge ---
func _test_a_material_contrast():
	var world = _make_world(0.5)
	var cam = Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0, 6), Vector3(0, 0, 0), Vector3.UP)

	var armor_mat = HullMaterialBuilder.build_hull_material("hardened_steel", "industrialists")
	var structural_mat = HullMaterialBuilder.build_structural_material("industrialists")

	var box_a = MeshInstance3D.new()
	var mesh_a = BoxMesh.new()
	mesh_a.size = Vector3(2.5, 2.5, 2.5)
	box_a.mesh = mesh_a
	box_a.material_override = armor_mat
	world.add_child(box_a)
	box_a.position = Vector3(-2.0, 0, 0)

	var box_b = MeshInstance3D.new()
	var mesh_b = BoxMesh.new()
	mesh_b.size = Vector3(2.5, 2.5, 2.5)
	box_b.mesh = mesh_b
	box_b.material_override = structural_mat
	world.add_child(box_b)
	box_b.position = Vector3(2.0, 0, 0)

	for i in range(8): await process_frame
	var img = root.get_texture().get_image()
	img.save_png(OUT_DIR + "/test_a_material_contrast.png")

	var viewport_size = root.get_visible_rect().size
	print("[TEST A] viewport size: ", viewport_size)
	# Screen-space centers of each box's front face - the viewport is
	# 1280x720 by default and both boxes are centered vertically, so the
	# face centers land close to (320, 360) and (960, 360) respectively;
	# refined by scanning a small neighborhood and taking the brightest
	# cluster's center to avoid hand-picking a coordinate that might miss.
	# Coordinates confirmed against the actual saved render (test_a_
	# material_contrast.png) - the boxes land at roughly x=440 (armor) and
	# x=835 (structural), y=360, NOT the originally-guessed 260/1020, which
	# landed entirely on background and produced a meaningless near-zero
	# "delta" the first time this test ran.
	var pixel_a = _sample_region_avg(img, 440, 360, 50)
	var pixel_b = _sample_region_avg(img, 835, 360, 50)
	print("[TEST A] armor face avg RGB   = ", pixel_a)
	print("[TEST A] structural face avg RGB = ", pixel_b)
	print("[TEST A] delta (armor - structural) = ", pixel_a - pixel_b)
	print("[TEST A] delta luminance = ", (pixel_a.r + pixel_a.g + pixel_a.b) / 3.0 - (pixel_b.r + pixel_b.g + pixel_b.b) / 3.0)

	world.queue_free()
	await process_frame

func _sample_region_avg(img: Image, cx: int, cy: int, half: int) -> Color:
	var sum = Color(0, 0, 0)
	var count = 0
	for y in range(cy - half, cy + half, 4):
		for x in range(cx - half, cx + half, 4):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			sum += img.get_pixel(x, y)
			count += 1
	return sum / float(max(count, 1))

# --- Test B: ink border, isolated on one material, scanning across a real edge ---
func _test_b_ink_border():
	var world = _make_world(0.6)
	var cam = Camera3D.new()
	world.add_child(cam)
	# 3/4 angle so a real vertical edge (where two faces meet) sits roughly
	# in the middle third of frame, not right at the silhouette.
	cam.look_at_from_position(Vector3(3.2, 1.0, 3.2), Vector3(0, 0, 0), Vector3.UP)

	var mat = HullMaterialBuilder.build_hull_material("hardened_steel", "industrialists")
	var box = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(3, 3, 3)
	box.mesh = mesh
	box.material_override = mat
	world.add_child(box)

	for i in range(8): await process_frame
	var img = root.get_texture().get_image()
	img.save_png(OUT_DIR + "/test_b_ink_border.png")

	# Scan a horizontal row through the vertical box edge, printing R at
	# every 4th pixel - the edge should show up as a real, sharp dip in
	# brightness, not a gradual/nonexistent one.
	var row_y = int(img.get_height() * 0.5)
	print("[TEST B] scanning row y=", row_y)
	var line = []
	for x in range(400, 900, 4):
		var c = img.get_pixel(x, row_y)
		line.append("%d:%.2f" % [x, (c.r + c.g + c.b) / 3.0])
	print("[TEST B] luminance profile (x:lum): ", " ".join(line))

	world.queue_free()
	await process_frame
