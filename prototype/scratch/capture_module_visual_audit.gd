extends SceneTree
# Windowed visual check: how do module meshes actually look in the Design
# Lab right now? Places a representative spread of weapon/support module
# types on a hull and screenshots from a few angles.
# Run: ./Godot_v4.3-stable_win64.exe --path . scratch/capture_module_visual_audit.gd

func _init():
	var out_dir = "res://progress_captures/2026-07-18_module_visual_audit"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	root.size = Vector2i(1280, 800)
	for i in range(10): await process_frame

	scene._place_hull_from_ui("heavy_hull")
	await process_frame

	scene._place_weapon_from_ui("basic_cannon", Vector3(0, 0.75, -2.0), Vector3.UP)
	await process_frame
	scene._place_weapon_from_ui("rotary_cannon", Vector3(1.5, 0.75, -1.0), Vector3.UP)
	await process_frame
	scene._place_weapon_from_ui("gauss_railgun", Vector3(-1.5, 0.75, -1.0), Vector3.UP)
	await process_frame
	scene._place_weapon_from_ui("heavy_howitzer", Vector3(0, 0.75, 0.5), Vector3.UP)
	await process_frame
	scene._place_weapon_from_ui("missile_pod", Vector3(1.5, 0.75, 1.5), Vector3.UP)
	await process_frame
	scene._place_weapon_from_ui("sensor_suite", Vector3(-1.5, 0.75, 1.5), Vector3.UP)
	await process_frame
	scene._place_weapon_from_ui("repair_array", Vector3(0, 0.75, 2.3), Vector3.UP)
	await process_frame
	scene._place_weapon_from_ui("flak_cannon", Vector3(2.5, 0.75, 0), Vector3.UP)
	await process_frame
	scene._place_weapon_from_ui("resource_harvester", Vector3(-2.5, 0.75, 0), Vector3.UP)
	await process_frame

	var cam = root.get_camera_3d()
	if cam:
		cam.global_position = Vector3(9, 8, 9)
		cam.look_at(Vector3(0, 0.5, 0), Vector3.UP)
	for i in range(3): await process_frame
	root.get_texture().get_image().save_png("%s/wide_iso.png" % out_dir)
	print("[MODULE-AUDIT] wide_iso.png saved")

	if cam:
		cam.global_position = Vector3(3, 3, 4)
		cam.look_at(Vector3(0, 0.75, -1), Vector3.UP)
	for i in range(3): await process_frame
	root.get_texture().get_image().save_png("%s/close_cannons.png" % out_dir)
	print("[MODULE-AUDIT] close_cannons.png saved")

	if cam:
		cam.global_position = Vector3(-3, 3, 3)
		cam.look_at(Vector3(-1, 0.75, 1.5), Vector3.UP)
	for i in range(3): await process_frame
	root.get_texture().get_image().save_png("%s/close_support.png" % out_dir)
	print("[MODULE-AUDIT] close_support.png saved")

	quit(0)
