extends Node
# One-off UI screenshot capture for verification - saves to progress_captures
# Run via: godot -s capture_ui_screenshots.gd

var screenshot_dir := "user://../../prototype/progress_captures/2026-07-17_ui_pass"
var screenshot_count := 0

func _ready():
	# Ensure output directory exists
	var dir = DirAccess.open("user://../../prototype/progress_captures")
	if dir:
		dir.make_absolute_path(screenshot_dir)

	print("UI Screenshot Capture Starting...")
	await get_tree().process_frame
	await get_tree().process_frame

	# Load and screenshot Design Lab
	await load_and_capture_scene("res://scenes/MainLab.tscn", "design_lab_ui_sidebars")

	# Load and screenshot Skirmish HUD
	await load_and_capture_scene("res://scenes/Skirmish.tscn", "skirmish_hud_bars")

	print("UI Screenshot Capture Complete! Saved to: %s" % screenshot_dir)
	get_tree().quit()

func load_and_capture_scene(scene_path: String, name_prefix: String) -> void:
	print("Loading scene: %s" % scene_path)
	var scene = load(scene_path)
	if not scene:
		print("ERROR: Failed to load scene: %s" % scene_path)
		return

	var instance = scene.instantiate()
	get_tree().root.add_child(instance)

	# Wait for UI to render
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	# Capture screenshot
	var viewport = get_viewport()
	var image = viewport.get_texture().get_image()

	var filename = "%s/%s.png" % [screenshot_dir, name_prefix]
	print("Saving screenshot: %s" % filename)
	image.save_png(filename)

	# Clean up
	instance.queue_free()
	await get_tree().process_frame
