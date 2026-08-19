extends Node
# One-off: load Battle.tscn, wait for the world to finish building (match_director
# emits `world_ready` after async navmesh bake + scatter + roster + units + HUD),
# then settle a few extra frames for SDFGI/SSIL cascades, screenshot the
# viewport, save to visual_regression/captures/capture_battle.png, quit.
# Used for verifying the post-scatter-PBR-rewrite look. Not part of any test
# suite - delete after the verification run if you want; keeping it under
# prototype/tools/ so it doesn't pollute the main scripts dir.

func _ready():
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame

	var scene = load("res://scenes/Battle.tscn").instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame

	# match_director.gd's _ready is a coroutine — it awaits async terrain bake,
	# scatter spawn, navmesh rebake, unit spawn, HUD, AI. The world_ready signal
	# is emitted at the very end of all of that. We hang on it directly.
	if scene.has_signal("world_ready"):
		await scene.world_ready
	else:
		push_warning("[capture_battle] Battle scene has no world_ready signal — waiting 60 frames as fallback")
		for i in range(60):
			await get_tree().process_frame

	# SDFGI / SSIL need the camera to be still so their cascades settle, and
	# the wetness/curvature bakes need a frame to upload. 12 frames is plenty.
	for i in range(12):
		await get_tree().process_frame

	var img = get_viewport().get_texture().get_image()
	var out_dir = "res://visual_regression/captures"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	img.save_png(ProjectSettings.globalize_path(out_dir + "/capture_battle.png"))
	print("[capture_battle] saved " + out_dir + "/capture_battle.png")
	get_tree().quit()
