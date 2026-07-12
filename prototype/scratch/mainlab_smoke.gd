extends Node
# Windowed smoke test of the REAL MainLab entry scene + real placement flow:
# spawn a hull via the actual UI method, place a couple of real weapons via
# the actual drag-drop target method, screenshot, quit.

func _ready():
	var root = get_tree().current_scene
	await get_tree().process_frame
	await get_tree().process_frame

	if root.has_method("_place_hull_from_ui"):
		root._place_hull_from_ui("assault_hull")
	await get_tree().process_frame

	if root.has_method("_place_weapon_from_ui"):
		root._place_weapon_from_ui("gauss_railgun", Vector3(0, 0.65, -0.5), Vector3.UP)
		root._place_weapon_from_ui("wheels", Vector3.ZERO, Vector3.DOWN)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var img = get_viewport().get_texture().get_image()
	img.save_png("res://scratch/mainlab_smoke.png")
	print("[MAINLAB-SMOKE] Screenshot saved.")
	get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())
