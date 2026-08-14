extends SceneTree
# What does get_hull_collision() return for the Bulwark hull?
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_hull_collision_check.gd

func _init():
	var MeshAssetLoader = load("res://scripts/mesh_asset_loader.gd")

	var hull_type := "brenntal_mbt"
	var collision_res = MeshAssetLoader.get_hull_collision(hull_type)
	var authored = MeshAssetLoader.get_hull_mesh(hull_type)

	print("Hull: %s" % hull_type)
	print("  authored mesh : %s" % authored)
	print("  collision res: %s" % collision_res)

	if collision_res != null:
		print("  collision type: %s" % type_string(typeof(collision_res)))
		var pieces = collision_res.to_shapes()
		print("  piece count   : %d" % pieces.size())
		if pieces.size() > 0:
			print("  first piece type: %s" % type_string(typeof(pieces[0])))
			print("  first piece points: %s" % pieces[0].points)
	else:
		print("  (no collision resource)")

	quit(0)
