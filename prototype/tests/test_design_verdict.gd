extends "res://tests/suite_base.gd"
# DesignVerdict suites. Registration order lives in run_tests.gd's SUITE_ORDER.
#
# This is the first piece of the Design Lab rework and it is deliberately the
# most testable one: DesignVerdict takes a Dictionary and returns an Array, so
# every case below runs without a Lab, a hull, or a rendered frame.

const Verdict = preload("res://scripts/design_verdict.gd")


# A minimal analyze()-shaped result. Built by hand rather than by running
# DesignStats, because the point is to test the JUDGEMENT, not the measurement -
# and a hand-built fixture can express states (unpowered, wildly overloaded) that
# would take a contrived hull to produce for real.
func _stats(overrides: Dictionary = {}) -> Dictionary:
	var base := {
		"has_weapons": true,
		"is_harvester": false,
		"drivetrain": {
			"has_locomotion": true,
			"weight": 800.0,
			"capacity": 1000.0,
			"load_ratio": 0.8,
			"is_overloaded": false,
			"is_underloaded": false,
			"capacity_limited": false,
			"speed_lost_to_overload": 0.0,
			"speed_gained_from_underload": 0.0,
			"chassis_top_speed": 20.0,
		},
		"weapon_range": {"spotter_required": []},
		"power": {"generation": 100.0, "draw": 40.0},
	}
	for k in overrides:
		base[k] = overrides[k]
	return base


func _has(verdicts: Array, headline: String) -> bool:
	for v in verdicts:
		if v["headline"] == headline:
			return true
	return false


func test_verdict_clean_design_reports_balanced() -> bool:
	print("Running Test Suite: DesignVerdict - A Clean Design Reports Balanced...")
	var v := Verdict.evaluate(_stats())
	if v.size() != 1 or v[0]["headline"] != "BALANCED":
		print("  [FAIL] Expected exactly one BALANCED verdict, got ", v)
		return false
	# BALANCED must never appear ALONGSIDE a complaint - that would be the
	# interface contradicting itself in two adjacent lines.
	var bad := Verdict.evaluate(_stats({"has_weapons": false}))
	if _has(bad, "BALANCED"):
		print("  [FAIL] BALANCED appeared next to a real warning: ", bad)
		return false
	print("  [PASS] Clean designs report BALANCED, and only when nothing else fired.")
	return true


func test_verdict_ranks_worst_first() -> bool:
	print("Running Test Suite: DesignVerdict - Worst Verdict Leads...")
	var stats := _stats({
		"has_weapons": false,
		"power": {"generation": 0.0, "draw": 30.0},
	})
	var v := Verdict.evaluate(stats)
	if v.is_empty():
		print("  [FAIL] Expected verdicts, got none")
		return false
	# UNPOWERED is BLOCKING, UNARMED is only a WARNING, so the blocking one has
	# to be what the rail shows first.
	if v[0]["headline"] != "UNPOWERED":
		print("  [FAIL] Expected UNPOWERED to lead, got ", v[0]["headline"], " from ", v)
		return false
	if Verdict.headline(stats)["headline"] != "UNPOWERED":
		print("  [FAIL] headline() disagrees with evaluate()[0]")
		return false
	# And the severities must be non-decreasing across the list.
	for i in range(1, v.size()):
		if v[i]["severity"] < v[i - 1]["severity"]:
			print("  [FAIL] Verdicts are not sorted worst-first: ", v)
			return false
	print("  [PASS] Blocking verdicts lead and the list is ordered by severity.")
	return true


func test_verdict_overload_uses_the_drivetrains_own_flag() -> bool:
	print("Running Test Suite: DesignVerdict - Overload Follows Drivetrain, Not A Local Rule...")
	# Marginally over: real per drivetrain.gd, but not worth shouting about, so no
	# BLOCKING verdict. This is the one place a threshold is applied on top of the
	# model, and it exists so a 1% overload does not read like a broken design.
	var marginal := _stats()
	marginal["drivetrain"]["is_overloaded"] = true
	marginal["drivetrain"]["load_ratio"] = 1.01
	if _has(Verdict.evaluate(marginal), "OVER CAPACITY"):
		print("  [FAIL] A 1% overload should not raise OVER CAPACITY")
		return false

	var bad := _stats()
	bad["drivetrain"]["is_overloaded"] = true
	bad["drivetrain"]["load_ratio"] = 1.6
	bad["drivetrain"]["weight"] = 1600.0
	bad["drivetrain"]["speed_lost_to_overload"] = 7.5
	var v := Verdict.evaluate(bad)
	if not _has(v, "OVER CAPACITY"):
		print("  [FAIL] A 60% overload should raise OVER CAPACITY, got ", v)
		return false
	# The detail has to quote the real figures, not restate the ratio.
	if not ("1,600" in v[0]["detail"] and "7.5" in v[0]["detail"]):
		print("  [FAIL] OVER CAPACITY detail should cite weight and speed lost, got '", v[0]["detail"], "'")
		return false
	print("  [PASS] Overload verdict follows drivetrain's flag and quotes its figures.")
	return true


# THE MISCLASSIFICATION THIS GUARDS. A harvester and a pillbox are both unarmed
# and both immobile-or-nearly, and calling either one "UNARMED - cannot damage
# anything" would be the Lab nagging about a design working exactly as intended.
func test_verdict_does_not_scold_legitimate_unarmed_designs() -> bool:
	print("Running Test Suite: DesignVerdict - Harvesters And Emplacements Are Not Mistakes...")
	var harvester := _stats({"has_weapons": false, "is_harvester": true})
	var hv := Verdict.evaluate(harvester)
	if _has(hv, "UNARMED"):
		print("  [FAIL] A harvester should not be scolded as UNARMED, got ", hv)
		return false
	if not _has(hv, "HARVESTER"):
		print("  [FAIL] A harvester should be identified as one, got ", hv)
		return false

	var pillbox := _stats()
	pillbox["drivetrain"]["has_locomotion"] = false
	var pv := Verdict.evaluate(pillbox)
	if not _has(pv, "STATIC EMPLACEMENT"):
		print("  [FAIL] A design with no drive should read as a static emplacement, got ", pv)
		return false
	for entry in pv:
		if entry["severity"] == Verdict.Severity.BLOCKING:
			print("  [FAIL] No drive is a design choice, not a blocking fault: ", entry)
			return false
	print("  [PASS] Harvesters and emplacements are described, not scolded.")
	return true


func test_verdict_flags_weapons_that_outrange_vision() -> bool:
	print("Running Test Suite: DesignVerdict - Weapons Outranging Their Own Sight...")
	var stats := _stats({
		"weapon_range": {"spotter_required": [{"name": "artillery", "reach": 90.0}]},
	})
	var v := Verdict.evaluate(stats)
	if not _has(v, "OUTRANGES ITS OWN VISION"):
		print("  [FAIL] A spotter-required weapon should be flagged, got ", v)
		return false
	print("  [PASS] Weapons that cannot see their own range are called out.")
	return true


func test_verdict_survives_a_junk_result() -> bool:
	print("Running Test Suite: DesignVerdict - Degrades On An Empty Or Partial Result...")
	if not Verdict.evaluate({}).is_empty():
		print("  [FAIL] An empty stats dictionary should produce no verdicts")
		return false
	# A partial result must not crash. clear_hull() calls update_stats(null), and
	# an earlier version of DesignStats returned a keyless drivetrain that took
	# the whole Lab down - this is that failure mode, guarded from the other side.
	var partial := Verdict.evaluate({"has_weapons": true})
	if partial.is_empty():
		print("  [FAIL] A partial result should still yield something, got none")
		return false
	print("  [PASS] Empty and partial analyze() results are handled without crashing.")
	return true
