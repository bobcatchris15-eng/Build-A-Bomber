extends SceneTree
# Phase 2 acceptance: base, economy, harvest loop, production.
#
# The question this exists to answer is the one that motivated the whole phase:
# do multiple harvesters returning at the same time DOCK, or do they pile onto
# one point and shove? Everything else here is supporting evidence.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_battle_phase2.gd

const HarvesterFSMScript = preload("res://scripts/battle/economy/harvester_fsm.gd")
const BuildingCatalogScript = preload("res://scripts/battle/economy/building_catalog.gd")

const TICKS := 3000


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

	# --- Base ---------------------------------------------------------------
	var structures: Array = battle.get_team_structures(0)
	var kinds: Array = []
	for s in structures:
		kinds.append(s.kind)
	print("  player structures: %s" % str(kinds))
	if not ("hq" in kinds and "refinery" in kinds):
		failures.append("a starting base should include an HQ and a refinery")

	var refinery = battle.nearest_refinery(Vector3.ZERO, 0)
	if refinery == null:
		failures.append("no refinery found for team 0")
		_finish(battle, failures)
		return
	print("  refinery dock bays: %d" % refinery.bay_count())
	if refinery.bay_count() < 2:
		failures.append("a refinery needs multiple bays or the queue cannot form")

	# --- The two entry points -----------------------------------------------
	# Chris's model: one queue, reachable from a hovering toolbox AND from a
	# radial menu on a contributing structure. Both must exist and both must read
	# the same ProductionService.
	if battle.production_hud == null:
		failures.append("no production HUD was built")
	else:
		var hq = null
		for s in structures:
			if s.kind == "hq":
				hq = s
		if hq != null:
			battle.production_hud.open_structure_ring(hq, Vector2(400, 300))
			var ring_found := false
			for child in battle.production_hud.get_children():
				if child is UIRadialMenu:
					ring_found = true
					print("  ring on HQ opened: %s" % child.is_open())
			if not ring_found:
				failures.append("clicking a contributing structure raised no radial menu")

	# --- Bay reservation is exclusive ---------------------------------------
	# The core of the fix. Two harvesters must never be handed the same bay.
	var a := Node3D.new()
	var b := Node3D.new()
	battle.add_child(a)
	battle.add_child(b)
	var bay_a: int = refinery.reserve_bay(a)
	var bay_b: int = refinery.reserve_bay(b)
	if bay_a < 0 or bay_b < 0 or bay_a == bay_b:
		failures.append("two harvesters were given bays %d and %d" % [bay_a, bay_b])
	# Idempotent: re-asking must return the SAME bay, not leak a second one.
	if refinery.reserve_bay(a) != bay_a:
		failures.append("re-reserving leaked a second bay")
	# Fill every bay, then confirm the next caller is turned away rather than
	# being quietly handed an out-of-range index.
	var hogs: Array = []
	while true:
		var extra := Node3D.new()
		battle.add_child(extra)
		var got: int = refinery.reserve_bay(extra)
		if got < 0:
			break
		hogs.append(extra)
		if hogs.size() > 16:
			failures.append("refinery handed out unlimited bays")
			break
	print("  bays exhausted after %d extra claimants" % hogs.size())
	refinery.release_bay(a)
	refinery.release_bay(b)
	for h in hogs:
		refinery.release_bay(h)
	a.queue_free()
	b.queue_free()
	for h in hogs:
		h.queue_free()

	# --- Harvest loop -------------------------------------------------------
	var harvesters: Array = []
	for u in battle.get_team_units(0):
		if u.is_harvester:
			harvesters.append(u)
	print("  harvesters in the starting force: %d" % harvesters.size())
	if harvesters.is_empty():
		failures.append("no harvester spawned - ore_trucker.json should mount resource_harvester")
		_finish(battle, failures)
		return

	# Add more so several return together, which is the case that used to jam.
	var trucker: Dictionary = battle.bp_manager.load_blueprint("res://data/loadout/ore_trucker.json")
	var origin: Vector3 = harvesters[0].global_position
	for i in range(3):
		var extra = battle.spawn_unit(trucker, 0, origin + Vector3(float(i) * 5.0 - 5.0, 0, 6.0))
		if extra != null:
			harvesters.append(extra)
	print("  harvesters total: %d" % harvesters.size())

	var metal_before: int = battle.economy.metal(0)
	for _i in range(TICKS):
		await physics_frame
	var metal_after: int = battle.economy.metal(0)
	print("  metal %d -> %d" % [metal_before, metal_after])

	# Production is drawing from the same bank, so a strict increase is not the
	# assertion - delivery happening at all is. Nothing was queued here, so any
	# rise is harvested income.
	if metal_after <= metal_before:
		failures.append("harvesters delivered nothing in %d ticks" % TICKS)

	var states: Dictionary = {}
	for h in harvesters:
		if not is_instance_valid(h):
			continue
		var state_name: String = HarvesterFSMScript.State.keys()[h.harvester.state]
		states[state_name] = states.get(state_name, 0) + 1
	print("  harvester states: %s" % str(states))

	# NOT STACKED. The regression: every harvester steering at the refinery
	# origin and arriving inside its neighbours.
	var closest := 1.0e9
	for i in range(harvesters.size()):
		for j in range(i + 1, harvesters.size()):
			if not is_instance_valid(harvesters[i]) or not is_instance_valid(harvesters[j]):
				continue
			var p: Vector3 = harvesters[i].global_position
			var q: Vector3 = harvesters[j].global_position
			closest = minf(closest, Vector2(p.x - q.x, p.z - q.z).length())
	print("  closest harvester pair: %.2f m" % closest)
	if closest < 1.5:
		failures.append("harvesters ended up stacked (%.2f m apart)" % closest)

	# No bay may be held twice at rest, which would mean the reservation
	# bookkeeping drifted over a long run.
	var held: Array = []
	for h in harvesters:
		if not is_instance_valid(h) or h.harvester.bay_index < 0:
			continue
		if not is_instance_valid(h.harvester.refinery):
			continue
		var key := "%d:%d" % [h.harvester.refinery.get_instance_id(), h.harvester.bay_index]
		if key in held:
			failures.append("two harvesters hold the same bay after %d ticks" % TICKS)
			break
		held.append(key)

	# --- Production ---------------------------------------------------------
	# The RA speed table, which the research this rebuild follows wanted to
	# replace with an invented logarithmic curve.
	var one: int = battle.production.contributor_count(0, BuildingCatalogScript.QUEUE_BUILDING)
	print("  building-queue contributors: %d" % one)
	if one < 1:
		failures.append("the HQ should contribute to the building queue")

	battle.economy.credit(0, 5000, 5000)
	var job: Dictionary = battle.production.enqueue_structure(
		0, BuildingCatalogScript.QUEUE_BUILDING, "power_plant", 180, 40, 12.0)
	if job.is_empty():
		failures.append("could not enqueue a power plant")
	else:
		# A one-element Array, not a bool. GDScript lambdas capture local
		# variables BY VALUE, so `ready = true` inside the callback would set a
		# copy and the outer flag would stay false forever - which is exactly
		# what this probe reported on its first run.
		var ready := [false]
		battle.production.structure_ready.connect(func(_t, _q, _j): ready[0] = true)
		for _i in range(60 * 20):
			await physics_frame
			if ready[0]:
				break
		print("  power plant completed: %s" % str(ready[0]))
		if not ready[0]:
			failures.append("a queued structure never completed")

	# A heavy tank with no heavy manufactory must be refused at the door rather
	# than sitting in a line that can never advance.
	var refused: Dictionary = battle.production.enqueue_unit(
		0, {"name": "X"}, 10, 10, 5.0, BuildingCatalogScript.QUEUE_HEAVY)
	if not refused.is_empty():
		failures.append("a queue with no contributing structure accepted a job")

	_finish(battle, failures)


func _finish(battle: Node, failures: Array) -> void:
	battle.queue_free()
	await process_frame
	if failures.is_empty():
		print("[PASS] battle phase 2")
		quit(0)
	else:
		for f in failures:
			print("  [FAIL] %s" % f)
		print("[FAIL] battle phase 2: %d problem(s)" % failures.size())
		quit(1)
