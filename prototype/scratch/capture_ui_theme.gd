extends SceneTree
# Scratch: windowed screenshots proving the brushed-aluminum UI theme
# switches with faction across screens. Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_ui_theme.gd

func _capture(path: String):
	var img = root.get_texture().get_image()
	img.save_png(path)
	print("[CAPTURE] saved ", path)

func _init():
	DirAccess.make_dir_recursive_absolute("res://progress_captures/2026-07-13/ui_theme")

	# MainMenu (default/no faction configured yet)
	var main_menu = load("res://scenes/MainMenu.tscn").instantiate()
	root.add_child(main_menu)
	current_scene = main_menu
	for i in range(4): await process_frame
	_capture("res://progress_captures/2026-07-13/ui_theme/main_menu_default.png")
	main_menu.queue_free()
	await process_frame

	# MatchSetup - default (Auto), then switched to Zealots, then Cybernetics
	var setup_scene = load("res://scenes/MatchSetup.tscn").instantiate()
	root.add_child(setup_scene)
	current_scene = setup_scene
	for i in range(4): await process_frame
	_capture("res://progress_captures/2026-07-13/ui_theme/match_setup_auto.png")

	var zealots_idx = setup_scene.FACTIONS.find("zealots")
	setup_scene.player_faction_btn.selected = zealots_idx
	setup_scene.player_faction_btn.item_selected.emit(zealots_idx)
	for i in range(4): await process_frame
	_capture("res://progress_captures/2026-07-13/ui_theme/match_setup_zealots.png")

	var cyber_idx = setup_scene.FACTIONS.find("cybernetics")
	setup_scene.player_faction_btn.selected = cyber_idx
	setup_scene.player_faction_btn.item_selected.emit(cyber_idx)
	for i in range(4): await process_frame
	_capture("res://progress_captures/2026-07-13/ui_theme/match_setup_cybernetics.png")
	setup_scene.queue_free()
	await process_frame

	# Design Lab sidebar under two different hull factions
	var lab_scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(lab_scene)
	current_scene = lab_scene
	for i in range(4): await process_frame
	var placer = lab_scene
	if placer.has_method("_place_hull_from_ui"):
		placer._place_hull_from_ui("medium_hull")
	for i in range(4): await process_frame
	var hull = placer.get_node_or_null("Hull")
	if hull:
		hull.set_meta("faction", "scavengers")
		if placer.has_method("update_hull_appearance"):
			placer.update_hull_appearance()
		call_group("stat_ui", "update_stats", hull)
	for i in range(4): await process_frame
	_capture("res://progress_captures/2026-07-13/ui_theme/design_lab_scavengers.png")
	lab_scene.queue_free()
	await process_frame

	# Skirmish HUD under player_faction = "cartel"
	var match_config = root.get_node_or_null("MatchConfig")
	if match_config:
		match_config.player_faction = "cartel"
	var skirmish = load("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	for i in range(6): await process_frame
	_capture("res://progress_captures/2026-07-13/ui_theme/skirmish_hud_cartel.png")
	skirmish.queue_free()
	await process_frame
	if match_config:
		match_config.player_faction = ""

	quit(0)
