extends SceneTree
# Why do harvesters not deliver?
#
# Follows every harvester through a full round trip and reports what state it is
# in, how much it is carrying, and - when it is trying to dock - how close it has
# actually managed to get to the bay it reserved.
#
# The distance-to-bay trace is the point. "Stuck in MOVING_TO_BAY at 3.4 m from a
# bay with DOCK_DISTANCE 2.0" and "never reserved a bay at all" are the same
# symptom from outside (metal never rises) and completely different bugs.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_harvester_dock.gd

const HarvesterFSMScript = preload("res://scripts/battle/economy/harvester_fsm.gd")

const TICKS := 5400
const SAMPLE_EVERY := 600


func _init():
	var packed = load("res://scenes/Battle.tscn")
	var battle = packed.instantiate()
	root.add_child(battle)
	for _i in range(6):
		await process_frame

	var refinery = battle.nearest_refinery(Vector3.ZERO, 0)
	print("  refinery at %s  footprint %s  bays %d"
		% [str(refinery.global_position.round()), str(refinery.footprint), refinery.bay_count()])
	for i in range(refinery.bay_count()):
		print("    bay %d at %s (%.1f m from centre)"
			% [i, str(refinery.bay_position(i).round()),
				refinery.global_position.distance_to(refinery.bay_position(i))])
	print("  DOCK_DISTANCE %.1f   WORK_DISTANCE %.1f   UNLOAD_TIME %.1f"
		% [HarvesterFSMScript.DOCK_DISTANCE, HarvesterFSMScript.WORK_DISTANCE,
			HarvesterFSMScript.UNLOAD_TIME])

	# THE DECISIVE CHECK. A building carves a hole in the navmesh, and Recast then
	# shrinks the walkable surface further by the agent radius. If a dock bay lands
	# inside that margin then no NavigationAgent3D can ever path to it: the agent
	# reports "arrived" at the nearest walkable point instead, which may be metres
	# short. map_get_closest_point() returns exactly that point, so the gap between
	# it and the bay is how far off the navmesh the bay is.
	var nav_map: RID = battle.get_ground_nav_map()
	for i in range(refinery.bay_count()):
		var bay: Vector3 = refinery.bay_position(i)
		var reachable: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, bay)
		print("    bay %d: nearest navmesh point is %.2f m away %s"
			% [i, bay.distance_to(reachable),
				"<-- OFF THE NAVMESH" if bay.distance_to(reachable) > 0.5 else ""])

	var harvesters: Array = []
	for u in battle.get_team_units(0):
		if u.is_harvester:
			harvesters.append(u)
	# A couple more, so bay contention is part of the picture.
	var hb: Dictionary = battle.bp_manager.load_blueprint("res://data/loadout/ore_trucker.json")
	if not hb.is_empty():
		for i in range(2):
			var h = battle.spawn_unit(hb, 0, refinery.global_position + Vector3(10.0 + i * 6.0, 0, 10.0))
			if h != null:
				harvesters.append(h)
	for _i in range(4):
		await process_frame
	print("  harvesters: %d" % harvesters.size())
	if harvesters.is_empty():
		battle.queue_free()
		quit(1)
		return

	# How close each harvester has EVER got to its reserved bay. A minimum that
	# never drops under DOCK_DISTANCE is the whole answer.
	var closest_approach: Dictionary = {}
	var states_seen: Dictionary = {}
	var deliveries := 0
	var metal_start: int = battle.economy.metal(0)

	for tick in range(TICKS):
		await physics_frame
		for h in harvesters:
			if not is_instance_valid(h) or h.harvester == null:
				continue
			var fsm = h.harvester
			var name: String = HarvesterFSMScript.State.keys()[fsm.state]
			states_seen[name] = states_seen.get(name, 0) + 1
			if fsm.state == HarvesterFSMScript.State.MOVING_TO_BAY \
					and is_instance_valid(fsm.refinery) and fsm.bay_index >= 0:
				var d: float = h.global_position.distance_to(fsm.refinery.bay_position(fsm.bay_index))
				closest_approach[h] = minf(closest_approach.get(h, 1.0e9), d)

		if tick % SAMPLE_EVERY == 0:
			var parts: Array = []
			for h in harvesters:
				if not is_instance_valid(h) or h.harvester == null:
					continue
				var fsm = h.harvester
				var d := -1.0
				if is_instance_valid(fsm.refinery) and fsm.bay_index >= 0:
					d = h.global_position.distance_to(fsm.refinery.bay_position(fsm.bay_index))
				parts.append("%s cargo=%d bay=%d d=%.1f" % [
					HarvesterFSMScript.State.keys()[fsm.state], fsm.cargo(), fsm.bay_index, d])
				if fsm.state == HarvesterFSMScript.State.MOVING_TO_BAY and d > 5.0:
					var nav_ok := "no-agent"
					if is_instance_valid(h.nav_agent):
						nav_ok = "finished" if h.nav_agent.is_navigation_finished() else "pathing"
					print("      ^ at %s  on_wall=%s  nav=%s  stuck_timer=%.1f  speed=%.1f  move_speed=%.1f"
						% [str(h.global_position.round()), str(h.is_on_wall()), nav_ok,
							fsm._stuck_timer, Vector2(h.velocity.x, h.velocity.z).length(),
							h.move_speed])
			print("  t=%4d metal=%d  |  %s" % [tick, battle.economy.metal(0), " | ".join(parts)])

	print("")
	print("  metal %d -> %d over %d ticks" % [metal_start, battle.economy.metal(0), TICKS])
	print("  state occupancy (unit-ticks): %s" % str(states_seen))
	for h in harvesters:
		if closest_approach.has(h):
			# The threshold is per-unit (_dock_distance()), not the DOCK_DISTANCE
			# floor - it scales with the truck's own arrive slop.
			print("  closest it ever got to its reserved bay: %.2f m (needs <= %.2f for this hull)"
				% [closest_approach[h], h.harvester._dock_distance()])
		else:
			print("  never held a bay reservation at all")

	battle.queue_free()
	await process_frame
	quit(0)
