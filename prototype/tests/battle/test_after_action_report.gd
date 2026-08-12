extends "res://tests/suite_base.gd"
# The after-action report, built for real.
#
# WHY THIS EXISTS. after_action_report.gd assigned Label.alignment - a property
# Label does not have - which raised at runtime and aborted _build_ui() on that
# line, EVERY TIME. The report had never rendered past its header for as long as
# it had been wired: no per-design table, no MVP, no buttons, no way out but the
# escape key. Nothing caught it because nothing ever built the thing.
#
# So these suites do the one thing that would have: construct the report from a
# representative stats dictionary and assert the finished tree. A GDScript
# runtime error aborts the function silently and leaves a half-built UI behind,
# so "the controls that should exist do exist" is the only assertion that
# actually detects it.

const ReportScript = preload("res://scripts/after_action_report.gd")

# Deliberately exercises every branch the table has: a design that fought and
# lost units, one that was built and did nothing, and one that was never built
# at all (which used to win MVP).
const STATS := {
	"Bulwark MBT": {
		"built": 6, "lost": 4, "kills": 9, "damage_dealt": 4200.0,
		"damage_taken_kinetic": 900.0, "damage_taken_thermal": 120.0,
		"damage_taken_explosive": 60.0, "damage_taken_energy": 1500.0,
		"metal_spent": 1800, "hull_type": "block_heavy_meridian_a",
	},
	"Scrapper Ore Trucker": {
		"built": 3, "lost": 1, "kills": 0, "damage_dealt": 0.0,
		"damage_taken_kinetic": 200.0, "damage_taken_thermal": 0.0,
		"damage_taken_explosive": 0.0, "damage_taken_energy": 0.0,
		"metal_spent": 450, "hull_type": "block_main_meridian_a",
	},
	"Never Fielded": {
		"built": 0, "lost": 0, "kills": 0, "damage_dealt": 0.0,
		"damage_taken_kinetic": 0.0, "damage_taken_thermal": 0.0,
		"damage_taken_explosive": 0.0, "damage_taken_energy": 0.0,
		"metal_spent": 0, "hull_type": "block_scout_meridian_a",
	},
}


func _build(is_op: bool, stats: Dictionary = STATS):
	var report = ReportScript.new()
	root.add_child(report)
	report.setup(true, 421.0, stats, is_op)
	return report


func _all(node: Node, out: Array) -> Array:
	out.append(node)
	for child in node.get_children():
		_all(child, out)
	return out


func _labels(report) -> Array:
	var texts: Array = []
	for node in _all(report, []):
		if node is Label:
			texts.append(str(node.text))
	return texts


func _buttons(report) -> Array:
	var out: Array = []
	for node in _all(report, []):
		if node is Button and not (node is OptionButton):
			out.append(node)
	return out


# The regression test proper: the report must build ALL of itself. Every one of
# these was missing when _build_ui() aborted at line 66.
func test_after_action_report_builds_its_whole_self() -> bool:
	print("Running Test Suite: After-action report - the whole report renders...")
	var report = _build(false)
	await tree.process_frame

	var ok := true
	var texts: Array = _labels(report)
	var joined: String = "\n".join(PackedStringArray(texts))

	for required in ["BLUEPRINT PERFORMANCE BREAKDOWN", "BEST PERFORMING DESIGN", "ASSESSMENT"]:
		if not joined.contains(required):
			print("  [FAIL] The report is missing its '", required, "' section")
			ok = false

	# One row per design, plus the header row. A grid that never got populated
	# still has its headers, so the count is what distinguishes them.
	var grid: GridContainer = null
	for node in _all(report, []):
		if node is GridContainer:
			grid = node
			break
	if grid == null:
		print("  [FAIL] The per-design table was never built")
		ok = false
	else:
		var expected: int = grid.columns * (STATS.size() + 1)
		if grid.get_child_count() != expected:
			print("  [FAIL] Table has %d cells, expected %d (%d columns x %d rows)"
				% [grid.get_child_count(), expected, grid.columns, STATS.size() + 1])
			ok = false

	# The way out. A report with no buttons is a trap - it covers the screen and
	# stops mouse input, which is exactly what shipped.
	var button_texts: Array = []
	for b in _buttons(report):
		button_texts.append(str(b.text))
	if button_texts.is_empty():
		print("  [FAIL] The report has no buttons at all - there is no way out of it")
		ok = false
	elif not "\n".join(PackedStringArray(button_texts)).contains("Main Menu"):
		print("  [FAIL] No Main Menu button: ", button_texts)
		ok = false

	report.queue_free()
	await tree.process_frame
	if ok:
		print("  [PASS] Table, MVP, assessment and action bar all present (%d labels, %d buttons)."
			% [texts.size(), button_texts.size()])
	return ok


# Energy is one of the four damage classes and MatchStats has always recorded it.
# The report summed the other three, so a match against energy weapons understated
# what landed and named the wrong threat in its assessment.
func test_after_action_report_counts_energy_damage() -> bool:
	print("Running Test Suite: After-action report - energy damage is not dropped...")
	var report = _build(false)
	await tree.process_frame

	var ok := true
	var joined: String = "\n".join(PackedStringArray(_labels(report)))

	# Bulwark took 900+120+60+1500 = 2580. Dropping energy would print 1080.
	if not joined.contains("2580"):
		print("  [FAIL] Damage taken excludes energy - expected a 2580 total, got none")
		ok = false
	# Energy is 1500/2580 = 58%, the dominant class, so the assessment must name it.
	if not joined.to_lower().contains("energy weapons"):
		print("  [FAIL] Energy was the dominant damage class and the assessment did not say so")
		ok = false

	report.queue_free()
	await tree.process_frame
	if ok:
		print("  [PASS] Energy counts toward damage taken and drives the assessment.")
	return ok


# MVP scored dmg_dealt/metal against a -1 sentinel, so a design with nothing
# built scored 0 and beat it. In a match where the player's army never landed a
# shot, the "best performing design" was one they never fielded.
func test_after_action_report_mvp_must_have_been_fielded() -> bool:
	print("Running Test Suite: After-action report - the MVP was actually built...")
	var report = _build(false)
	await tree.process_frame

	var ok := true
	var joined: String = "\n".join(PackedStringArray(_labels(report)))
	if joined.contains("Never Fielded"):
		# It legitimately appears as a table row; what must not happen is it being
		# named MVP. The MVP label sits directly under the heading.
		var labels: Array = _labels(report)
		var idx: int = labels.find("BEST PERFORMING DESIGN")
		if idx >= 0 and idx + 1 < labels.size() and labels[idx + 1] == "Never Fielded":
			print("  [FAIL] A design that was never built was named best performer")
			ok = false

	# And the honest empty case: nothing built at all reports N/A, not a name.
	report.queue_free()
	var empty = _build(false, {"Nothing": {"built": 0, "damage_dealt": 0.0, "metal_spent": 0}})
	await tree.process_frame
	var empty_labels: Array = _labels(empty)
	var empty_idx: int = empty_labels.find("BEST PERFORMING DESIGN")
	if empty_idx >= 0 and empty_idx + 1 < empty_labels.size():
		if empty_labels[empty_idx + 1] != "N/A":
			print("  [FAIL] With nothing built, the MVP should be N/A, got '",
				empty_labels[empty_idx + 1], "'")
			ok = false

	empty.queue_free()
	await tree.process_frame
	if ok:
		print("  [PASS] MVP requires a design to have been built, and is N/A when none was.")
	return ok


# The campaign seam, from the report's side: is_operation must produce a control
# the player can actually press. A true flag feeding a branch that never renders
# is the same as no flag at all - which is how this failed the first time.
func test_after_action_report_offers_the_next_engagement() -> bool:
	print("Running Test Suite: After-action report - the campaign branch renders...")
	var ok := true

	var skirmish = _build(false)
	await tree.process_frame
	for b in _buttons(skirmish):
		if str(b.text).begins_with("Next Engagement"):
			print("  [FAIL] A skirmish debrief offered a next engagement")
			ok = false
	skirmish.queue_free()

	var campaign = _build(true)
	await tree.process_frame
	var found := false
	for b in _buttons(campaign):
		if str(b.text).begins_with("Next Engagement"):
			found = true
	if not found:
		var names: Array = []
		for b in _buttons(campaign):
			names.append(str(b.text))
		print("  [FAIL] A campaign debrief has no next-engagement button: ", names)
		ok = false
	campaign.queue_free()

	await tree.process_frame
	if ok:
		print("  [PASS] The next-engagement button appears only in a campaign debrief.")
	return ok
