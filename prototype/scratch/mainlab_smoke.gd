extends Node
# Windowed smoke test of the REAL MainLab entry scene + real placement flow:
# spawn a hull via the actual UI method, place a couple of real weapons via
# the actual drag-drop target method, screenshot, quit.

func _ready():
	var root = get_tree().current_scene
	await get_tree().process_frame
	await get_tree().process_frame

	if root.has_method("_place_hull_from_ui"):
		root._place_hull_from_ui("assault_hull")
	await get_tree().process_frame

	if root.has_method("_place_weapon_from_ui"):
		root._place_weapon_from_ui("gauss_railgun", Vector3(0, 0.65, -0.5), Vector3.UP)
		root._place_weapon_from_ui("wheels", Vector3.ZERO, Vector3.DOWN)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var img = get_viewport().get_texture().get_image()
	img.save_png("res://scratch/mainlab_smoke.png")
	print("[MAINLAB-SMOKE] Screenshot saved (with railgun + wheels).")

	# Real-scene undo/redo integration check (module_placer.gd + gizmo_3d.gd's
	# absolute "/root/MainLab" lookups only work when this node is actually
	# named "MainLab" at scene root - the synthetic unit test can't catch that).
	if root.has_method("undo") and root.has_method("can_undo"):
		print("[MAINLAB-SMOKE] can_undo before undo: ", root.can_undo())
		root.undo()
		await get_tree().process_frame
		var count_after_undo = 0
		for child in root.hull.get_children():
			if child.has_meta("module_data"):
				count_after_undo += 1
		print("[MAINLAB-SMOKE] Modules after 1x undo: ", count_after_undo)
		var img2 = get_viewport().get_texture().get_image()
		img2.save_png("res://scratch/mainlab_smoke_after_undo.png")

		root.redo()
		await get_tree().process_frame
		var count_after_redo = 0
		for child in root.hull.get_children():
			if child.has_meta("module_data"):
				count_after_redo += 1
		print("[MAINLAB-SMOKE] Modules after redo: ", count_after_redo)
		var img3 = get_viewport().get_texture().get_image()
		img3.save_png("res://scratch/mainlab_smoke_after_redo.png")

	get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())
