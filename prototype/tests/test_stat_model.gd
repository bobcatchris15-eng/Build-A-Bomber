extends "res://tests/suite_base.gd"
# Stat-model suites. Registration order lives in run_tests.gd's SUITE_ORDER.
#
# These are pure-math suites in the test_design_verdict.gd mould: ModuleData is
# a Resource, so every case below runs with no Lab, no hull and no rendered
# frame. What they guard is the arithmetic between a slider and a stat, which
# is the layer where two long-lived defects hid because nothing ever asserted
# the shape of the curve, only that a number came out.
#
#   1. Count-style tweaks (barrel_count, tube_count, leg_count, ...) normalized
#      against a hardcoded literal instead of the module's own declared
#      default, so touching a slider silently rescaled the module. Fixed by
#      ModuleCatalog.count_tweak_normalizer(); guarded here both as a table
#      check against the two spec dictionaries and as a behavioural check
#      through ModuleData itself.
#
#   2. protectedness ("Armor Level") bought HP more cheaply per kilogram than
#      it charged for it, making the slider strictly dominant. Fixed by raising
#      the weight coefficient above the HP coefficient in module_data.gd;
#      guarded here by asserting HP-per-kilogram strictly falls as armor rises.

const LabDocumentScript = preload("res://scripts/lab_document.gd")


# ModuleData built from a type's real catalog entry, so the numbers under test
# are the ones the game ships rather than a fixture that can agree with a bug.
func _module(type_id: String, tweaks: Dictionary) -> ModuleData:
	var catalog_data = ModuleCatalog.get_module_data(type_id)
	var data = ModuleData.new()
	data.type_id = type_id
	data.base_hp = catalog_data.get("hp", 0.0)
	data.base_weight = catalog_data.get("weight", 0.0)
	data.cost_metal = catalog_data.get("metal", 0)
	data.cost_crystal = catalog_data.get("crystal", 0)
	data.base_dps = catalog_data.get("dps", 0.0)
	data.tweaks = tweaks
	return data


# Every (type_id, spec) pair across BOTH declaration sites, so a suite can walk
# the whole vocabulary without caring which file a slider was declared in.
# TWEAK_SPECS owns modules; LOCOMOTION_TWEAK_SPECS owns running gear; their key
# sets are disjoint and the loop below asserts nothing about that either way.
func _all_tweak_specs() -> Array:
	var out := []
	for type_id in LabDocumentScript.TWEAK_SPECS:
		for spec in LabDocumentScript.TWEAK_SPECS[type_id]:
			out.append([type_id, spec])
	for type_id in ModuleCatalog.LOCOMOTION_TWEAK_SPECS:
		for spec in ModuleCatalog.LOCOMOTION_TWEAK_SPECS[type_id]:
			out.append([type_id, spec])
	return out


func test_count_tweak_normalizer_matches_declared_defaults() -> bool:
	print("Running Test Suite: Count Tweak Normalizer Matches Declared Defaults...")
	# THE DRIFT GUARD. ModuleCatalog.COUNT_TWEAK_DEFAULTS is a hand-written
	# mirror of stat_calculator.gd's TWEAK_SPECS - it has to be, because
	# stat_calculator.gd preloads module_data.gd which preloads module_catalog.gd,
	# so the catalog cannot read the specs without a cycle. A test file has no
	# such constraint and can preload both, which is the whole reason this
	# check is expressible here and nowhere else.
	#
	# Mirrored tables in this codebase drift (see design_verdict.gd and
	# drivetrain.gd for the previous two). The rule is exact: for every
	# count-style tweak on every module in either spec table, the normalizer
	# must equal the slider's declared default, so the multiplier is precisely
	# 1.0 for an untouched module.
	var mismatches := []
	var checked := 0
	for pair in _all_tweak_specs():
		var type_id: String = pair[0]
		var spec: Dictionary = pair[1]
		var tweak_name: String = spec.get("name", "")
		if not ModuleCatalog.is_count_tweak(tweak_name):
			continue
		checked += 1
		var declared := float(spec.get("default", -1.0))
		var normalizer := ModuleCatalog.count_tweak_normalizer(type_id, tweak_name)
		if declared <= 0.0:
			mismatches.append("%s.%s declares a non-positive default (%s) - a count of zero cannot normalize" % [type_id, tweak_name, declared])
		elif abs(normalizer - declared) > 0.0001:
			mismatches.append("%s.%s declares default %s but normalizes by %s" % [type_id, tweak_name, declared, normalizer])

	if not mismatches.is_empty():
		print("  [FAIL] Normalizer disagrees with the declared slider default:")
		for m in mismatches:
			print("         ", m)
		return false
	# A silent zero here would mean the walk found nothing - a renamed constant
	# or an emptied table would pass an all-clear that never ran.
	if checked == 0:
		print("  [FAIL] Walked both spec tables and found no count-style tweaks at all - the tables or ModuleCatalog.is_count_tweak() moved")
		return false
	print("  [PASS] All %d count-style tweaks normalize by their own declared default." % checked)
	return true


func test_count_tweaks_are_neutral_at_their_declared_default() -> bool:
	print("Running Test Suite: Count Tweaks Are Neutral At Their Default...")
	# The behavioural half of the same guard, run through ModuleData rather
	# than the table: writing a slider's default into `tweaks` must produce
	# byte-identical weight, cost and dps to leaving `tweaks` empty.
	#
	# This is the defect exactly as a player met it. `tweaks` stays empty until
	# a slider is touched, so the first nudge of Barrel Count was the first
	# time the divisor ran - and on a basic_cannon it turned 40 dps / 80 kg /
	# 30 metal into 6.7 / 13 / 5, which the Lab then saved.
	var broken := []
	for pair in _all_tweak_specs():
		var type_id: String = pair[0]
		var spec: Dictionary = pair[1]
		var tweak_name: String = spec.get("name", "")
		if not ModuleCatalog.is_count_tweak(tweak_name):
			continue
		var untouched := _module(type_id, {})
		var at_default := _module(type_id, {tweak_name: float(spec.get("default", 0.0))})
		if abs(untouched.get_weight() - at_default.get_weight()) > 0.001:
			broken.append("%s.%s weight %s -> %s" % [type_id, tweak_name, untouched.get_weight(), at_default.get_weight()])
		if untouched.get_cost() != at_default.get_cost():
			broken.append("%s.%s cost %s -> %s" % [type_id, tweak_name, untouched.get_cost(), at_default.get_cost()])
		if abs(untouched.get_dps() - at_default.get_dps()) > 0.001:
			broken.append("%s.%s dps %s -> %s" % [type_id, tweak_name, untouched.get_dps(), at_default.get_dps()])

	if not broken.is_empty():
		print("  [FAIL] Writing a slider's own default changed the module:")
		for b in broken:
			print("         ", b)
		return false

	# Two anchored cases, named because they are the two ends of the original
	# report: basic_cannon is the worst mis-scale (1 declared barrel against a
	# /6 literal) and rotary_cannon is the one module the literal fitted, which
	# therefore must come through this fix completely unmoved.
	var cannon := _module("basic_cannon", {"barrel_count": 1.0})
	if cannon.get_dps() != 40.0 or cannon.get_weight() != 80.0 or cannon.get_cost() != Vector2i(30, 0):
		print("  [FAIL] basic_cannon at its declared 1 barrel should read 40 dps / 80 kg / 30 metal, got ",
			cannon.get_dps(), " dps / ", cannon.get_weight(), " kg / ", cannon.get_cost())
		return false
	var gatling := _module("rotary_cannon", {"barrel_count": 6.0})
	if gatling.get_dps() != 105.0 or gatling.get_weight() != 110.0 or gatling.get_cost() != Vector2i(45, 5):
		print("  [FAIL] rotary_cannon at its declared 6 barrels should be unchanged at 105 dps / 110 kg / 45 metal + 5 crystal, got ",
			gatling.get_dps(), " dps / ", gatling.get_weight(), " kg / ", gatling.get_cost())
		return false

	print("  [PASS] Every count slider is a no-op at its own default, and the anchored weapons hold.")
	return true


func test_count_tweaks_scale_linearly_from_their_default() -> bool:
	print("Running Test Suite: Count Tweaks Scale Linearly From Their Default...")
	# Neutrality at the default is necessary but not sufficient - a normalizer
	# that returned the default and then squared it would pass the suite above.
	# Weight is the stat every count tweak feeds, so it is the one checked:
	# doubling the count must double the mass, within round_to_half()'s 0.25
	# quantum.
	var broken := []
	for pair in _all_tweak_specs():
		var type_id: String = pair[0]
		var spec: Dictionary = pair[1]
		var tweak_name: String = spec.get("name", "")
		if not ModuleCatalog.is_count_tweak(tweak_name):
			continue
		var declared := float(spec.get("default", 0.0))
		var doubled := _module(type_id, {tweak_name: declared * 2.0})
		var expected := _module(type_id, {}).get_weight() * 2.0
		if abs(doubled.get_weight() - expected) > 0.26:
			broken.append("%s.%s doubling %s -> %s expected weight %s, got %s" % [
				tweak_name, type_id, declared, declared * 2.0, expected, doubled.get_weight()])

	if not broken.is_empty():
		print("  [FAIL] Count tweaks are not linear in the count:")
		for b in broken:
			print("         ", b)
		return false
	print("  [PASS] Doubling any count doubles the module's mass.")
	return true


func test_armor_level_costs_more_mass_than_it_buys() -> bool:
	print("Running Test Suite: Armor Level Costs More Mass Than It Buys...")
	# protectedness used to be strictly dominant: +25% hp against +15% weight
	# per level meant every level made a module both tougher AND lighter for
	# what it carried, so there was never a reason to take less. The fix put
	# the weight coefficient above the HP coefficient (module_data.gd), and
	# this is the property that must never invert again.
	#
	# Both halves are asserted, because "worse per kilogram" is trivially
	# satisfiable by armor that does nothing at all:
	#   - HP must strictly RISE with the level, or the slider is not armor.
	#   - HP per kilogram must strictly FALL, or the slider is not a trade.
	# Checked across every module that declares protectedness rather than one
	# sample, because the two stats round independently (round_to_half) and a
	# light module is where a shallow curve would first flatten into a tie.
	var inversions := []
	var modules_checked := 0
	for type_id in LabDocumentScript.TWEAK_SPECS:
		for spec in LabDocumentScript.TWEAK_SPECS[type_id]:
			if spec.get("name", "") != "protectedness":
				continue
			modules_checked += 1
			var step := float(spec.get("step", 1.0))
			var p := float(spec.get("min", 0.0))
			var prev_hp := -1.0
			var prev_ratio := -1.0
			while p <= float(spec.get("max", 0.0)) + 0.0001:
				var data := _module(type_id, {"protectedness": p})
				var hp := data.get_hp()
				var weight := data.get_weight()
				if weight <= 0.0:
					inversions.append("%s has no weight to charge armor against" % type_id)
					break
				var ratio := hp / weight
				if prev_hp >= 0.0 and hp <= prev_hp:
					inversions.append("%s armor level %s did not increase HP (%s -> %s)" % [type_id, p, prev_hp, hp])
				if prev_ratio >= 0.0 and ratio >= prev_ratio:
					inversions.append("%s armor level %s is not worse per kg (%.4f -> %.4f)" % [type_id, p, prev_ratio, ratio])
				prev_hp = hp
				prev_ratio = ratio
				p += step

	if not inversions.is_empty():
		print("  [FAIL] Armor Level is still a free win somewhere:")
		for i in inversions:
			print("         ", i)
		return false
	if modules_checked == 0:
		print("  [FAIL] No module in TWEAK_SPECS declares protectedness - the tweak was renamed or dropped")
		return false
	print("  [PASS] Across %d modules, armor always adds HP and always costs mass efficiency." % modules_checked)
	return true
