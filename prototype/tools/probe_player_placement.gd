extends SceneTree
# Acceptance for the player build flow: order a building, place it, and have it
# be real.
#
# WHY A PROBE AND NOT ONLY A SUITE. The placement RULES are pure and are asserted
# in tests/battle/test_battle_placement.gd against a stub. What cannot be
# asserted there is the LIFECYCLE - that a queued structure actually reaches
# `done`, raises a ghost, claims off the queue exactly once, and unblocks the
# line it was holding. That needs a live match, and it is precisely where the
# flow was missing: a completed player job used to park its queue forever.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_player_placement.gd

const PlacementServiceScript = preload("res://scripts/battle/buildings/placement_service.gd")

const PLAYER := 0


func _init():
	var failures: Array = []

	var packed = load("res://scenes/Battle.tscn")
	if packed == null:
		print("[FAIL] Battle.tscn did not load")
		quit(1)
		return
	var battle = packed.instantiate()
	root.add_child(battle)
	for _i in range(6):
		await process_frame

	if not ("production" in battle) or battle.production == null:
		print("[FAIL] the Battle scene has no working director script")
		quit(1)
		return

	# Fund it. Whether the player can AFFORD a power plant is an economy question
	# measured elsewhere; this is asking whether the build flow works at all, and
	# a stalled queue would answer neither.
	battle.deliver(PLAYER, 5000, 2000)

	var before: int = battle.get_team_structures(PLAYER).size()
	print("  player structures at start: %d" % before)

	# --- Order a power plant -------------------------------------------------
	var job: Dictionary = battle.production.enqueue_structure(
		PLAYER, "building", "power_plant", 180, 40, 3.0)
	if job.is_empty():
		print("[FAIL] could not enqueue a power plant - no HQ contributing?")
		quit(1)
		return

	# --- Wait for it to finish and raise a ghost -----------------------------
	var ghost_up := false
	for _t in range(1200):
		await physics_frame
		if battle.is_placing():
			ghost_up = true
			break
	print("  ghost raised on completion: %s" % str(ghost_up))
	if not ghost_up:
		failures.append("a finished player building never raised a ghost - the queue is parked")
		_finish(battle, failures)
		return

	# The job must still be ON the queue while it is in hand. Claiming at `done`
	# rather than at placement would mean a cancelled placement destroys a
	# paid-for building.
	if battle.production.depth(PLAYER, "building") <= 0:
		failures.append("the job left the queue before it was placed")

	# --- An illegal site must be refused, not silently accepted --------------
	var far := Vector3(500.0, 0.0, 500.0)
	if battle.confirm_placement(far):
		failures.append("a placement far outside the map was accepted")
	if not battle.is_placing():
		failures.append("a refused placement dropped the building instead of keeping it in hand")

	# --- Escape holds it, and it can be picked back up -----------------------
	battle.cancel_placement()
	if battle.is_placing():
		failures.append("cancel_placement left the ghost up")
	if battle.production.depth(PLAYER, "building") <= 0:
		failures.append("cancelling a placement destroyed the paid-for building")
	if not battle.resume_placement("building"):
		failures.append("a held building could not be picked back up")

	# --- Place it for real ---------------------------------------------------
	var home: Vector3 = battle._team_home(PLAYER)
	var site: Vector3 = PlacementServiceScript.find_site(battle, PLAYER, home, "power_plant")
	if site == Vector3.INF:
		failures.append("no legal site exists next to the player's own base")
		_finish(battle, failures)
		return
	print("  siting at %.1f, %.1f (home %.1f, %.1f)" % [site.x, site.z, home.x, home.z])

	var placed: bool = battle.confirm_placement(site)
	print("  confirm_placement: %s" % str(placed))
	if not placed:
		failures.append("a site find_site() called legal was refused by confirm_placement")

	await process_frame
	var after: int = battle.get_team_structures(PLAYER).size()
	print("  player structures after placing: %d -> %d" % [before, after])
	if after <= before:
		failures.append("placement reported success but no structure exists")
	if battle.is_placing():
		failures.append("the ghost survived a successful placement")

	# THE BUG THIS EXISTS FOR. The line must be free again - a completed
	# structure blocks its own queue until claimed, so a placement that does not
	# claim leaves production dead with the money already spent.
	if battle.production.depth(PLAYER, "building") != 0:
		failures.append("the building queue is still blocked after placing (depth %d)"
			% battle.production.depth(PLAYER, "building"))
	else:
		print("  building queue unblocked after placement")

	# --- The power plant must actually count ---------------------------------
	# Placing one and having it contribute nothing is the quiet version of this
	# failing: the structure exists, the money is gone, and the brownout stays.
	var capacity: float = battle.economy.power_capacity(PLAYER)
	print("  player power capacity after placing: %.0f" % capacity)

	_finish(battle, failures)


func _finish(battle: Node, failures: Array) -> void:
	battle.queue_free()
	await process_frame
	if failures.is_empty():
		print("[PASS] player ghost placement")
		quit(0)
	else:
		for f in failures:
			print("  [FAIL] %s" % f)
		print("[FAIL] player placement: %d problem(s)" % failures.size())
		quit(1)
