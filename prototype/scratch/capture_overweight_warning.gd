extends SceneTree
# Scratch: validates the overweight warning - place enough heavy modules
# on a locomotion setup to exceed its weight capacity, and confirm the
# weight label turns orange with a tooltip explaining why. Must run
# WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_overweight_warning.gd

func _init():
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	for i in range(4): await process_frame

	var stat_ui = get_first_node_in_group("stat_ui")

	# Baseline: bare hull, no locomotion at all - capacity is 0, so the
	# overload check should never fire (total_weight_capacity <= 0.0 guard).
	stat_ui.update_stats(scene.hull)
	print("No locomotion: color=", stat_ui.weight_label.modulate, " tooltip='", stat_ui.weight_label.tooltip_text, "'")

	# Place light wheels (small capacity) then stack several heavy weapons
	# on top until total_weight blows past the wheels' own capacity.
	scene._place_weapon_from_ui("wheels", Vector3(0, -0.5, 0), Vector3.UP)
	scene.hull.set_meta("locomotion_type", "wheels")
	scene.hull.set_meta("locomotion_settings", {"count": 4, "size": 1.0})
	for i in range(2): await process_frame
	stat_ui.update_stats(scene.hull)
	print("Wheels only: color=", stat_ui.weight_label.modulate, " tooltip='", stat_ui.weight_label.tooltip_text, "'")

	for i in range(8):
		scene._place_weapon_from_ui("heavy_howitzer", Vector3(i * 0.01, 0.9, i * 0.3), Vector3.UP)
	for i in range(2): await process_frame
	stat_ui.update_stats(scene.hull)
	print("Overloaded with howitzers: color=", stat_ui.weight_label.modulate, " tooltip='", stat_ui.weight_label.tooltip_text, "'")

	root.size = Vector2i(1280, 720)
	for i in range(4): await process_frame
	DirAccess.make_dir_recursive_absolute("res://progress_captures/2026-07-13/overweight_warning")
	root.get_texture().get_image().save_png("res://progress_captures/2026-07-13/overweight_warning/overweight_orange.png")
	print("[CAPTURE] saved overweight_orange.png")
	quit(0)
