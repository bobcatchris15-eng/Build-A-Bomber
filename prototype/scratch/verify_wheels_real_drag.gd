extends SceneTree
# Unlike verify_wheels_tweak_ui.gd (which calls the slider's handler function
# directly, bypassing real input), this drives the ACTUAL HSlider control
# with real simulated mouse events - click-drag-release at its real screen
# rect - exactly what a player does. Catches input-routing bugs (mouse_filter,
# z-order, a per-frame-repositioning popup stealing the drag) that a direct
# function call can't catch.
# Must run WITHOUT --headless (needs a real viewport for input + rendering).
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/verify_wheels_real_drag.gd --path .

func _init():
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 800)
	for i in range(6): await process_frame

	scene.clear_hull()
	await process_frame
	scene._place_hull_from_ui("medium_hull")
	for i in range(6): await process_frame

	scene.update_locomotion("wheels", {"wheel_size": 1.0, "num_axles": 4, "wheels_per_axle": 1})
	for i in range(6): await process_frame

	var hull = scene.hull
	var stat_ui = scene.get_node("UI_StatBlock")
	var wheel_module = null
	for child in hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "wheels":
			wheel_module = child
			break
	if not wheel_module:
		print("[FAIL] no wheels module found")
		quit(1)
		return

	scene._select_module(wheel_module)
	for i in range(6): await process_frame

	print("[INFO] popup_panel.visible=", stat_ui.popup_panel.visible)
	print("[INFO] size_container.visible=", stat_ui.size_container.visible, " global_rect=", stat_ui.size_container.get_global_rect())
	var slider: HSlider = stat_ui.size_slider
	print("[INFO] size_slider global_rect=", slider.get_global_rect(), " visible_in_tree=", slider.is_visible_in_tree(), " mouse_filter=", slider.mouse_filter)
	print("[INFO] size_slider value BEFORE drag: ", slider.value)

	var before_settings = hull.get_meta("locomotion_settings", {}).duplicate()
	print("[INFO] locomotion_settings BEFORE drag: ", before_settings)

	var rect = slider.get_global_rect()
	var start_pos = Vector2(rect.position.x + rect.size.x * 0.1, rect.position.y + rect.size.y * 0.5)
	var end_pos = Vector2(rect.position.x + rect.size.x * 0.9, rect.position.y + rect.size.y * 0.5)

	var down = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = start_pos
	down.global_position = start_pos
	Input.parse_input_event(down)
	await process_frame

	# Drag in several steps, like a real mouse motion stream.
	for i in range(1, 11):
		var t = i / 10.0
		var pos = start_pos.lerp(end_pos, t)
		var motion = InputEventMouseMotion.new()
		motion.position = pos
		motion.global_position = pos
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		await process_frame

	var up = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = end_pos
	up.global_position = end_pos
	Input.parse_input_event(up)
	for i in range(6): await process_frame

	print("[INFO] size_slider value AFTER drag: ", slider.value)

	var after_hull = scene.hull
	var after_settings = after_hull.get_meta("locomotion_settings", {}) if after_hull else {}
	print("[INFO] locomotion_settings AFTER drag: ", after_settings)

	var wheel_count_after = 0
	if after_hull:
		for child in after_hull.get_children():
			if child.has_meta("module_data") and child.get_meta("module_data").type_id == "wheels":
				for gc in child.get_children():
					if gc is MeshInstance3D and gc.mesh and "wheel_hub" in str(gc.mesh.resource_path):
						wheel_count_after += 1
	print("[INFO] wheel_hub mesh instances after drag: ", wheel_count_after)

	var ok = true
	if abs(slider.value - float(before_settings.get("wheel_size", 1.0))) < 0.01:
		print("[FAIL] slider.value never changed from its starting value - real mouse drag did not register on the slider at all")
		ok = false
	if after_settings.get("wheel_size", -999.0) == before_settings.get("wheel_size", -1.0):
		print("[FAIL] hull.locomotion_settings.wheel_size did not change after a real drag")
		ok = false

	if ok:
		print("[PASS] real mouse drag on size_slider produced a real wheel_size change.")
		quit(0)
	else:
		quit(1)
