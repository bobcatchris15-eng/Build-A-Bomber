extends SceneTree
# The Test Range dummy-damage suite, run alone and repeatedly. It is on
# run_tests.gd's documented flake list ("a real timing race, not suite-order
# contamination"), and this turn's changes should not be able to reach it - so
# the question is whether it fails independently of them.

const WeaponsSuite = preload("res://tests/test_weapons_and_damage.gd")


func _init():
	var passes := 0
	for i in range(4):
		var suite = WeaponsSuite.new()
		suite.tree = self
		suite.root = root
		var ok: bool = await suite.test_target_dummies_actually_take_damage_in_test_range()
		print(">>> run %d: %s" % [i + 1, "PASS" if ok else "FAIL"])
		if ok:
			passes += 1
	print("")
	print("%d/4 passed" % passes)
	quit(0 if passes > 0 else 1)
