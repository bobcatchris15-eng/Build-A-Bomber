extends Node
# Windowed visual verification: interceptor_hull at default nose shape vs
# a sharp taper (0.35x) vs a flared nose (1.4x), to confirm the deform
# looks like a real reshape, not a broken/degenerate mesh.

func _ready():
	var root = get_tree().current_scene
	await get_tree().process_frame
	await get_tree().process_frame

	var cases = [
		["default", 1.0],
		["sharp_taper", 0.35],
		["flared", 1.4],
	]

	for i in range(cases.size()):
		if root.hull:
			root.clear_hull()
		await get_tree().process_frame
		root._place_hull_from_ui("interceptor_hull")
		await get_tree().process_frame
		root.hull.set_meta("nose_taper", cases[i][1])
		root.update_hull_appearance()
		await get_tree().process_frame
		await get_tree().process_frame

		var cam = get_viewport().get_camera_3d()
		if cam:
			cam.global_position = Vector3(3, 2, 3.5)
			cam.look_at(Vector3(0, 0.2, 0), Vector3.UP)
		await get_tree().process_frame
		await get_tree().process_frame

		var img = get_viewport().get_texture().get_image()
		img.save_png("res://scratch/nose_taper_%s.png" % cases[i][0])
		print("[NOSE-TAPER-VERIFY] Saved: ", cases[i][0])

	get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())
