extends "res://tests/suite_base.gd"
# The Operations setup screen and the campaign state it produces.
#
# Headless cannot press a button or drive a drag, so nothing here drives the UI
# through input. What it does instead is assert the screen's OUTPUT contract -
# build_itinerary() - and the manager's pure functions, which is where every one
# of these could actually go wrong.

const OperationsManagerScript = preload("res://scripts/operations_manager.gd")
const OperationsSetupScript = preload("res://scripts/operations_setup.gd")
const MapCatalogScript = preload("res://scripts/map_catalog.gd")


func _screen():
	var screen = OperationsSetupScript.new()
	root.add_child(screen)
	return screen


# 3 is the floor and 12 the ceiling, and the SpinBox must actually carry them -
# a range that disagrees with the manager's clamp means the screen can build an
# itinerary the campaign then silently truncates.
func test_operations_engagement_count_spans_three_to_twelve() -> bool:
	print("Running Test Suite: Operations - the engagement count is 3 to 12...")
	var screen = _screen()
	await tree.process_frame

	var ok := true
	if int(screen.engagements_spin.min_value) != 3 or int(screen.engagements_spin.max_value) != 12:
		print("  [FAIL] Engagement range is %d..%d, expected 3..12"
			% [int(screen.engagements_spin.min_value), int(screen.engagements_spin.max_value)])
		ok = false

	for count in [3, 7, 12]:
		screen.engagements_spin.value = count
		await tree.process_frame
		var itinerary: Array = screen.build_itinerary()
		if itinerary.size() != count:
			print("  [FAIL] Asked for %d engagements, got %d" % [count, itinerary.size()])
			ok = false
			continue
		# One map picker per engagement, or the itinerary is not something the
		# player chose - it is something the screen made up.
		if screen._map_pickers.size() != count:
			print("  [FAIL] %d engagements but %d map pickers"
				% [count, screen._map_pickers.size()])
			ok = false

	screen.queue_free()
	await tree.process_frame
	if ok:
		print("  [PASS] 3-12 engagements, each with its own map picker.")
	return ok


# Every engagement must name a REAL map. "Random" resolving to "" would hand
# MatchConfig an empty map id, which falls back to the default map - so a random
# itinerary would silently be the same map every round.
func test_operations_itinerary_resolves_every_map() -> bool:
	print("Running Test Suite: Operations - every engagement names a real map...")
	var screen = _screen()
	await tree.process_frame
	screen.engagements_spin.value = 8
	await tree.process_frame

	# Force every slot to Random, the case that resolves late.
	for picker in screen._map_pickers:
		picker.selected = 0
	var itinerary: Array = screen.build_itinerary()

	var known: Array = MapCatalogScript.get_map_ids()
	var ok := true
	var seen := {}
	for stage in itinerary:
		var map_id: String = str(stage.get("map_id", ""))
		if not known.has(map_id):
			print("  [FAIL] Engagement resolved to a map that does not exist: '", map_id, "'")
			ok = false
		seen[map_id] = true

	# A hand-picked slot must survive verbatim rather than being re-rolled.
	if screen._map_pickers.size() >= 2 and known.size() >= 1:
		screen._map_pickers[1].selected = 1 # index 0 is Random
		var picked: Array = screen.build_itinerary()
		if str(picked[1].get("map_id", "")) != str(known[0]):
			print("  [FAIL] A hand-picked map was not honoured: wanted '", known[0],
				"', got '", picked[1].get("map_id", ""), "'")
			ok = false

	screen.queue_free()
	await tree.process_frame
	if ok:
		print("  [PASS] 8 random engagements all resolved to real maps (%d distinct), and a hand-picked one is honoured."
			% seen.size())
	return ok


# Changing the count must not reshuffle maps the player already chose. This is
# the bug the rebuild-on-change approach invites, and it is invisible - the
# itinerary just quietly becomes a different campaign.
func test_operations_changing_the_count_keeps_chosen_maps() -> bool:
	print("Running Test Suite: Operations - resizing preserves picked maps...")
	var screen = _screen()
	await tree.process_frame
	screen.engagements_spin.value = 4
	await tree.process_frame

	var chosen: Array = []
	for i in range(screen._map_pickers.size()):
		# Deliberately not the defaults: rotate each pick one step forward.
		var sel: int = 1 + ((i + 2) % MapCatalogScript.get_map_ids().size())
		screen._map_pickers[i].selected = sel
		chosen.append(sel)

	screen.engagements_spin.value = 6
	await tree.process_frame

	var ok := true
	if screen._map_pickers.size() != 6:
		print("  [FAIL] Expected 6 pickers after resize, got ", screen._map_pickers.size())
		ok = false
	else:
		for i in range(chosen.size()):
			if screen._map_pickers[i].selected != chosen[i]:
				print("  [FAIL] Engagement %d changed map on resize: %d -> %d"
					% [i + 1, chosen[i], screen._map_pickers[i].selected])
				ok = false

	screen.queue_free()
	await tree.process_frame
	if ok:
		print("  [PASS] Growing 4 -> 6 engagements left the first four picks untouched.")
	return ok


# The chosen difficulty is where the operation ENDS, not a flat setting. If the
# ramp collapsed to "every round is the picked tier", the opening engagement
# stops being the cheap place to find out what your roster does wrong.
func test_operations_difficulty_ramps_toward_the_choice() -> bool:
	print("Running Test Suite: Operations - difficulty ramps to the chosen tier...")
	var ok := true

	var hard: Array = []
	for i in range(6):
		hard.append(OperationsManagerScript.ramped_difficulty(i, 6, "hard"))
	if hard[0] != "normal":
		print("  [FAIL] A 'hard' operation should open below hard, opened on: ", hard[0])
		ok = false
	if hard[hard.size() - 1] != "hard":
		print("  [FAIL] A 'hard' operation should END on hard, ended on: ", hard[hard.size() - 1])
		ok = false

	# Easy has nothing below it. Ramping off the bottom of the table would either
	# wrap to hard or index out of range; both are worse than staying flat.
	for i in range(5):
		if OperationsManagerScript.ramped_difficulty(i, 5, "easy") != "easy":
			print("  [FAIL] An 'easy' operation must stay easy, round %d was %s"
				% [i + 1, OperationsManagerScript.ramped_difficulty(i, 5, "easy")])
			ok = false

	# total_stages is derived, not stored. It used to be a separate field that a
	# custom itinerary left stale at 3.
	var mgr = OperationsManagerScript.new()
	mgr.start_new_operation(OperationsManagerScript.default_itinerary(9, "normal"), "normal")
	if mgr.total_stages != 9:
		print("  [FAIL] total_stages is ", mgr.total_stages, " after a 9-stage itinerary")
		ok = false
	mgr.free()

	if ok:
		print("  [PASS] hard ramps normal->hard, easy stays easy, total_stages follows the itinerary.")
	return ok
