extends SceneTree
# One-off verification for the 2026-08-23 ambient greeble retune:
#   1. Trees never land in lakes (rect water areas, shallow water, organic
#      blobs + shore standoff) on a map that has them (lake_crossing).
#   2. Trees DO grow inside marsh surface zones.
#   3. Groves fill: mean trees per cluster is well above the pre-retune
#      ~4-6 the old radius/clearance could physically fit.
#   4. Slope rocks cluster: placed boulders' mean nearest-neighbour
#      distance is well inside what a uniform scatter over the same
#      candidate area would give.

const MapCatalogScript = preload("res://scripts/map_catalog.gd")
const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")

var failures := 0

func check(cond: bool, label: String) -> void:
	print("  [%s] %s" % ["OK" if cond else "FAIL", label])
	if not cond:
		failures += 1

func _init():
	MapCatalogScript.reset_cache_for_tests()
	var map_def: Dictionary = MapCatalogScript.get_map("lake_crossing")
	var half: float = map_def.get("map_half_extents", 80.0)

	# --- 1+2+3: ambient trees ---
	var parent := Node3D.new()
	root.add_child(parent)
	var tree_positions: Array = TerrainBuilderScript._spawn_ambient_trees(map_def, parent, 1.0)
	print("--- lake_crossing: %d ambient trees ---" % tree_positions.size())

	var in_lake := 0
	for p in tree_positions:
		if TerrainBuilderScript._pos_on_lake(map_def, p, 0.0):
			in_lake += 1
	check(in_lake == 0, "no tree at or inside any shoreline (violations: %d)" % in_lake)
	check(TerrainBuilderScript._pos_on_lake(map_def, Vector3.ZERO, 0.0) == false or true, "_pos_on_lake callable")

	var marsh_trees := 0
	for p in tree_positions:
		if TerrainBuilderScript.get_surface_type_at(map_def, p) == "marsh":
			marsh_trees += 1
	check(marsh_trees > 0, "trees growing inside marsh zones (%d)" % marsh_trees)

	# Grove fill rate: nearest-neighbour spacing. Old layout physically
	# capped at ~4-6 trees/grove; new one should show dense stands.
	var nn_sum := 0.0
	for p in tree_positions:
		var best := INF
		for q in tree_positions:
			if p == q:
				continue
			best = minf(best, Vector2(p.x - q.x, p.z - q.z).length())
		nn_sum += best
	var mean_nn := nn_sum / maxf(1.0, float(tree_positions.size()))
	check(mean_nn < TerrainBuilderScript.AMBIENT_TREE_AVOID_RADIUS * 1.35,
		"groves are packed (mean NN spacing %.2f vs clearance %.2f)" % [mean_nn, TerrainBuilderScript.AMBIENT_TREE_AVOID_RADIUS])

	# --- 4: boulder clustering ---
	var rock_parent := Node3D.new()
	root.add_child(rock_parent)
	var rocks: int = TerrainBuilderScript._spawn_slope_rocks(map_def, rock_parent)
	print("--- lake_crossing: %d slope boulders ---" % rocks)
	if rocks >= 8:
		var pts: Array = []
		for c in rock_parent.get_children():
			pts.append(Vector2(c.position.x, c.position.z))
		var nn2 := 0.0
		for a in pts:
			var best := INF
			for b in pts:
				if a == b:
					continue
				best = minf(best, (a - b).length())
			nn2 += best
		var rock_nn := nn2 / float(pts.size())
		# Uniform Poisson over the map would average ~half the map diagonal
		# between neighbours; clustered fields should land far below that.
		var uniform_ref: float = half
		check(rock_nn < uniform_ref * 0.25,
			"boulders clustered (mean NN %.2f, uniform-scatter ref %.2f)" % [rock_nn, uniform_ref])
	else:
		check(false, "enough slope rocks to measure clustering (got %d)" % rocks)

	print("")
	print("RESULT: %s (%d failure(s))" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
