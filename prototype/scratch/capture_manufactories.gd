extends SceneTree
# Scratch: windowed screenshot of a Skirmish base showing the 3 size-tiered
# manufactories (light/medium/heavy) clustered at the map's factory spawn
# point, plus the build bar's 3 new manufactory buttons.
func _init():
	var skirmish = load("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	for i in range(6): await process_frame

	var cam = skirmish.camera
	cam.set_process(false)
	# Player base is around z=+30ish on lake_crossing - frame the factory cluster.
	var p_start = skirmish.current_map.player_start
	cam.global_position = p_start.factory + Vector3(0, 22, 20)
	cam.rotation_degrees = Vector3(-48, 0, 0)
	for i in range(4): await process_frame

	DirAccess.make_dir_recursive_absolute("res://progress_captures/2026-07-13/manufactories")
	var img = root.get_texture().get_image()
	img.save_png("res://progress_captures/2026-07-13/manufactories/manufactory_cluster.png")
	print("[CAPTURE] saved manufactory_cluster.png")

	# Also capture the build bar (bottom of the HUD) showing the 3 new buttons.
	cam.global_position = Vector3(0, 30, 45)
	cam.rotation_degrees = Vector3(-70, 0, 0)
	for i in range(4): await process_frame
	var img2 = root.get_texture().get_image()
	img2.save_png("res://progress_captures/2026-07-13/manufactories/build_bar.png")
	print("[CAPTURE] saved build_bar.png")

	skirmish.queue_free()
	await process_frame
	quit(0)
