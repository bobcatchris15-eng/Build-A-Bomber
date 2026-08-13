extends SceneTree
# Renders the Design Lab and saves the parts dock to a PNG, closed and open.
#
# Styling is the one kind of change a headless assert cannot judge - "does this
# read as a chipped steel toolbox" is not a number - so this exists to put an
# actual image in front of a human rather than to pass.
#
# It also covers the failure mode a unit test would miss and that this dock
# actually shipped: an open drawer whose card grid was parented to a bare
# Control, which reserved no layout height, so the cards drew over the next
# drawer's header. That is invisible to any assertion about the metadata
# contract and obvious in a screenshot.
#
# NOT --headless: this captures the rendered frame, so it needs a real
# rendering context and therefore a window.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --path . \
#          --script tools/probe_parts_dock_look.gd

const OUT_CLOSED := "user://parts_dock_closed.png"
const OUT_OPEN := "user://parts_dock_open.png"

# The dock is DOCK_LEFT_INSET (20) + TOOLBOX_WIDTH (320) wide, plus a margin so
# the crop shows the edge of the box against the 3D viewport behind it.
const CROP_W := 380


func _init():
	var packed = load("res://scenes/MainLab.tscn")
	if packed == null:
		print("[FAIL] MainLab.tscn did not load")
		quit(1)
		return
	var inst = packed.instantiate()
	root.add_child(inst)
	# Enough frames for the theme materials to bind and the dock to lay out.
	for _i in range(30):
		await process_frame

	var parts = inst.get_node_or_null("UI_PartsMenu")
	if parts == null:
		print("[FAIL] UI_PartsMenu not found under MainLab")
		quit(1)
		return

	_shoot(OUT_CLOSED)

	# Open the first drawer of the visible family. Through the header button's
	# own toggle rather than by setting the grid visible directly, so the
	# accordion and the pressed state stay in step - the same path a click takes.
	var opened := ""
	for section in parts.sections_for("hulls"):
		var header: Button = section.get_meta("header_btn")
		header.button_pressed = true
		opened = str(section.get_meta("drawer_category", "?"))
		break
	for _i in range(30):
		await process_frame
	print("opened drawer: %s" % opened)

	_shoot(OUT_OPEN)
	quit(0)


func _shoot(path: String) -> void:
	var full: Image = root.get_texture().get_image()
	var w: int = mini(CROP_W, full.get_width())
	var img: Image = full.get_region(Rect2i(0, 0, w, full.get_height()))
	img.save_png(path)
	print("wrote %s  (%dx%d)" % [ProjectSettings.globalize_path(path),
		img.get_width(), img.get_height()])
