extends "res://tests/suite_base.gd"
# THE ECONOMY BALANCE TARGET, pinned.
#
# Chris's spec, 2026-08-07:
#
#   A normal economy - ONE refinery and FOUR harvesters - should GROW its
#   resources on hand with ONE manufactory running continuously, and should
#   roughly 80% keep up with TWO running continuously.
#
# These suites test the ARITHMETIC of that, not a live match. The live
# measurement is tools/probe_economy_balance.gd, which drives a real map with
# real travel and takes four minutes; this is the part that can be asserted in
# milliseconds and is what actually catches a constant being edited without the
# consequence being noticed.

const DesignCostingScript = preload("res://scripts/battle/economy/design_costing.gd")
const HarvesterFSMScript = preload("res://scripts/battle/economy/harvester_fsm.gd")

# One production line's spend rate, in cost-units (metal + 2 x crystal) per
# second. Derived below rather than trusted.
const DRAW_PER_LINE := 20.0
# Measured round-trip overhead on open_plains: driving plus the unload dwell,
# everything in a trip that is not extraction. Used to predict income from the
# constants without running a match.
const TRIP_OVERHEAD_SECONDS := 4.1
const TARGET_HARVESTERS := 4

# Credits per raw unit of cargo, averaged over what harvesters actually choose to
# gather. NOT 1.0: the four resources are worth 1.0 to 4.0 credits each and
# value-weighted node selection deliberately biases trucks toward the expensive
# ones, so a hopper of cargo is worth more than its size. Measured at 1.375 by
# tools/probe_economy_balance.gd on open_plains; it is a map property, since it
# depends on what is within reach of a base.
const MEAN_CREDITS_PER_CARGO := 1.375


# The load-bearing fact the whole balance rests on: build_time_for_cost() is
# proportional to cost, and the drip-feed spends the whole cost across exactly
# that time, so EVERY design draws the same 20 cost-units/s while building.
# Cheap scout or heavy tank, the spend rate is identical.
#
# If that ever stops being true, "one manufactory draws 20/s" stops being a
# meaningful sentence and this whole target needs restating - which is why it is
# asserted rather than assumed.
func test_every_design_draws_the_same_rate_while_building() -> bool:
	print("Running Test Suite: Economy - a production line draws a flat rate...")
	var ok := true
	var checked := 0
	for name in ["rattler_scout", "bulwark_mbt", "warden_aa", "ore_trucker"]:
		var path := "res://data/loadout/%s.json" % name
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var cost: int = DesignCostingScript.blueprint_cost(data)
		var time: float = DesignCostingScript.build_time_for_cost(cost)
		var units: float = float(cost)
		# The clamps (3 s floor, 40 s ceiling) legitimately break proportionality
		# for very cheap or very expensive designs. A bundled design hitting one
		# is worth knowing about, but is not a failure of this rule.
		if is_equal_approx(time, 3.0) or is_equal_approx(time, 40.0):
			print("    (%s is clamped at %.0fs - outside the proportional band)"
				% [data.get("name", name), time])
			continue
		checked += 1
		var draw: float = units / time
		if not is_equal_approx(snappedf(draw, 0.1), DRAW_PER_LINE):
			print("  [FAIL] '%s' draws %.2f cost-units/s, expected %.0f"
				% [data.get("name", name), draw, DRAW_PER_LINE])
			ok = false
	if checked < 3:
		print("  [FAIL] Only %d designs were in the proportional band - not enough to check" % checked)
		ok = false
	if ok:
		print("  [PASS] %d designs all draw exactly %.0f cost-units/s while building."
			% [checked, DRAW_PER_LINE])
	return ok


# The income side, predicted from the constants. A trip delivers `capacity` and
# takes (extraction cycles x HARVEST_TIME) + overhead, so income per harvester is
# capacity / trip time - and four of them have to clear 1.6 lines.
#
# THE TRAP THIS EXISTS TO CATCH: raising capacity ALONE does not raise income. It
# lengthens the trip by exactly as much as it adds to the load, because
# extraction is the same rate. The chunk has to move with the hopper, and this
# fails if someone edits one without the other.
func test_four_harvesters_meet_the_stated_target() -> bool:
	print("Running Test Suite: Economy - 4 harvesters vs 1 and 2 production lines...")
	var fsm = HarvesterFSMScript.new()
	fsm.configure(1, "medium_hull")

	var capacity: float = float(fsm.capacity)
	var cycles: float = ceil(capacity / float(fsm._chunk_size()))
	var trip: float = cycles * HarvesterFSMScript.HARVEST_TIME + TRIP_OVERHEAD_SECONDS
	# Converted to credits, because that is what a production queue spends. A
	# hopper of oil and a hopper of lumber are the same cargo and four times apart
	# in value, so asserting against raw cargo would be asserting against the one
	# quantity the economy does not care about.
	var income: float = (capacity / trip) * float(TARGET_HARVESTERS) * MEAN_CREDITS_PER_CARGO

	var ok := true
	print("    capacity %d, chunk %d, %d cycles, trip %.1fs -> %.1f credits/s from %d harvesters"
		% [fsm.capacity, fsm._chunk_size(), int(cycles), trip, income, TARGET_HARVESTERS])

	# One line: must GROW, and not marginally - a rounding-error surplus is not a
	# growing economy.
	if income <= DRAW_PER_LINE:
		print("  [FAIL] Against one production line (%.0f/s) the economy shrinks: %.1f/s"
			% [DRAW_PER_LINE, income])
		ok = false

	# Two lines: ~80%. Banded, because this is a design target rather than a
	# constant - but a band tight enough that drifting out of it is a real change.
	var keep_up: float = income / (DRAW_PER_LINE * 2.0)
	if keep_up < 0.7 or keep_up > 0.95:
		print("  [FAIL] Against two production lines the economy keeps up %.0f%%, target 80%% (0.70-0.95)"
			% (keep_up * 100.0))
		ok = false

	if ok:
		print("  [PASS] One line grows (+%.1f/s), two lines keep up %.0f%%."
			% [income - DRAW_PER_LINE, keep_up * 100.0])
	return ok


# The hopper is a property of the DESIGN. It used to be a flat 50 for everything,
# which in a game whose premise is that you design the units meant a purpose-built
# ore hauler carried exactly as much as a scout with a harvester bolted on.
func test_harvester_capacity_comes_from_the_design() -> bool:
	print("Running Test Suite: Economy - hopper and extraction scale with the design...")
	var ok := true

	var one = HarvesterFSMScript.new()
	one.configure(1, "medium_hull")
	var two = HarvesterFSMScript.new()
	two.configure(2, "medium_hull")
	var heavy = HarvesterFSMScript.new()
	heavy.configure(1, "heavy_hull")
	var light = HarvesterFSMScript.new()
	light.configure(1, "light_hull")

	if two.capacity <= one.capacity:
		print("  [FAIL] A second harvester module does not raise the hopper: %d vs %d"
			% [two.capacity, one.capacity])
		ok = false
	if heavy.capacity <= one.capacity or light.capacity >= one.capacity:
		print("  [FAIL] Hull tier does not scale the hopper: light %d, medium %d, heavy %d"
			% [light.capacity, one.capacity, heavy.capacity])
		ok = false

	# THE IMPORTANT ONE. Extraction has to scale with the hopper, or a bigger
	# harvester just spends longer standing at the patch and delivers no more per
	# second - the change would look like a buff and measure as nothing.
	for pair in [[two, one], [heavy, one]]:
		var big = pair[0]
		var small = pair[1]
		var big_cycles: float = ceil(float(big.capacity) / float(big._chunk_size()))
		var small_cycles: float = ceil(float(small.capacity) / float(small._chunk_size()))
		if not is_equal_approx(big_cycles, small_cycles):
			print("  [FAIL] Fill takes %d cycles on the larger design vs %d on the baseline - extraction did not scale with the hopper"
				% [int(big_cycles), int(small_cycles)])
			ok = false

	if ok:
		print("  [PASS] light %d / medium %d / heavy %d / twin-module %d, all filling in the same number of cycles."
			% [light.capacity, one.capacity, heavy.capacity, two.capacity])
	return ok
