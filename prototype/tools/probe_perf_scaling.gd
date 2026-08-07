extends SceneTree
# WHERE THE FRAME TIME GOES, AS UNIT COUNT CLIMBS.
#
# Established so far: not a leak (probe_perf_drift.gd), and not material
# fragmentation (probe_unit_render_cost.gd - 22 material objects per unit
# against 19 genuinely distinct, so a cache buys ~15% and not a 10x).
#
# That leaves CPU work that scales with unit count, which headless CAN measure
# honestly: physics, navigation, vision and AI all run without a renderer.
#
# The shape of the curve is the diagnosis:
#
#   LINEAR      per-unit work. Expensive, but it is load, and the fix is a
#               budget or a tick-rate, not a bug.
#   QUADRATIC   every unit looking at every other unit. That is a bug, and at
#               13 units it is 169 interactions - which is exactly the range
#               Chris was playing in when it fell under 10 FPS.
#
# So spawn in steps and time the physics frame at each step. Reports the mean
# of the middle of each window (discarding the spawn spike, which is a
# one-off construction cost and not what a steady slide is made of).
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_perf_scaling.gd

const STEPS := [1, 2, 4, 8, 16, 24, 32, 48]
const SETTLE_FRAMES := 120
const MEASURE_FRAMES := 240


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

	# One mid-weight combat design, repeated - mixing designs would confound
	# unit COUNT with per-design mesh count, and count is the variable here.
	var design: Dictionary = {}
	for d in battle.roster:
		if str(d.get("name", "")) == "Bulwark MBT":
			design = d
			break
	if design.is_empty() and battle.roster.size() > 0:
		design = battle.roster[0]

	print("=== FRAME TIME vs UNIT COUNT ===")
	print("%6s %10s %10s %10s %10s"
		% ["units", "ms/frame", "us/unit", "vs linear", "fps_equiv"])

	var spawned := 0
	var baseline_per_unit := 0.0
	for target in STEPS:
		while spawned < target:
			var ang := TAU * float(spawned) / float(STEPS[STEPS.size() - 1])
			var pos := Vector3(cos(ang), 0.0, sin(ang)) * (20.0 + float(spawned))
			battle.spawn_unit(design, battle.PLAYER_TEAM, pos)
			spawned += 1
			await process_frame

		for _i in range(SETTLE_FRAMES):
			await physics_frame

		var t0 := Time.get_ticks_usec()
		for _i in range(MEASURE_FRAMES):
			await physics_frame
		var total := float(Time.get_ticks_usec() - t0)

		var ms_per_frame := (total / float(MEASURE_FRAMES)) / 1000.0
		var us_per_unit := (total / float(MEASURE_FRAMES)) / float(target)
		if baseline_per_unit <= 0.0:
			baseline_per_unit = us_per_unit
		print("%6d %10.2f %10.1f %10.2fx %10.1f"
			% [target, ms_per_frame, us_per_unit,
				us_per_unit / maxf(0.01, baseline_per_unit),
				1000.0 / maxf(0.01, ms_per_frame)])

	print("")
	print("'vs linear' is per-unit cost against the 1-unit baseline.")
	print("Flat = linear scaling. Climbing = quadratic - every unit is")
	print("looking at every other unit somewhere in the tick.")

	battle.queue_free()
	await process_frame
	quit(0)
