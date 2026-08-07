extends SceneTree
# Instrumentation for the AI economy stall (OPERATIONS_PLAN.md, blocker #1).
#
# probe_battle_ai.gd reports the SYMPTOM - three harvesters, zero combat units,
# metal pinned at 0 - but not the cause, because it samples the balance rather
# than the flows. Two teams can both sit at 0 metal for opposite reasons: one has
# no income, the other is spending it as fast as it lands. Those need different
# fixes, so this measures the flows directly:
#
#   * INCOME: every credit() the harvesters deliver, accumulated per window.
#   * DRAW: every metal the production queues actually pull, accumulated the same
#     way, by diffing each head job's remaining_cost_metal across the window.
#   * STALLED TIME: the fraction of ticks the head job could not be paid for.
#
# It also runs LONG. The AI's opening is three harvesters before anything else,
# and at these costs that is more than the 120 s probe_battle_ai watches - so
# "never fields a combat unit" and "has not fielded one yet" are indistinguish-
# able at 7200 ticks. The question this answers is which of those it is.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_ai_economy.gd

const QUEUES := ["light", "medium", "heavy", "building", "defense"]

const TICKS := 36000        # 10 minutes of match time at 60 Hz
const WINDOW := 1800        # report every 30 s

var _team := 1
var _income_window := 0
var _income_total := 0
var _winner := -1
var _last_metal := 0


func _init():
	var packed = load("res://scenes/Battle.tscn")
	if packed == null:
		print("[FAIL] Battle.tscn did not load")
		quit(1)
		return
	var battle = packed.instantiate()
	root.add_child(battle)
	for _i in range(6):
		await process_frame

	if not ("commander" in battle) or battle.commander == null:
		print("[FAIL] the Battle scene has no working director script")
		quit(1)
		return

	# Income is measured at the ledger, not at the harvester, so anything that
	# credits the AI is counted - including the difficulty trickle, which is
	# exactly the sort of thing that can make an economy look healthier in a probe
	# than it is in a match.
	# Also a member for the capture-by-value reason above: a captured local here
	# stays frozen at the opening balance, so every credit is measured against 450
	# forever and the income column silently reads zero.
	_last_metal = battle.economy.metal(_team)
	battle.economy.resources_changed.connect(func(t: int):
		if t != _team:
			return
		var now: int = battle.economy.metal(_team)
		var d: int = now - _last_metal
		_last_metal = now
		if d > 0:
			_income_window += d
			_income_total += d)

	# The director's whole _physics_process is gated on `game_over`, so once the
	# match resolves production and the commander both stop and every column below
	# freezes. Without this the tail reads as a second bug - metal piling up beside
	# an idle queue and a stuck decision - when it is just the match being finished.
	# `_winner` is a member, not a local: GDScript lambdas capture by VALUE, so a
	# lambda assigning to a captured local updates its own copy and the outer
	# variable never changes. Which reads as "the match ended with no winner".
	var ended_at := -1
	battle.match_ended.connect(func(w: int): _winner = w)

	print("  tick |  metal | harv | comb | income/30s | draw/30s | stalled | queues")

	var draw_window := 0.0
	var stalled_ticks := 0
	var remaining_last := {}
	var first_combat := -1
	var first_combat_queue := -1

	for tick in range(TICKS):
		await physics_frame
		if battle.game_over:
			ended_at = tick
			break

		# Draw is diffed per queue head. A job leaving the queue (completed or
		# cancelled) shows up as a negative delta, which is not a draw, so only
		# decreases within the SAME job label are counted.
		var any_stalled := false
		for qn in QUEUES:
			var q: Array = battle.production.queue(_team, qn)
			if q.is_empty():
				remaining_last.erase(qn)
				continue
			var job: Dictionary = q[0]
			var key := "%s|%s" % [qn, job.get("label", "?")]
			var rem: float = job.get("remaining_cost_metal", 0.0)
			if remaining_last.get(qn, {}).get("key", "") == key:
				draw_window += maxf(0.0, remaining_last[qn]["rem"] - rem)
			remaining_last[qn] = {"key": key, "rem": rem}
			if job.get("stalled", false):
				any_stalled = true
		if any_stalled:
			stalled_ticks += 1

		var combat := 0
		for u in battle.get_team_units(_team):
			if not u.is_harvester:
				combat += 1
		if combat > 0 and first_combat < 0:
			first_combat = tick

		# A queue that has never once been non-empty for a combat unit is a
		# different failure from one that fills and drains, so the moment the AI
		# first commits to a non-harvester is recorded separately from delivery.
		if first_combat_queue < 0:
			for qn in QUEUES:
				for job in battle.production.queue(_team, qn):
					if not job.get("is_structure", false) \
							and not str(job.get("label", "")).to_lower().contains("harvest"):
						first_combat_queue = tick
						break
				if first_combat_queue >= 0:
					break

		if tick % WINDOW == 0:
			var s: Dictionary = battle.commander.read_state()
			var qd: Array = []
			for qn in QUEUES:
				var q: Array = battle.production.queue(_team, qn)
				if not q.is_empty():
					qd.append("%s:%d %s %.0fm left" % [qn, q.size(),
						q[0].get("label", "?"), q[0].get("remaining_cost_metal", -1.0)])
			print("  %5d | %6d | %4d | %4d | %10d | %8.0f | %6.0f%% | %s"
				% [tick, s["metal"], s["harvesters"], combat, _income_window,
					draw_window, 100.0 * float(stalled_ticks) / float(WINDOW),
					("idle" if qd.is_empty() else ", ".join(qd))])
			print("        decision=%s  can_build_harvester=%s  scores: %s"
				% [battle.commander.action_name(battle.commander.last_action()),
					str(s["can_build_harvester"]), _score_line(battle.commander, s)])
			_income_window = 0
			draw_window = 0.0
			stalled_ticks = 0

	var final: Dictionary = battle.commander.read_state()
	print("")
	if ended_at >= 0:
		print("  MATCH ENDED at tick %d, winner=team %d - everything below stops here"
			% [ended_at, _winner])
	print("  total income over %d ticks: %d metal"
		% [(ended_at if ended_at >= 0 else TICKS), _income_total])
	print("  first combat unit QUEUED at tick: %s"
		% ("never" if first_combat_queue < 0 else str(first_combat_queue)))
	print("  first combat unit DELIVERED at tick: %s"
		% ("never" if first_combat < 0 else str(first_combat)))
	print("  final: harvesters=%d combat=%d metal=%d"
		% [final["harvesters"], final["combat_units"], final["metal"]])

	battle.queue_free()
	await process_frame
	if first_combat < 0:
		print("[FAIL] the AI never fielded a combat unit in %d ticks" % TICKS)
		quit(1)
	else:
		print("[PASS] the AI fielded its first combat unit at tick %d" % first_combat)
		quit(0)


func _score_line(commander, state: Dictionary) -> String:
	var scores: Dictionary = commander.score_all(state)
	var parts: Array = []
	for action in scores:
		if scores[action] > 0.0:
			parts.append("%s=%.2f" % [commander.action_name(action), scores[action]])
	return "all zero" if parts.is_empty() else ", ".join(parts)
