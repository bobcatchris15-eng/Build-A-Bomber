extends SceneTree
# Catches the first-contact hitch with context attached.
#
# Ruled out so far, each by measurement rather than argument:
#   * unit simulation  - 0.03-0.16ms across 2 to 34 units
#   * animation        - the battle layer has none
#   * munition visuals - 1.28ms to build, no first-draw penalty
#
# So this stages the thing Chris was actually looking at - two forces meeting -
# and records, for every frame, the counters that could explain a spike. When a
# frame goes over the threshold it prints that frame's DELTAS against the
# previous one, because "what changed on the bad frame" is the question; absolute
# counts on a slow frame say almost nothing.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --path . \
#          --script tools/probe_engagement_hitch.gd

const PER_SIDE := 6
const FRAMES := 900
const HITCH_MS := 33.0


func _init():
	var battle = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	while not battle.world_is_ready:
		await process_frame
	for _i in range(60):
		await process_frame

	# Two lines facing each other, just outside weapon reach, walked together.
	var player := _spawn_line(battle, battle.PLAYER_TEAM, -18.0)
	var enemy := _spawn_line(battle, battle.ENEMY_TEAM, 18.0)
	print("  fielded %d vs %d" % [player.size(), enemy.size()])
	for _i in range(90):
		await physics_frame

	for u in player:
		if is_instance_valid(u):
			u.set_internal_destination(Vector3(0, 0, 12.0))
	for u in enemy:
		if is_instance_valid(u):
			u.set_internal_destination(Vector3(0, 0, -12.0))

	print("")
	print("  frame |   ms  | d.nodes | d.orphans | d.draws | d.objects | alive")
	print("  ------+-------+---------+-----------+---------+-----------+------")

	var previous := _counters(battle)
	var last := Time.get_ticks_usec()
	var worst := 0.0
	var worst_at := 0
	var reported := 0
	for f in range(FRAMES):
		await physics_frame
		var now := Time.get_ticks_usec()
		var ms := float(now - last) / 1000.0
		last = now
		var current := _counters(battle)
		if ms > worst:
			worst = ms
			worst_at = f
		if ms >= HITCH_MS and reported < 20:
			reported += 1
			print("  %5d | %5.1f | %7d | %9d | %7d | %9d | %5d"
				% [f, ms,
					current["nodes"] - previous["nodes"],
					current["orphans"] - previous["orphans"],
					current["draws"] - previous["draws"],
					current["objects"] - previous["objects"],
					current["alive"]])
		previous = current

	# WEAPONS ARE NOT IN THE "units" GROUP. attach_weapons() sets auto_weapon.gd
	# onto the hull's MODULE nodes and calls set_physics_process(true) on each, so
	# they tick independently of the unit that carries them. An earlier probe
	# concluded "unit simulation is free" by disabling _physics_process on group
	# members only - which left every weapon running, and measured units that
	# were not fighting anyway. This closes that hole.
	var with_weapons := await _mean(150)
	var disabled := _set_weapons(battle, false)
	var without_weapons := await _mean(150)
	_set_weapons(battle, true)
	print("")
	print("  %d weapon nodes ticking" % disabled)
	print("  mean with weapons: %.2f ms    without: %.2f ms    weapons cost %.2f ms"
		% [with_weapons, without_weapons, with_weapons - without_weapons])

	print("")
	print("  worst frame %.2f ms at tick %d;  %d hitch frame(s) over %.0fms"
		% [worst, worst_at, reported, HITCH_MS])
	battle.queue_free()
	await process_frame
	quit(0)


func _set_weapons(battle, on: bool) -> int:
	var n := 0
	for u in battle.get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u):
			continue
		n += _walk_weapons(u, on)
	return n


func _walk_weapons(node: Node, on: bool) -> int:
	var n := 0
	if node.get_script() != null and "fire_range" in node:
		node.set_physics_process(on)
		n += 1
	for c in node.get_children():
		n += _walk_weapons(c, on)
	return n


func _mean(frames: int) -> float:
	var last := Time.get_ticks_usec()
	var total := 0.0
	for _i in range(frames):
		await physics_frame
		var now := Time.get_ticks_usec()
		total += float(now - last) / 1000.0
		last = now
	return total / float(frames)


func _spawn_line(battle, team: int, z: float) -> Array:
	var out: Array = []
	if battle.roster.is_empty():
		return out
	for i in range(PER_SIDE):
		# Skips harvesters and turret designs - neither closes to fight, and a
		# line that will not engage measures nothing.
		var blueprint: Dictionary = battle.roster[i % battle.roster.size()]
		if battle.is_defence_design(blueprint):
			continue
		var at := Vector3(float(i) * 4.0 - 10.0, 0.0, z)
		var unit = battle.spawn_unit(blueprint, team, at)
		if unit != null:
			out.append(unit)
	return out


func _counters(battle) -> Dictionary:
	var alive := 0
	for u in battle.get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and not u.is_dead:
			alive += 1
	return {
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"alive": alive,
	}
