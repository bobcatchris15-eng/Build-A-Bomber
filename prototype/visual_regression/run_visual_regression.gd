extends Node
# Windowed screenshot-diff visual regression suite (greenlit this pass -
# previously logged as "investigated, not built" in DECISIONS_NEEDED.md).
# Needs real rendering (headless Godot's dummy renderer doesn't rasterize),
# so this runs as its own windowed pass, separate from run_tests.gd:
#   Godot_v4.3-stable_win64_console.exe visual_regression/VisualRegression.tscn
#
# Each scenario: build a specific game state, screenshot it, compare against
# a checked-in baseline PNG (ScreenshotDiff, 6% per-channel tolerance / 2%
# of sampled pixels - absorbs anti-aliasing and font-hinting noise without
# missing a real regression). No baseline yet for a scenario -> the capture
# becomes the new baseline and that's reported distinctly from a pass/fail,
# so a first run doesn't look like it "passed" when it actually established
# the goalposts for the first time.

const ScreenshotDiffScript = preload("res://scripts/screenshot_diff.gd")
const BASELINE_DIR = "res://visual_regression/baselines"
const CAPTURE_DIR = "res://visual_regression/captures"

var results: Array = []

func _ready():
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASELINE_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))

	await _scenario_mainlab_empty()
	await _scenario_mainlab_module_placement()
	await _scenario_mainlab_armor_facet_fitting()
	await _scenario_mainlab_module_popup()
	await _scenario_skirmish_hud()

	_print_summary()
	get_tree().quit()

func _capture_and_compare(scenario_name: String):
	await get_tree().process_frame
	await get_tree().process_frame
	var img = get_viewport().get_texture().get_image()
	var capture_path = CAPTURE_DIR + "/" + scenario_name + ".png"
	img.save_png(capture_path)

	var baseline_path = BASELINE_DIR + "/" + scenario_name + ".png"
	var baseline_abs = ProjectSettings.globalize_path(baseline_path)
	if not FileAccess.file_exists(baseline_abs):
		img.save_png(baseline_path)
		results.append({"name": scenario_name, "status": "NEW BASELINE", "detail": "no prior baseline existed - this capture is now the baseline"})
		return

	var result = ScreenshotDiffScript.compare_files(ProjectSettings.globalize_path(capture_path), baseline_abs)
	if result.match:
		results.append({"name": scenario_name, "status": "PASS", "detail": "%.3f%% pixels differed (within tolerance)" % (result.diff_fraction * 100.0)})
	else:
		results.append({"name": scenario_name, "status": "FAIL", "detail": result.reason})

func _print_summary():
	print("\n==============================================")
	print("    VISUAL REGRESSION REPORT")
	print("==============================================")
	var pass_count = 0
	var fail_count = 0
	var new_count = 0
	for r in results:
		print("  [%s] %s - %s" % [r.status, r.name, r.detail])
		if r.status == "PASS": pass_count += 1
		elif r.status == "FAIL": fail_count += 1
		else: new_count += 1
	print("\n  %d pass, %d fail, %d new baseline(s) established." % [pass_count, fail_count, new_count])
	print("==============================================\n")

# --- Scenarios ---

func _scenario_mainlab_empty():
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame
	await _capture_and_compare("mainlab_empty_ui")
	scene.queue_free()
	await get_tree().process_frame

func _scenario_mainlab_module_placement():
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame

	# MainLab.tscn already has a default "Hull" node baked in
	# (interceptor_hull, size 2.4x0.8x3.2 - confirmed by inspecting the
	# first capture, NOT medium_hull as the module_placer.gd _ready()
	# fallback meta would suggest) - _place_hull_from_ui() is a no-op once
	# a hull exists, so these scenarios build on top of the scene's own
	# default rather than fighting it. Half-extents: 1.2/0.4/1.6.
	scene._place_weapon_from_ui("basic_cannon", Vector3(0, 0.6, -0.8), Vector3.UP)
	await get_tree().process_frame
	scene._place_weapon_from_ui("heavy_machine_gun", Vector3(0.9, 0.5, 0.6), Vector3.UP)
	await get_tree().process_frame
	scene._place_weapon_from_ui("tracked_treads", Vector3.ZERO, Vector3.DOWN)
	await get_tree().process_frame
	scene._deselect_module()

	await _capture_and_compare("mainlab_module_placement")
	scene.queue_free()
	await get_tree().process_frame

func _scenario_mainlab_armor_facet_fitting():
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame

	# Default hull is interceptor_hull (size 2.4x0.8x3.2) - half-extents
	# 1.2/0.4/1.6. A single top-facet plate only (not right+back together -
	# on a hull this small, two full-facet-covering armor plates legitimately
	# overlap near the corners, and check_all_clipping() correctly flags
	# that with the real red clipping material. That's the system working
	# as intended, not a bug - confirmed by inspecting the first capture,
	# where the "giant red block" was genuine overlapping-armor clipping,
	# not a missing mesh or rendering glitch. Kept to one plate here so
	# this scenario demonstrates normal facet-fitting, not a clipping case.
	scene._place_weapon_from_ui("armor_plating", Vector3(0.0, 0.85, 0.0), Vector3.UP)
	await get_tree().process_frame
	scene._deselect_module()

	await _capture_and_compare("mainlab_armor_facet_fitting")
	scene.queue_free()
	await get_tree().process_frame

func _scenario_mainlab_module_popup():
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame

	scene._place_weapon_from_ui("gauss_railgun", Vector3(0, 0.5, -1.0), Vector3.UP)
	await get_tree().process_frame

	# _place_weapon_from_ui() doesn't return the placed node - find it by
	# scanning the hull, same pattern other tests use.
	var weapon = null
	for child in scene.hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "gauss_railgun":
			weapon = child
			break
	var stat_ui = get_tree().get_first_node_in_group("stat_ui")
	if stat_ui and weapon:
		stat_ui.on_module_selected(weapon)
	await get_tree().process_frame

	await _capture_and_compare("mainlab_module_stat_popup")
	scene.queue_free()
	await get_tree().process_frame

func _scenario_skirmish_hud():
	var scene = load("res://scenes/Skirmish.tscn").instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame
	await get_tree().process_frame

	await _capture_and_compare("skirmish_hud")
	scene.queue_free()
	await get_tree().process_frame
