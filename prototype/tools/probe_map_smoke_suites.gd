extends SceneTree
# Runs the ten map-smoke suites BY THEMSELVES, through the real helper.
#
# Written to answer why all ten failed after the retirement commit. The answer
# was neither the maps nor the migrated production check: suite_base's helper
# queried the ground navmesh before NavigationServer3D had published it, so
# map_get_path() returned an empty array and every resource node read as
# unreachable. See suite_base._await_nav_map(). Kept because it is the cheapest
# way to re-check all ten without a full-suite run.

const TerrainSuite = preload("res://tests/test_terrain_and_maps.gd")

const SMOKES := [
	"test_map_open_plains_smoke",
	"test_map_lake_crossing_smoke",
	"test_map_highland_chokepoint_smoke",
	"test_map_coastal_strand_smoke",
	"test_map_twin_bridges_smoke",
	"test_map_twin_summits_smoke",
	"test_map_close_quarters_smoke",
	"test_map_urban_sprawl_smoke",
	"test_map_scattered_peaks_smoke",
	"test_map_ore_basin_smoke",
]


func _init():
	# suite_base extends RefCounted and is HANDED its tree/root rather than being
	# a Node in the tree - add_child()ing it is an error, not a shortcut.
	var suite = TerrainSuite.new()
	suite.tree = self
	suite.root = root

	var failed: Array = []
	for name in SMOKES:
		var ok: bool = await Callable(suite, name).call()
		print(">>> %s: %s" % [name, "PASS" if ok else "FAIL"])
		if not ok:
			failed.append(name)

	print("")
	if failed.is_empty():
		print("[PASS] all %d map smokes pass" % SMOKES.size())
		quit(0)
	else:
		print("[FAIL] %d/%d fail in isolation too - the failure is real: %s"
			% [failed.size(), SMOKES.size(), str(failed)])
		quit(1)
