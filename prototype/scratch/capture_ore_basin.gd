extends SceneTree
# Ore Basin verification: 3 clustered resource fields visible from an
# overhead angle. Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64.exe --script scratch/capture_ore_basin.gd --path .

func _init():
	var out_dir = "res://progress_captures/2026-07-27_ore_basin"
	DirAccess.make_dir_recursive_absolute(out_dir)

	await process_frame # autoloads (MatchConfig) aren't attached yet on the very first _init() frame
	var match_config = root.get_node_or_null("MatchConfig")
	if match_config:
		match_config.selected_map_id = "ore_basin"
	else:
		print("[CAPTURE] WARNING: MatchConfig autoload not found, map may default")
	var scene = load("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 800)
	for i in range(10): await process_frame
	scene.debug_reveal_all_fog = true
	scene._recalc_fog_of_war()
	await process_frame

	var cam = scene.camera
	cam.global_position = Vector3(0, 160, 0.001)
	cam.rotation_degrees = Vector3(-89.9, 0, 0)
	for i in range(4): await process_frame

	root.get_texture().get_image().save_png("%s/ore_basin_overhead.png" % out_dir)
	print("[CAPTURE] Ore Basin overhead view saved, map_id=", scene.current_map.get("name", "?"))
	quit(0)
