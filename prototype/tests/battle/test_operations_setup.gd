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


# --- The loop -----------------------------------------------------------------

# A campaign has to survive quitting. Blueprints already do; this is the only
# other thing worth keeping, and it is JSON for the same reason they are.
func test_operations_campaign_round_trips_through_disk() -> bool:
	print("Running Test Suite: Operations - a campaign survives save/load...")
	var mgr = OperationsManagerScript.new()
	mgr.start_new_operation(OperationsManagerScript.default_itinerary(5, "hard"), "hard")
	mgr.set_player_roster(["res://a.json", "res://b.json"])
	mgr.record_stage_result({
		"victory": true,
		"duration": 421.5,
		"designs": {"Bulwark MBT": {"built": 4, "kills": 7, "lost": 1}},
		"player_designs": ["Bulwark MBT"],
		"enemy_designs": ["Magpie Ore Hauler", "Warden AA"],
	})
	mgr.advance_to_next_stage()
	var path: String = mgr.save_path()
	var ok := mgr.save()
	if not ok:
		print("  [FAIL] save() reported failure writing ", path)
		mgr.free()
		return false

	var restored = OperationsManagerScript.new()
	if not restored.load_from(path):
		print("  [FAIL] load_from() refused ", path)
		mgr.free()
		restored.free()
		return false

	if restored.current_stage != 1:
		print("  [FAIL] current_stage came back as ", restored.current_stage, ", expected 1")
		ok = false
	if restored.total_stages != 5:
		print("  [FAIL] itinerary came back with ", restored.total_stages, " stages, expected 5")
		ok = false
	if restored.player_roster_paths != ["res://a.json", "res://b.json"]:
		print("  [FAIL] the drafted roster did not survive: ", restored.player_roster_paths)
		ok = false

	# The combat log is the part counter-drafting will read, so it has to come
	# back whole rather than as a count.
	var log: Array = restored.fielded_history()
	if log.size() != 1:
		print("  [FAIL] combat log came back with ", log.size(), " entries, expected 1")
		ok = false
	elif log[0].get("enemy_designs", []) != ["Magpie Ore Hauler", "Warden AA"]:
		print("  [FAIL] what the enemy fielded did not survive: ", log[0].get("enemy_designs", []))
		ok = false

	# A save from a schema that has moved on must be REFUSED, not half-applied.
	var bogus = OperationsManagerScript.new()
	if bogus.from_dict({"version": 999, "stages_itinerary": [{"map_id": "x"}]}):
		print("  [FAIL] a future save version was accepted")
		ok = false
	bogus.free()

	DirAccess.remove_absolute(path)
	mgr.free()
	restored.free()
	if ok:
		print("  [PASS] A 5-engagement campaign round-trips: stage, itinerary, roster and combat log.")
	return ok


# advance_to_next_stage() and record_stage_result() had zero call sites for the
# whole rebuild - the campaign never moved and the failure mode was SILENCE, not
# an error. So this asserts the pointer actually walks the itinerary and stops.
func test_operations_loop_advances_and_terminates() -> bool:
	print("Running Test Suite: Operations - the loop advances and ends...")
	var mgr = OperationsManagerScript.new()
	mgr.start_new_operation(OperationsManagerScript.default_itinerary(3, "normal"), "normal")

	var ok := true
	var completed := [false]
	mgr.operation_completed.connect(func(_r): completed[0] = true)

	if not mgr.has_next_stage():
		print("  [FAIL] A fresh 3-engagement operation reports no next engagement")
		ok = false

	var maps_seen: Array = []
	for i in range(3):
		maps_seen.append(str(mgr.get_current_stage_info().get("map_id", "")))
		mgr.record_stage_result({"victory": i % 2 == 0, "player_designs": [], "enemy_designs": []})
		var more: bool = mgr.advance_to_next_stage()
		if i < 2 and not more:
			print("  [FAIL] Operation ended early, after engagement ", i + 1)
			ok = false
		if i == 2 and more:
			print("  [FAIL] Operation did not end after its last engagement")
			ok = false

	if mgr.is_active_operation:
		print("  [FAIL] The operation is still active after its last engagement")
		ok = false
	if not completed[0]:
		print("  [FAIL] operation_completed never fired")
		ok = false
	if mgr.stage_results_history.size() != 3:
		print("  [FAIL] combat log has ", mgr.stage_results_history.size(), " entries, expected 3")
		ok = false
	# The itinerary must actually be walked - three engagements all on stage 0's
	# map would look identical from the outside.
	for i in range(3):
		if str(mgr.stages_itinerary[i].get("map_id", "")) != maps_seen[i]:
			print("  [FAIL] Engagement %d was fought on '%s', itinerary says '%s'"
				% [i + 1, maps_seen[i], mgr.stages_itinerary[i].get("map_id", "")])
			ok = false

	DirAccess.remove_absolute(mgr.save_path())
	mgr.free()
	if ok:
		print("  [PASS] Three engagements walked in order, then the operation closed itself.")
	return ok


# The draft screen is what makes an operation more than a playlist. Two things
# must hold: it opens on last round's roster, and Deploy writes the NEXT
# engagement's map - not the one just fought.
func test_operations_draft_carries_the_roster_and_the_next_map() -> bool:
	print("Running Test Suite: Operations - the draft screen carries roster and map...")
	# THE AUTOLOADS, not fresh nodes. Both are registered in project.godot now, so
	# adding a second node under the same name gets it silently RENAMED by Godot
	# and the screen goes on writing to the real singleton - which is exactly how
	# this test first failed, reporting an empty map that had been written to a
	# node the test was not holding.
	var mgr = root.get_node_or_null("OperationsManager")
	var config = root.get_node_or_null("MatchConfig")
	var owned: Array = []
	if mgr == null:
		mgr = OperationsManagerScript.new()
		mgr.name = "OperationsManager"
		root.add_child(mgr)
		owned.append(mgr)
	if config == null:
		config = Node.new()
		config.name = "MatchConfig"
		config.set_script(load("res://scripts/match_config.gd"))
		root.add_child(config)
		owned.append(config)

	mgr.start_new_operation(OperationsManagerScript.default_itinerary(4, "normal"), "normal")
	mgr.record_stage_result({"victory": false, "player_designs": [], "enemy_designs": ["Warden AA"]})
	mgr.advance_to_next_stage()

	var screen = load("res://scripts/operations_draft.gd").new()
	root.add_child(screen)
	await tree.process_frame

	var ok := true
	var expected_map: String = str(mgr.stages_itinerary[1].get("map_id", ""))
	screen.write_match_config()
	if str(config.selected_map_id) != expected_map:
		print("  [FAIL] Deploy wrote map '", config.selected_map_id,
			"', expected engagement 2's map '", expected_map, "'")
		ok = false

	# The picker opens on the previous roster. Asserted through the picker's own
	# output contract, and only for designs the library actually still has - a
	# clean test install may have none, which is not a failure of this code.
	var library: Array = screen.roster_picker._data_by_path.keys()
	if library.size() >= 2:
		screen.roster_picker.fill_from([library[0], library[1]])
		var carried: Array = screen.roster_picker.ordered_paths()
		if carried.size() != 2 or carried[0] != library[0]:
			print("  [FAIL] The draft did not open on the carried roster: ", carried)
			ok = false
		# A path the library no longer has must leave a gap, not a dead slot.
		screen.roster_picker.fill_from(["res://data/loadout/__deleted__.json"])
		if screen.roster_picker.ordered_paths().size() != 2:
			print("  [FAIL] A deleted design was slotted anyway: ",
				screen.roster_picker.ordered_paths())
			ok = false
	else:
		print("  (blueprint library has %d named designs - roster carry-over unasserted)"
			% library.size())

	DirAccess.remove_absolute(mgr.save_path())
	# The autoloads outlive this suite, so the campaign state they were lent has
	# to be handed back - a later suite instantiating Battle.tscn would otherwise
	# find itself mid-operation.
	mgr.reset_operation()
	screen.queue_free()
	for node in owned:
		node.queue_free()
	await tree.process_frame
	if ok:
		print("  [PASS] Deploy writes the next engagement's map, and the roster carries forward.")
	return ok
