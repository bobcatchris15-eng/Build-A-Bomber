extends SceneTree
# Scratch: windowed verification of the fog-of-war shroud (Skirmish
# refinement, Phase A). Must run WITHOUT --headless (dummy renderer never
# rasterizes - see project memory gotcha).
#
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_fog_shroud.gd -- <out_dir>
#
# Three shots proving the three-state model: (1) match start - mostly black,
# a small revealed disc around the player's own base, (2) a scout unit sent
# deep into unexplored territory - a new revealed disc appears out there,
# (3) the scout pulled back home - the patch it just left goes DIMMED, not
# back to black, while a fresh disc stays clear around wherever it is now.

func _init():
	var args = OS.get_cmdline_user_args()
	var out_dir = args[0] if args.size() > 0 else "res://progress_captures/scratch_fog"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var skirmish = load("res://scenes/Skirmish.tscn").instantiate()
	skirmish.map_id = "lake_crossing"
	root.add_child(skirmish)
	current_scene = skirmish
	for i in range(4):
		await process_frame

	var half: float = skirmish.current_map.get("map_half_extents", 80.0)
	var cam: Camera3D = skirmish.camera
	cam.set_process(false)
	cam.global_position = Vector3(0, half * 2.1, 0.01)
	cam.rotation_degrees = Vector3(-90, 0, 0)

	skirmish._recalc_fog_of_war()
	for i in range(3):
		await process_frame
	root.get_texture().get_image().save_png(out_dir + "/1_match_start.png")
	print("[CAPTURE] saved 1_match_start.png")

	# Grab any player combat unit (spawned starting harvester counts fine
	# too - just needs a vision_range) and drive it far into unexplored
	# territory near the enemy's side, well outside the base's own vision.
	var scout = skirmish.get_team_units(skirmish.PLAYER_TEAM)[0]
	var home_pos = scout.global_position
	scout.global_position = Vector3(-25, scout.global_position.y, -30)
	skirmish._recalc_fog_of_war()
	for i in range(3):
		await process_frame
	root.get_texture().get_image().save_png(out_dir + "/2_scout_deep.png")
	print("[CAPTURE] saved 2_scout_deep.png")

	scout.global_position = home_pos
	skirmish._recalc_fog_of_war()
	for i in range(3):
		await process_frame
	root.get_texture().get_image().save_png(out_dir + "/3_scout_returned.png")
	print("[CAPTURE] saved 3_scout_returned.png")

	skirmish.queue_free()
	await process_frame
	quit(0)
