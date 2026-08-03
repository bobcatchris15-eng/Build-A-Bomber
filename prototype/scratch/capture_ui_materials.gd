extends SceneTree
# Visual capture for the material/theme pass and the radial tweak system.
#
# Compare against progress_captures/2026-07-30/ui_pass12/ - that is the state
# this work is meant to move on from (flat StyleBoxFlat chrome, two static
# rails, no radial ring).
#
# Must run WITHOUT --headless, since it reads back the rendered framebuffer.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_ui_materials.gd

const OUT_DIR = "res://progress_captures/2026-08-02-ui-materials"


func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.size = Vector2i(1600, 900)
	await _capture_menu()
	await _capture_lab()
	print("[CAPTURE] done -> %s" % OUT_DIR)
	quit()


func _shot(name: String) -> void:
	# Two frames of settle before every read-back: the material shaders take
	# their panel_size from a `resized` signal, so a capture on the first frame
	# catches them at their fallback size and misreports the grain.
	for i in range(4):
		await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, name])
	print("[CAPTURE] %s" % name)


func _capture_menu() -> void:
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	root.add_child(menu)
	for i in range(10):
		await process_frame
	await _shot("main_menu")
	menu.queue_free()
	await process_frame


func _capture_lab() -> void:
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	for i in range(10):
		await process_frame

	# A hull plus a weapon, so the Lab is showing something rather than an
	# empty stage - the ui_pass12 baseline captured an empty one and it made
	# the chrome impossible to judge in context.
	if scene.has_method("clear_hull"):
		scene.clear_hull()
		await process_frame
	if scene.has_method("_place_hull_from_ui"):
		scene._place_hull_from_ui("medium_hull")
		for i in range(6):
			await process_frame

	var cam = root.get_camera_3d()
	if cam and "_distance" in cam:
		cam._distance = 12.0
		cam.position.z = 12.0
		cam.get_parent().rotation.y = deg_to_rad(-32.0)
		cam.get_parent().rotation.x = deg_to_rad(-16.0)
		await process_frame

	await _shot("main_lab")

	# Bolt a weapon on, then select it, so the radial ring and the callout
	# constellation are actually on screen. This is the whole point of phase 6
	# and it appears in no previous capture. Placement goes through
	# module_placer._place_weapon(), which is what a real drag-drop ends up
	# calling - a hand-built Node3D would not carry the module_data meta the
	# selection path keys off.
	var stats = scene.get_node_or_null("UI_StatBlock")
	# module_placer.gd is the script on the MainLab root itself, so the scene
	# node IS the placer - there is no "ModulePlacer" child (see MainLab.tscn).
	var placer = scene
	var picked: Node3D = null
	if placer.has_method("_place_weapon"):
		picked = placer._place_weapon("autocannon", Vector3(0, 1.2, 0), Vector3.UP)
		for i in range(6):
			await process_frame

	var hull = scene.get_node_or_null("Hull")
	if picked == null and hull:
		for child in hull.get_children():
			if child is Node3D and child.has_meta("module_data"):
				picked = child
				break
	if picked:
		# Go through module_placer._select_module(), not straight to the stat
		# block. Selection is what attaches the Gizmo3D and builds the firing
		# envelope; calling on_module_selected() directly only drives the 2D
		# side and captures a scene with no manipulator and no arc in it.
		if placer.has_method("_select_module"):
			placer._select_module(picked)
		elif stats:
			stats.on_module_selected(picked)
		for i in range(10):
			await process_frame
		await _shot("main_lab_selected")
	else:
		print("[CAPTURE] no placed module found; skipped the selection shot")
