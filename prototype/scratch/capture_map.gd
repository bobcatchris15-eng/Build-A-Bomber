extends SceneTree
# Scratch: windowed map screenshot capture (map variety batch). Must run
# WITHOUT --headless - the dummy renderer used in headless mode never
# actually rasterizes anything (see project memory gotcha).
#
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_map.gd -- <map_id> <out_dir> [focus_x] [focus_z] [focus_height]
#
# Takes two screenshots: a top-down overview of the whole map, and an
# angled in-scene shot centered on (focus_x, focus_z) at focus_height -
# useful for framing a specific feature (a bridge, a hill, a city block).

func _init():
	var args = OS.get_cmdline_user_args()
	var map_id = args[0] if args.size() > 0 else "lake_crossing"
	var out_dir = args[1] if args.size() > 1 else "res://progress_captures/2026-07-13/scratch"
	var focus_x = float(args[2]) if args.size() > 2 else 0.0
	var focus_z = float(args[3]) if args.size() > 3 else 0.0
	var focus_height = float(args[4]) if args.size() > 4 else 22.0

	DirAccess.make_dir_recursive_absolute(out_dir)

	var skirmish = load("res://scenes/Skirmish.tscn").instantiate()
	skirmish.map_id = map_id
	root.add_child(skirmish)
	current_scene = skirmish
	for i in range(4):
		await process_frame

	print("[CAPTURE] map=", map_id, " name=", skirmish.current_map.get("name", "?"), " half_extents=", skirmish.current_map.get("map_half_extents", 80.0))

	var cam: Camera3D = skirmish.camera
	cam.set_process(false)
	var half: float = skirmish.current_map.get("map_half_extents", 80.0)

	# Top-down overview
	cam.global_position = Vector3(0, half * 2.1, 0.01) # tiny z offset - straight-down pitch + zero roll can be numerically unstable
	cam.rotation_degrees = Vector3(-90, 0, 0)
	for i in range(3):
		await process_frame
	var img_top = root.get_texture().get_image()
	img_top.save_png(out_dir + "/" + map_id + "_topdown.png")
	print("[CAPTURE] saved ", out_dir + "/" + map_id + "_topdown.png")

	# Angled in-scene shot over the focus point
	cam.global_position = Vector3(focus_x, focus_height, focus_z + focus_height * 0.9)
	cam.rotation_degrees = Vector3(-40, 0, 0)
	for i in range(3):
		await process_frame
	var img_scene = root.get_texture().get_image()
	img_scene.save_png(out_dir + "/" + map_id + "_scene.png")
	print("[CAPTURE] saved ", out_dir + "/" + map_id + "_scene.png")

	skirmish.queue_free()
	await process_frame
	quit(0)
