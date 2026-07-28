extends SceneTree
# A4 verification: real graphical hp bars (shader-driven, damaged to ~40%)
# + animated selection ring on a unit and a building. Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64.exe --path . scratch/capture_a4_hp_bars.tscn

func _init():
	var out_dir = "res://progress_captures/2026-07-27_a4_hp_bars"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene = load("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 800)
	for i in range(10): await process_frame

	# Damage the player HQ and a live unit to ~40% so the bar's mid/low
	# gradient and damage flash are both visible in the capture.
	scene.player_hq.take_damage(scene.player_hq.max_hp * 0.6, "explosive")
	scene.player_hq.set_selected(true)
	var units = scene.get_team_units(scene.PLAYER_TEAM)
	if not units.is_empty():
		var u = units[0]
		u.hp = u.max_hp * 0.35
		u._update_hp_bar()
		u.set_selected(true)
	for i in range(4): await process_frame

	var cam = scene.camera
	cam.global_position = scene.player_hq.global_position + Vector3(0, 8, 18)
	cam.look_at(scene.player_hq.global_position, Vector3.UP)
	for i in range(4): await process_frame

	root.get_texture().get_image().save_png("%s/a4_hp_bars_and_selection.png" % out_dir)
	print("[CAPTURE] A4 hp bars + selection rings saved")
	quit(0)
