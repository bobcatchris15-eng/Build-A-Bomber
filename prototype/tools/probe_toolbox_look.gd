extends SceneTree
# Renders the real Battle HUD and saves the toolbox strip to a PNG.
#
# Styling is the one kind of change a headless assert cannot judge - "does this
# read as stamped metal" is not a number - so this exists to put an actual image
# in front of a human rather than to pass. It also catches the failure mode that
# a test would not: a StampedLabel that parses, lays out, reports a sane rect and
# draws nothing at all.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --path . \
#          --script tools/probe_toolbox_look.gd

const OUT := "user://toolbox_look.png"


func _init():
	var packed = load("res://scenes/Battle.tscn")
	if packed == null:
		print("[FAIL] Battle.tscn did not load")
		quit(1)
		return
	root.add_child(packed.instantiate())
	# Enough frames for the toolboxes to finish sliding up from their idle
	# position - capturing mid-slide would show them half off the bottom edge.
	for _i in range(180):
		await process_frame

	var full: Image = root.get_texture().get_image()
	full.save_png("user://battle_full.png")

	var img: Image = full.duplicate()
	# The bottom strip only. The whole frame is mostly battlefield and the
	# lettering is the thing under review.
	var h: int = mini(300, img.get_height())
	img = img.get_region(Rect2i(0, img.get_height() - h, img.get_width(), h))
	img.save_png(OUT)
	print("wrote %s  (%dx%d)" % [ProjectSettings.globalize_path(OUT),
		img.get_width(), img.get_height()])
	quit(0)
