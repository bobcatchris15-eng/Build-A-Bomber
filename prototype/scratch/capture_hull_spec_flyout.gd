extends SceneTree
# Visual proof for VISUAL/UI plan items 5-6b: the hull-spec flyout renders where
# it is supposed to, on the CANVAS plate, and the tweak callouts now sit on their
# own CANVAS plate with a signal edge instead of a flat BASE_900 box.
#
# Two shots, because the two changes are only judgeable in different states:
#   hull_spec_flyout  - the Lab with the flyout open off its trigger.
#   callout_material  - a selected module, so the callout constellation is up.
#
# Must run WITHOUT --headless: it reads back the rendered framebuffer, and the
# whole point is the material plates, which the dummy renderer does not draw.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_hull_spec_flyout.gd

const OUT_DIR = "res://progress_captures/2026-08-03-flyout-callout"


func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.content_scale_size = Vector2i(1600, 900)
	await process_frame

	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in range(12):
		await process_frame

	# A hull plus a weapon, so the Lab is showing something. An empty stage makes
	# the chrome impossible to judge in context - the ui_pass12 baseline learned
	# this the hard way, see capture_ui_materials.gd.
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

	var stats = scene.get_node_or_null("UI_StatBlock")

	# --- Shot 1: the flyout, open off its trigger ---
	if stats and stats.hull_spec_btn:
		stats._on_hull_spec_pressed()
		# open_from defers placement two frames on purpose; give it more.
		for i in range(8):
			await process_frame
		await _shot("hull_spec_flyout")
		if stats._hull_spec_flyout != null:
			stats._hull_spec_flyout.close()
			for i in range(4):
				await process_frame
	else:
		print("[CAPTURE] SKIP hull_spec_flyout - no trigger button found")

	# --- Shot 2: the callout constellation on a selected module ---
	var picked: Node3D = null
	if scene.has_method("_place_weapon"):
		picked = scene._place_weapon("autocannon", Vector3(0, 1.2, 0), Vector3.UP)
		for i in range(6):
			await process_frame
	if picked and scene.has_method("_select_module"):
		scene._select_module(picked)
		for i in range(8):
			await process_frame
		await _shot("callout_material")
	else:
		print("[CAPTURE] SKIP callout_material - module placement/selection unavailable")

	print("[CAPTURE] done -> %s" % OUT_DIR)
	quit()


func _shot(name: String) -> void:
	# The panel shaders take panel_size from a `resized` signal, so a read-back on
	# the first frame catches them at their fallback size and misreports the grain.
	for i in range(4):
		await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, name])
	print("[CAPTURE] %s" % name)
