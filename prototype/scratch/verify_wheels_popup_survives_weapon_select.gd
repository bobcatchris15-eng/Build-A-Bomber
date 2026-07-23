extends SceneTree
# Regression guard: size_container/count_container/wheels_per_axle_container
# are PERSISTENT nodes reparented once into popup_tweaks_container, unlike
# every other popup tweak widget which is freed and rebuilt per selection.
# Selecting a weapon (which clears popup_tweaks_container's disposable
# children) must NOT free these three - confirms the queue_free() guard in
# on_module_selected() actually protects them.
# Run headless: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/verify_wheels_popup_survives_weapon_select.gd --path .

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

	stat_ui.on_module_selected(wheel_module)
	await process_frame

	# Now place and select a weapon module to force the popup's disposable
	# children to be cleared.
	var weapon_module = scene._place_weapon("basic_cannon", hull.global_position + Vector3(0, 1, 0), Vector3.UP)
	await process_frame
	stat_ui.on_module_selected(weapon_module)
	await process_frame
	await process_frame

	var ok = true
	if not is_instance_valid(stat_ui.size_container):
		print("[FAIL] size_container was freed when a weapon was selected")
		ok = false
	if not is_instance_valid(stat_ui.count_container):
		print("[FAIL] count_container was freed when a weapon was selected")
		ok = false
	if not is_instance_valid(stat_ui.wheels_per_axle_container):
		print("[FAIL] wheels_per_axle_container was freed when a weapon was selected")
		ok = false
	if ok and stat_ui.size_container.visible:
		print("[FAIL] size_container still visible while a weapon is selected")
		ok = false

	# Re-select the wheels module afterward - the sliders must still work.
	stat_ui.on_module_selected(wheel_module)
	await process_frame
	if ok and not stat_ui.size_container.visible:
		print("[FAIL] size_container did not come back visible after reselecting the wheels module")
		ok = false

	if ok:
		print("[PASS] wheels popup sliders survive a weapon selection in between.")
		quit(0)
	else:
		quit(1)
