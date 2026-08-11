extends SceneTree
# Refinery-construction hitch. Reported 2026-08-10: a Skirmish dropped
# to ~2 FPS the moment the player started building the refinery and
# never recovered, even after the building was placed. The "never
# recovered" part is the interesting half - the drop is one thing,
# but a 2 FPS floor after construction is something starting up
# DURING construction and not stopping.
#
# HOW THE PROBE NOW WORKS.
#
# The previous version had two real bugs:
#   1. `economy.add_team(team, max(cost*2, 1000))` was used to top up
#      credits, but add_team is the *starting* credits constructor -
#      second arg replaces the team's credits, doesn't add. The probe
#      actually zeroed the player out and then enqueue failed at the
#      door (could not afford).
#   2. enqueue_structure for the "Building" queue needs a live
#      Building-queue contributor. The Skirmish player has only the
#      HQ; that gate is "has at least one HQ" and the HQ counts, so
#      this part actually worked - but the credit failure above
#      masked it. The probe now credits FIRST and verifies the
#      enqueue returned a non-empty job, and aborts with a clear
#      reason if it did not.
#
# After the enqueue is confirmed, the probe records every frame's
# delta. The report breaks the sample into three windows:
#   - baseline (60 frames before enqueue)
#   - build window (enqueue -> structure_ready)
#   - post window (structure_ready -> end of sample)
# If the post window is more than 2x slower than the baseline, the
# hitch is something construction introduced and never released.
# If the worst single frame is in the build window, the cost is in
# the build-tick path itself.
#
# The probe also reports the worst 5 frames. Look there first - if
# the worst frame is < 100 ms, the per-frame cost the player
# reported (2 FPS = 500 ms/frame) is NOT in the production tick and
# the user's hand-test had something else going on (shader compile,
# asset streaming, navmesh rebake on placement - all of which only
# fire on placement, not enqueue).
#
# CANDIDATES THE PROBE RULES IN OR OUT.
#
#   1. Per-frame work that grew with the open Building queue (the
#      production HUD's `_layout_toolboxes` called unconditionally
#      on every _process, walking get_combined_minimum_size() over
#      every open slot). PRODUCTION_HUD FIX LANDED 2026-08-10.
#   2. structure_ready signal handler cost. A one-shot, can't be
#      "never recovered" - ruled in only if the worst frame is the
#      frame structure_ready fires.
#   3. NavigationServer3D rebake on structure placement. ASYNC per
#      the comment at match_director.gd:1140-1163 - should not
#      block. If the worst frame is the first frame after a
#      placement, this is the suspect.
#   4. economy.recalculate_power() called per placement. O(N)
#      per call where N = structures. Trivial unless a placement
#      fires the call inside a per-frame loop somewhere.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --path prototype \
#          --script tools/probe_building_construction_hitch.gd

const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const BattleTscn = preload("res://scenes/Battle.tscn")
const BuildingCatalogScript = preload("res://scripts/battle/economy/building_catalog.gd")
const DesignCostingScript = preload("res://scripts/battle/economy/design_costing.gd")
const ProductionServiceScript = preload("res://scripts/battle/economy/production_service.gd")
const EconomyServiceScript = preload("res://scripts/battle/economy/economy_service.gd")
const MatchConfig = preload("res://scripts/match_config.gd")
const MatchRuleSetScript = preload("res://scripts/match_rule_set.gd")

const SAMPLE_HZ := 0.5
const POST_CONSTRUCTION_FRAMES := 600  # ~10 seconds at 60fps

var _frame_deltas: Array = []
var _construction_started_frame: int = -1
var _construction_completed_frame: int = -1
var _start_wallclock: float = 0.0
var _end_wallclock: float = 0.0
var _last_frame_ms: float = 0.0
var _frame_count: int = 0


func _init():
	# Set up a deterministic Skirmish on a small map. We force the
	# starting credits high so the build can start immediately, and
	# we set the same faction on both sides so the player isn't
	# fighting a moving target. Phase 5: the six legacy pre-match
	# MatchConfig fields are gone - everything goes on the rule set.
	var config = _ensure_match_config()
	config.selected_map_id = "open_plains"
	config.rule_set = MatchRuleSetScript.skirmish("open_plains",
		"industrialists", "industrialists", [], "easy")
	# Top up starting credits so the build can start immediately.
	# The rule set's default sentinel (-1 = "use director default")
	# would land on a too-low credit bank; the probe needs credits
	# ready before the first build queue tick.
	config.rule_set.starting_credits = 10000

	var battle = BattleTscn.instantiate()
	root.add_child(battle)
	print("[probe] Waiting for Battle.tscn world_is_ready...")
	while not battle.world_is_ready:
		await process_frame
	print("[probe] World is ready. Letting things settle for 60 frames.")
	for _i in range(60):
		await process_frame
		_record_frame()

	# The signal we actually want to time is the one production_service
	# emits when a structure finishes construction. Hook it so we can
	# bracket the construction window.
	if battle.production:
		if not battle.production.structure_ready.is_connected(_on_structure_ready):
			var err = battle.production.structure_ready.connect(_on_structure_ready)
			if err != OK:
				print("[probe] structure_ready connect returned ", err,
					" (signal is signal-only or already connected)")

	# Enqueue a refinery build. The Skirmish player has just an HQ, and
	# the HQ is the Building queue's contributor, so the enqueue gate
	# passes. Credits were topped at 10000 above, well above refinery
	# cost on any map.
	var player_team: int = 0
	var cost: int = DesignCostingScript.cost_for("refinery", player_team, battle.economy)
	var build_time: float = float(BuildingCatalogScript.get_building("refinery").get("build_time", 10.0))
	print("[probe] Refinery cost=", cost, " build_time=", build_time, "s player_credits=",
		battle.economy.credits(player_team))

	# The actual enqueue. If this returns {} the build will not start
	# and the probe is testing nothing - bail with a clear reason.
	var result: Dictionary = battle.production.enqueue_structure(
		player_team, "Building", "refinery", cost, build_time, {})
	if result.is_empty():
		print("[probe] FAIL: enqueue_structure returned {} - cannot measure a build that never started.")
		print("[probe]   Likely causes: cost not met, missing required buildings, kind unknown.")
		print("[probe]   Building queue contributors alive: ",
			battle.production.contributor_count(player_team, "Building"))
		_quit(battle)
		return

	print("[probe] Enqueued. Build will run on next physics tick.")
	_construction_started_frame = _frame_count
	_start_wallclock = Time.get_ticks_msec() / 1000.0

	# Run the game. Record every frame's delta and a one-line
	# snapshot at SAMPLE_HZ.
	var sample_acc: float = 0.0
	var post_complete: int = 0
	while post_complete < POST_CONSTRUCTION_FRAMES:
		await process_frame
		_frame_count += 1
		_last_frame_ms = _record_frame()
		sample_acc += _last_frame_ms
		if sample_acc >= SAMPLE_HZ:
			sample_acc -= SAMPLE_HZ
			var fps: float = 1000.0 / max(_last_frame_ms, 0.001)
			print("[probe] frame ", _frame_count,
				"  dt=", "%.2f" % _last_frame_ms, "ms",
				"  fps=", "%.1f" % fps)
		if _construction_completed_frame >= 0:
			post_complete += 1
		if _frame_count > 18000:  # safety cap at ~5 minutes
			break

	_report(battle)


func _on_structure_ready(_team: int, _queue: String, _job: Dictionary) -> void:
	_construction_completed_frame = _frame_count
	_end_wallclock = Time.get_ticks_msec() / 1000.0
	print("[probe] structure_ready fired at frame ", _construction_completed_frame,
		". construction wallclock: ",
		"%.2f" % (_end_wallclock - _start_wallclock), "s")


func _record_frame() -> float:
	var delta: float = get_root().get_process_delta_time() * 1000.0
	_frame_deltas.append(delta)
	return delta


func _report(battle) -> void:
	print("")
	print("[probe] === Refinery-construction hitch report ===")
	print("[probe] Total frames recorded: ", _frame_deltas.size())
	if _end_wallclock > _start_wallclock:
		print("[probe] Construction wallclock: ",
			"%.2f" % (_end_wallclock - _start_wallclock), "s")
	# Three windows: baseline, build, post.
	var base_start: int = 0
	var base_end: int = min(60, _frame_deltas.size())
	var build_start: int = _construction_started_frame if _construction_started_frame >= 0 else 0
	var build_end: int = _construction_completed_frame if _construction_completed_frame >= 0 else _frame_deltas.size()
	var post_start: int = build_end
	var post_end: int = _frame_deltas.size()

	var baseline := _stats(base_start, base_end)
	print("[probe] Baseline (frames 0..60): avg=", "%.2f" % baseline[0], "ms",
		"  worst=", "%.2f" % baseline[1], "ms")
	if build_end > build_start:
		var build := _stats(build_start, build_end)
		print("[probe] Build window (frames ", build_start, "..", build_end, "): avg=",
			"%.2f" % build[0], "ms", "  worst=", "%.2f" % build[1], "ms")
	if post_end > post_start:
		var post := _stats(post_start, post_end)
		print("[probe] Post window (frames ", post_start, "..", post_end, "): avg=",
			"%.2f" % post[0], "ms", "  worst=", "%.2f" % post[1], "ms")
		# The decisive test: is the post window 2x slower than baseline?
		if baseline[0] > 0.0 and (post[0] / baseline[0]) > 2.0:
			print("[probe] POST WINDOW IS >2x SLOWER THAN BASELINE.")
			print("[probe]   The hitch is something construction introduced and never released.")
		elif post[1] > 100.0:
			print("[probe]   Post-window worst frame is ", "%.2f" % post[1],
				"ms - one big spike, not a sustained 2 FPS floor.")
		else:
			print("[probe]   Post-window is within 2x of baseline - the hand-test hitch")
			print("[probe]   was not reproduced. Possible causes:")
			print("[probe]     - the hand-test was on a different map / loadout")
			print("[probe]     - the hand-test triggered placement (which this probe does not)")
			print("[probe]     - the FPS issue is in a screen the headless probe does not render")

	# The worst 5 frames across the whole sample.
	var sorted := _frame_deltas.duplicate()
	sorted.sort()
	sorted.reverse()
	var top5 := sorted.slice(0, min(5, sorted.size()))
	print("[probe] Worst 5 frames (ms): ", top5)
	_quit(battle)


func _stats(from: int, to: int) -> Array:
	if from >= to:
		return [0.0, 0.0]
	var sum: float = 0.0
	var worst: float = 0.0
	for i in range(from, to):
		sum += _frame_deltas[i]
		worst = max(worst, _frame_deltas[i])
	return [sum / max(to - from, 1), worst]


func _quit(battle) -> void:
	battle.queue_free()
	await process_frame
	quit()


func _ensure_match_config() -> Node:
	var existing = root.get_node_or_null("MatchConfig")
	if existing != null:
		return existing
	var mc = Node.new()
	mc.name = "MatchConfig"
	mc.set_script(MatchConfig)
	root.add_child(mc)
	return mc
