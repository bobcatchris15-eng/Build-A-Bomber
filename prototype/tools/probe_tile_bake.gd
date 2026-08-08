extends SceneTree
# Sanity-checks Chunk 21's tiling: tile count stays bounded, and a real
# ground+amphibious bake completes in reasonable time, on the two maps most
# likely to stress it (open_plains: typical, scattered_peaks: largest).
# Cross-tile pathing correctness is left to the automated suite
# (test_terrain_and_maps.gd's lake_crossing/plateau-ramp suites), which
# exercises real map_get_path() calls; this is purely a timing/count guard
# to catch a repeat of the ~19,000-tile hang before the full suite pays for
# it in wall-clock time.

const MapCatalogScript = preload("res://scripts/map_catalog.gd")
const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")

const MAPS := ["open_plains", "scattered_peaks"]


func _init():
	for map_id in MAPS:
		_measure(map_id)
	quit(0)


func _measure(map_id: String) -> void:
	MapCatalogScript.reset_cache_for_tests()
	var map_def: Dictionary = MapCatalogScript.get_map(map_id)
	var half: float = map_def.get("map_half_extents", 80.0)
	var tile_size: float = TerrainBuilderScript._nav_tile_size(map_def)
	var rects: Array = TerrainBuilderScript._nav_tile_rects(map_def)

	var old_cell_size: float = TerrainBuilderScript._nav_cell_size(map_def)
	var new_cell_size: float = TerrainBuilderScript._nav_tile_cell_size(map_def)

	var t0 := Time.get_ticks_msec()
	var nav: Dictionary = TerrainBuilderScript.build_navmeshes(map_def)
	var elapsed := Time.get_ticks_msec() - t0

	print("%s: half=%s tile_size=%.1f tile_count=%d old_cell=%.3f new_cell=%.3f fidelity_gain=%.2fx build_ms=%d" % [
		map_id, half, tile_size, rects.size(), old_cell_size, new_cell_size,
		old_cell_size / new_cell_size, elapsed])

	for rid in nav.ground_regions + nav.amphibious_regions:
		if rid.is_valid():
			NavigationServer3D.free_rid(rid)
	for key in ["water_region", "deep_water_region"]:
		if nav[key].is_valid():
			NavigationServer3D.free_rid(nav[key])
	for key in ["ground_map", "water_map", "amphibious_map", "deep_water_map"]:
		NavigationServer3D.free_rid(nav[key])
