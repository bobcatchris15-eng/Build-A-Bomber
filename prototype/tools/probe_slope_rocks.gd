extends SceneTree
# Playtest item #4/#5: boulders should be heaviest on slopes, and cliffs/
# ravines should read as the same geology as the loose rock. Verifies the
# density curve is monotonic, that the real pass actually places rock, and -
# the claim that matters - that where it places rock is genuinely steeper
# than the map average.

const MapCatalogScript = preload("res://scripts/map_catalog.gd")
const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")


func _init():
	print("--- density curve ---")
	var prev := -1.0
	for s in [0.0, 0.05, 0.12, 0.2, 0.35, 0.5, 0.7, 1.0]:
		var d: float = TerrainBuilderScript.slope_rock_density(s)
		var ok: String = "OK" if d >= prev else "NOT MONOTONIC"
		print("  slope=%.2f -> density=%.3f  %s" % [s, d, ok])
		prev = d

	MapCatalogScript.reset_cache_for_tests()
	for map_id in ["open_plains", "highland_chokepoint"]:
		var map_def: Dictionary = MapCatalogScript.get_map(map_id)
		var half: float = map_def.get("map_half_extents", 80.0)
		var parent := Node3D.new()
		root.add_child(parent)
		var placed: int = TerrainBuilderScript._spawn_slope_rocks(map_def, parent)
		print("--- ", map_id, " ---")
		print("  placed=", placed, " (cap ", TerrainBuilderScript.SLOPE_ROCK_MAX_COUNT, ")")

		# Mean slope where rocks actually landed vs. mean slope of the map.
		var rock_slope := 0.0
		for c in parent.get_children():
			rock_slope += TerrainBuilderScript._slope_at(map_def, c.position.x, c.position.z)
		var map_slope := 0.0
		var n := 0
		var step: float = half / 30.0
		var x := -half
		while x < half:
			var z := -half
			while z < half:
				map_slope += TerrainBuilderScript._slope_at(map_def, x, z)
				n += 1
				z += step
			x += step
		if placed > 0:
			print("  mean slope UNDER placed rocks = %.4f" % (rock_slope / placed))
		print("  mean slope across whole map      = %.4f" % (map_slope / n))
		parent.queue_free()
	quit(0)
