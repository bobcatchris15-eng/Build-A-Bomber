extends SceneTree
# Real simulated mouse-drag on the new Road Wheels slider (genuinely new
# code, not just reused wheels infrastructure) - confirms it actually
# registers real input and updates the model smoothly, same rigor applied to
# the wheels sliders.
# Must run WITHOUT --headless. Run:
# ./Godot_v4.3-stable_win64_console.exe --script scratch/verify_treads_real_drag.gd --path .

func _drag(slider: HSlider, from_t: float, to_t: float, steps: int = 6):
	var rect = slider.get_global_rect()
	var start_pos = Vector2(rect.position.x + rect.size.x * from_t, rect.position.y + rect.size.y * 0.5)
	var end_pos = Vector2(rect.position.x + rect.size.x * to_t, rect.position.y + rect.size.y * 0.5)
	var down = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = start_pos
	down.global_position = start_pos
	Input.parse_input_event(down)
	await process_frame
	for i in range(1, steps + 1):
		var t = i / float(steps)
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
	for i in range(8): await process_frame

func _init():
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 800)
	for i in range(6): await process_frame

	scene.clear_hull()
	await process_frame
	scene._place_hull_from_ui("medium_hull")
	for i in range(6): await process_frame

	scene.update_locomotion("tracked_treads", {"tread_width": 1.0, "road_wheel_count": 5})
	for i in range(6): await process_frame

	var hull = scene.hull
	var stat_ui = scene.get_node("UI_StatBlock")
	var tread_module = null
	for child in hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "tracked_treads":
			tread_module = child
			break
	scene._select_module(tread_module)
	for i in range(6): await process_frame

	await _drag(stat_ui.road_wheel_count_slider, 0.05, 0.95)
	print("[INFO] road_wheel_count_slider value after drag: ", stat_ui.road_wheel_count_slider.value)

	var wheels_after = 0
	for gc in tread_module.get_children():
		if gc is MeshInstance3D and gc.mesh and "wheel_hub" in str(gc.mesh.resource_path):
			wheels_after += 1
	print("[INFO] road wheel meshes after drag: ", wheels_after)
	print("[INFO] hull.locomotion_settings: ", scene.hull.get_meta("locomotion_settings", {}))

	var ok = true
	if abs(stat_ui.road_wheel_count_slider.value - 5.0) < 0.5:
		print("[FAIL] slider value never changed - real drag did not register")
		ok = false
	if wheels_after < 6:
		print("[FAIL] road wheel count did not increase via real drag")
		ok = false

	if ok:
		print("[PASS] Road Wheels slider responds correctly to real mouse drag.")
		quit(0)
	else:
		quit(1)
