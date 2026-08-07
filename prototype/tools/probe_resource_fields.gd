extends SceneTree
const Suite = preload("res://tests/battle/test_resource_fields.gd")
const SUITES := [
	"test_resource_catalog_aliases_metal_to_ore",
	"test_resource_values_form_a_real_ladder",
	"test_a_field_scatters_and_refills",
	"test_oil_wells_are_single_points",
	"test_every_map_offers_lumber_and_oil",
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
