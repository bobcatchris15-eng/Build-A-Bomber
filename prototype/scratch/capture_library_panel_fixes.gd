extends SceneTree
# Scratch: validates the Blueprint Library panel's delete-confirmation
# dialog and load-failure error dialog. Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_library_panel_fixes.gd

const LibraryPanelScript = preload("res://scripts/blueprint_library_panel.gd")

func _init():
	var out_dir = "res://progress_captures/2026-07-13/library_panel_fixes"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 720)
	for i in range(6): await process_frame

	var panel = Control.new()
	panel.set_script(LibraryPanelScript)
	scene.add_child(panel)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/library_rows_with_timestamp.png" % out_dir)
	print("[CAPTURE] saved library_rows_with_timestamp.png")

	# Delete confirmation dialog
	if not panel.blueprint_manager.list_blueprints().is_empty():
		var first_id = panel.blueprint_manager.list_blueprints()[0].get("id", "")
		panel._on_delete_pressed(first_id, "Test Design For Delete Confirm")
		for i in range(4): await process_frame
		root.get_texture().get_image().save_png("%s/delete_confirmation.png" % out_dir)
		print("[CAPTURE] saved delete_confirmation.png")
		# Cancel it so we don't actually delete a real saved design.
		for child in panel.get_children():
			if child is ConfirmationDialog:
				child.get_cancel_button().pressed.emit()
		for i in range(2): await process_frame

	# Rename dialog
	if not panel.blueprint_manager.list_blueprints().is_empty():
		var first_id = panel.blueprint_manager.list_blueprints()[0].get("id", "")
		panel._on_rename_pressed(first_id, "Untitled Design")
		for i in range(4): await process_frame
		root.get_texture().get_image().save_png("%s/rename_dialog.png" % out_dir)
		print("[CAPTURE] saved rename_dialog.png")
		for child in panel.get_children():
			if child is ConfirmationDialog:
				child.get_cancel_button().pressed.emit()
		for i in range(2): await process_frame

	# Load-failure error dialog (bogus id that can't possibly load)
	panel._on_load_pressed("definitely_not_a_real_blueprint_id_12345")
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/load_failure_error.png" % out_dir)
	print("[CAPTURE] saved load_failure_error.png")
	print("Panel still open (should be true - load failure must not close it): ", is_instance_valid(panel) and panel.is_inside_tree())

	quit(0)
