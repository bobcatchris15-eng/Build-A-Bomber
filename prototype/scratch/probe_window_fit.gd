extends SceneTree
# Scratch: verify the window fit against the REAL display, not an assumed
# one. Autoloads don't run under --script, so this calls the same logic
# directly and reports what it did.

const WindowFit = preload("res://scripts/window_fit.gd")

func _init():
	var screen := DisplayServer.window_get_current_screen()
	print("screen count : ", DisplayServer.get_screen_count())
	print("screen size  : ", DisplayServer.screen_get_size(screen))
	print("usable rect  : ", DisplayServer.screen_get_usable_rect(screen))
	print("window before: size=", DisplayServer.window_get_size(),
		" pos=", DisplayServer.window_get_position())

	var fitter = Node.new()
	fitter.set_script(WindowFit)
	root.add_child(fitter)
	fitter.fit_to_screen()
	await process_frame

	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	var size := DisplayServer.window_get_size()
	var pos := DisplayServer.window_get_position()
	print("window after : size=", size, " pos=", pos)

	# The actual assertions the bug was about.
	var fits_h: bool = pos.x >= usable.position.x and pos.x + size.x <= usable.position.x + usable.size.x
	var fits_v: bool = pos.y >= usable.position.y and pos.y + size.y <= usable.position.y + usable.size.y
	print("fully inside work area horizontally: ", fits_h)
	print("fully inside work area vertically  : ", fits_v, "  <- taskbar overlap bug")
	print("uses screen width fraction         : %.2f" % (float(size.x) / float(usable.size.x)))
	quit(0)
