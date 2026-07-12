extends Node
func _ready():
	var root = get_tree().current_scene
	await get_tree().process_frame
	await get_tree().process_frame

	root._place_hull_from_ui("heavy_hull")
	await get_tree().process_frame
	root._place_weapon_from_ui("armor_plating", Vector3(0, 0.75, -1.5), Vector3.UP)
	await get_tree().process_frame

	var armor = null
	for c in root.hull.get_children():
		if c.has_meta("module_data") and c.get_meta("module_data").type_id == "armor_plating":
			armor = c
			break
	root._select_module(armor)
	await get_tree().process_frame
	await get_tree().process_frame

	var img = get_viewport().get_texture().get_image()
	img.save_png("res://scratch/armor_material_ui.png")
	print("[ARMOR-MAT-UI-VERIFY] Screenshot saved.")
	get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())
