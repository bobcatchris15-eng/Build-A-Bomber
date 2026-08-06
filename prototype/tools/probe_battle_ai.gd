extends SceneTree
# Phase 3 acceptance: does the opponent actually play?
#
# The old AI could be "working" in the sense that its timers fired while doing
# nothing a player would recognise as strategy. So the questions here are about
# whether the decisions COMPOSE into an opening:
#
#   * does it get past the opening deadlock (no factory, so no harvester; no
#     harvester, so no factory) and build something
#   * does its economy actually grow, or does it sit on its starting money
#   * does it produce units, and do squads take orders
#   * is it fog-gated - it must not react to units it cannot see
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_battle_ai.gd

const CommanderScript = preload("res://scripts/battle/ai/commander.gd")

const TICKS := 3600
const SAMPLE_EVERY := 600


func _init():
	var failures: Array = []

	var packed = load("res://scenes/Battle.tscn")
	if packed == null:
		print("[FAIL] Battle.tscn did not load")
		quit(1)
		return
	var battle = packed.instantiate()
	root.add_child(battle)
	for _i in range(6):
		await process_frame

	# A parse error in match_director.gd leaves the scene root as a plain Node3D
	# with none of its script's members. Reading `commander` off that is a hard
	# error mid-probe, which aborts before _finish() and leaves the process
	# HANGING rather than failing - so it is checked explicitly.
	if not ("commander" in battle):
		print("[FAIL] the Battle scene has no director script - check for a parse error")
		quit(1)
		return
	if battle.commander == null:
		_finish(battle, ["no commander was created"])
		return
	print("  enemy roster: %d designs" % battle.enemy_roster.size())
	if battle.enemy_roster.is_empty():
		failures.append("the AI has no designs of its own to build")

	# --- The opening move ----------------------------------------------------
	# Scored directly rather than waited for, so a deadlock is reported as a
	# deadlock instead of as "nothing happened for two minutes".
	var opening: Dictionary = battle.commander.read_state()
	print("  opening state: metal=%d harvesters=%d manufactories=%d refineries=%d"
		% [opening["metal"], opening["harvesters"], opening["manufactories"], opening["refineries"]])
	var scores: Dictionary = battle.commander.score_all(opening)
	var lines: Array = []
	for action in scores:
		lines.append("%s=%.2f" % [battle.commander.action_name(action), scores[action]])
	print("  opening scores: %s" % ", ".join(lines))
	var first: int = battle.commander.decide(opening)
	print("  opening decision: %s" % battle.commander.action_name(first))
	if first < 0:
		failures.append("the AI could not decide on ANY opening action - every option scored zero")

	# --- Play it out ---------------------------------------------------------
	var start_structures: int = battle.get_team_structures(1).size()
	var seen_actions: Dictionary = {}
	for tick in range(TICKS):
		await physics_frame
		var a: int = battle.commander.last_action()
		if a >= 0:
			var key: String = battle.commander.action_name(a)
			seen_actions[key] = seen_actions.get(key, 0) + 1
		if tick % SAMPLE_EVERY == 0:
			var s: Dictionary = battle.commander.read_state()
			print("  t=%4d metal=%4d harv=%d combat=%d manu=%d structures=%d  doing=%s"
				% [tick, s["metal"], s["harvesters"], s["combat_units"], s["manufactories"],
					battle.get_team_structures(1).size(), battle.commander.action_name(a)])

	var end_structures: int = battle.get_team_structures(1).size()
	var final: Dictionary = battle.commander.read_state()
	print("")
	print("  structures %d -> %d" % [start_structures, end_structures])
	print("  final: harvesters=%d combat=%d manufactories=%d metal=%d"
		% [final["harvesters"], final["combat_units"], final["manufactories"], final["metal"]])
	print("  actions taken: %s" % str(seen_actions))

	# Defensive designs must be BUILDABLE, not just present in the roster. A
	# turret design nothing can place is decoration.
	var defence: Dictionary = battle.ai_design_for_role(1, "defense")
	print("  defence design available: %s" % (defence.get("name", "NONE")))
	if defence.is_empty():
		failures.append("the AI has no defensive design it can build")
	else:
		var before_def: int = battle.get_team_structures(1).size()
		# Fund it. Whether the AI can AFFORD a turret is an economy question and is
		# measured above; this is asking whether the placement path works at all,
		# and a starved queue would answer neither.
		battle.deliver(1, 3000, 800)
		if not battle.ai_build_defence(1):
			failures.append("ai_build_defence could not queue a turret")
		else:
			for _t in range(1800):
				await physics_frame
			var placed := 0
			var armed := 0
			for s2 in battle.get_team_structures(1):
				if s2.kind == "defense":
					placed += 1
					# A turret that cannot shoot is a decorative box, and "placed"
					# alone would report it as a success.
					if s2.attack_range > 0.0:
						armed += 1
					print("    turret '%s' hp=%.0f reach=%.1f m"
						% [s2.kind, s2.max_hp, s2.attack_range])
			if placed > 0 and armed <= 0:
				failures.append("a defence was placed but mounts no working weapon")
			print("  turrets placed: %d (structures %d -> %d)"
				% [placed, before_def, battle.get_team_structures(1).size()])
			if placed <= 0:
				failures.append("a queued defence never got placed")

	if end_structures <= start_structures:
		failures.append("the AI never completed a single building")
	if final["harvesters"] <= 0:
		failures.append("the AI never fielded a harvester - its economy cannot grow")
	if seen_actions.size() <= 1:
		failures.append("the AI only ever chose one action - it is not responding to state")

	# --- Fog discipline ------------------------------------------------------
	# The AI must not count units it cannot see. Spawn a flyer far away, out of
	# any plausible vision, and confirm the AI's read of the battlefield does not
	# include it - this is what stops "counter-picking" from being clairvoyance.
	var blueprint: Dictionary = battle.bp_manager.load_blueprint("res://data/loadout/bulwark_mbt.json")
	var before_seen: int = battle.commander.read_state()["enemy_seen"]
	var hidden = battle.spawn_unit(blueprint, 0, Vector3(0, 0, -400.0))
	for _i in range(4):
		await process_frame
	battle.vision.tick()
	var after_seen: int = battle.commander.read_state()["enemy_seen"]
	print("  enemy_seen before/after spawning a unit 400 m away: %d / %d" % [before_seen, after_seen])
	if after_seen > before_seen:
		failures.append("the AI counted a unit it cannot possibly see - it is not fog-gated")

	_finish(battle, failures)


func _finish(battle: Node, failures: Array) -> void:
	battle.queue_free()
	await process_frame
	if failures.is_empty():
		print("[PASS] battle phase 3 - the opponent")
		quit(0)
	else:
		for f in failures:
			print("  [FAIL] %s" % f)
		print("[FAIL] battle phase 3: %d problem(s)" % failures.size())
		quit(1)
