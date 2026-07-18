extends SceneTree
# Hull modding pass (2026-07-18) visual verification. Run windowed (NOT
# --headless - the dummy renderer doesn't actually rasterize, see this
# project's own memory notes):
#   ./Godot_v4.3-stable_win64.exe --path . --script scratch/capture_hull_modding.gd
#
# Shows: (1) Parts Catalog collapsed to 2 drawers (Vehicle / Static
# Building), (2) Vehicle drawer expanded - includes the real mod hull
# button, (3) Static Building drawer expanded, (4) the real user://mods/hulls
# test mod hull (prospectors_folly_hull) actually placed as the Design
# Lab's active hull.

func _init():
	var out_dir = "res://progress_captures/2026-07-18_hull_modding"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 800)

	for i in range(10): await process_frame

	var parts_menu = scene.get_node_or_null("UI_PartsMenu")
	var tab_hulls = parts_menu.get_node_or_null("PanelContainer/VBoxContainer/TabContainer/Hulls/VBoxContainer") if parts_menu else null

	print("[CAPTURE] Saving 2-drawer collapsed state...")
	root.get_texture().get_image().save_png("%s/01_parts_catalog_two_drawers_collapsed.png" % out_dir)

	if tab_hulls:
		for child in tab_hulls.get_children():
			if child.has_meta("drawer_category") and child.get_meta("drawer_category") == "Vehicle":
				child.get_meta("content_container").visible = true
				break
		await process_frame
		await process_frame
		print("[CAPTURE] Saving Vehicle drawer expanded...")
		root.get_texture().get_image().save_png("%s/02_vehicle_drawer_expanded.png" % out_dir)

		for child in tab_hulls.get_children():
			if child.has_meta("drawer_category"):
				child.get_meta("content_container").visible = (child.get_meta("drawer_category") == "Static Building")
		await process_frame
		await process_frame
		print("[CAPTURE] Saving Static Building drawer expanded...")
		root.get_texture().get_image().save_png("%s/03_static_building_drawer_expanded.png" % out_dir)

		# Collapse again before placing a hull so the drawer doesn't obscure the 3D view.
		for child in tab_hulls.get_children():
			if child.has_meta("drawer_category"):
				child.get_meta("content_container").visible = false
	else:
		print("[ERROR] Could not find Hulls tab container")

	# Place the real committed mod hull (user://mods/hulls/prospectors_folly_hull.*)
	# through the exact same code path a player clicking its Parts Catalog
	# button would trigger.
	scene.clear_hull()
	await process_frame
	scene._place_hull_from_ui("prospectors_folly_hull")
	for i in range(6): await process_frame

	var cam = root.get_camera_3d()
	if cam and "_distance" in cam:
		cam._distance = 9.0
		cam.position.z = 9.0
		cam.get_parent().rotation.y = deg_to_rad(-30.0)
		cam.get_parent().rotation.x = deg_to_rad(-15.0)
		await process_frame

	print("[CAPTURE] Saving mod hull placed in Design Lab...")
	root.get_texture().get_image().save_png("%s/04_mod_hull_placed_in_design_lab.png" % out_dir)

	print("[CAPTURE] Done.")
	quit(0)
