extends SceneTree
# Day 2 / Track A capture probe.
#
# SKIRMISH_PERF_TROUBLESHOOTING.md §5 Track A. The 2026-08-19 log
# had 77 s of <untimed> across the first 66 s of a base-building
# session (structures_built: 36, units_spawned: 2). The Day 1 work
# retired the single `commander` bucket and added `ai_placement_site`;
# Day 2 adds `navmesh_sync_rebake` + `navmesh_invalidate` (around the
# urgent-path rebake on every structure placement), `battle_resource_load`
# (around the building GLB load), and `render_frame` (a thin _process
# section so the gap between physics ticks is named).
#
# This probe drives the same base-building case the user is hitting -
# player only, no AI opponent - and prints a single line per stall so
# the JSONL log and the engine stdout can be correlated on frame number.
#
# Run from prototype/:
#   ./Godot_v4.7.1-stable_win64_console.exe --headless --verbose --path . \
#       --script res://tools/probe_day2_base_build.gd

const BattleTscn = preload("res://scenes/Battle.tscn")
const BuildingCatalogScript = preload("res://scripts/battle/economy/building_catalog.gd")
const ResourceCatalogScript = preload("res://scripts/battle/economy/resource_catalog.gd")
const MatchConfig = preload("res://scripts/match_config.gd")
const MatchRuleSetScript = preload("res://scripts/match_rule_set.gd")
const Profiler = preload("res://scripts/battle/battle_profiler.gd")
const BattleLogger = preload("res://scripts/battle/battle_logger.gd")

# Structure kinds to build, in order. Covers the common base
# composition: power -> refinery -> light_manufactory -> 2 defenses.
# Each kind forces a different GLB load (battle_resource_load) and a
# different carve footprint (navmesh_sync_rebake), so a per-kind stall
# table can be cross-referenced with structure_built events in the log.
const BUILD_SEQUENCE := [
	"power_plant",
	"refinery",
	"light_manufactory",
	"defense",
	"defense",
	"tech_lab",
]

# How many physics frames to wait between placements. ~60 frames at 30 Hz
# is 2 s, enough for the urgent-path rebake to complete and the next
# placement to land on a settled frame. Also gives the BattleLogger
# enough frames between events to make per-hitch correlation readable.
const FRAMES_BETWEEN := 60

# Wall-clock budget for the whole probe. If the urgent path stalls
# everything for tens of seconds, this still cuts off before the
# 10-minute test timeout.
const WALL_BUDGET_S := 120.0


var _last_frame_ms: float = 0.0
var _last_dominant: String = ""
var _stalls: Array = []


func _init() -> void:
	var config := _ensure_match_config()
	# A small, quiet map. lake_crossing is the 2026-08-19 case but
	# open_plains is faster to boot and forces every structure kind
	# through the urgent navmesh path (no water carve shortcuts).
	config.selected_map_id = "open_plains"
	# Player only, no enemy team. The reported case is "no active AI
	# opponent" - commander.tick() should never run. If it does, that's
	# evidence the AI side is alive and would confuse the
	# <untimed> attribution.
	config.rule_set = MatchRuleSetScript.skirmish("open_plains",
		"industrialists", "industrialists", [], "easy")
	# Top up credits so the player can actually place the sequence
	# without waiting for harvester income.
	config.rule_set.starting_credits = 100000

	var battle = BattleTscn.instantiate()
	root.add_child(battle)
	print("[probe] Waiting for Battle.tscn world_is_ready...")
	while not battle.world_is_ready:
		await process_frame
	# 30 Hz physics for Skirmish is applied by match_director.gd's
	# _ready (the Day 1 defect-2 fix moved the assignment up). The
	# BattleLogger MATCH_BEGIN header records the resolved rate; the
	# [match_director] stdout line records the assignment. Both
	# already exist - the probe just reads back from the engine and
	# reports it, rather than asserting a value that depends on the
	# director's _ready having completed.
	print("[probe] World ready at physics_ticks_per_second=%d" %
		Engine.physics_ticks_per_second)
	if Engine.physics_ticks_per_second != 30:
		print("[probe] WARNING: expected 30 Hz Skirmish, got %d Hz. " \
			% Engine.physics_ticks_per_second
			+ "Defect 2 may have regressed; check the BattleLogger " \
			+ "header and the [match_director] stdout line.")
	# Let things settle for ~2 s of physics time so the boot-path
	# navmesh bake and any first-instance resource load (e.g. the
	# shroud shader) don't end up in the placement-window numbers.
	for _i in range(60):
		await process_frame

	# Run the build sequence. Each placement calls _place_structure
	# directly with a hand-picked site, so the probe is reproducible
	# regardless of where the AI would have put a building.
	for i in range(BUILD_SEQUENCE.size()):
		var kind: String = BUILD_SEQUENCE[i]
		var frame_before: int = Engine.get_physics_frames()
		var wall_before: float = Time.get_ticks_msec() / 1000.0
		_place_at(battle, kind, _site_for(i))
		await process_frame
		# Capture per-section cost on the placement frame. The
		# BattleLogger writes this anyway, but the probe also prints
		# it so a quick --verbose run names the stall without the
		# reader having to open the JSONL.
		var nav_sync_ms: float = Profiler.last_sections.get(
			"navmesh_sync_rebake", 0) / 1000.0
		var nav_inv_ms: float = Profiler.last_sections.get(
			"navmesh_invalidate", 0) / 1000.0
		var load_ms: float = Profiler.last_sections.get(
			"battle_resource_load", 0) / 1000.0
		var render_ms: float = Profiler.last_sections.get(
			"render_frame", 0) / 1000.0
		var frame_total: float = Profiler.last_frame_ms
		var wall_after: float = Time.get_ticks_msec() / 1000.0
		var dominant: String = Profiler.last_dominant
		print("[probe] placement %d/%d kind=%s frame=%d wall=%.3fs " \
			% [i + 1, BUILD_SEQUENCE.size(), kind,
				frame_before, wall_after - wall_before]
			+ "total=%.1fms dominant=%s nav_sync=%.1fms nav_inv=%.1fms " \
			% [frame_total, dominant, nav_sync_ms, nav_inv_ms]
			+ "load=%.1fms render=%.1fms" % [load_ms, render_ms])
		if frame_total > 100.0:
			_stalls.append({
				"kind": kind,
				"frame": frame_before,
				"total_ms": frame_total,
				"dominant": dominant,
				"nav_sync_ms": nav_sync_ms,
				"nav_inv_ms": nav_inv_ms,
				"load_ms": load_ms,
				"render_ms": render_ms,
			})
		# Wait between placements so the urgent-path rebake has time
		# to finish and the next placement lands on a settled frame.
		for _j in range(FRAMES_BETWEEN):
			await process_frame
			if (Time.get_ticks_msec() / 1000.0) - wall_before > WALL_BUDGET_S:
				print("[probe] WALL BUDGET HIT at kind=%s, aborting" % kind)
				_report_and_quit(battle)
				return

	_report_and_quit(battle)


# Place a structure directly via the director's _place_structure, so
# the placement goes through the production -> structure_ready ->
# on_structure_ready -> _place_structure -> _mark_navmesh_dirty chain
# the real match uses. Bypasses the player's ghost / placement
# service, which is the right thing for a probe - we want to time the
# building-mesh / navmesh-rebake cost, not the UI.
func _place_at(battle, kind: String, site: Vector3) -> void:
	var player_team: int = 0
	var stats: Dictionary = BuildingCatalogScript.get_stats(kind)
	if stats.is_empty():
		print("[probe] unknown kind %s, skipping" % kind)
		return
	# _place_structure creates the structure, parents it to the
	# director, runs Structure._ready() (which is the load + mesh
	# build path - battle_resource_load section), and emits
	# structure_built. With under_construction=true, the live signal
	# is suppressed and the caller is expected to call
	# s.begin_construction() to start the build timer.
	var s: Structure = battle._place_structure(kind, player_team, site, true)
	if s == null:
		print("[probe] _place_structure(%s) returned null" % kind)
		return
	# Skip the build timer entirely - we want to time the rebake
	# cost, not the construction UI. The structure is alive in the
	# structures group, which is what _mark_navmesh_dirty walks.
	s.finish_construction()
	# The same navmesh-dirty trigger _on_structure_ready would have
	# fired. This is the urgent path the user is hitting every
	# placement; it is what the new navmesh_sync_rebake +
	# navmesh_invalidate sections measure.
	battle.economy.recalculate_power(player_team,
		battle.get_team_structures(player_team))
	battle._mark_navmesh_dirty(true)


# Site layout: a line of placements so the navmesh carve set is
# small and predictable. Spacing picked so two adjacent buildings
# never share a navmesh tile.
func _site_for(index: int) -> Vector3:
	return Vector3(8.0 * float(index + 1), 0.0, 12.0)


func _report_and_quit(battle) -> void:
	# Final report. The interesting fields are the totals and the
	# worst single placement, which is what the next measurement
	# step has to beat.
	var stats: Dictionary = Profiler.frame_stats()
	print("")
	print("=== Day 2 / Track A capture summary ===")
	print("frames:           %d" % stats.get("frames", 0))
	print("hitch threshold:  %.1f ms (derived from %d Hz tick rate)" \
		% [stats.get("hitch_threshold_ms", 0.0),
			Engine.physics_ticks_per_second])
	print("over threshold:   %d" % stats.get("over_hitch_threshold", 0))
	print("worst:            %.1f ms" % stats.get("worst", 0.0))
	print("p95:              %.1f ms" % stats.get("p95", 0.0))
	print("p99:              %.1f ms" % stats.get("p99", 0.0))
	print("")
	print("Section totals (ms), sorted by total descending:")
	for s in Profiler.sections():
		print("  %-26s total=%8.1f  mean=%6.2f  worst=%7.1f  frames=%d" \
			% [s["section"], s["total_ms"], s["mean_ms"],
				s["worst_ms"], s["frames"]])
	print("")
	print("Stalls > 100 ms on placement frames: %d" % _stalls.size())
	for st in _stalls:
		print("  kind=%s frame=%d total=%.1fms dominant=%s " \
			% [st["kind"], st["frame"], st["total_ms"], st["dominant"]]
			+ "nav_sync=%.1fms nav_inv=%.1fms load=%.1fms render=%.1fms" \
			% [st["nav_sync_ms"], st["nav_inv_ms"],
				st["load_ms"], st["render_ms"]])
	# Dump the JSONL log to a stable path so the post-mortem reader
	# has it. dump_now() returns a path or ""; either way the next
	# step is the same - the per-frame data is in Profiler.sections()
	# which we just printed.
	var dump_path: String = ""
	if BattleLogger.enabled and BattleLogger.log_path != "":
		dump_path = ProjectSettings.globalize_path(BattleLogger.log_path)
		print("BattleLogger JSONL: %s" % dump_path)
	battle.queue_free()
	quit(0)


# The match director's setup assumes /root/MatchConfig exists. The
# unit tests do not instantiate it; the probe must, with the same
# shape scene_router.gd produces.
func _ensure_match_config() -> Node:
	var existing := root.get_node_or_null("MatchConfig")
	if existing != null:
		return existing
	var mc = MatchConfig.new()
	mc.name = "MatchConfig"
	root.add_child(mc)
	return mc
