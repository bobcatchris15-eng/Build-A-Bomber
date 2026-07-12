extends Node
func _ready():
	var root = get_tree().current_scene
	await get_tree().process_frame
	await get_tree().process_frame
	root._place_hull_from_ui("medium_hull")
	await get_tree().process_frame
	await get_tree().process_frame
	var img = get_viewport().get_texture().get_image()
	img.save_png("res://scratch/threshold_wrap_fixed.png")
	print("[WRAP-VERIFY] Screenshot saved.")
	get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())
