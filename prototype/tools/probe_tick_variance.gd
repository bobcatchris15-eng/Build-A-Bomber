extends SceneTree
# FRAME TIME VARIANCE — IDLE vs COMBAT.
#
# probe_perf_scaling.gd measured cost-vs-count. This measures COST SHAPE:
#   idle    units spawned, same team, no orders → no weapons fire
#   combat  red vs blue teams → weapons auto-acquire and fire
#
# If combat p95/worst >> idle p95/worst: combat subsystems (projectiles,
# auto_weapon targeting, VFX) are the bottleneck.
# If they are similar: the cost is structural — Fix A (30Hz) or Fix B
# (reduce per-unit coefficient) is the path.
#
# Movement is NOT measured here — probe_perf_scaling.gd already covers it.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_tick_variance.gd

const UNIT_COUNT := 16
const SETTLE_FRAMES := 120
const MEASURE_STEPS := 600  # ~10s at 60Hz


func _init():
	await process_frame

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

	var design: Dictionary = {}
	for d in battle.roster:
		if str(d.get("name", "")) == "Bulwark MBT":
			design = d
			break
	if design.is_empty() and battle.roster.size() > 0:
		design = battle.roster[0]
	if design.is_empty():
		print("[FAIL] no unit design in roster")
		quit(1)
		return

	# Phase 1: idle — all units on same team, no orders, no combat
	print("=== PHASE 1: IDLE (%d units, no orders) ===" % UNIT_COUNT)
	var idle_units: Array = []
	for i in range(UNIT_COUNT):
		var ang := TAU * float(i) / float(UNIT_COUNT)
		var pos := Vector3(cos(ang), 0.0, sin(ang)) * (15.0 + float(i) * 2.0)
		var u = battle.spawn_unit(design, battle.PLAYER_TEAM, pos)
		if u != null: idle_units.append(u)
		await process_frame
	for _i in range(SETTLE_FRAMES):
		await physics_frame
	var idle_samples: Array = []
	await _measure_samples(idle_samples, MEASURE_STEPS)
	_print_summary("idle", idle_samples)

	# Phase 2: combat — red vs blue, auto-acquire weapons
	print("=== PHASE 2: COMBAT (%d vs %d, auto-acquire) ==="
		% [UNIT_COUNT / 2, UNIT_COUNT / 2])
	for u in idle_units:
		if is_instance_valid(u):
			u.queue_free()
	await process_frame
	await process_frame
	battle.clear_hull_cache()

	var red: Array = []
	var blue: Array = []
	for i in range(UNIT_COUNT / 2):
		var rpos := Vector3(cos(float(i) * 0.8) * 20.0, 0.0, sin(float(i) * 0.8) * 5.0 - 15.0)
		var bpos := Vector3(cos(float(i) * 0.8) * 20.0, 0.0, sin(float(i) * 0.8) * 5.0 + 15.0)
		var r = battle.spawn_unit(design, battle.PLAYER_TEAM, rpos)
		var b = battle.spawn_unit(design, battle.ENEMY_TEAM, bpos)
		if r != null: red.append(r)
		if b != null: blue.append(b)
		await process_frame

	# Wait for weapons to acquire and fire
	for _i in range(SETTLE_FRAMES):
		await physics_frame
	var combat_samples: Array = []
	await _measure_samples(combat_samples, MEASURE_STEPS)
	_print_summary("combat", combat_samples)

	battle.queue_free()
	await process_frame
	quit(0)


func _measure_samples(out: Array, steps: int) -> void:
	out.clear()
	for _i in range(steps):
		var t0 := Time.get_ticks_usec()
		await physics_frame
		var ms: float = (float(Time.get_ticks_usec() - t0)) / 1000.0
		out.append(ms)


func _print_summary(label: String, samples: Array) -> void:
	if samples.is_empty():
		print("  %-8s  no samples" % label)
		return
	var sorted: Array = samples.duplicate()
	sorted.sort()
	var sum: float = 0.0
	for s in sorted: sum += float(s)
	var n := sorted.size()
	var mean: float = sum / float(n)
	var p50: float = float(sorted[int(n * 0.50)])
	var p95: float = float(sorted[int(n * 0.95)])
	var p99: float = float(sorted[int(n * 0.99)])
	var worst: float = float(sorted[n - 1])
	var fps: float = 1000.0 / maxf(0.001, mean)
	print("  %-8s  mean %6.2f ms  p50 %6.2f  p95 %6.2f  p99 %6.2f  worst %6.2f ms  %.0f fps"
		% [label, mean, p50, p95, p99, worst, fps])
