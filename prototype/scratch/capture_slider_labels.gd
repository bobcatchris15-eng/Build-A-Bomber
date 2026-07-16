extends SceneTree
# Scratch: validates the wheel/tread/rotor/leg Size and Count sliders now
# show live numeric values instead of a static label with no readout.
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_slider_labels.gd

func _init():
	var out_dir = "res://progress_captures/2026-07-13/slider_labels"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 720)
	for i in range(6): await process_frame

	# Place wheels on the default hull directly (bypassing drag-drop input
	# simulation) then select the module to trigger on_module_selected().
	scene._place_weapon_from_ui("wheels", Vector3(0, -0.5, 0), Vector3.UP)
	for i in range(4): await process_frame

	var stat_ui = get_first_node_in_group("stat_ui")
	var wheels_module = null
	for child in scene.hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "wheels":
			wheels_module = child
			break
	if wheels_module:
		stat_ui.on_module_selected(wheels_module)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/wheel_slider_default.png" % out_dir)
	print("[CAPTURE] saved wheel_slider_default.png, size_label='", stat_ui.size_label.text, "' count_label='", stat_ui.count_label.text, "'")

	# Move the size slider and confirm the label updates live.
	stat_ui.size_slider.value = 2.0
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/wheel_slider_moved.png" % out_dir)
	print("[CAPTURE] saved wheel_slider_moved.png, size_label='", stat_ui.size_label.text, "' count_label='", stat_ui.count_label.text, "'")

	quit(0)
