extends Node
func _ready():
	var root = get_tree().current_scene
	await get_tree().process_frame
	await get_tree().process_frame

	root._place_hull_from_ui("light_hull")
	await get_tree().process_frame
	root._place_weapon_from_ui("fixed_wing_engine", Vector3.ZERO, Vector3.DOWN)
	await get_tree().process_frame

	var cam = get_viewport().get_camera_3d()
	if cam:
		cam.global_position = Vector3(5, 3, 5)
		cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	var img = get_viewport().get_texture().get_image()
	img.save_png("res://scratch/new_loco_fixedwing.png")

	root.clear_hull()
	await get_tree().process_frame
	root._place_hull_from_ui("heavy_hull")
	await get_tree().process_frame
	root._place_weapon_from_ui("naval_propeller", Vector3.ZERO, Vector3.DOWN)
	await get_tree().process_frame
	await get_tree().process_frame
	var img2 = get_viewport().get_texture().get_image()
	img2.save_png("res://scratch/new_loco_naval.png")

	print("[NEW-LOCO-VERIFY] Screenshots saved.")
	get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())
