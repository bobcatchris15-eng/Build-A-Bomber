extends SceneTree
# The counter-draft suites alone.

const Suite = preload("res://tests/battle/test_counter_draft.gd")

const SUITES := [
	"test_counter_draft_classifies_real_designs",
	"test_counter_draft_answers_an_air_force",
	"test_counter_draft_never_demotes_the_harvester",
	"test_counter_draft_ignores_a_token_threat",
	"test_counter_draft_weights_recent_engagements",
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
		print("[PASS] all %d counter-draft suites pass" % SUITES.size())
		quit(0)
	else:
		print("[FAIL] %d failing: %s" % [failed.size(), str(failed)])
		quit(1)
