extends Node
# Windowed visual verification: place a weapon, select it, screenshot the
# gold rotation ring gizmo alongside the X/Z scale handles.

func _ready():
	var root = get_tree().current_scene
	await get_tree().process_frame
	await get_tree().process_frame

	root._place_hull_from_ui("medium_hull")
	await get_tree().process_frame
	root._place_weapon_from_ui("basic_cannon", Vector3(0, 0.5, 0), Vector3.UP)
	await get_tree().process_frame

	var cannon = null
	for child in root.hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "basic_cannon":
			cannon = child
			break
	root._select_module(cannon)
	await get_tree().process_frame
	await get_tree().process_frame

	var cam = get_viewport().get_camera_3d()
	if cam:
		cam.global_position = Vector3(3, 3, 4)
		cam.look_at(Vector3(0, 0.6, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame

	var img = get_viewport().get_texture().get_image()
	img.save_png("res://scratch/rotation_ring.png")
	print("[ROTATION-RING-VERIFY] Screenshot saved.")
	get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())
