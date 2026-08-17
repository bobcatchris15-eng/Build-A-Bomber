extends "res://tests/suite_base.gd"
# Stat-model suites. Registration order lives in run_tests.gd's SUITE_ORDER.
#
# These are pure-math suites in the test_design_verdict.gd mould: ModuleData is
# a Resource, so every case below runs with no Lab, no hull and a minimal
# synthetic hull node (no mesh, no scene) where one is needed. What they guard
# is the arithmetic between a slider and a stat, which is the layer where two
# long-lived defects hid because nothing ever asserted the shape of the curve,
# only that a number came out.
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
#
#   3. The "tuned for the unit" pass (Chris, 2026-08-16). Locomotion
#      auto-scales visually to the hull, and the drivetrain's load and
#      speed math is off `carried_weight` (everything except hull + loco).
#      These pin the two halves: locomotion_layout's node_scale_for /
#      scale_multiplier_for honour the hull-relative factors, and a
#      bare hull on a chassis is load_ratio 0 / not overloaded.

const LabDocumentScript = preload("res://scripts/lab_document.gd")
const DrivetrainForStatModel = preload("res://scripts/drivetrain.gd")
const LocomotionLayoutForStatModel = preload("res://scripts/locomotion_layout.gd")
const LiveryScript = preload("res://scripts/livery.gd")


# ModuleData built from a type's real catalog entry, so the numbers under test
# are the ones the game ships rather than a fixture that can agree with a bug.
func _module(type_id: String, tweaks: Dictionary) -> ModuleData:
	return _module_categorized(type_id, str(ModuleCatalog.get_module_data(type_id).get("category", "module")), tweaks)


# Same as _module but lets the caller pin the category - the catalog entry
# stores the module's own category (weapons, sensors, etc.) but a synthetic
# drivetrain test needs to mark something as "locomotion" so the drivetrain
# math picks it up.
func _module_categorized(type_id: String, category: String, tweaks: Dictionary) -> ModuleData:
	var catalog_data = ModuleCatalog.get_module_data(type_id)
	var data = ModuleData.new()
	data.type_id = type_id
	data.category = category
	data.base_hp = catalog_data.get("hp", 0.0)
	data.base_weight = catalog_data.get("weight", 0.0)
	data.cost_metal = catalog_data.get("metal", 0)
	data.cost_crystal = catalog_data.get("crystal", 0)
	data.base_dps = catalog_data.get("dps", 0.0)
	data.tweaks = tweaks
	return data


# Synthetic hull for the drivetrain tests. Drivetrain.analyze() only reads
# type_id, armor_*, hull_scale and faction meta and walks module_data children,
# so we can skip the mesh and the rest of the Lab rig.
func _make_hull(hull_type: String, hull_scale: Vector3, modules: Array) -> Node3D:
	var hull := Node3D.new()
	hull.name = "TestHull"
	hull.set_meta("type_id", hull_type)
	hull.set_meta("armor_material", "hardened_steel")
	hull.set_meta("armor_thickness", 1.0)
	hull.set_meta("hull_scale", hull_scale)
	hull.set_meta("faction", LiveryScript.NO_LIVERY)
	for m in modules:
		var child := Node3D.new()
		child.name = "Mod"
		child.scale = Vector3.ONE
		child.set_meta("module_data", m)
		hull.add_child(child)
	return hull


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


# ============================================================================
# 2026-08-16: locomotion auto-scales to the hull, and the drivetrain's load
# and speed math is off `carried_weight` (everything except hull + loco) -
# the "tuned for the unit" pass.
# ============================================================================

## node_scale_for() reflects the hull's volume for every type that opted in
## to HULL_RELATIVE - the default, the entire roster except `legs` and
## `ornithopter_wing`. The factor is the cube root of the hull's volume,
## applied UNIFORMLY to all three axes - so a 2x bigger hull in every
## dimension makes the wheel 2x bigger, and a 2x bigger hull in just one
## dimension makes the wheel ~1.26x bigger (proportional, not stretched
## to match the hull's aspect ratio). The previous (footprint, height,
## footprint) split made tall+narrow hulls grow egg-shaped wheels
## (Chris, 2026-08-16); this pins the uniform scale so a future
## "let's HULL_RELATIVE everything" simplification cannot reintroduce that.
func test_locomotion_node_scale_tracks_hull_factors() -> bool:
	print("Running Test Suite: Locomotion Node Scale Tracks Hull Factors (HULL_RELATIVE default)...")
	var relative_types := [
		"wheels", "tracked_treads", "heavy_quad_tracks", "helicopter_rotors",
		"hover_engine", "fixed_wing_engine", "buoyant_envelope",
		"half_track", "rocker_bogie", "pontoon_wheels", "air_cushion_skirt",
		"anti_grav_plate", "screw_drive",
	]
	var broken := []
	# 1. Reference hull (1,1) gives uniform 1.0 across all three axes. This
	# is the inert point: an unmodified hull must produce unmodified
	# locomotion, same as before this pass existed.
	for type_id in relative_types:
		var got: Vector3 = LocomotionLayoutForStatModel.node_scale_for(type_id, 1.0, 1.0)
		if not got.is_equal_approx(Vector3.ONE):
			broken.append("%s at reference hull expected (1,1,1), got %s" % [type_id, got])
	# 2. The proportionality invariant - the thing the user actually asked
	# for (Chris, 2026-08-16). The PREVIOUS (footprint, height, footprint)
	# code would have given a STRETCHED scale for a non-cube hull: a hull
	# 2x tall but 1x in plan would have produced (footprint=1, height=2,
	# footprint=1) - an egg. The new code produces (cbrt(2), cbrt(2),
	# cbrt(2)) - a uniform 1.26x scale that is the same wheel, just bigger.
	# Pin both halves: (a) the new scale is uniform (X==Y==Z), and
	# (b) the uniform value matches the cube root of the volume.
	var h2 := 2.0
	var fp1 := 1.0
	var expected_uniform: float = pow(h2 * fp1 * fp1, 1.0 / 3.0)  # cbrt(2) ~ 1.26
	for type_id in relative_types:
		var got: Vector3 = LocomotionLayoutForStatModel.node_scale_for(type_id, h2, fp1)
		if absf(got.x - got.y) > 0.001 or absf(got.y - got.z) > 0.001:
			broken.append("%s at (h=2, fp=1) must be UNIFORM (the egg fix), got %s" % [type_id, got])
		if absf(got.x - expected_uniform) > 0.001:
			broken.append("%s at (h=2, fp=1) expected uniform %.4f, got %s"
				% [type_id, expected_uniform, got])
	# 3. Symmetric case: 1x tall, 2x plan. Same invariant - the wheel
	# must be uniform, just a different size (different volume).
	var h1 := 1.0
	var fp2 := 2.0
	var expected_uniform_2: float = pow(h1 * fp2 * fp2, 1.0 / 3.0)  # cbrt(4) ~ 1.587
	for type_id in relative_types:
		var got: Vector3 = LocomotionLayoutForStatModel.node_scale_for(type_id, h1, fp2)
		if absf(got.x - got.y) > 0.001 or absf(got.y - got.z) > 0.001:
			broken.append("%s at (h=1, fp=2) must be UNIFORM (the egg fix), got %s" % [type_id, got])
		if absf(got.x - expected_uniform_2) > 0.001:
			broken.append("%s at (h=1, fp=2) expected uniform %.4f, got %s"
				% [type_id, expected_uniform_2, got])
	# 4. The cube hull - 2x in every axis - gives 2x uniformly. (This one
	# BOTH the old per-axis code AND the new uniform code handle the same
	# way; pinned as a sanity check that the uniform scale is not 0 on a
	# bigger hull.)
	for type_id in relative_types:
		var got: Vector3 = LocomotionLayoutForStatModel.node_scale_for(type_id, 2.0, 2.0)
		if not got.is_equal_approx(Vector3(2.0, 2.0, 2.0)):
			broken.append("%s at 2x cube hull expected (2,2,2), got %s" % [type_id, got])
	if not broken.is_empty():
		print("  [FAIL] HULL_RELATIVE types did not match the proportional cube-root scale:")
		for b in broken:
			print("         ", b)
		return false

	# `legs` is the one opt-out where this would be the giant-spider-legs
	# problem: a hull-relative scale on a leg scales the leg's length, which
	# raises the body, which scales the leg more, in a feedback loop. Pinned
	# to FIXED so a future "let's HULL_RELATIVE everything" simplification
	# cannot undo the override.
	var legs_scale: Vector3 = LocomotionLayoutForStatModel.node_scale_for("legs", 1.6, 1.3)
	if not legs_scale.is_equal_approx(Vector3.ONE):
		print("  [FAIL] legs must stay FIXED regardless of hull size, got ", legs_scale)
		return false

	# `ornithopter_wing` is the other opt-out: its 2x node_scale is the
	# "impractically long wings" archetype (Chris, 2026-08-02), and a
	# hull-relative scale would compound the 2x with the hull's own
	# footprint. Pinned to FIXED so a future "let's HULL_RELATIVE everything"
	# simplification cannot undo the override.
	var wing_scale: Vector3 = LocomotionLayoutForStatModel.node_scale_for("ornithopter_wing", 1.6, 1.3)
	if not wing_scale.is_equal_approx(Vector3(2.0, 1.0, 2.0)):
		print("  [FAIL] ornithopter_wing must keep its 2x node_scale, got ", wing_scale)
		return false

	print("  [PASS] Every HULL_RELATIVE type scales uniformly by cbrt(volume); legs + ornithopter stay FIXED.")
	return true


## scale_multiplier_for() is the partner to node_scale_for(): module_data's
## `scale_multiplier` field reads it, so a HULL_RELATIVE part's catalog
## weight scales with the hull it lands on. A 2x bigger wheel weighs more
## than a 1x wheel, whether the size was a player choice or a consequence
## of the hull - and the chassis/loco mass scaling with the hull is exactly
## what Drivetrain.analyze() subtracts to get `carried_weight`.
func test_locomotion_scale_multiplier_tracks_node_scale() -> bool:
	print("Running Test Suite: Locomotion Scale Multiplier Tracks Node Scale (HULL_RELATIVE weights reflect hull size)...")
	# HULL_RELATIVE: same factor the geometry got, in all three axes.
	# Using a 2x cube hull so the math is cbrt(2*2*2) = 2.
	var wheels_mult: Vector3 = LocomotionLayoutForStatModel.scale_multiplier_for("wheels", 2.0, 2.0)
	if not wheels_mult.is_equal_approx(Vector3(2.0, 2.0, 2.0)):
		print("  [FAIL] wheels scale_multiplier at 2x cube hull expected (2,2,2), got ", wheels_mult)
		return false
	# FIXED types get their declared `node_scale` - unchanged from before.
	var legs_mult: Vector3 = LocomotionLayoutForStatModel.scale_multiplier_for("legs", 1.6, 1.3)
	if not legs_mult.is_equal_approx(Vector3.ONE):
		print("  [FAIL] legs scale_multiplier expected Vector3.ONE, got ", legs_mult)
		return false
	var wing_mult: Vector3 = LocomotionLayoutForStatModel.scale_multiplier_for("ornithopter_wing", 1.6, 1.3)
	if not wing_mult.is_equal_approx(Vector3(2.0, 1.0, 2.0)):
		print("  [FAIL] ornithopter_wing scale_multiplier expected (2,1,2), got ", wing_mult)
		return false
	print("  [PASS] HULL_RELATIVE folds cube-root-of-volume into scale_multiplier (uniform, all axes); FIXED types stay as declared.")
	return true


## The whole point of the change. A bare hull on a chassis is the
## locomotor's natural state: hull + chassis, nothing to carry. Before
## the change, this registered as load_ratio = (hull+loco)/capacity, which
## lit the overweight warning on every hull the moment it was placed
## and before the player touched any weapons. After: load_ratio = 0.0,
## is_overloaded = false, and adding weapons is what moves the number.
func test_drivetrain_bare_hull_is_not_overloaded() -> bool:
	print("Running Test Suite: Drivetrain - A Bare Hull On A Chassis Is Not Overloaded...")
	var wheels := _module_categorized("wheels", "locomotion", {})
	var hull := _make_hull("brenntal_medium_a", Vector3.ONE, [wheels])
	root.add_child(hull)
	var dt: Dictionary = DrivetrainForStatModel.analyze(hull)
	hull.queue_free()
	if not bool(dt.get("has_locomotion", false)):
		print("  [FAIL] wheels on a bare hull should register as a unit with locomotion")
		return false
	if bool(dt.get("is_overloaded", true)):
		print("  [FAIL] bare hull + wheels is not overloaded; got load_ratio %s / capacity %s"
			% [dt.get("load_ratio", "?"), dt.get("capacity", "?")])
		return false
	if not is_zero_approx(float(dt.get("load_ratio", -1.0))):
		print("  [FAIL] bare hull + wheels should be load_ratio 0.0, got %s" % dt.get("load_ratio", "?"))
		return false
	# Chassis/loco split: weight = hull_weight + loco_weight + carried_weight.
	# The hull has mass, so weight must be strictly greater than loco + carried.
	var w: float = float(dt.get("weight", 0.0))
	var lw: float = float(dt.get("loco_weight", 0.0))
	var cw: float = float(dt.get("carried_weight", 0.0))
	var hull_only: float = w - lw - cw
	if hull_only <= 0.0:
		print("  [FAIL] hull should have positive mass; weight=%s loco=%s carried=%s gives hull=%s"
			% [w, lw, cw, hull_only])
		return false
	if not is_zero_approx(cw):
		print("  [FAIL] carried_weight should be 0 on a bare hull, got %s" % cw)
		return false
	if lw <= 0.0:
		print("  [FAIL] loco_weight should be the wheels' mass, got %s" % lw)
		return false
	print("  [PASS] Bare hull + chassis: weight = hull (%.0f) + loco (%.0f), load_ratio = 0, not overloaded."
		% [hull_only, lw])
	return true


## Adding weapons moves the load. A chassis rated at 360 kg (wheels) with
## 180 kg of weapons is at 50% load - half the rating, no overload, and
## the hull's own mass has NOT entered the ratio. Before the change the
## hull's mass would have pushed this to 100%+ and triggered an overload.
func test_drivetrain_weapons_add_to_load_ratio() -> bool:
	print("Running Test Suite: Drivetrain - Weapons Move Load Ratio, Hull Mass Does Not...")
	var wheels := _module_categorized("wheels", "locomotion", {})
	var weapon := _module("basic_cannon", {})
	var hull := _make_hull("brenntal_medium_a", Vector3.ONE, [wheels, weapon])
	root.add_child(hull)
	var dt: Dictionary = DrivetrainForStatModel.analyze(hull)
	hull.queue_free()
	var cw: float = float(dt.get("carried_weight", 0.0))
	var cap: float = float(dt.get("capacity", 0.0))
	var lr: float = float(dt.get("load_ratio", 0.0))
	if cw <= 0.0:
		print("  [FAIL] carried_weight should be the cannon's mass, got %s" % cw)
		return false
	if cap <= 0.0:
		print("  [FAIL] wheels should provide a non-zero capacity, got %s" % cap)
		return false
	if not is_equal_approx(lr, cw / cap):
		print("  [FAIL] load_ratio %s should equal carried_weight/capacity %s/%s" % [lr, cw, cap])
		return false
	if bool(dt.get("is_overloaded", false)):
		print("  [FAIL] one cannon on wheels should not overload; got load_ratio %s" % lr)
		return false
	print("  [PASS] One cannon on wheels: load_ratio = carried/capacity = %s, not overloaded." % lr)
	return true


## Speed is the second half of the "tuned for the unit" reading: thrust /
## carried_weight, not thrust / total_weight. A heavy hull on the same
## chassis + same weapons as a light hull must hit the same power_top_speed,
## because the locomotor is calibrated for the unit regardless of the
## chassis size. The chassis_top_speed cap is per-type and still binds
## for a typical design.
func test_drivetrain_speed_uses_carried_weight_not_total() -> bool:
	print("Running Test Suite: Drivetrain - Speed Is Off Carried Weight, Hull Size Doesn't Move It...")
	var wheels := _module_categorized("wheels", "locomotion", {})
	var weapon := _module("basic_cannon", {})
	# Same chassis, same weapons, different hull sizes. The hull's own
	# scale should not move the locomotor's powerplant answer.
	var light := _make_hull("brenntal_medium_a", Vector3.ONE, [wheels, weapon])
	var heavy := _make_hull("brenntal_medium_a", Vector3(1.5, 1.5, 1.5), [wheels, weapon])
	root.add_child(light)
	root.add_child(heavy)
	var light_dt: Dictionary = DrivetrainForStatModel.analyze(light)
	var heavy_dt: Dictionary = DrivetrainForStatModel.analyze(heavy)
	light.queue_free()
	heavy.queue_free()
	if not is_equal_approx(float(light_dt.get("power_top_speed", -1.0)),
			float(heavy_dt.get("power_top_speed", -2.0))):
		print("  [FAIL] same chassis + same weapons must give same power_top_speed; got %s vs %s"
			% [light_dt.get("power_top_speed", "?"), heavy_dt.get("power_top_speed", "?")])
		return false
	# And the total mass DID differ - which is what the carried_weight split
	# makes safe to ignore for the drivetrain.
	if is_equal_approx(float(light_dt.get("weight", 0.0)),
			float(heavy_dt.get("weight", 0.0))):
		print("  [FAIL] the two test rigs were supposed to have different total weight, both read %s"
			% light_dt.get("weight", "?"))
		return false
	print("  [PASS] power_top_speed identical on light + heavy hull with same chassis and same weapons.")
	return true


## Sharp end of the "tuned for the unit" math: an over-stacked weapon load
## on a chassis still overloads. The carried_weight split does not turn
## capacity into a free pass; it just removes the hull+loco from the
## numerator. A weapons load past capacity is what overloads, exactly as
## before, and the overload multiplier still bites.
func test_drivetrain_overload_still_fires_from_carried_weight() -> bool:
	print("Running Test Suite: Drivetrain - Overload Still Fires, Just From Carried Weight...")
	var wheels := _module_categorized("wheels", "locomotion", {})
	# wheels is rated 360 kg (ModuleCatalog: "base_weight_capacity": 360.0).
	# Stack two artillery pieces (250 kg each) - 500 kg on a 360 kg chassis
	# is well into overload territory. Picked artillery over basic_cannon
	# because the lighter gun only adds up to 160 kg for two, which is below
	# capacity and would not exercise the overload branch at all.
	var weapon_a := _module("artillery", {})
	var weapon_b := _module("artillery", {})
	var hull := _make_hull("brenntal_medium_a", Vector3.ONE, [wheels, weapon_a, weapon_b])
	root.add_child(hull)
	var dt: Dictionary = DrivetrainForStatModel.analyze(hull)
	hull.queue_free()
	var cw: float = float(dt.get("carried_weight", 0.0))
	var cap: float = float(dt.get("capacity", 0.0))
	if cw <= cap:
		print("  [FAIL] expected two artillery (carried=%s) to exceed wheels capacity (%s)" % [cw, cap])
		return false
	if not bool(dt.get("is_overloaded", false)):
		print("  [FAIL] carried_weight %s past capacity %s should overload, got load_ratio %s"
			% [cw, cap, dt.get("load_ratio", "?")])
		return false
	var lost: float = float(dt.get("speed_lost_to_overload", 0.0))
	if lost <= 0.0:
		print("  [FAIL] overloaded unit must lose speed; got speed_lost_to_overload %s" % lost)
		return false
	print("  [PASS] carried_weight %s on capacity %s overloaded: %s m/s lost."
		% [cw, cap, lost])
	return true
