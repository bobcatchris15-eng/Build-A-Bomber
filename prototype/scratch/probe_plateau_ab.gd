extends SceneTree
# Scratch: test_b6_heightmap_plateau_approachable_from_any_side fails at
# cell_size 1.0 (max_y 2.0) AND at 0.5 (max_y 1.0) against a required 2.5.
# Two candidate causes, and they must not be conflated:
#   (a) the coarser Recast cell genuinely stops resolving the plateau ramp
#   (b) the corner-height cache I added to _build_ground_faces() is wrong
#
# The 1.0 run predates the cache and the 0.5 run includes it, so the suite
# alone cannot separate them. This replicates the test's own pathing check
# across the full cell_size ladder, and independently verifies the cache by
# comparing _build_ground_faces() output with the cache warm vs. cold.
#
# Usage: ./godot.exe --script scratch/probe_plateau_ab.gd --path .

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")

const FIXTURE := "res://data/test_fixtures/terrain/test_terrain.json"

func _init():
	var file = FileAccess.open(FIXTURE, FileAccess.READ)
	var json = JSON.new()
	json.parse(file.get_as_text())
	file.close()
	var map_def: Dictionary = json.get_data()

	# --- (b) first: is the cache output-identical to computing every time? ---
	TerrainBuilder.reset_heightmap_cache_for_tests()
	var cold = TerrainBuilder._build_ground_faces(map_def, [])
	var warm = TerrainBuilder._build_ground_faces(map_def, [])
	print("cache check: cold %d verts, warm %d verts, identical=%s"
		% [cold.size(), warm.size(), str(cold == warm)])

	# Compare against heights computed directly, bypassing the cache, by
	# clearing between every call.
	TerrainBuilder.reset_heightmap_cache_for_tests()
	var fresh = TerrainBuilder._build_ground_faces(map_def, [])
	print("cache check: fresh-after-reset identical to cold=%s" % str(fresh == cold))
	print("")

	# --- (a) the real question: does the ramp survive each cell_size? ---
	# Same approach points and success bar as the test itself.
	var approaches = [
		{"side": "north", "start": Vector3(-40, 0, 45)},
		{"side": "south", "start": Vector3(-25, 0, 0)},
	]
	var target := Vector3(-40, 3, 20) # plateau top

	print("cell_size  side    path pts   max_y   (test needs max_y >= 2.5)")
	for cs in [0.25, 0.5, 1.0]:
		TerrainBuilder.reset_heightmap_cache_for_tests()
		var nav = _bake_with_cell_size(map_def, cs)
		await process_frame
		await process_frame
		for a in approaches:
			var path = NavigationServer3D.map_get_path(nav, a["start"], target, true)
			var max_y := -999.0
			for p in path:
				max_y = max(max_y, p.y)
			print("  %-8.2f %-7s %5d      %6.3f" % [cs, a["side"], path.size(), max_y])
	quit(0)

# Rebuilds just the ground map at an explicit cell_size, mirroring
# build_navmeshes()'s ground half.
func _bake_with_cell_size(map_def: Dictionary, cs: float) -> RID:
	var m = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(m, cs)
	NavigationServer3D.map_set_cell_height(m, cs)
	NavigationServer3D.map_set_active(m, true)
	var region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, m)
	var verts = TerrainBuilder._build_ground_faces(map_def, [])
	NavigationServer3D.region_set_navigation_mesh(region, TerrainBuilder._bake_nav_mesh(verts, cs))
	return m
