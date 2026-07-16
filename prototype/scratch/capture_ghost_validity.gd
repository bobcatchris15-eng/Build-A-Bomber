extends SceneTree
# Scratch: validates the placement ghost now colors live by validity
# (green=valid, red=invalid) instead of always being green. Directly
# drives _begin_placement/_placement_validity/ghost color update rather
# than simulating real mouse events (InputEventMouseMotion needs a real
# viewport pointer, awkward to fake reliably) - this exercises the exact
# same code path skirmish.gd's own _unhandled_input calls.
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_ghost_validity.gd

func _init():
	var out_dir = "res://progress_captures/2026-07-13/ghost_validity"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var skirmish_scene = load("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish_scene)
	root.size = Vector2i(1280, 720)
	for i in range(10): await process_frame

	skirmish_scene._begin_placement({"kind": "light_manufactory", "cost_metal": 0, "cost_crystal": 0})
	for i in range(2): await process_frame

	# Valid spot: right next to the player's own HQ.
	var hq_pos = skirmish_scene.player_hq.global_position
	var valid_pos = hq_pos + Vector3(6, 0, 0)
	skirmish_scene.placement_ghost.global_position = valid_pos
	var v1 = skirmish_scene._placement_validity(valid_pos)
	skirmish_scene.placement_ghost.material_override.albedo_color = skirmish_scene.GHOST_COLOR_VALID if v1.valid else skirmish_scene.GHOST_COLOR_INVALID
	print("valid_pos validity: ", v1, " ghost color: ", skirmish_scene.placement_ghost.material_override.albedo_color)
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png("%s/ghost_valid_green.png" % out_dir)
	print("[CAPTURE] saved ghost_valid_green.png")

	# Invalid spot: far from any base, but still within camera view.
	var far_pos = hq_pos + Vector3(45, 0, 10)
	skirmish_scene.placement_ghost.global_position = far_pos
	var v2 = skirmish_scene._placement_validity(far_pos)
	skirmish_scene.placement_ghost.material_override.albedo_color = skirmish_scene.GHOST_COLOR_VALID if v2.valid else skirmish_scene.GHOST_COLOR_INVALID
	print("far_pos validity: ", v2, " ghost color: ", skirmish_scene.placement_ghost.material_override.albedo_color)
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png("%s/ghost_invalid_red.png" % out_dir)
	print("[CAPTURE] saved ghost_invalid_red.png")

	quit(0)
