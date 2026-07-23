extends SceneTree
# Confirms tracked_treads' new Road Wheels slider + existing Tread Width
# slider both route through update_locomotion_geometry_tweak() (no respawn),
# actually change the spawned road-wheel mesh count / tread scale, and the
# click-target collider stays in sync with tread_width.
# Run headless: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/verify_treads_tweak_ui.gd --path .

func _count_wheel_hub_meshes(module: Node3D) -> int:
	var n = 0
	for gc in module.get_children():
		if gc is MeshInstance3D and gc.mesh and "wheel_hub" in str(gc.mesh.resource_path):
			n += 1
	return n

func _init():
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	for i in range(4): await process_frame

	scene.clear_hull()
	await process_frame
	scene._place_hull_from_ui("medium_hull")
	for i in range(4): await process_frame

	scene.update_locomotion("tracked_treads", {"tread_width": 1.0, "road_wheel_count": 5})
	for i in range(4): await process_frame

	var hull = scene.hull
	var stat_ui = scene.get_node("UI_StatBlock")
	var tread_module = null
	for child in hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "tracked_treads":
			tread_module = child
			break
	if not tread_module:
		print("[FAIL] no tracked_treads module spawned")
		quit(1)
		return

	stat_ui.on_module_selected(tread_module)
	await process_frame

	var ok = true
	if not stat_ui.road_wheel_count_container.visible:
		print("[FAIL] road_wheel_count_container not visible when tracked_treads selected")
		ok = false
	if stat_ui.count_container.visible:
		print("[FAIL] count_container should stay hidden for tracked_treads (fixed 2 instances)")
		ok = false

	var wheels_before = _count_wheel_hub_meshes(tread_module)
	print("[INFO] road wheels before: ", wheels_before)

	stat_ui.road_wheel_count_slider.value = 8
	stat_ui._on_road_wheel_count_changed(8)
	await process_frame

	if tread_module != scene.hull.get_children().filter(func(c): return c.has_meta("module_data") and c.get_meta("module_data").type_id == "tracked_treads")[0]:
		print("[FAIL] tread module got replaced/reselected on a road_wheel_count change (should be in-place, no respawn)")
		ok = false

	var wheels_after = _count_wheel_hub_meshes(tread_module)
	print("[INFO] road wheels after setting to 8: ", wheels_after)
	if wheels_after != 8:
		print("[FAIL] expected 8 road wheel meshes, got ", wheels_after)
		ok = false

	# Tread width + collider sync check.
	var static_body = tread_module.get_children().filter(func(c): return c is StaticBody3D)[0]
	var shape: BoxShape3D = static_body.get_children().filter(func(c): return c is CollisionShape3D)[0].shape
	print("[INFO] collider size at tread_width=1.0: ", shape.size)

	stat_ui.size_slider.value = 2.0
	stat_ui._on_size_value_changed(2.0)
	await process_frame
	print("[INFO] collider size at tread_width=2.0: ", shape.size)
	if shape.size.x < 1.5:
		print("[FAIL] tread collider did not widen with tread_width")
		ok = false

	var settings = hull.get_meta("locomotion_settings", {})
	print("[INFO] hull.locomotion_settings: ", settings)
	if int(settings.get("road_wheel_count", 0)) != 8:
		print("[FAIL] hull.locomotion_settings.road_wheel_count not persisted correctly")
		ok = false
	if abs(float(settings.get("tread_width", 0.0)) - 2.0) > 0.01:
		print("[FAIL] hull.locomotion_settings.tread_width not persisted correctly")
		ok = false

	if ok:
		print("[PASS] tracked_treads Road Wheels + Tread Width tweaks verified.")
		quit(0)
	else:
		quit(1)
