extends SceneTree
# Does a finished match actually feed the campaign?
#
# The unit suites assert the manager's bookkeeping and the draft screen's output
# in isolation. THE SEAM BETWEEN THEM is the part that was broken for the whole
# rebuild - match_director passed `false` for is_operation unconditionally and
# nothing called record_stage_result - and a seam is exactly what a unit test
# cannot see. So this ends a real match inside a real operation and asks whether
# the campaign noticed.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_operations_loop.gd

const OperationsManagerScript = preload("res://scripts/operations_manager.gd")
const CommanderScript = preload("res://scripts/battle/ai/commander.gd")


func _init():
	var failures: Array = []

	# A SceneTree script's _init() runs BEFORE the autoloads are instantiated, so
	# looking one up on the first line reports it missing no matter how it is
	# registered.
	await process_frame

	var ops = root.get_node_or_null("OperationsManager")
	if ops == null:
		print("[FAIL] OperationsManager is not an autoload - the whole point of this wiring")
		quit(1)
		return
	ops.start_new_operation(OperationsManagerScript.default_itinerary(3, "normal"), "normal")
	var save_path: String = ops.save_path()

	var config = root.get_node_or_null("MatchConfig")
	if config:
		config.selected_map_id = str(ops.get_current_stage_info().get("map_id", ""))

	var battle = preload("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	var guard := 0
	while not battle.world_is_ready and guard < 3000:
		await process_frame
		guard += 1
	if not battle.world_is_ready:
		print("[FAIL] Battle never built its world")
		quit(1)
		return
	print("  match started on '%s' (engagement 1 of %d)" % [battle.map_id, ops.total_stages])

	# Let it actually run for a moment. MatchStats only accumulates while the
	# match is live, correctly, so an instant win legitimately records a duration
	# of zero and the recorded-duration check below would be asserting nothing.
	for _i in range(120):
		await physics_frame

	# Kill the enemy HQ outright rather than playing it out - the win CONDITION
	# is tested elsewhere; what is being measured here is what happens after it.
	var enemy_hq = null
	for s in battle.get_team_structures(battle.ENEMY_TEAM):
		if s.kind == "hq":
			enemy_hq = s
			break
	if enemy_hq == null:
		print("[FAIL] no enemy HQ to destroy")
		quit(1)
		return
	enemy_hq.take_damage(999999.0, "kinetic", null)

	# The report is deliberately deferred behind RESULT_BEAT so the killing blow
	# is seen before it is covered up, so this has to wait it out.
	var beat: float = battle.RESULT_BEAT + 1.0
	var frames := int(beat * 60.0) + 120
	for _i in range(frames):
		await process_frame

	if not battle.game_over:
		failures.append("the match never ended after the enemy HQ died")

	# 1. The result reached the combat log.
	if ops.stage_results_history.size() != 1:
		failures.append("combat log has %d entries after one engagement, expected 1"
			% ops.stage_results_history.size())
	else:
		var entry: Dictionary = ops.stage_results_history[0]
		if not entry.get("victory", false):
			failures.append("the engagement was won but recorded as a loss")
		if (entry.get("enemy_designs", []) as Array).is_empty():
			failures.append("what the enemy fielded was not recorded - counter-drafting has nothing to read")
		if (entry.get("player_designs", []) as Array).is_empty():
			failures.append("what the player fielded was not recorded")
		if float(entry.get("duration", 0.0)) <= 0.0:
			failures.append("the engagement recorded a zero duration")

	# 2. The report offers a next engagement. Reading the button rather than the
	#    flag: `is_operation` being true means nothing if the branch it feeds does
	#    not produce a control the player can press.
	var report = _find_report(battle)
	if report == null:
		failures.append("no after-action report was shown")
	else:
		if not report.is_operation:
			failures.append("the report was built as a skirmish debrief, not a campaign one")
		if _find_button(report, "Next Engagement") == null:
			failures.append("the report offers no way to continue the operation")

	# 3. Advancing walks the itinerary and the campaign is on disk.
	if not ops.advance_to_next_stage():
		failures.append("advance_to_next_stage() ended a 3-engagement operation after one")
	if ops.current_stage != 1:
		failures.append("current_stage is %d after advancing once" % ops.current_stage)
	var expected: String = str(ops.stages_itinerary[1].get("map_id", ""))
	if str(ops.get_current_stage_info().get("map_id", "")) != expected:
		failures.append("engagement 2 does not point at the itinerary's second map")
	if not FileAccess.file_exists(save_path):
		failures.append("the campaign was never written to disk at %s" % save_path)

	battle.queue_free()
	await process_frame

	# --- Engagement 2: does the AI actually bring something different? --------
	#
	# The counter-draft is unit-tested as a pure reordering, but what matters is
	# whether match_director APPLIES it - the log has to reach _load_roster()
	# through the autoload, on a real second match. The first engagement above
	# recorded whatever the bundled roster is; this overwrites the threat tags
	# with an air force so the answer is unambiguous.
	if not ops.stage_results_history.is_empty():
		ops.stage_results_history[0]["player_threats"] = ["air", "air", "air", "air"]

	var second = preload("res://scenes/Battle.tscn").instantiate()
	root.add_child(second)
	guard = 0
	while not second.world_is_ready and guard < 3000:
		await process_frame
		guard += 1

	# ASKED THROUGH ai_design_for_role(), not by reading the list. That function is
	# what actually consumes the ordering, and it filters defence designs out of
	# unit roles - so the raw first entry can legitimately be a SAM turret while
	# the unit the AI builds is something else entirely. Checking the list
	# directly measures the wrong thing.
	var unit_pick: Dictionary = second.ai_design_for_role(second.ENEMY_TEAM, "anti_air")
	var general_pick: Dictionary = second.ai_design_for_role(second.ENEMY_TEAM, "general")
	var defence_pick: Dictionary = second.ai_design_for_role(second.ENEMY_TEAM, "defense")
	print("  engagement 2: AA unit '%s', general '%s', defence '%s'" % [
		unit_pick.get("name", "NONE"), general_pick.get("name", "NONE"),
		defence_pick.get("name", "NONE")])

	if unit_pick.is_empty():
		failures.append("the AI cannot name an anti-air unit to build after an all-air engagement")

	# The real question the reorder exists to answer: when the AI builds a
	# GENERAL-purpose unit - its most common action by far - does the air threat
	# change what it reaches for? Every design fills "general", so this is decided
	# purely by roster order.
	if not general_pick.is_empty() \
			and not CommanderScript.design_fills_role(general_pick, "anti_air"):
		failures.append("after an all-air engagement the AI's general-purpose pick is '%s', which cannot shoot at aircraft - the counter-draft is not reaching _load_roster()"
			% general_pick.get("name", "?"))

	second.queue_free()
	await process_frame

	DirAccess.remove_absolute(save_path)
	ops.reset_operation()

	if failures.is_empty():
		print("[PASS] a finished match records its result, offers the next engagement, and persists")
		quit(0)
	else:
		for f in failures:
			print("  [FAIL] %s" % f)
		print("[FAIL] operations loop: %d problem(s)" % failures.size())
		quit(1)


func _find_report(node: Node):
	if node.name == "AfterActionReport":
		return node
	for child in node.get_children():
		var found = _find_report(child)
		if found != null:
			return found
	return null


func _find_button(node: Node, text: String):
	if node is Button and str(node.text).begins_with(text):
		return node
	for child in node.get_children():
		var found = _find_button(child, text)
		if found != null:
			return found
	return null
