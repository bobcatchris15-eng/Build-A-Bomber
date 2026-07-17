extends SceneTree
# Parts Catalog drawer UI verification: shows collapsible category drawers
# Captures: all drawers collapsed, then with one expanded to show content
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script prototype/scratch/capture_drawer_ui.gd

func _init():
	var out_dir = "res://progress_captures/2026-07-17_ui_pass"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 800)
	for i in range(8): await process_frame

	var cam = root.get_camera_3d()

	# Load default hull for context
	scene.clear_hull()
	await process_frame
	scene._place_hull_from_ui("medium_hull")
	for i in range(4): await process_frame

	if cam and "_distance" in cam:
		cam._distance = 11.0
		cam.position.z = 11.0
		cam.get_parent().rotation.y = deg_to_rad(-30.0)
		cam.get_parent().rotation.x = deg_to_rad(-15.0)
		await process_frame

	# Capture 1: All drawers collapsed (default state)
	root.get_texture().get_image().save_png("%s/drawer_ui_collapsed.png" % out_dir)
	print("[CAPTURE] Parts Catalog with drawers collapsed saved")

	# Expand the first drawer (Ground) to show content
	var parts_menu = scene.get_node_or_null("UI_PartsMenu")
	if parts_menu:
		var tab_hulls = parts_menu.get_node_or_null("PanelContainer/VBoxContainer/TabContainer/Hulls/VBoxContainer")
		if tab_hulls:
			for child in tab_hulls.get_children():
				if child.has_meta("drawer_category") and child.get_meta("drawer_category") == "Ground":
					# Click the drawer to expand it
					var header_btn = child.get_meta("header_btn")
					header_btn.emit_signal("pressed")
					await process_frame
					await process_frame
					break
		else:
			print("[WARN] Could not find tab_hulls VBoxContainer")
	else:
		print("[WARN] Could not find UI_PartsMenu node")

	# Capture 2: Ground drawer expanded, showing its contents
	root.get_texture().get_image().save_png("%s/drawer_ui_ground_expanded.png" % out_dir)
	print("[CAPTURE] Parts Catalog with Ground drawer expanded saved")

	# Collapse Ground, expand Naval to show drawer switching
	var parts_menu2 = scene.get_node_or_null("UI_PartsMenu")
	if parts_menu2:
		var tab_hulls2 = parts_menu2.get_node_or_null("PanelContainer/VBoxContainer/TabContainer/Hulls/VBoxContainer")
		if tab_hulls2:
			for child in tab_hulls2.get_children():
				if child.has_meta("drawer_category"):
					var category = child.get_meta("drawer_category")
					if category == "Ground":
						var header_btn = child.get_meta("header_btn")
						header_btn.emit_signal("pressed")
						await process_frame
					elif category == "Naval":
						var header_btn = child.get_meta("header_btn")
						header_btn.emit_signal("pressed")
						await process_frame
						await process_frame
						break

	# Capture 3: Naval drawer expanded (drawer switching)
	root.get_texture().get_image().save_png("%s/drawer_ui_naval_expanded.png" % out_dir)
	print("[CAPTURE] Parts Catalog with Naval drawer expanded (switching) saved")

	quit(0)
