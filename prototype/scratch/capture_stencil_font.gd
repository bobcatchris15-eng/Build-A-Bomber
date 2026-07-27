extends SceneTree
# Quick visual check of the new stencil default font on the actual MainMenu.
# Must run WITHOUT --headless.

func _init():
	DirAccess.make_dir_recursive_absolute("res://progress_captures/2026-07-26_stencil_font")
	var menu = preload("res://scenes/MainMenu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	for i in range(6): await process_frame
	var img = root.get_texture().get_image()
	img.save_png("res://progress_captures/2026-07-26_stencil_font/main_menu.png")
	print("[CAPTURE] saved main_menu.png")
	quit(0)
