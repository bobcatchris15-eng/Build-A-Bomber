extends SceneTree
# WHY DOES THE AI STILL FIELD NOTHING?
#
# The economy rebalance fixed the arithmetic - four harvesters now out-earn a
# production line by 12 cost-units/s - and the AI still ends 7200 ticks with
# combat=0 while choosing BUILD_GENERAL thousands of times. So the money is no
# longer the story, and the queue is.
#
# OPERATIONS_PLAN.md said this a week ago and it was never done: "instrument the
# production queue directly rather than tune further". This is that.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_ai_queue.gd

const HarvFSM = preload("res://scripts/battle/economy/harvester_fsm.gd")

const TICKS := 5400
const SAMPLE_EVERY := 600
const TEAM := 1


func _init():
	await process_frame

	var battle = preload("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	var guard := 0
	while not battle.world_is_ready and guard < 3000:
		await process_frame
		guard += 1

	print("=== AI QUEUE INSTRUMENTATION ===")
	var completions := 0
	battle.production.unit_completed.connect(func(team, queue_name, bp):
		if team == TEAM:
			completions += 1
			print("    *** COMPLETED %s from '%s' queue" % [bp.get("name", "?"), queue_name]))

	for tick in range(TICKS):
		await physics_frame
		if tick % SAMPLE_EVERY != 0:
			continue

		var s: Dictionary = battle.commander.read_state()
		print("  t=%4d credits=%4d harv=%d combat=%d  doing=%s"
			% [tick, s["credits"], s["harvesters"], s["combat_units"],
				battle.commander.action_name(battle.commander.last_action())])

		for qn in ["light", "medium", "heavy", "building", "defense"]:
			var q: Array = battle.production.queue(TEAM, qn)
			if q.is_empty():
				continue
			var head: Dictionary = q[0]
			# `done` with the job still in the queue is the smoking gun: the unit
			# is paid for and finished, and something is refusing to let it out.
			print("      %-8s depth=%d head='%s' time_left=%.1f/%.1f left=%.0f cr stalled=%s done=%s"
				% [qn, q.size(), head.get("label", "?"), head.get("time_left", -1.0),
					head.get("total_time", -1.0), head.get("remaining_cost", -1.0),
					head.get("stalled", false), head.get("done", false)])
			if head.get("done", false):
				# exit_blockers_for() holds a finished unit until its factory door
				# is clear. If harvesters are parked on the exit, the line stops
				# forever and every credit after it is spent on a job that can
				# never pop.
				var blockers: Array = battle.exit_blockers_for(TEAM, qn)
				var names: Array = []
				for b in blockers:
					names.append("%s%s" % [b.blueprint.get("name", "?"),
						" (harvester)" if b.is_harvester else ""])
				print("        DONE BUT HELD. exit blockers: %s" % str(names))

		var contributors: Array = []
		for qn2 in ["light", "medium", "heavy"]:
			contributors.append("%s:%d" % [qn2, battle.production.contributor_count(TEAM, qn2)])
		print("      contributors %s" % str(contributors))

	print("")
	print("  units completed for the AI over %d ticks: %d" % [TICKS, completions])
	battle.queue_free()
	await process_frame
	quit(0)
