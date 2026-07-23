extends SceneTree
# Two reported bugs, reproduced with REAL simulated mouse drag input:
# 1. Dragging axle count UP (e.g. to 8) then DOWN again should actually
#    reduce the wheel count back down, not stick at the high value.
# 2. Dragging the Wheels-Per-Axle (dually) slider should change the
#    per-axle wheel count (1 <-> 2), same as the other sliders.
# Must run WITHOUT --headless (needs a real viewport for input).
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/verify_wheels_count_down_and_dually.gd --path .

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
	for i in range(10): await process_frame

func _count_wheel_hub_meshes(hull: Node3D) -> int:
	var n = 0
	if not hull: return n
	for child in hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "wheels":
			for gc in child.get_children():
				if gc is MeshInstance3D and gc.mesh and "wheel_hub" in str(gc.mesh.resource_path):
					n += 1
	return n

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
	scene._select_module(wheel_module)
	for i in range(6): await process_frame

	var ok = true

	# --- Drag count UP to (near) max ---
	await _drag(stat_ui.count_slider, 0.1, 0.9)
	print("[INFO] count_slider value after UP drag: ", stat_ui.count_slider.value)
	print("[INFO] wheel_hub meshes after UP drag: ", _count_wheel_hub_meshes(scene.hull))
	print("[INFO] hull.locomotion_settings after UP drag: ", scene.hull.get_meta("locomotion_settings", {}))

	# NOT manually reselecting here - relying purely on the automatic
	# deferred reselect from the UP drag, same as a real user who just keeps
	# dragging the same still-open popup without re-clicking the module.

	# --- Now drag count back DOWN ---
	await _drag(stat_ui.count_slider, 0.9, 0.1)
	print("[INFO] count_slider value after DOWN drag: ", stat_ui.count_slider.value)
	var wheels_after_down = _count_wheel_hub_meshes(scene.hull)
	print("[INFO] wheel_hub meshes after DOWN drag: ", wheels_after_down)
	print("[INFO] hull.locomotion_settings after DOWN drag: ", scene.hull.get_meta("locomotion_settings", {}))

	if wheels_after_down >= 8:
		print("[FAIL] axle count did not decrease when dragged back down (stuck at high value)")
		ok = false

	# --- Dually (wheels_per_axle) slider, real drag - again NOT manually
	# reselecting, relying on the automatic deferred reselect from the DOWN
	# drag just above.
	print("[INFO] current_selected_module valid: ", is_instance_valid(stat_ui.current_selected_module), " type: ", stat_ui.current_selected_module.get_meta("module_data").type_id if is_instance_valid(stat_ui.current_selected_module) and stat_ui.current_selected_module.has_meta("module_data") else "n/a")
	print("[INFO] wheels_per_axle_container.visible before dually drag: ", stat_ui.wheels_per_axle_container.visible)
	print("[INFO] wheels_per_axle_slider global_rect: ", stat_ui.wheels_per_axle_slider.get_global_rect())
	var wpa_before = _count_wheel_hub_meshes(scene.hull)
	var axle_count_before = int(scene.hull.get_meta("locomotion_settings", {}).get("num_axles", 0))
	print("[INFO] wheel_hub meshes before dually drag: ", wpa_before, " (axles=", axle_count_before, ")")

	await _drag(stat_ui.wheels_per_axle_slider, 0.05, 0.95)
	print("[INFO] wheels_per_axle_slider value after drag: ", stat_ui.wheels_per_axle_slider.value)
	var wpa_after = _count_wheel_hub_meshes(scene.hull)
	print("[INFO] wheel_hub meshes after dually drag: ", wpa_after)
	print("[INFO] hull.locomotion_settings after dually drag: ", scene.hull.get_meta("locomotion_settings", {}))

	if abs(stat_ui.wheels_per_axle_slider.value - 1.0) < 0.01:
		print("[FAIL] wheels_per_axle_slider value never changed from 1.0 - real drag did not register")
		ok = false
	if wpa_after <= wpa_before:
		print("[FAIL] wheels_per_axle drag did not increase the spawned wheel_hub mesh count")
		ok = false

	if ok:
		print("[PASS] axle count decreases correctly and dually slider works via real drag.")
		quit(0)
	else:
		quit(1)
