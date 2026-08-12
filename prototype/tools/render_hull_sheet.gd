# Renders every vehicle hull to one contact-sheet PNG, through Godot's real
# renderer with backface culling ON.
#
# This is the visual counterpart to scratch/hull_probe/verify_winding.gd. That
# script proves the winding matches known-good assets numerically; this one
# proves it by eye, because an inside-out hull renders as a hollow shell with
# its near faces missing and there is no mistaking it in an image.
#
# Must run WITHOUT --headless: it needs a real rendering device.
#
#   ./Godot_v4.7.1-stable_win64_console.exe --path . \
#       --script tools/render_hull_sheet.gd -- <out.png> [--cols 10] [--cell 320x240]

extends SceneTree

const HULLS_DIR := "res://assets/models/hulls"

# Front-left-above. Godot's nose is -Z, so the camera has to sit on the -Z side
# to see the front of the vehicle rather than its transom.
const VIEW_DIR := Vector3(0.85, 0.52, -1.0)


func _init() -> void:
	var out_path := "hull_sheet.png"
	var cols := 10
	var cell := Vector2i(320, 240)
	var only := PackedStringArray()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i].to_lower().ends_with(".png"):
			out_path = args[i]
		elif args[i] == "--cols" and i + 1 < args.size():
			cols = int(args[i + 1])
		elif args[i] == "--only" and i + 1 < args.size():
			only = args[i + 1].split(",")
		elif args[i] == "--cell" and i + 1 < args.size():
			var parts: PackedStringArray = args[i + 1].split("x")
			if parts.size() == 2:
				cell = Vector2i(int(parts[0]), int(parts[1]))

	var ids := _vehicle_hull_ids()
	if not only.is_empty():
		var filtered: Array = []
		for id in ids:
			if id in only:
				filtered.append(id)
		ids = filtered
	if ids.is_empty():
		print("SHEET: no vehicle hulls found in %s" % HULLS_DIR)
		quit(1)
		return
	print("SHEET: %d hulls, %d cols, cell %s" % [ids.size(), cols, cell])

	var rows: int = int(ceil(float(ids.size()) / float(cols)))
	var sheet := Image.create(cols * cell.x, rows * cell.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.10, 0.11, 0.13, 1.0))

	var vp := SubViewport.new()
	vp.size = cell
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.14, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.45, 0.50)
	e.ambient_light_energy = 0.75
	env.environment = e
	vp.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 138, 0)
	key.light_energy = 2.1
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-14, -46, 0)
	fill.light_energy = 0.65
	vp.add_child(fill)

	var cam := Camera3D.new()
	vp.add_child(cam)

	var label := Label.new()
	label.position = Vector2(6, cell.y - 26)
	label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	label.add_theme_font_size_override("font_size", 15)
	vp.add_child(label)

	var placed := 0
	for i in ids.size():
		var id: String = ids[i]
		var inst := _load_hull(id)
		if inst == null:
			print("SHEET: skip %s (no .glb)" % id)
			continue
		vp.add_child(inst)

		# Framed from the sidecar's declared size rather than a measured AABB.
		# Every vehicle hull is authored centred on the origin with its AABB
		# equal to that size, so the two are the same number - and reading the
		# sidecar means the framing does not depend on the instance being
		# inside the tree yet.
		var size: Vector3 = _declared_size(id)
		var radius: float = maxf(size.length() * 0.5, 0.01)
		# look_at_from_position, not look_at: the camera was only just added and
		# is not inside the tree, so it has no global_transform to rotate.
		cam.look_at_from_position(
			VIEW_DIR.normalized() * radius * 2.55, Vector3.ZERO, Vector3.UP)
		label.text = id

		# Two frames: one for the scene to be added, one for the render target
		# to actually contain it.
		await process_frame
		await RenderingServer.frame_post_draw
		await process_frame
		await RenderingServer.frame_post_draw

		var img := vp.get_texture().get_image()
		# The viewport's render target is not RGBA8, and blit_rect refuses a
		# format mismatch outright rather than converting for you.
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		var col := i % cols
		var row := int(i / cols)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
			Vector2i(col * cell.x, row * cell.y))
		placed += 1

		vp.remove_child(inst)
		inst.queue_free()

	var err := sheet.save_png(out_path)
	if err != OK:
		print("SHEET: save_png failed err=%d for %s" % [err, out_path])
		quit(1)
		return
	print("SHEET: wrote %s (%d hulls)" % [out_path, placed])
	quit(0)


func _vehicle_hull_ids() -> Array:
	# Sidecar-driven, same as HullLoader: is_foundation filters the static
	# defenses out so the sheet is the vehicle catalogue only.
	var out: Array = []
	var dir := DirAccess.open(HULLS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.get_extension() == "json":
			var path := "%s/%s" % [HULLS_DIR, f]
			var text := FileAccess.get_file_as_string(path)
			var data = JSON.parse_string(text)
			if typeof(data) == TYPE_DICTIONARY and not data.get("is_foundation", false):
				out.append(f.get_basename())
		f = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _load_hull(id: String) -> Node3D:
	var path := "%s/%s.glb" % [HULLS_DIR, id]
	if not ResourceLoader.exists(path):
		return null
	var res := load(path)
	if res is PackedScene:
		return (res as PackedScene).instantiate() as Node3D
	if res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res as Mesh
		return mi
	return null


func _declared_size(id: String) -> Vector3:
	var text := FileAccess.get_file_as_string("%s/%s.json" % [HULLS_DIR, id])
	var data = JSON.parse_string(text)
	if typeof(data) == TYPE_DICTIONARY:
		var s = data.get("size", null)
		if typeof(s) == TYPE_ARRAY and s.size() == 3:
			return Vector3(s[0], s[1], s[2])
	return Vector3.ONE * 4.0
