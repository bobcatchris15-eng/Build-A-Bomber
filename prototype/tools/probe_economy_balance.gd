extends SceneTree
# ECONOMY BALANCE, against a stated target.
#
# Chris's spec, 2026-08-07:
#
#   A normal economy - ONE refinery and FOUR harvesters - should GROW its
#   resources on hand with ONE manufactory running continuously, and should
#   roughly 80% keep up with TWO running continuously.
#
# That is a ratio, so it can be measured rather than argued about. Two numbers
# decide it:
#
#   INCOME   what 4 harvesters actually deliver per second, on a real map, with
#            real travel. Not a constant of the harvester - the round trip is
#            mostly driving - so it has to be measured in a match, not derived.
#
#   DRAW     what a continuously-running production queue spends per second.
#            This one IS derivable and the derivation is the interesting part:
#            build_time_for_cost() is credits * 0.05, and the drip-feed spends
#            the whole cost across exactly that time, so a queue draws
#            credits / (credits * 0.05) = 20 CREDITS per second
#            REGARDLESS OF WHAT IS BEING BUILT. Cheap scout or heavy tank, the
#            spend rate is identical. Only the clamps (3 s floor, 40 s ceiling)
#            break that, and only for designs outside 60..800 cost.
#
# So the target reduces to: income >= 1.6 x 20 = 32 credits/s, which also
# satisfies "grows against one line" with 60% headroom.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_economy_balance.gd

const DesignCostingScript = preload("res://scripts/battle/economy/design_costing.gd")
const HarvesterFSM = preload("res://scripts/battle/economy/harvester_fsm.gd")

# Seconds of match time to average income over. Long enough to cover several
# full round trips including the first drive out, which is unrepresentative.
const MEASURE_SECONDS := 180.0
const WARMUP_SECONDS := 30.0

const TARGET_HARVESTERS := 4

# One production line's spend, in CREDITS per second.
const DRAW_PER_LINE := 20.0
# Chris's spec: 80% of two lines.
const TARGET_INCOME := DRAW_PER_LINE * 2.0 * 0.8


func _init():
	await process_frame

	var map_id := "open_plains"
	var config = root.get_node_or_null("MatchConfig")
	if config:
		config.selected_map_id = map_id

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

	print("=== ECONOMY BALANCE: %s ===" % map_id)
	_report_draw()

	# --- Build the stated baseline: 1 refinery, 4 harvesters -----------------
	var refineries := 0
	for s in battle.get_team_structures(battle.PLAYER_TEAM):
		if s.kind == "refinery":
			refineries += 1
	var harvester_bp: Dictionary = {}
	for design in battle.roster:
		for m in design.get("modules", []):
			if str(m.get("type_id", "")) == "resource_harvester":
				harvester_bp = design
				break
		if not harvester_bp.is_empty():
			break
	if harvester_bp.is_empty():
		print("[FAIL] no harvester design in the roster")
		quit(1)
		return

	var spawn: Vector3 = Vector3.ZERO
	for s in battle.get_team_structures(battle.PLAYER_TEAM):
		if s.kind == "refinery":
			spawn = s.global_position
			break

	var live := _harvester_count(battle)
	while live < TARGET_HARVESTERS:
		battle.spawn_unit(harvester_bp, battle.PLAYER_TEAM,
			spawn + Vector3(randf_range(-8.0, 8.0), 0.0, randf_range(-8.0, 8.0)))
		live += 1
		await process_frame
	print("  baseline: %d refinery, %d harvesters (capacity %d, chunk %d/%.1fs, unload %.1fs)"
		% [refineries, _harvester_count(battle), HarvesterFSM.new().capacity,
			HarvesterFSM.HARVEST_CHUNK, HarvesterFSM.HARVEST_TIME, HarvesterFSM.UNLOAD_TIME])

	# --- Measure -------------------------------------------------------------
	# Counted from the LEDGER, not from the income estimator: income_rate()
	# is an exponentially-weighted average built for the HUD, and averaging an
	# average is a good way to measure something other than what happened.
	# Production is idle here, so the ledger only moves when a harvester delivers.
	for _i in range(int(WARMUP_SECONDS * 60.0)):
		await physics_frame

	var start_credits: int = battle.economy.credits(battle.PLAYER_TEAM)
	var samples: Array = []
	var ticks := int(MEASURE_SECONDS * 60.0)
	for i in range(ticks):
		await physics_frame
		if i % 1800 == 0 and i > 0:
			var t: float = float(i) / 60.0
			var gained: float = float(battle.economy.credits(battle.PLAYER_TEAM) - start_credits)
			samples.append(gained / t)
			print("    t=%3.0fs  income %.1f credits/s" % [t, gained / t])

	var income: float = float(battle.economy.credits(battle.PLAYER_TEAM) - start_credits) \
		/ MEASURE_SECONDS

	print("")
	print("  INCOME  %.2f credits/s  (%.2f per harvester)"
		% [income, income / float(maxi(1, _harvester_count(battle)))])

	# --- Judge ---------------------------------------------------------------
	print("")
	print("  one line  (draw %.0f/s): %s  - net %+.1f/s" % [DRAW_PER_LINE,
		"GROWS" if income > DRAW_PER_LINE else "SHRINKS", income - DRAW_PER_LINE])
	print("  two lines (draw %.0f/s): keeps up %.0f%%  (target 80%%)"
		% [DRAW_PER_LINE * 2.0, (income / (DRAW_PER_LINE * 2.0)) * 100.0])
	print("  target income %.0f/s, actual %.1f/s -> need x%.2f"
		% [TARGET_INCOME, income, TARGET_INCOME / maxf(0.01, income)])

	battle.queue_free()
	await process_frame
	quit(0)


func _harvester_count(battle) -> int:
	var n := 0
	for u in battle.get_team_units(battle.PLAYER_TEAM):
		if u.is_harvester and not u.is_dead:
			n += 1
	return n


# The draw side, derived and then spot-checked against real designs - if a
# bundled design does not draw 20/s, it is outside the build-time clamps and the
# whole "one line = 20/s" model has an exception worth knowing about.
func _report_draw() -> void:
	print("  --- draw per production line ---")
	for path in ["res://data/loadout/rattler_scout.json",
			"res://data/loadout/bulwark_mbt.json"]:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var cost: int = DesignCostingScript.blueprint_cost(data)
		var time: float = DesignCostingScript.build_time_for_cost(cost)
		var units: float = float(cost)
		print("    %-22s cost %5d cr  time %.1fs  draw %.1f cost-units/s%s"
			% [str(data.get("name", "?")), cost, time, units / time,
				"   <- CLAMPED" if is_equal_approx(time, 3.0) or is_equal_approx(time, 40.0) else ""])
