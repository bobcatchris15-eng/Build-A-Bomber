extends SceneTree
# The five non-smoke terrain suites that were also failing on empty paths, run
# together so the nav-map-synchronisation fix can be judged on them directly
# rather than only through a 20-minute full run.

const TerrainSuite = preload("res://tests/test_terrain_and_maps.gd")

const SUITES := [
	"test_b5_heightmap_navmesh_rejects_steep_slope",
	"test_b6_heightmap_plateau_approachable_from_any_side",
	"test_b8_large_map_navmesh_bake_does_not_crash_recast",
	"test_b10_spawn_fairness_lint_passes_real_maps_and_catches_bad_ones",
	"test_bridges_carve_a_real_ground_crossing_through_water",
]


func _init():
	var suite = TerrainSuite.new()
	suite.tree = self
	suite.root = root

	var failed: Array = []
	for name in SUITES:
		var ok: bool = await Callable(suite, name).call()
		print(">>> %s: %s" % [name, "PASS" if ok else "FAIL"])
		if not ok:
			failed.append(name)

	print("")
	if failed.is_empty():
		print("[PASS] all %d navmesh suites pass" % SUITES.size())
		quit(0)
	else:
		print("[FAIL] %d still failing: %s" % [failed.size(), str(failed)])
		quit(1)
