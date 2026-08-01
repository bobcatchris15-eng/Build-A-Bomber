extends SceneTree
# Parts Bin redesign verification. Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script res://scratch/capture_parts_menu_redesign.gd

func _init():
	var out_dir = "res://scratch"
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 900)
	for i in range(8): await process_frame
	scene.clear_hull()
	await process_frame
	scene._place_hull_from_ui("medium_hull")
	for i in range(6): await process_frame

	var menu = scene.get_node_or_null("UI_PartsMenu")
	var tabs = menu.get_node("PanelContainer/VBoxContainer/TabContainer")

	root.get_texture().get_image().save_png("%s/menu_0_collapsed.png" % out_dir)
	print("[CAPTURE] collapsed")

	# Modules tab, Direct-Fire Guns open
	tabs.current_tab = 1
	for i in range(3): await process_frame
	for d in menu._all_drawers:
		if d.get_meta("drawer_category") == "Direct-Fire Guns":
			d.get_meta("header_btn").emit_signal("pressed")
			break
	for i in range(20): await process_frame
	root.get_texture().get_image().save_png("%s/menu_1_modules_open.png" % out_dir)
	print("[CAPTURE] modules open")

	menu._search_box.text = "mort"
	menu._on_search_changed("mort")
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png("%s/menu_2_search.png" % out_dir)
	print("[CAPTURE] search")
	quit(0)
