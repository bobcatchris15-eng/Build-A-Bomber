extends SceneTree
# Scratch: windowed check that the raised rts_camera.gd max_height (120,
# was 45) actually shows meaningfully more of a scaled-up map at max
# zoom-out, from the real gameplay pitch angle (not the top-down override
# other capture scripts use).
#
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_camera_zoom.gd -- <map_id> <out_dir>

func _init():
	var args = OS.get_cmdline_user_args()
	var map_id = args[0] if args.size() > 0 else "twin_bridges"
	var out_dir = args[1] if args.size() > 1 else "res://progress_captures/scratch_zoom"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var skirmish = load("res://scenes/Skirmish.tscn").instantiate()
	skirmish.map_id = map_id
	root.add_child(skirmish)
	current_scene = skirmish
	for i in range(4):
		await process_frame

	var cam = skirmish.camera
	print("[CAPTURE] map=", map_id, " half_extents=", skirmish.current_map.get("map_half_extents", 80.0), " cam min/max height=", cam.min_height, "/", cam.max_height)

	# Force the whole shroud clear for this shot only - verifying the camera
	# can SEE more battlefield, not re-testing fog (already covered
	# elsewhere), and a mostly-black unexplored shroud would swamp the shot.
	skirmish._fog_shroud_image.fill(Color(0, 0, 0, 0))
	skirmish._fog_shroud_texture.update(skirmish._fog_shroud_image)

	cam.height = cam.max_height
	cam._apply_pitch()
	cam.global_position = Vector3(skirmish.current_map.player_start.hq.x, cam.height, skirmish.current_map.player_start.hq.z * 0.3)
	for i in range(3):
		await process_frame
	root.get_texture().get_image().save_png(out_dir + "/" + map_id + "_max_zoom_out.png")
	print("[CAPTURE] saved ", map_id, "_max_zoom_out.png")

	skirmish.queue_free()
	await process_frame
	quit(0)
