extends SceneTree
# Where does the time go as unit count climbs?
#
# Chris reports "noticeable stuttering with a half dozen or so units" and
# suspects the animation. The new battle units have NO locomotion animation at
# all - unit.gd's _physics_process is orders, economy, movement, vertical,
# move_and_slide, and nothing spins a wheel - so if the report is real the cost
# is somewhere else, and this finds out where before anything is changed.
#
# A STUTTER IS A WORST-FRAME PROBLEM, not a mean one. perf_hud.gd's header
# already records that 8 units in sustained combat measured 15.4ms against 15.3ms
# for an empty map: the mean is flat, which is exactly why the mean is the wrong
# statistic. Everything below reports the worst single frame and the count of
# frames over 33ms alongside the mean, so a spike that ruins the feel while
# barely moving the average cannot hide.
#
# Timed with Time.get_ticks_usec() per frame rather than read from
# Performance.TIME_PROCESS, which refreshes on its own ~1Hz cadence and returns
# the same stale number when sampled per frame.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --path . \
#          --script tools/probe_unit_stutter.gd

const COUNTS := [0, 4, 8, 16, 32]
const SETTLE := 60
const WATCH := 180


func _init():
	# VSYNC OFF FIRST. With it on, every row of this table reported a mean of
	# 16.6ms - which is 60fps, i.e. the refresh rate, not the cost of anything.
	# A regression has to exceed the frame budget entirely before it moves a
	# vsynced mean, so the measurement is blind exactly where it matters.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	var battle = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	while not battle.world_is_ready:
		await process_frame
	for _i in range(60):
		await process_frame

	print("")
	print("  units | mean ms | p95 ms | worst ms | >33ms |  sim ms | render ms | draws")
	print("  ------+---------+--------+----------+-------+---------+-----------+------")

	var spawned: Array = []
	var previous := 0
	for target in COUNTS:
		for _i in range(target - previous):
			var unit = _spawn(battle)
			if unit != null:
				spawned.append(unit)
		previous = target
		for _i in range(SETTLE):
			await physics_frame
		var stats := await _measure(WATCH)
		# SIM vs RENDER. The whole question is whether this is CPU simulation cost
		# or draw cost, and they want opposite fixes - a cheaper _physics_process
		# against fewer/simpler draws. Measured by turning every unit's physics
		# processing off and re-timing the same scene: whatever remains is render.
		var sim_off := await _measure_without_unit_physics(battle, 90)
		print("  %5d | %7.2f | %6.2f | %8.2f | %5d | %7.2f | %9.2f | %5d"
			% [_live(battle), stats["mean"], stats["p95"], stats["worst"],
				stats["hitches"], stats["mean"] - sim_off, sim_off,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])

	print("")
	print("  Read the WORST and >33ms columns, not the mean.")
	battle.queue_free()
	await process_frame
	quit(0)


func _spawn(battle):
	if battle.roster.is_empty():
		return null
	var blueprint: Dictionary = battle.roster[0]
	var at: Vector3 = Vector3(randf_range(-30, 30), 0, randf_range(-30, 30))
	return battle.spawn_unit(blueprint, battle.PLAYER_TEAM, at)


func _live(battle) -> int:
	var n := 0
	for u in battle.get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and not u.is_dead:
			n += 1
	return n


func _agents(battle) -> int:
	var n := 0
	for u in battle.get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and u.get_node_or_null("NavigationAgent3D") != null:
			n += 1
	return n


# Re-times the identical scene with unit simulation switched off, so the
# difference attributes cost to sim rather than to draw. Restored afterwards, or
# every later row would measure a progressively more frozen match.
func _measure_without_unit_physics(battle, frames: int) -> float:
	var units: Array = battle.get_tree().get_nodes_in_group("units")
	for u in units:
		if is_instance_valid(u):
			u.set_physics_process(false)
	var stats := await _measure(frames)
	for u in units:
		if is_instance_valid(u):
			u.set_physics_process(true)
	return stats["mean"]


func _measure(frames: int) -> Dictionary:
	var samples: Array[float] = []
	var last := Time.get_ticks_usec()
	for _i in range(frames):
		await physics_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - last) / 1000.0)
		last = now
	samples.sort()
	var total := 0.0
	var hitches := 0
	for s in samples:
		total += s
		if s > 33.0:
			hitches += 1
	return {
		"mean": total / float(samples.size()),
		"p95": samples[int(float(samples.size()) * 0.95)],
		"worst": samples[samples.size() - 1],
		"hitches": hitches,
	}
