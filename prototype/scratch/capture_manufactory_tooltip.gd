extends SceneTree
# Scratch: validates the manufactory-tier tooltip on the Total Weight
# label reads correctly for light/medium/heavy hulls, and that the AI
# difficulty dropdown in MatchSetup now has real tooltips. Native OS
# tooltip popups are timing-driven and awkward to force into a screenshot
# reliably, so this verifies the underlying tooltip_text property values
# directly instead. Must run WITHOUT --headless (still needs a real
# renderer to instantiate the scenes cleanly).
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_manufactory_tooltip.gd

func _init():
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	for i in range(4): await process_frame

	var stat_ui = get_first_node_in_group("stat_ui")

	for hull_id in ["light_hull", "medium_hull", "heavy_hull", "pillbox_foundation"]:
		scene.hull.set_meta("type_id", hull_id)
		stat_ui.update_stats(scene.hull)
		print(hull_id, " -> weight_label tooltip: '", stat_ui.weight_label.tooltip_text, "'")

	var setup_scene = load("res://scenes/MatchSetup.tscn").instantiate()
	root.add_child(setup_scene)
	for i in range(4): await process_frame
	print("Difficulty dropdown tooltip: '", setup_scene.difficulty_btn.tooltip_text, "'")
	print("Difficulty item 0 tooltip: '", setup_scene.difficulty_btn.get_item_tooltip(0), "'")
	print("Difficulty item 2 tooltip: '", setup_scene.difficulty_btn.get_item_tooltip(2), "'")

	quit(0)
