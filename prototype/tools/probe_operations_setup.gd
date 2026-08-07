extends SceneTree
# The four Operations setup suites on their own, so the screen can be iterated
# on without a full-suite round trip.

const Suite = preload("res://tests/battle/test_operations_setup.gd")

const SUITES := [
	"test_operations_engagement_count_spans_three_to_twelve",
	"test_operations_itinerary_resolves_every_map",
	"test_operations_changing_the_count_keeps_chosen_maps",
	"test_operations_difficulty_ramps_toward_the_choice",
]


func _init():
	var suite = Suite.new()
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
		print("[PASS] all %d operations suites pass" % SUITES.size())
		quit(0)
	else:
		print("[FAIL] %d failing: %s" % [failed.size(), str(failed)])
		quit(1)
