extends SceneTree
# A full-length instrumented battle run, and its own control.
#
# WHAT CHRIS ASKED FOR, and why it is two runs. Instrumentation is not free, so a
# profiled run alone cannot say what an event costs in a real match - it can only
# say what it costs while being watched. Running the SAME match twice, once with
# BattleProfiler on and once off, and differencing the frame statistics, gives
# the observer cost explicitly instead of assuming it away.
#
# The two runs are made comparable by seeding the RNG identically and issuing the
# same scripted orders on the same ticks. They will still diverge - combat is
# chaotic and a single different damage roll cascades - so the comparison is
# between DISTRIBUTIONS over ~18000 frames, not between individual frames.
#
# DURATION is wall time, not frames: a five-minute run that hitches produces
# fewer frames, and cutting it off at a frame count would quietly shorten exactly
# the runs worth measuring.
#
# Usage:
#   Godot_v4.7.1-stable_win64_console.exe --path . \
#       --script tools/profile_battle_run.gd -- [seconds] [on|off]

# Reached through preload, not through the `BattleProfiler` global class name.
# The static flag set via one and read via the other did not agree - the section
# table came back empty from a run that was supposedly profiled - so the harness
# and the game code now go through the identical resource.
const Profiler = preload("res://scripts/battle/battle_profiler.gd")

const DEFAULT_SECONDS := 300.0
const SEED := 20260807
const HARVESTERS := 6
const SQUAD_SIZE := 4
const SQUADS := 3

var _seconds: float = DEFAULT_SECONDS
var _profiled: bool = true


func _init():
	_read_args()
	seed(SEED)
	Profiler.enabled = _profiled
	Profiler.reset()

	var battle = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	# WITHOUT THIS THE RUN IS NOT REPRESENTATIVE. Several systems reach the match
	# through get_tree().current_scene, which a hand-instantiated scene leaves
	# null - auto_weapon._effects_parent() then falls back to the root Window and
	# every AoE hit threw "Invalid type in function 'crater'". That is thousands
	# of scripted errors a run, which is itself a per-frame cost, and it would
	# have contaminated exactly the numbers this harness exists to produce.
	current_scene = battle
	while not battle.world_is_ready:
		await process_frame

	print("")
	print("=== battle run: %.0fs, profiler %s ==="
		% [_seconds, "ON" if _profiled else "OFF"])

	await _field_forces(battle)

	# Wall-clock frame sampling runs regardless of the profiler, so the control
	# run still produces a comparable frame-time distribution.
	var times: Array[float] = []
	var started := Time.get_ticks_usec()
	var last := started
	var next_wave := 45.0
	var elapsed := 0.0
	while elapsed < _seconds:
		await physics_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
		elapsed = float(now - started) / 1_000_000.0
		if elapsed >= next_wave:
			next_wave += 45.0
			await _send_squad(battle)
		if battle.game_over:
			print("  match ended at %.0fs - reporting what was gathered" % elapsed)
			break

	_report(times, battle)
	quit(0)


func _read_args() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1 and args[0].is_valid_float():
		_seconds = args[0].to_float()
	if args.size() >= 2:
		_profiled = args[1] != "off"


# Harvesters plus standing forces, so the run exercises the economy as well as
# combat - Chris's report is about a match with both running, and an all-combat
# run would miss the harvest loop entirely.
func _field_forces(battle) -> void:
	var harvester := _find_design(battle, true)
	if not harvester.is_empty():
		for i in range(HARVESTERS):
			battle.spawn_unit(harvester, battle.PLAYER_TEAM,
				Vector3(randf_range(-25, 25), 0, randf_range(-25, 25)))
	for team in [battle.PLAYER_TEAM, battle.ENEMY_TEAM]:
		var z: float = -30.0 if team == battle.PLAYER_TEAM else 30.0
		for i in range(SQUAD_SIZE * 2):
			var design := _find_design(battle, false)
			if design.is_empty():
				continue
			battle.spawn_unit(design, team, Vector3(float(i) * 3.0 - 12.0, 0, z))
	for _i in range(30):
		await physics_frame


func _send_squad(battle) -> void:
	var design := _find_design(battle, false)
	if design.is_empty():
		return
	var sent: Array = []
	for i in range(SQUAD_SIZE):
		var unit = battle.spawn_unit(design, battle.PLAYER_TEAM,
			Vector3(float(i) * 3.0 - 4.0, 0, -30.0))
		if unit != null:
			sent.append(unit)
	for unit in sent:
		if is_instance_valid(unit):
			unit.set_internal_destination(Vector3(randf_range(-20, 20), 0, 30.0))
	await physics_frame


func _find_design(battle, want_harvester: bool) -> Dictionary:
	for design in battle.roster:
		if battle.is_defence_design(design):
			continue
		var is_harv: bool = bool(design.get("is_harvester", false)) \
			or str(design.get("name", "")).to_lower().contains("harvest")
		if is_harv == want_harvester:
			return design
	return {}


func _report(times: Array[float], battle) -> void:
	times.sort()
	var sum := 0.0
	var over_33 := 0
	var over_100 := 0
	for t in times:
		sum += t
		if t > 33.0:
			over_33 += 1
		if t > 100.0:
			over_100 += 1
	var n := times.size()
	print("")
	print("  FRAMES  %d over %.0fs" % [n, _seconds])
	print("  mean %.2f  p50 %.2f  p95 %.2f  p99 %.2f  worst %.2f ms"
		% [sum / float(n), times[int(n * 0.50)], times[int(n * 0.95)],
			times[int(n * 0.99)], times[n - 1]])
	print("  frames over 33ms: %d (%.2f%%)   over 100ms: %d"
		% [over_33, 100.0 * float(over_33) / float(n), over_100])
	print("  units alive at end: %d" % battle.get_tree().get_nodes_in_group("units").size())

	if not _profiled:
		print("")
		print("  (control run - no section breakdown by design)")
		return

	print("")
	print("  SECTION          total ms     mean ms    worst ms   frames")
	print("  ---------------------------------------------------------")
	for row in Profiler.sections():
		print("  %-14s %10.1f %10.4f %10.2f %8d"
			% [row["section"], row["total_ms"], row["mean_ms"],
				row["worst_ms"], row["frames"]])

	print("")
	print("  WHAT DOMINATED THE HITCH FRAMES (>33ms)")
	var blame := Profiler.hitch_blame(33.0)
	if blame.is_empty():
		print("    none")
	for row in blame:
		print("    %-14s %5d hitch(es), worst frame %.1f ms"
			% [row["section"], row["hitches"], row["worst_ms"]])
	print("")
	print("  '<untimed>' means the frame's cost was outside every instrumented")
	print("  section - rendering, physics, or something not yet wrapped.")
