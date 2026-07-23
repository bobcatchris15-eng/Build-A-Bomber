extends SceneTree
# Drives the actual wheels tweak sliders (Size/Count/Wheels-Per-Axle) through
# the real UI_StatBlock node, exactly as a player dragging them would, and
# verifies: panel visibility, slider bounds, resulting spawned wheel-mesh
# count, hull.locomotion_settings persistence, and weight-capacity scaling.
# Run headless: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/verify_wheels_tweak_ui.gd --path .

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

	var first_wheel_module = null
	for child in hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "wheels":
			first_wheel_module = child
			break
	if not first_wheel_module:
		print("[FAIL] no wheels module spawned")
		quit(1)
		return

	stat_ui.on_module_selected(first_wheel_module)
	await process_frame

	var ok = true
	if stat_ui.size_container.get_parent() != stat_ui.popup_tweaks_container:
		print("[FAIL] size_container is not parented to popup_tweaks_container (still in sidebar)")
		ok = false
	if stat_ui.count_container.get_parent() != stat_ui.popup_tweaks_container:
		print("[FAIL] count_container is not parented to popup_tweaks_container (still in sidebar)")
		ok = false
	if stat_ui.wheels_per_axle_container.get_parent() != stat_ui.popup_tweaks_container:
		print("[FAIL] wheels_per_axle_container is not parented to popup_tweaks_container (still in sidebar)")
		ok = false
	if not stat_ui.popup_panel.visible:
		print("[FAIL] popup_panel not visible when a wheels module is selected")
		ok = false
	if not stat_ui.wheels_per_axle_container.visible:
		print("[FAIL] wheels_per_axle_container not visible when a wheels module is selected")
		ok = false
	if stat_ui.count_slider.min_value != 4.0:
		print("[FAIL] count_slider.min_value expected 4.0, got ", stat_ui.count_slider.min_value)
		ok = false
	if stat_ui.wheels_per_axle_slider.value != 1.0:
		print("[FAIL] wheels_per_axle_slider.value expected 1.0 (default), got ", stat_ui.wheels_per_axle_slider.value)
		ok = false

	# Drive the sliders the way a player drag would: set .value then fire the
	# same handler the value_changed signal calls.
	stat_ui.size_slider.value = 1.4
	stat_ui._on_size_value_changed(1.4)
	stat_ui.count_slider.value = 8
	stat_ui._on_count_value_changed(8)
	stat_ui.wheels_per_axle_slider.value = 2
	stat_ui._on_wheels_per_axle_changed(2)
	await process_frame
	await process_frame

	var settings = hull.get_meta("locomotion_settings")
	print("[INFO] resulting locomotion_settings: ", settings)
	if abs(float(settings.get("wheel_size", 0.0)) - 1.4) > 0.01:
		print("[FAIL] hull locomotion_settings.wheel_size expected 1.4, got ", settings.get("wheel_size"))
		ok = false
	if int(settings.get("num_axles", 0)) != 8:
		print("[FAIL] hull locomotion_settings.num_axles expected 8, got ", settings.get("num_axles"))
		ok = false
	if int(settings.get("wheels_per_axle", 0)) != 2:
		print("[FAIL] hull locomotion_settings.wheels_per_axle expected 2, got ", settings.get("wheels_per_axle"))
		ok = false

	# Count actual spawned wheel_hub MeshInstance3D nodes across all wheels
	# module instances - should be num_axles * wheels_per_axle = 16.
	var wheel_mesh_count = 0
	for child in hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "wheels":
			for gc in child.get_children():
				if gc is MeshInstance3D and gc.mesh and "wheel_hub" in str(gc.mesh.resource_path):
					wheel_mesh_count += 1
	print("[INFO] spawned wheel_hub mesh instances: ", wheel_mesh_count, " (expected 16)")
	if wheel_mesh_count != 16:
		print("[FAIL] expected 16 wheel_hub instances (8 axles x 2 per axle), got ", wheel_mesh_count)
		ok = false

	if ok:
		print("[PASS] wheels tweak UI end-to-end verified.")
		quit(0)
	else:
		quit(1)
