extends Node
# Windowed visual verification: place weapons on top, side, and as a
# frame-built railgun, to see the mount hardware differentiation.

func _ready():
	var root = get_tree().current_scene
	await get_tree().process_frame
	await get_tree().process_frame

	root._place_hull_from_ui("heavy_hull")
	await get_tree().process_frame

	# Top facet: pintle stand visible under the weapon.
	root._place_weapon_from_ui("heavy_machine_gun", Vector3(0, 0.75, -1.5), Vector3.UP)
	await get_tree().process_frame

	# Side facet: sponson-embedded, collar visible at the surface.
	root._place_weapon_from_ui("heavy_machine_gun", Vector3(3.0, 0.3, 1.0), Vector3.RIGHT)
	await get_tree().process_frame

	# Frame-built railgun: embedded deep, no extra hardware.
	root._place_weapon_from_ui("gauss_railgun", Vector3(0, 0.75, 2.0), Vector3.UP)
	await get_tree().process_frame

	root._select_module(null)
	await get_tree().process_frame

	var cam = get_viewport().get_camera_3d()
	if cam:
		cam.global_position = Vector3(7, 5, 8)
		cam.look_at(Vector3(0, 0.5, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame

	var img = get_viewport().get_texture().get_image()
	img.save_png("res://scratch/mounting_angled.png")

	if cam:
		cam.global_position = Vector3(1.5, 3.5, -1.0)
		cam.look_at(Vector3(0, 0.7, -1.5), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	var img2 = get_viewport().get_texture().get_image()
	img2.save_png("res://scratch/mounting_closeup_top.png")

	print("[MOUNTING-VERIFY] Screenshots saved.")
	get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())
