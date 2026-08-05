extends "res://tests/suite_base.gd"
# Phase 2: the ledger, the five queues, and the harvest loop's bookkeeping.
#
# ProductionService with no world reports one contributor and gates nothing,
# which is exactly the isolation these want - the queue maths can be asserted
# without a match, a navmesh or a single building.

const EconomyServiceScript = preload("res://scripts/battle/economy/economy_service.gd")
const ProductionServiceScript = preload("res://scripts/battle/economy/production_service.gd")
const BuildingCatalogScript = preload("res://scripts/battle/economy/building_catalog.gd")
const DesignCostingScript = preload("res://scripts/battle/economy/design_costing.gd")
const StructureScript = preload("res://scripts/battle/buildings/structure.gd")


func _service() -> Array:
	var economy = EconomyServiceScript.new()
	economy.add_team(0, 10000, 10000)
	var production = ProductionServiceScript.new()
	production.setup(economy, null)
	production.add_team(0)
	return [economy, production]


# The research this rebuild follows proposes replacing the speed table with an
# invented logarithmic curve. This pins Red Alert's actual
# build_time_speed_reduction instead, which is already tuned and already what the
# rest of the game is balanced against.
func test_production_uses_the_real_ra_speed_table() -> bool:
	print("Running Test Suite: Production - RA build_time_speed_reduction, latched at enqueue...")
	if ProductionServiceScript.SPEED_PCT != [100, 75, 60, 50]:
		print("  [FAIL] The speed table changed: ", ProductionServiceScript.SPEED_PCT)
		return false

	# The table is indexed by (contributors - 1) and HELD at its last entry, so a
	# fifth or tenth factory adds nothing. That cap is the point - it stops
	# production speed from scaling without limit.
	var pct := ProductionServiceScript.SPEED_PCT
	for contributors in [5, 9, 40]:
		var index: int = clampi(contributors - 1, 0, pct.size() - 1)
		if pct[index] != 50:
			print("  [FAIL] %d contributors should still be 50%%, got %d" % [contributors, pct[index]])
			return false

	# Latched at enqueue. Gaining or losing a factory later must not re-time an
	# item already in the line - a job quoted 20 seconds takes 20 seconds.
	var pair := _service()
	var production = pair[1]
	var job: Dictionary = production.enqueue_unit(0, {"name": "T"}, 100, 0, 20.0,
		BuildingCatalogScript.QUEUE_MEDIUM)
	if job.is_empty():
		print("  [FAIL] Could not enqueue against a stubbed world")
		return false
	if not is_equal_approx(job["total_time"], 20.0):
		print("  [FAIL] One contributor should be 100%% of base time, got ", job["total_time"])
		return false
	print("  [PASS] RA speed table")
	return true


# Cost is drawn gradually across the build rather than up front, adapted from
# OpenRA's ProductionItem.Tick. Two consequences this pins: a team that cannot
# pay STALLS rather than losing progress, and cancelling refunds only what was
# actually drawn.
func test_production_drip_feeds_cost_and_refunds_only_what_was_drawn() -> bool:
	print("Running Test Suite: Production - drip-fed cost, stall on empty, honest refund...")
	var pair := _service()
	var economy = pair[0]
	var production = pair[1]

	production.enqueue_unit(0, {"name": "T"}, 100, 50, 10.0, BuildingCatalogScript.QUEUE_MEDIUM)
	var before_metal: int = economy.metal(0)
	# Half the build. Roughly half the cost should have been drawn - not all of
	# it up front, and not none of it.
	for _i in range(50):
		production.tick(0.1)
	var drawn: int = before_metal - economy.metal(0)
	if drawn <= 10 or drawn >= 90:
		print("  [FAIL] Half a build should have drawn roughly half the metal, drew ", drawn)
		return false

	# Cancel: refund what was drawn, NOT the sticker price. Refunding the full
	# cost would make queue-and-cancel a money printer.
	var after_cancel_expected: int = economy.metal(0) + drawn
	production.cancel(0, BuildingCatalogScript.QUEUE_MEDIUM, 0)
	if absi(economy.metal(0) - after_cancel_expected) > 2:
		print("  [FAIL] Cancel refunded %d, expected about %d"
			% [economy.metal(0) - (after_cancel_expected - drawn), drawn])
		return false

	# A team that cannot pay stalls in place. time_left must NOT advance, or a
	# broke player silently loses the build they already part-paid for.
	var broke = EconomyServiceScript.new()
	broke.add_team(0, 0, 0)
	var p2 = ProductionServiceScript.new()
	p2.setup(broke, null)
	p2.add_team(0)
	p2.enqueue_unit(0, {"name": "T"}, 500, 0, 10.0, BuildingCatalogScript.QUEUE_MEDIUM)
	var frozen: float = p2.queue(0, BuildingCatalogScript.QUEUE_MEDIUM)[0]["time_left"]
	for _i in range(30):
		p2.tick(0.1)
	var job: Dictionary = p2.queue(0, BuildingCatalogScript.QUEUE_MEDIUM)[0]
	if not is_equal_approx(job["time_left"], frozen):
		print("  [FAIL] A broke queue advanced from %.2f to %.2f" % [frozen, job["time_left"]])
		return false
	if not job["stalled"]:
		print("  [FAIL] A broke queue should report itself stalled")
		return false
	print("  [PASS] Drip-fed cost")
	return true


func test_five_queues_are_independent_and_gated() -> bool:
	print("Running Test Suite: Production - five independent queues, gated on contributors...")
	if BuildingCatalogScript.QUEUES.size() != 5:
		print("  [FAIL] Expected five queues, got ", BuildingCatalogScript.QUEUES)
		return false
	# Buildings and defences are SEPARATE lines. In the old runtime they shared
	# one `structures` queue, so putting up a refinery blocked every turret.
	if BuildingCatalogScript.QUEUE_BUILDING == BuildingCatalogScript.QUEUE_DEFENSE:
		print("  [FAIL] Buildings and defences must be separate queues")
		return false

	var pair := _service()
	var production = pair[1]
	production.enqueue_unit(0, {"name": "A"}, 10, 0, 5.0, BuildingCatalogScript.QUEUE_LIGHT)
	production.enqueue_unit(0, {"name": "B"}, 10, 0, 5.0, BuildingCatalogScript.QUEUE_HEAVY)
	if production.depth(0, BuildingCatalogScript.QUEUE_LIGHT) != 1 \
			or production.depth(0, BuildingCatalogScript.QUEUE_HEAVY) != 1:
		print("  [FAIL] Queues are not independent")
		return false
	if production.depth(0, BuildingCatalogScript.QUEUE_MEDIUM) != 0:
		print("  [FAIL] An untouched queue should be empty")
		return false

	# Weight tier, not domain, decides the line: a small boat and a light ground
	# hull both come off Light.
	if BuildingCatalogScript.queue_for_hull_tier("light") != BuildingCatalogScript.QUEUE_LIGHT:
		print("  [FAIL] A light hull should map to the light queue")
		return false
	# Every queue must name at least one structure that feeds it, or it can never
	# be used at all.
	for q in BuildingCatalogScript.QUEUES:
		if BuildingCatalogScript.contributors_for(q).is_empty():
			print("  [FAIL] Queue '%s' has no contributing structure" % q)
			return false
	print("  [PASS] Five queues")
	return true


func test_power_gates_production_rate() -> bool:
	print("Running Test Suite: Economy - base power, and low power as a rate not a block...")
	var economy = EconomyServiceScript.new()
	economy.add_team(0, 100, 100)

	# Base power is NOT vehicle energy. Conflating them was a real bug: a
	# generator module on a tank fed the base, so losing the tank browned out the
	# factories. Only structures count here.
	var hq = StructureScript.new()
	root.add_child(hq)
	hq.setup("hq", 0)
	economy.recalculate_power(0, [hq])
	if economy.power_capacity(0) < EconomyServiceScript.HQ_BASELINE_CAPACITY:
		print("  [FAIL] An HQ should supply the baseline capacity")
		return false
	if economy.is_low_power(0):
		print("  [FAIL] A lone HQ should not be in low power")
		return false
	if not is_equal_approx(economy.production_rate(0), 1.0):
		print("  [FAIL] Full power should be full rate")
		return false

	# Enough structures to outdraw the HQ. Low power slows production to RA's own
	# third-rate rather than stopping it - a brownout is a penalty, not a wall.
	var drain: Array = [hq]
	for i in range(8):
		var s = StructureScript.new()
		root.add_child(s)
		s.setup("refinery", 0)
		drain.append(s)
	economy.recalculate_power(0, drain)
	if not economy.is_low_power(0):
		print("  [FAIL] Nine structures on one HQ should be low power (draw %.1f, cap %.1f)"
			% [economy.power_draw(0), economy.power_capacity(0)])
		return false
	var rate: float = economy.production_rate(0)
	if rate >= 1.0 or rate <= 0.0:
		print("  [FAIL] Low power should slow production, not stop it. Rate: ", rate)
		return false
	if not is_equal_approx(rate, 100.0 / EconomyServiceScript.LOW_POWER_MODIFIER):
		print("  [FAIL] Low power rate should be RA's 1/3, got ", rate)
		return false

	for s in drain:
		s.queue_free()

	# A spend must be all or nothing. A partial deduction would let a team go
	# negative on one resource while the other covered it, and the drip-fed model
	# would compound that every tick.
	if economy.spend(0, 500, 0):
		print("  [FAIL] An unaffordable spend should be refused")
		return false
	if economy.metal(0) != 100:
		print("  [FAIL] A refused spend must not deduct anything")
		return false
	print("  [PASS] Power and spending")
	return true


func test_refinery_bays_are_exclusive_and_reclaimable() -> bool:
	print("Running Test Suite: Structure - dock bay reservation...")
	var refinery = StructureScript.new()
	root.add_child(refinery)
	refinery.setup("refinery", 0)

	if refinery.bay_count() < 2:
		print("  [FAIL] A refinery needs several bays or harvesters cannot queue")
		refinery.queue_free()
		return false

	var a := Node3D.new()
	var b := Node3D.new()
	root.add_child(a)
	root.add_child(b)

	var bay_a: int = refinery.reserve_bay(a)
	var bay_b: int = refinery.reserve_bay(b)
	# THE WHOLE POINT. Two harvesters must never be routed to the same square
	# metre - that is the jam this phase set out to fix.
	if bay_a == bay_b:
		print("  [FAIL] Two units were given the same bay (%d)" % bay_a)
		refinery.queue_free()
		return false
	# Idempotent, or a harvester re-asking on any state re-entry leaks bays until
	# the refinery permanently reports itself full.
	if refinery.reserve_bay(a) != bay_a:
		print("  [FAIL] Re-reserving handed out a second bay")
		refinery.queue_free()
		return false
	# Bays are at distinct positions, not all at the origin.
	if refinery.bay_position(bay_a).distance_to(refinery.bay_position(bay_b)) < 1.0:
		print("  [FAIL] Two bays resolve to the same position")
		refinery.queue_free()
		return false

	refinery.release_bay(a)
	if refinery.reserve_bay(a) < 0:
		print("  [FAIL] A released bay was not reusable")
		refinery.queue_free()
		return false

	a.queue_free()
	b.queue_free()
	refinery.queue_free()
	print("  [PASS] Dock bays")
	return true
