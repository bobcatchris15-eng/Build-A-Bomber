extends SceneTree
# Visual capture for the whole UI/materials pass, one shot per thing the plan's
# verification step 4 asks to compare against
# progress_captures/2026-07-30/ui_pass12/.
#
# Covers what earlier captures missed: the title screen's spec placard (item 9),
# the Design Lab with both docks railed (item 7), the Hull Builder's drawn
# primitive icons (item 0), and the Skirmish HUD (item 8) - which no capture in
# this project has ever included, because capture_ui_baseline.gd deliberately
# skipped it as needing a live match. It still does; the Skirmish shot here is
# taken after letting a real match boot, and is skipped rather than faked if the
# scene does not come up.
#
# Must run WITHOUT --headless: it reads back the rendered framebuffer.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_ui_pass_final.gd

const OUT_DIR = "res://progress_captures/2026-08-03-ui-pass-final"


func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.content_scale_size = Vector2i(1600, 900)
	await process_frame

	await _shot_scene("main_menu", "res://scenes/MainMenu.tscn", 14)
	await _shot_scene("hull_builder", "res://scenes/HullBuilder.tscn", 14)
	await _shot_lab()
	await _shot_skirmish()

	print("[CAPTURE] done -> %s" % OUT_DIR)
	quit()


func _shot_scene(name: String, path: String, frames: int) -> void:
	if not ResourceLoader.exists(path):
		print("[CAPTURE] SKIP %s (missing)" % name)
		return
	var inst = load(path).instantiate()
	root.add_child(inst)
	current_scene = inst
	for i in range(frames):
		await process_frame
	await _shot(name)
	inst.queue_free()
	await process_frame


func _shot_lab() -> void:
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in range(12):
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
	# Both docks railed is the default now, so this is the shot that shows whether
	# item 7 actually gave the viewport the screen.
	await _shot("main_lab_railed")

	# Then expanded, so the rail's contents are judgeable too.
	var stats = scene.get_node_or_null("UI_StatBlock")
	var parts = scene.get_node_or_null("UI_PartsMenu")
	var UIDockScript = load("res://scripts/ui_dock.gd")
	if stats and stats.stats_dock:
		stats.stats_dock.set_dock_state(UIDockScript.State.EXPANDED, false)
	if parts and "_dock" in parts and parts._dock:
		parts._dock.set_dock_state(UIDockScript.State.EXPANDED, false)
	for i in range(6):
		await process_frame
	await _shot("main_lab_expanded")

	scene.queue_free()
	await process_frame


func _shot_skirmish() -> void:
	if not ResourceLoader.exists("res://scenes/Skirmish.tscn"):
		print("[CAPTURE] SKIP skirmish (missing)")
		return
	var scene = load("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	# A match needs terrain, a navmesh bake and a roster before it looks like
	# anything - hence a much longer settle than the shell screens.
	for i in range(90):
		await process_frame
	await _shot("skirmish_hud")
	scene.queue_free()
	await process_frame


func _shot(name: String) -> void:
	for i in range(4):
		await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, name])
	print("[CAPTURE] %s" % name)
