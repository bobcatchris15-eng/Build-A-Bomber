extends SceneTree
# The economy-balance arithmetic suites alone.

const Suite = preload("res://tests/battle/test_economy_balance.gd")

const SUITES := [
	"test_every_design_draws_the_same_rate_while_building",
	"test_four_harvesters_meet_the_stated_target",
	"test_harvester_capacity_comes_from_the_design",
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
	print("[%s] %d/%d passed" % ["PASS" if failed.is_empty() else "FAIL", SUITES.size() - failed.size(), SUITES.size()])
	quit(0 if failed.is_empty() else 1)
