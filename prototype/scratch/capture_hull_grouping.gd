extends SceneTree
# Scratch: validates hull buttons in the Parts Catalog are now grouped by
# domain (Ground/Naval/Air/Static Defense) and each shows a stat-preview
# tooltip naming its domain and key stats. Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_hull_grouping.gd

func _init():
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 720)
	for i in range(6): await process_frame

	var parts_menu = scene.get_node("UI_PartsMenu")
	var tab_hulls = parts_menu.tab_hulls
	print("Hull button order:")
	for child in tab_hulls.get_children():
		print("  ", child.text, " -> tooltip: '", child.tooltip_text.split("\n")[0], "'")

	root.get_texture().get_image().save_png("res://progress_captures/2026-07-13/hull_grouping/parts_catalog_grouped.png")
	print("[CAPTURE] saved parts_catalog_grouped.png")

	quit(0)
