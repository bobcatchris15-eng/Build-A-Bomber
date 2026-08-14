extends SceneTree
# GODOT KERNEL vs GDSCRIPT COST — wall-clock measurement.
#
# probe_perf_scaling.gd established that ~2.4ms/frame is the per-unit cost at
# 60Hz. But that conflates two different things:
#
#   GDSCRIPT COST   the actual work inside unit._physics_process and the
#                   director's _physics_process — steering, nav, move_and_slide.
#                   Fixable by reducing the tick rate or the coefficient.
#
#   GODOT KERNEL COST the scene tree walking, signal dispatch, group membership
#                     maintenance that Godot does for every Node3D, every frame.
#                     Proportional to node count and connections, not code content.
#
# The previous attempt at this probe measured frame time (via `await physics_frame`),
# which is locked to vsync/physics-thread sleep and showed 0 delta. This version
# measures WALL-CLOCK time to count physics frames directly:
#
#   Pass A  physics ENABLED  → time to wait for N physics steps
#   Pass B  physics DISABLED → time to wait for N physics steps
#   delta   = GDScript cost for N steps
#   kernel  = Pass B baseline (the physics thread still runs, but units don't tick)
#
# If kernel is > 30% of total at unit counts you care about, the node structure
# itself is the problem — consider object pooling or batch processing.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_gdkernel_overhead.gd

const SETTLE_FRAMES := 60
const MEASURE_STEPS := 120  # number of physics steps to count per pass


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

	# Spawn all 16 units in a ring
	const MAX_UNITS := 16
	var all_units: Array = []
	for i in range(MAX_UNITS):
		var ang := TAU * float(i) / float(MAX_UNITS)
		var pos := Vector3(cos(ang), 0.0, sin(ang)) * (15.0 + float(i) * 2.0)
		var u = battle.spawn_unit(design, battle.PLAYER_TEAM, pos)
		if u != null:
			all_units.append(u)
		await process_frame

	for _i in range(SETTLE_FRAMES):
		await physics_frame

	print("=== GODOT KERNEL vs GDSCRIPT COST (%d units) ===" % all_units.size())
	print("(wall-clock measurement, %d physics steps per pass)" % MEASURE_STEPS)
	print("%-6s %8s %8s %8s %8s  %s"
		% ["active", "A (ms)", "B (ms)", "delta", "kernel%", "notes"])
	print()

	for active_count in [1, 4, 8, 16]:
		# Pass A — all `active_count` units have physics enabled
		for i in range(all_units.size()):
			if is_instance_valid(all_units[i]):
				all_units[i].set_physics_process(i < active_count)
		for _i in range(SETTLE_FRAMES):
			await physics_frame
		var ms_a := await _time_physics_steps(MEASURE_STEPS)

		# Pass B — all `active_count` units have physics DISABLED (kernel only)
		for i in range(all_units.size()):
			if is_instance_valid(all_units[i]) and i < active_count:
				all_units[i].set_physics_process(false)
		for _i in range(SETTLE_FRAMES):
			await physics_frame
		var ms_b := await _time_physics_steps(MEASURE_STEPS)

		var delta := ms_a - ms_b
		var kernel_pct := (ms_b / maxf(0.001, ms_a)) * 100.0
		var gd_cost_per_unit := delta / float(active_count) if active_count > 0 else 0.0
		var note := ""
		if kernel_pct > 70.0:
			note = "  <-- kernel dominant"
		elif kernel_pct < 30.0:
			note = "  <-- GDScript dominant"
		print("%-6d %8.2f %8.2f %8.2f %7.1f%%%s"
			% [active_count, ms_a, ms_b, delta, kernel_pct, note])

		# Re-enable for next iteration
		for i in range(all_units.size()):
			if is_instance_valid(all_units[i]):
				all_units[i].set_physics_process(true)

	battle.queue_free()
	await process_frame
	print()
	print("A = physics ENABLED  (GDScript + kernel)")
	print("B = physics DISABLED (kernel only)")
	print("delta = GDScript cost for %d physics steps" % MEASURE_STEPS)
	print("kernel%% = kernel / total  (high = node structure problem)")
	print("wall-clock: Time.get_ticks_usec around each await physics_frame")
	quit(0)


# Count `steps` physics frames and return wall-clock ms per step.
# Uses Time.get_ticks_usec around the await so vsync/thread-sleep doesn't
# hide the real cost the way frame-time measurement does.
func _time_physics_steps(steps: int) -> float:
	var start_us := Time.get_ticks_usec()
	for _i in range(steps):
		await physics_frame
	return (float(Time.get_ticks_usec() - start_us) / float(steps)) / 1000.0
