extends SceneTree
# Confirms the wheels click-target collider (a) starts sized/positioned
# proportionally to wheel_size at placement, and (b) stays in sync when
# wheel_size changes live via the (now respawn-free) size slider drag.
# Run headless: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/verify_wheels_click_target.gd --path .

func _init():
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	for i in range(4): await process_frame

	scene.clear_hull()
	await process_frame
	scene._place_hull_from_ui("medium_hull")
	for i in range(4): await process_frame

	scene.update_locomotion("wheels", {"wheel_size": 1.0, "num_axles": 4, "wheels_per_axle": 1})
	for i in range(4): await process_frame

	var hull = scene.hull
	var stat_ui = scene.get_node("UI_StatBlock")
	var wheel_module = null
	for child in hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "wheels":
			wheel_module = child
			break

	var static_body = wheel_module.get_children().filter(func(c): return c is StaticBody3D)[0]
	var shape: BoxShape3D = static_body.get_children().filter(func(c): return c is CollisionShape3D)[0].shape
	print("[INFO] collider size at wheel_size=1.0: ", shape.size, " body pos: ", static_body.position)

	scene._select_module(wheel_module)
	for i in range(4): await process_frame
	stat_ui.size_slider.value = 2.0
	stat_ui._on_size_value_changed(2.0)
	for i in range(4): await process_frame

	print("[INFO] collider size at wheel_size=2.0: ", shape.size, " body pos: ", static_body.position)

	var ok = true
	if shape.size.x < 2.4:
		print("[FAIL] collider did not grow with wheel_size (still small after size=2.0)")
		ok = false

	if ok:
		print("[PASS] wheels click-target collider stays in sync with wheel_size.")
		quit(0)
	else:
		quit(1)
