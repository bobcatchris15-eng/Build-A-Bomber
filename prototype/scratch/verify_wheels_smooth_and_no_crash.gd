extends SceneTree
# Two real-input regression checks:
# 1. Dragging the SIZE slider should update the model SMOOTHLY (mid-drag,
#    not just on release) - the wheel mesh scale should change partway
#    through the drag, not stay frozen at the starting value until mouse-up.
# 2. Dragging the COUNT (axle) slider must NOT crash/hang - this used to hit
#    an unguarded freed-instance access in module_placer.gd's
#    _deselect_module() (get_children() on a stale `selected_module` after
#    update_locomotion() had already queue_free()'d it), which under the
#    editor debugger reads as "the game locks up".
# Must run WITHOUT --headless (needs a real viewport for input).
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/verify_wheels_smooth_and_no_crash.gd --path .

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

	# --- Test 1: smooth mid-drag update on the SIZE slider ---
	var slider: HSlider = stat_ui.size_slider
	var rect = slider.get_global_rect()
	var start_pos = Vector2(rect.position.x + rect.size.x * 0.1, rect.position.y + rect.size.y * 0.5)
	var mid_pos = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y * 0.5)
	var end_pos = Vector2(rect.position.x + rect.size.x * 0.9, rect.position.y + rect.size.y * 0.5)

	var wheel_scale_before = wheel_module.get_child(0).scale.x if wheel_module.get_child_count() > 0 else -1.0

	var down = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = start_pos
	down.global_position = start_pos
	Input.parse_input_event(down)
	await process_frame

	var motion1 = InputEventMouseMotion.new()
	motion1.position = mid_pos
	motion1.global_position = mid_pos
	motion1.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion1)
	await process_frame
	await process_frame

	# Read the wheel's own wheel_hub scale mid-drag, BEFORE releasing the mouse.
	var mid_drag_scale = -1.0
	var still_same_module = false
	for child in hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "wheels":
			if child == wheel_module:
				still_same_module = true
			for gc in child.get_children():
				if gc is MeshInstance3D and gc.mesh and "wheel_hub" in str(gc.mesh.resource_path):
					mid_drag_scale = gc.scale.x
			break

	print("[INFO] wheel_module unchanged mid-drag (no respawn/reselect): ", still_same_module)
	print("[INFO] size_slider value mid-drag: ", slider.value)
	print("[INFO] wheel_hub scale mid-drag: ", mid_drag_scale)

	var up = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = mid_pos
	up.global_position = mid_pos
	Input.parse_input_event(up)
	for i in range(4): await process_frame

	var ok = true
	if not still_same_module:
		print("[FAIL] wheels module was respawned/reselected mid-drag on the SIZE slider (should never happen)")
		ok = false
	if abs(mid_drag_scale - 1.0) < 0.01:
		print("[FAIL] wheel_hub scale did not change mid-drag - size slider is still not updating live")
		ok = false

	# --- Test 2: dragging COUNT (axle count) must not crash ---
	var count_slider: HSlider = stat_ui.count_slider
	var crect = count_slider.get_global_rect()
	var cstart = Vector2(crect.position.x + crect.size.x * 0.1, crect.position.y + crect.size.y * 0.5)
	var cend = Vector2(crect.position.x + crect.size.x * 0.9, crect.position.y + crect.size.y * 0.5)

	var cdown = InputEventMouseButton.new()
	cdown.button_index = MOUSE_BUTTON_LEFT
	cdown.pressed = true
	cdown.position = cstart
	cdown.global_position = cstart
	Input.parse_input_event(cdown)
	await process_frame

	for i in range(1, 6):
		var t = i / 5.0
		var pos = cstart.lerp(cend, t)
		var motion = InputEventMouseMotion.new()
		motion.position = pos
		motion.global_position = pos
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		await process_frame

	var cup = InputEventMouseButton.new()
	cup.button_index = MOUSE_BUTTON_LEFT
	cup.pressed = false
	cup.position = cend
	cup.global_position = cend
	Input.parse_input_event(cup)

	# If _deselect_module()'s freed-instance bug is still present, this is
	# roughly where a script error / hang would happen (the deferred
	# reselect fires within the next few frames after drag_ended).
	for i in range(20): await process_frame

	print("[INFO] count_slider value after drag: ", count_slider.value)
	print("[INFO] still alive after axle-count drag (reached this line without hanging/crashing).")

	var final_hull = scene.hull
	var wheel_count_final = 0
	if final_hull:
		for child in final_hull.get_children():
			if child.has_meta("module_data") and child.get_meta("module_data").type_id == "wheels":
				for gc in child.get_children():
					if gc is MeshInstance3D and gc.mesh and "wheel_hub" in str(gc.mesh.resource_path):
						wheel_count_final += 1
	print("[INFO] wheel_hub instances after axle-count drag: ", wheel_count_final)
	if wheel_count_final <= 4:
		print("[FAIL] axle count drag did not actually increase the wheel count")
		ok = false

	if ok:
		print("[PASS] size slider updates smoothly mid-drag; axle-count drag completes without crashing.")
		quit(0)
	else:
		quit(1)
