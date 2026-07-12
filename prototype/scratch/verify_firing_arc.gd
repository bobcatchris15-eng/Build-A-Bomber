extends Node
# Windowed visual verification of the firing arc visualization: builds a
# hull with a 360-traverse cannon and a blocking mast, selects the cannon
# (which builds the ArcCone), screenshots from a top-down angle so the
# red/blue wedge segments are clearly visible.

func _ready():
	var root = get_tree().current_scene
	await get_tree().process_frame
	await get_tree().process_frame

	root._place_hull_from_ui("heavy_hull")
	await get_tree().process_frame
	root._place_weapon_from_ui("basic_cannon", Vector3(0, 0.75, 0), Vector3.UP)
	await get_tree().process_frame
	root._place_weapon_from_ui("sensor_suite", Vector3(0, 0.75, -1.2), Vector3.UP)
	await get_tree().process_frame

	var cannon = null
	for child in root.hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "basic_cannon":
			cannon = child
			break
	root._select_module(cannon)
	await get_tree().process_frame
	await get_tree().process_frame

	# Reposition the designer camera to a top-down angle so the arc wedge is legible.
	var cam = get_viewport().get_camera_3d()
	if cam:
		cam.global_position = Vector3(0.01, 14, 0.01)
		cam.look_at(Vector3(0, 0, 0), Vector3.FORWARD)
	await get_tree().process_frame
	await get_tree().process_frame

	var img = get_viewport().get_texture().get_image()
	img.save_png("res://scratch/firing_arc_topdown.png")
	print("[FIRING-ARC-VERIFY] Screenshot saved.")

	# Also grab an angled shot for a more natural view.
	if cam:
		cam.global_position = Vector3(6, 5, 6)
		cam.look_at(Vector3(0, 0.5, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	var img2 = get_viewport().get_texture().get_image()
	img2.save_png("res://scratch/firing_arc_angled.png")
	print("[FIRING-ARC-VERIFY] Angled screenshot saved.")

	get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())
