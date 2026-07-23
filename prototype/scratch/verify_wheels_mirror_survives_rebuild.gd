extends SceneTree
# Confirms the LEFT-side (mirrored, scale_flip_x) wheels module's children
# stay mirrored after a live wheel_size change via
# update_locomotion_geometry_tweak() - this used to silently un-mirror the
# rebuilt driveshaft/gearbox/hub, putting them on the wrong side.
# Run headless: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/verify_wheels_mirror_survives_rebuild.gd --path .

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
	var mirrored_module = null
	for child in hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "wheels" and child.get_meta("scale_flip_x", false):
			mirrored_module = child
			break

	if not mirrored_module:
		print("[FAIL] no mirrored (scale_flip_x) wheels module found")
		quit(1)
		return

	var before_positions = {}
	for gc in mirrored_module.get_children():
		if gc is MeshInstance3D:
			before_positions[gc.name if gc.name != "" else str(gc)] = gc.transform.origin.x

	print("[INFO] mirrored module child X positions BEFORE resize: ", before_positions)

	scene.update_locomotion_geometry_tweak("wheels", "wheel_size", 1.6)
	for i in range(4): await process_frame

	var after_ok = true
	var found_mirrored_child = false
	for gc in mirrored_module.get_children():
		if gc is MeshInstance3D:
			found_mirrored_child = true
			var is_marked_mirrored = gc.get_meta("_mirrored", false)
			print("[INFO] child mesh=", gc.mesh.resource_path if gc.mesh else "?", " x=", gc.transform.origin.x, " _mirrored_meta=", is_marked_mirrored)
			if not is_marked_mirrored:
				after_ok = false

	if not found_mirrored_child:
		print("[FAIL] mirrored module has no MeshInstance3D children after rebuild")
		quit(1)
		return

	if not after_ok:
		print("[FAIL] mirrored module's rebuilt children are missing the _mirrored meta - mirror flip was lost on rebuild")
		quit(1)
		return

	print("[PASS] mirrored wheels module's children stay mirrored after a live wheel_size rebuild.")
	quit(0)
