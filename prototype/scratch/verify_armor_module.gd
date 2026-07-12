extends Node
# Windowed visual verification: place armor plates on top and one side
# facet of a hull, screenshot to confirm they auto-fit and center properly,
# and that the side plate mirrors to the opposite side.

func _ready():
	var root = get_tree().current_scene
	await get_tree().process_frame
	await get_tree().process_frame

	root._place_hull_from_ui("heavy_hull")
	await get_tree().process_frame

	# Top facet, clicked off-center - should still center + auto-fit.
	root._place_weapon_from_ui("armor_plating", Vector3(1.0, 0.75, -1.5), Vector3.UP)
	await get_tree().process_frame

	# Right-side facet - should mirror to the left.
	root._place_weapon_from_ui("armor_plating", Vector3(3.0, 0.0, 1.0), Vector3.RIGHT)
	await get_tree().process_frame

	root._select_module(null)
	await get_tree().process_frame

	var cam = get_viewport().get_camera_3d()
	if cam:
		cam.global_position = Vector3(8, 6, 9)
		cam.look_at(Vector3(0, 0.5, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame

	var img = get_viewport().get_texture().get_image()
	img.save_png("res://scratch/armor_module_angled.png")

	if cam:
		cam.global_position = Vector3(0.01, 14, 0.01)
		cam.look_at(Vector3(0, 0, 0), Vector3.FORWARD)
	await get_tree().process_frame
	await get_tree().process_frame
	var img2 = get_viewport().get_texture().get_image()
	img2.save_png("res://scratch/armor_module_topdown.png")

	print("[ARMOR-MODULE-VERIFY] Screenshots saved.")
	get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())
