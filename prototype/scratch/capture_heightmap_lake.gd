extends SceneTree
# Scratch: windowed verification of the heightmap terrain pilot (organic
# water_blob lake + real subdivided ground mesh) on lake_crossing. Clears
# the fog shroud for this shot only (already verified separately) so the
# terrain itself is actually visible. Must run WITHOUT --headless.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_heightmap_lake.gd -- <out_dir>

func _init():
	var args = OS.get_cmdline_user_args()
	var out_dir = args[0] if args.size() > 0 else "res://progress_captures/scratch_heightmap_lake"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var skirmish = load("res://scenes/Skirmish.tscn").instantiate()
	skirmish.map_id = "lake_crossing"
	root.add_child(skirmish)
	current_scene = skirmish
	for i in range(4):
		await process_frame

	skirmish._fog_shroud_image.fill(Color(0, 0, 0, 0))
	skirmish._fog_shroud_texture.update(skirmish._fog_shroud_image)

	var blob = skirmish.current_map.water_blobs[0]
	var cam: Camera3D = skirmish.camera
	cam.set_process(false)

	# Straight-down top view centered on the lake, close enough to actually
	# see the organic coastline (not the whole 240-unit map).
	cam.global_position = Vector3(blob.center.x, 55, blob.center.z + 0.01)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	for i in range(3):
		await process_frame
	root.get_texture().get_image().save_png(out_dir + "/lake_topdown_closeup.png")
	print("[CAPTURE] saved lake_topdown_closeup.png")

	# Angled gameplay-camera-style view over the shoreline, close enough to
	# see the ground mesh's real elevation ripple against the water's edge.
	cam.global_position = Vector3(blob.center.x - 18, 22, blob.center.z + 18)
	cam.rotation_degrees = Vector3(-38, 0, 0)
	for i in range(3):
		await process_frame
	root.get_texture().get_image().save_png(out_dir + "/lake_shoreline_angle.png")
	print("[CAPTURE] saved lake_shoreline_angle.png")

	skirmish.queue_free()
	await process_frame
	quit(0)
