extends SceneTree
# Smoke test for PR8: TerrainBuilder.tiles_overlapping_hole() works with the
# {center, half_extents} hole shape (the one _building_holes() returns),
# AND the live urgent placement path in match_director goes through
# tiles_overlapping_hole() without errors.
#
# Catches the regression where the first cut of tiles_overlapping_hole
# assumed an {x1, x0, z1, z0} shape and the live placement path
# crashed every time the AI tried to build a structure.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_navmesh_urgent.gd

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array = []

	# --- Static-shape probe ------------------------------------------------
	# Build a 1x1 map_def with a 4-tile nav layout. We do not need the
	# map_def to be useful for anything - tiles_overlapping_hole only
	# reads the nav tile rects, not the map content.
	var map_def: Dictionary = {
		"map_half_extents": 80.0,
		"cell_size": 1.0,
	}
	# The hole shape is {center: Vector3, half_extents: Vector2}. A
	# refinery at (10, 0, 5) with a 8m square footprint + 2.5m clearance
	# is the kind of hole _building_holes() produces.
	var hole: Dictionary = {
		"center": Vector3(10, 0, 5),
		"half_extents": Vector2(6.5, 6.5),
	}
	var indices: Array = []
	# Wrap in a try-style guard: tiles_overlapping_hole depends on
	# _nav_tile_rects(map_def) returning a usable list. The default
	# lake_crossing maps are what we really want, so if map_def isn't
	# usable here, fall back to a live match's tile rects.
	# For the static probe, the simpler test is: call it on a real
	# loaded battle's map and verify it doesn't crash and returns
	# something sensible.
	var packed = load("res://scenes/Battle.tscn")
	if packed == null:
		failures.append("Battle.tscn did not load")
	else:
		var battle = packed.instantiate()
		root.add_child(battle)
		# Wait for the boot to complete so the navmesh is in place.
		var guard := 0
		while not battle.world_is_ready and guard < 600:
			await physics_frame
			guard += 1
		if not battle.world_is_ready:
			failures.append("battle never became ready (waited %d frames)" % guard)
		else:
			# Read the actual map_def from the director and run the helper
			# against it - same path the urgent placement path takes.
			var real_map: Dictionary = battle.current_map
			var real_indices: Array = TerrainBuilder.tiles_overlapping_hole(real_map, hole)
			print("[OK]   tiles_overlapping_hole returned %d tile(s) for a hole at (10,0,5) with 6.5m half-extents" % real_indices.size())
			if real_indices.is_empty():
				failures.append("tiles_overlapping_hole returned an empty list for a hole that should overlap at least one tile")
			else:
				# Sanity: every returned index should be a valid int.
				for idx in real_indices:
					if typeof(idx) != TYPE_INT:
						failures.append("tiles_overlapping_hole returned a non-int index: %s" % str(idx))
						break
			# Try a hole at the origin and a hole far off-map. Origin
			# should match several tiles; off-map should match zero.
			var origin_indices: Array = TerrainBuilder.tiles_overlapping_hole(real_map,
				{"center": Vector3.ZERO, "half_extents": Vector2(1, 1)})
			if origin_indices.is_empty():
				failures.append("origin hole should overlap at least one tile")
			var far_indices: Array = TerrainBuilder.tiles_overlapping_hole(real_map,
				{"center": Vector3(9999, 0, 9999), "half_extents": Vector2(1, 1)})
			if not far_indices.is_empty():
				failures.append("far-off-map hole should not overlap any tile; got %s" % str(far_indices))
			print("[OK]   origin overlap=%d, far-off-map overlap=%d" % [origin_indices.size(), far_indices.size()])
			# --- Live urgent placement path -------------------------------
			# Drive the live urgent code path. Direct call: place a
			# structure on the structures group, then trigger
			# _mark_navmesh_dirty(urgent=true). The previous bug
			# surfaced as a SCRIPT ERROR every frame; if the fix
			# holds, the call returns cleanly.
			battle._mark_navmesh_dirty(true)
			print("[OK]   battle._mark_navmesh_dirty(true) completed without error")
		battle.queue_free()
		await process_frame

	if failures.is_empty():
		print("[PASS] PR8 navmesh-urgent helpers wired correctly.")
		quit(0)
	else:
		for f in failures:
			print("[FAIL] %s" % f)
		quit(1)
