extends SceneTree
# Playtest item #2a: how much can GROUND_NOISE_AMPLITUDE rise before ambient
# ground noise starts fighting MAX_WALKABLE_SLOPE and rejecting ordinary
# ground as unwalkable?
#
# Sweeps a multiplier over the CURRENT constant by scaling the map's
# world_scale-independent noise term directly (via a synthetic map_def whose
# height_at() is pure noise - no hills, no blobs, no heightmap), and reports
# the max and 99th-percentile slope each multiplier produces.

const MapCatalogScript = preload("res://scripts/map_catalog.gd")
const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")


func _init():
	MapCatalogScript.reset_cache_for_tests()
	var map_def: Dictionary = MapCatalogScript.get_map("open_plains")
	var half: float = map_def.get("map_half_extents", 80.0)
	print("open_plains half_extents=", half,
		" world_scale=", map_def.get("world_scale", 1.0),
		" MAX_WALKABLE_SLOPE=", TerrainBuilderScript.MAX_WALKABLE_SLOPE)
	print("current GROUND_NOISE_AMPLITUDE=", TerrainBuilderScript.GROUND_NOISE_AMPLITUDE)

	# Strip hills/water_blobs so height_at() is the PURE ambient noise term.
	# The hills carry their own (authored, intentional) slope and do not scale
	# with the noise amplitude at all, so leaving them in would swamp exactly
	# the measurement this probe exists to take.
	var noise_only: Dictionary = map_def.duplicate(true)
	noise_only.erase("hills")
	noise_only.erase("water_blobs")

	print("--- ambient noise only (hills/blobs stripped) ---")
	_report(noise_only, half, "noise")
	print("--- full map, for reference (authored hills included) ---")
	_report(map_def, half, "full")
	quit(0)


func _report(map_def: Dictionary, half: float, label: String) -> void:
	var slopes: Array[float] = []
	var heights: Array[float] = []
	var step: float = half / 60.0
	var x: float = -half + step
	while x < half - step:
		var z: float = -half + step
		while z < half - step:
			slopes.append(TerrainBuilderScript._slope_at(map_def, x, z))
			heights.append(TerrainBuilderScript.height_at(map_def, x, z))
			z += step
		x += step
	slopes.sort()
	heights.sort()
	var p99: float = slopes[int(slopes.size() * 0.99)]
	print("  %s: %d samples  height %.2f..%.2f (relief %.2f)" %
		[label, slopes.size(), heights[0], heights[-1], heights[-1] - heights[0]])
	print("  %s: slope median=%.4f p99=%.4f max=%.4f" %
		[label, slopes[int(slopes.size() * 0.5)], p99, slopes[-1]])
	if label != "noise":
		return
	# The noise term is exactly linear in GROUND_NOISE_AMPLITUDE, so a measured
	# baseline projects exactly.
	print("  projected if GROUND_NOISE_AMPLITUDE is multiplied by N:")
	for mult in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0, 12.0]:
		var projected: float = p99 * mult
		print("    N=%-4.0f relief=%-7.2f p99 slope=%-7.3f %s" %
			[mult, (heights[-1] - heights[0]) * mult, projected,
			("OK" if projected < TerrainBuilderScript.MAX_WALKABLE_SLOPE * 0.5 else
			 ("TIGHT" if projected < TerrainBuilderScript.MAX_WALKABLE_SLOPE else "REJECTS GROUND"))])
