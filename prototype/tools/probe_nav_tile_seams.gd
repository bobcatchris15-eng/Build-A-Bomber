extends SceneTree
# Regression for the 2026-08-23 playtest bug: "units path off on a tangent
# and decide there's an arbitrary line they won't cross." The line was a
# navmesh tile seam: tiles were baked as standalone islands and stitched
# only by a 4x edge_connection_margin fallback, so seams whose erosion/
# quantization gap exceeded the margin simply never connected, and seams
# with a few surviving portals routed units along the seam to reach them.
#
# The fix (terrain_builder.gd's NAV_TILE_BORDER_CELLS: filter_baking_aabb +
# border_size chunk baking) makes tile edges coincide exactly. This probe
# proves connectivity directly:
#   1. map_get_path across EVERY interior seam of both tiled surfaces
#      (ground + amphibious), at several offsets along each seam;
#   2. the long player-spawn -> enemy-spawn route reaching its endpoint
#      without a gross detour (the original "returns toward base first"
#      report).
#
# Harness notes (each cost a debugging round to learn):
#   * A freshly assembled nav map serves "query before first synchronization"
#     errors, then Vector3.ZERO fallbacks, for a variable number of sync
#     cycles - iteration_id thresholds are NOT reliable (observed needing
#     one OR two syncs on different runs of identical setup). The gate below
#     therefore waits until both tiled maps answer a known-on-mesh point
#     with real geometry.
#   * NavigationAgent3D-driven traversal is flaky under a bare SceneTree
#     (is_navigation_finished() can report true before any path exists,
#     ending a drive without motion). Path-level queries are deterministic;
#     leave locomotion to the gameplay probes.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_nav_tile_seams.gd

const MapCatalogScript = preload("res://scripts/map_catalog.gd")
const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")

const MAP_ID := "lake_crossing"
# A short hop across a seam. Long enough to clear any residual clip noise,
# short enough that a failure is the seam, not the terrain.
const HOP := 3.0

var _checked := 0
var _skipped := 0
var _failures := 0


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _check_hop(nav_map: RID, start: Vector3, goal: Vector3, label: String) -> void:
	# Both endpoints have to be on-mesh for the hop to test the seam rather
	# than a hole (a lake or rock near a seam legitimately blocks a sample).
	var s_close := NavigationServer3D.map_get_closest_point(nav_map, start)
	var g_close := NavigationServer3D.map_get_closest_point(nav_map, goal)
	if _flat_dist(s_close, start) > 1.0 or _flat_dist(g_close, goal) > 1.0:
		_skipped += 1
		return
	_checked += 1
	var path := NavigationServer3D.map_get_path(nav_map, start, goal, true)
	if path.is_empty() or _flat_dist(path[path.size() - 1], goal) > 1.5:
		_failures += 1
		if _failures <= 12:
			print("[FAIL] %s seam hop %s -> %s did not reach (points=%d end=%s)" % [
				label, start, goal, path.size(),
				path[path.size() - 1] if not path.is_empty() else "N/A"])
		return


func _check_seams(nav_map: RID, rects: Array, half: float, label: String) -> void:
	for r in rects:
		# Vertical seam at the rect's right edge, where a right neighbour
		# exists.
		if r.x1 < half - 0.5:
			for t in [0.15, 0.5, 0.85]:
				var z: float = lerpf(r.z0, r.z1, t)
				_check_hop(nav_map, Vector3(r.x1 - HOP, 0.0, z),
					Vector3(r.x1 + HOP, 0.0, z), label)
		# Horizontal seam at the rect's bottom edge.
		if r.z1 < half - 0.5:
			for t in [0.15, 0.5, 0.85]:
				var x: float = lerpf(r.x0, r.x1, t)
				_check_hop(nav_map, Vector3(x, 0.0, r.z1 - HOP),
					Vector3(x, 0.0, r.z1 + HOP), label)


func _free_nav(nav: Dictionary) -> void:
	for rid in nav.ground_regions + nav.amphibious_regions:
		if rid.is_valid():
			NavigationServer3D.free_rid(rid)
	for key in ["water_region", "deep_water_region"]:
		if nav[key].is_valid():
			NavigationServer3D.free_rid(nav[key])
	for key in ["ground_map", "water_map", "amphibious_map", "deep_water_map"]:
		NavigationServer3D.free_rid(nav[key])


func _init() -> void:
	MapCatalogScript.reset_cache_for_tests()
	var map_def: Dictionary = MapCatalogScript.get_map(MAP_ID)
	var half: float = map_def.get("map_half_extents", 80.0)
	var rects: Array = TerrainBuilderScript._nav_tile_rects(map_def)
	print("%s: half=%s tiles=%d tile_size=%.2f cell=%.3f border=%.2f" % [
		MAP_ID, half, rects.size(), TerrainBuilderScript._nav_tile_size(map_def),
		TerrainBuilderScript._nav_tile_cell_size(map_def),
		TerrainBuilderScript._nav_tile_cell_size(map_def) * TerrainBuilderScript.NAV_TILE_BORDER_CELLS])

	var nav: Dictionary = TerrainBuilderScript.build_navmeshes(map_def)
	# Readiness gate - behavioral, because frame/iteration timing proved
	# non-deterministic across runs: a freshly assembled nav map serves
	# zero-vectors for one or more sync cycles after mesh assignment
	# ("query before first synchronization", then Vector3.ZERO fallbacks).
	# Wait until BOTH tiled surfaces answer a known-on-mesh probe point
	# (an interior tile centre) with real geometry before any judging.
	var mid: Dictionary = rects[rects.size() / 2]
	var probe_point := Vector3((mid.x0 + mid.x1) * 0.5, 0.0,
		(mid.z0 + mid.z1) * 0.5)
	var ready := false
	for f in range(900):
		await physics_frame
		# Skip the first sync cycle or two without querying - a query on an
		# unsynced map prints a scary (harmless) server error every call.
		if NavigationServer3D.map_get_iteration_id(nav.ground_map) == 0 \
				or NavigationServer3D.map_get_iteration_id(nav.amphibious_map) == 0:
			continue
		if f % 5 != 0:
			continue
		var g_ok := _flat_dist(NavigationServer3D.map_get_closest_point(
			nav.ground_map, probe_point), probe_point) <= 1.0
		var a_ok := _flat_dist(NavigationServer3D.map_get_closest_point(
			nav.amphibious_map, probe_point), probe_point) <= 1.0
		if g_ok and a_ok:
			ready = true
			break
	if not ready:
		print("[FAIL] tiled nav maps never became queryable (probe point %s)" % probe_point)
		_free_nav(nav)
		quit(1)
		return

	_check_seams(nav.ground_map, rects, half, "ground")
	_check_seams(nav.amphibious_map, rects, half, "amphibious")
	print("seam hops: checked=%d skipped(off-mesh)=%d failures=%d" % [
		_checked, _skipped, _failures])

	# The original complaint's route shape: base to base, long haul.
	var player_spawn = MapCatalogScript.get_spawn(map_def, "player")
	var enemy_spawn = MapCatalogScript.get_spawn(map_def, "enemy")
	var start: Vector3 = player_spawn.harvester
	var goal: Vector3 = enemy_spawn.harvester
	var path := NavigationServer3D.map_get_path(nav.ground_map, start, goal, true)
	var straight := _flat_dist(start, goal)
	var reached := not path.is_empty() and _flat_dist(path[path.size() - 1], goal) <= 2.0
	var path_len := 0.0
	for i in range(1, path.size()):
		path_len += _flat_dist(path[i - 1], path[i])
	print("long route: reached=%s path_len=%.1f straight=%.1f ratio=%.2f" % [
		reached, path_len, straight, path_len / maxf(straight, 0.001)])
	if not reached:
		_failures += 1
		print("[FAIL] player->enemy route never reaches its endpoint")
	elif path_len > straight * 2.0:
		_failures += 1
		print("[FAIL] player->enemy route detours %.1fx past straight-line" % [
			path_len / straight])

	_free_nav(nav)
	if _failures > 0:
		print("[FAIL] %d seam/connectivity failure(s)" % _failures)
		quit(1)
	else:
		print("[PASS] all tile seams connected; long route direct")
	quit(0)
