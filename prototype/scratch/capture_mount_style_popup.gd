extends SceneTree
# Scratch: validates the module-selection popup now shows the mount_style
# (pintle/sponson/frame_built/turret) for a placed weapon, previously
# never surfaced anywhere. Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_mount_style_popup.gd

func _init():
	var out_dir = "res://progress_captures/2026-07-13/mount_style_popup"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 720)
	for i in range(6): await process_frame

	# Place a weapon on top of the default hull (pintle_top mount) directly.
	scene._place_weapon_from_ui("basic_cannon", Vector3(0, 0.575, 0), Vector3.UP)
	for i in range(4): await process_frame

	var stat_ui = get_first_node_in_group("stat_ui")
	var weapon_module = null
	for child in scene.hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "basic_cannon":
			weapon_module = child
			break
	if weapon_module:
		print("mount_style meta: '", weapon_module.get_meta("mount_style", "<none>"), "'")
		stat_ui.on_module_selected(weapon_module)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/weapon_popup_with_mount_style.png" % out_dir)
	print("[CAPTURE] saved weapon_popup_with_mount_style.png")
	print("popup_stats_label text: '", stat_ui.popup_stats_label.text, "'")

	quit(0)
