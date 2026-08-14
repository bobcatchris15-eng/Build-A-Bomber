extends SceneTree
# Check what hull type the roster uses and whether authored meshes exist.
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_roster_hulls.gd

func _init():
	await process_frame

	var battle = preload("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	var guard := 0
	while not battle.world_is_ready and guard < 3000:
		await process_frame
		guard += 1
	if not battle.world_is_ready:
		print("[FAIL] Battle never built its world")
		quit(1)
		return

	var MeshAssetLoader = load("res://scripts/mesh_asset_loader.gd")

	print("=== ROSTER HULLS ===")
	for design in battle.roster:
		var name: String = str(design.get("name", "(unnamed)"))
		var hull_type: String = str(design.get("hull_type", "???"))
		var authored = MeshAssetLoader.get_hull_mesh(hull_type)
		var collision = MeshAssetLoader.get_hull_collision(hull_type)
		var piece_count := -1
		if collision != null:
			var pieces = collision.to_shapes()
			piece_count = pieces.size()
		print("  %-20s  hull=%-25s  mesh=%s  collision=%s  pieces=%d"
			% [name, hull_type,
			   "yes" if authored else "NO ",
			   "yes" if collision else "NO ",
			   piece_count])

	battle.queue_free()
	await process_frame
	quit(0)
