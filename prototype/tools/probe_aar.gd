extends SceneTree
# The after-action report suites alone. The report is UI built entirely in code,
# so a single bad property assignment silently truncates it - iterating on it
# needs a faster loop than a full suite run.

const Suite = preload("res://tests/battle/test_after_action_report.gd")

const SUITES := [
	"test_after_action_report_builds_its_whole_self",
	"test_after_action_report_counts_energy_damage",
	"test_after_action_report_mvp_must_have_been_fielded",
	"test_after_action_report_offers_the_next_engagement",
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
		print("[PASS] all %d after-action report suites pass" % SUITES.size())
		quit(0)
	else:
		print("[FAIL] %d failing: %s" % [failed.size(), str(failed)])
		quit(1)
