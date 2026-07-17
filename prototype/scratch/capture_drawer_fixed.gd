extends SceneTree
# Capture drawer UI with improved header styling - should now be visible
# Shows: (1) all drawers collapsed, (2) Ground drawer expanded

func _init():
	var out_dir = "res://progress_captures/2026-07-17_ui_pass"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 800)

	# Wait for scene to fully initialize
	for i in range(10): await process_frame

	var cam = root.get_camera_3d()

	# Load hull for context
	scene.clear_hull()
	await process_frame
	scene._place_hull_from_ui("medium_hull")
	for i in range(6): await process_frame

	if cam and "_distance" in cam:
		cam._distance = 11.0
		cam.position.z = 11.0
		cam.get_parent().rotation.y = deg_to_rad(-30.0)
		cam.get_parent().rotation.x = deg_to_rad(-15.0)
		await process_frame

	# Capture 1: Collapsed state (all drawers with headers visible)
	print("[CAPTURE] Saving collapsed state...")
	root.get_texture().get_image().save_png("%s/drawer_fixed_collapsed.png" % out_dir)
	print("[CAPTURE] Collapsed state saved")

	# Now expand Ground drawer to show content
	var parts_menu = scene.get_node_or_null("UI_PartsMenu")
	if parts_menu:
		var tab_hulls = parts_menu.get_node_or_null("PanelContainer/VBoxContainer/TabContainer/Hulls/VBoxContainer")
		if tab_hulls:
			# Find and click Ground drawer header
			for child in tab_hulls.get_children():
				if child.has_meta("drawer_category") and child.get_meta("drawer_category") == "Ground":
					var header_btn = child.get_meta("header_btn")
					var content = child.get_meta("content_container")

					print("[DEBUG] Ground drawer found")
					print("[DEBUG] Content currently visible: %s" % content.visible)
					print("[DEBUG] Content has %d children" % content.get_child_count())

					# Manually set content visible instead of relying on signal
					content.visible = true
					await process_frame
					await process_frame

					print("[DEBUG] Content now visible: %s" % content.visible)
					break
		else:
			print("[ERROR] Could not find tab_hulls")
	else:
		print("[ERROR] Could not find UI_PartsMenu")

	# Capture 2: Ground drawer expanded (should show hull buttons)
	print("[CAPTURE] Saving Ground expanded state...")
	root.get_texture().get_image().save_png("%s/drawer_fixed_ground_expanded.png" % out_dir)
	print("[CAPTURE] Ground expanded state saved")

	quit(0)
