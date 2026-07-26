extends RefCounted
# RTS_CORE_ROADMAP.md Phase A1: the one production authority. Before this,
# the tier-resolve -> factory-exists -> legality -> afford -> spend ->
# build-time pipeline was implemented three times (skirmish.gd's
# _queue_player_unit, enemy_ai.gd's _queue_entry and _ensure_harvester) -
# every queue feature would otherwise need to land three times too.
#
# Model: OpenRA's ClassicProductionQueue (RA1), not the per-factory TD model.
# The queue lives per TEAM per TIER (light/medium/heavy), not per building -
# this game's "production category" already IS hull weight tier
# (ModuleCatalog.get_hull_size_tier()), which maps 1:1 onto a manufactory
# kind, so a shared per-tier line is the natural fit. Extra factories of the
# same tier are a later roadmap chunk's job (speed bonus, D3) - for now they
# just share the identical queue.
#
# building.gd's own `production_queue` var, for every manufactory, is an
# ALIAS (Array assignment is by-reference in GDScript) to this class's
# get_queue(team, tier) Array - not a copy. That's what lets every existing
# per-building test/UI read (`b.production_queue`, `_update_hp_bar()`) keep
# working unchanged: two manufactories of the same tier now show the exact
# same Array, which is the correct new behavior (one shared line), not a
# coincidence.

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")

const TIERS: Array = ["light", "medium", "heavy"]

var skirmish: Node3D = null

# queues[team][tier] = Array of {blueprint, time_left, total_time,
# total_cost_metal, total_cost_crystal, remaining_cost_metal (float),
# remaining_cost_crystal (float), paused}. RTS_CORE_ROADMAP.md D1: cost is
# drip-fed over the build now, not spent up front - remaining_cost_* tracks
# what's ACTUALLY been drawn so far (not an idealized "should be by now"
# value), which is what lets per-tick integer rounding never lose or gain
# cost over a build's whole lifetime (a rounded-down tick's shortfall just
# shows up as a bigger draw next tick).
var queues: Dictionary = {}

func setup(skirmish_node: Node3D):
	skirmish = skirmish_node

func get_queue(team: int, tier: String) -> Array:
	if not queues.has(team):
		queues[team] = {}
	if not queues[team].has(tier):
		queues[team][tier] = []
	return queues[team][tier]

func queue_depth(team: int, tier: String) -> int:
	return get_queue(team, tier).size()

# The single path both the player build bar (skirmish.gd's
# _queue_player_unit) and the AI (enemy_ai.gd's _queue_entry/
# _ensure_harvester) call through. cost_metal/cost_crystal are passed in
# rather than re-derived from the blueprint, since callers already have them
# (the player's roster entry, or the AI's own blueprint_cost() call) and
# faction-cost discounts get baked into a roster entry's cost at load time -
# recomputing here would silently skip that discount.
#
# RTS_CORE_ROADMAP.md D1: no longer requires the FULL cost banked up front -
# OpenRA lets you queue something you can't yet fully afford, as long as the
# factory/legality checks pass; the drip-feed in tick() below is what
# actually gates spending, pausing on the very first tick it can't afford
# rather than rejecting the queue attempt itself. Matches this chunk's own
# verify example (queue a 300-cost unit with only 100 banked).
#
# Returns {"queued": bool, "error": "no_factory"|"illegal"|"", "reason":
# <human string, only set for "illegal">, "tier": String} so a caller can
# surface a real status message without re-deriving why it failed.
func enqueue(team: int, blueprint: Dictionary, faction: String, cost_metal: int, cost_crystal: int) -> Dictionary:
	var hull_type = blueprint.get("hull_type", "medium_hull")
	var tier = ModuleCatalog.get_hull_size_tier(hull_type)
	if not skirmish.has_factory_of_tier(team, tier):
		return {"queued": false, "error": "no_factory", "reason": "", "tier": tier}
	var legality = ModuleCatalog.validate_build_legality(blueprint)
	if not legality.valid:
		return {"queued": false, "error": "illegal", "reason": legality.reason, "tier": tier}
	var build_time = skirmish.build_time_for_cost(Vector2i(cost_metal, cost_crystal))
	build_time *= FactionCatalog.get_passive(faction, "build_time_mult", 1.0)
	if skirmish.is_energy_deficit(team):
		build_time *= 1.5
	get_queue(team, tier).append({
		"blueprint": blueprint,
		"time_left": build_time,
		"total_time": build_time,
		"total_cost_metal": cost_metal,
		"total_cost_crystal": cost_crystal,
		"remaining_cost_metal": float(cost_metal),
		"remaining_cost_crystal": float(cost_crystal),
		"paused": false,
	})
	if team == skirmish._local_team() and skirmish.get_node_or_null("/root/AudioManager"):
		skirmish.get_node("/root/AudioManager").play_sfx("click")
	return {"queued": true, "error": "", "reason": "", "tier": tier}

# RTS_CORE_ROADMAP.md D1: cancels the item at `index` (0 = the front,
# currently-ticking item), refunding exactly what's been drawn so far
# (total_cost - remaining_cost) - not the full price, matching OpenRA. A
# freshly-queued, untouched item refunds its full cost since nothing's been
# spent yet; a build stalled 90% of the way through only gets that 90% back.
func cancel(team: int, tier: String, index: int) -> Dictionary:
	var q = get_queue(team, tier)
	if index < 0 or index >= q.size():
		return {}
	var job = q[index]
	var refund_metal = int(round(job.total_cost_metal - job.remaining_cost_metal))
	var refund_crystal = int(round(job.total_cost_crystal - job.remaining_cost_crystal))
	q.remove_at(index)
	if refund_metal > 0 or refund_crystal > 0:
		skirmish.add_resources(team, refund_metal, refund_crystal)
	return {"metal": refund_metal, "crystal": refund_crystal}

# RTS_CORE_ROADMAP.md D1: a manual pause (D2's right-click), distinct from
# the automatic pause-on-broke tick() already does on its own - only ever
# applies to the front item, matching the FIFO-front-only-ticks model
# everything else here already uses.
func set_paused(team: int, tier: String, paused: bool) -> void:
	var q = get_queue(team, tier)
	if q.is_empty(): return
	q[0].paused = paused

# Called every physics frame from skirmish.gd's _physics_process(). Only the
# front item per team+tier ticks (FIFO), matching the old per-building
# behavior. A dead building's job just keeps ticking here now (it used to
# freeze forever, since the old per-building _physics_process() returned
# early on is_dead) - if every factory of that tier dies before completion,
# the finished job has nowhere to spawn from and is silently dropped. A real
# refund-on-tier-loss is E3's job (RTS_CORE_ROADMAP.md), not this pass's.
func tick(delta: float):
	if not skirmish or skirmish.game_over: return
	# RTS_CORE_ROADMAP.md A2: debug_instant_build finishes the front job of
	# every queue on the next tick rather than skipping the timer entirely,
	# so spawn/legality/factory-death handling below all still run normally.
	var effective_delta = delta
	if "debug_instant_build" in skirmish and skirmish.debug_instant_build:
		effective_delta = 999999.0
	for team in queues.keys():
		for tier in TIERS:
			var q: Array = get_queue(team, tier)
			if q.is_empty(): continue
			var job = q[0]
			if job.get("paused", false): continue

			# RTS_CORE_ROADMAP.md D1: drip-fed cost, adapted from OpenRA's
			# ProductionItem.Tick (discrete ticks) to this project's
			# continuous delta-seconds. expected_remaining is computed off
			# the PROSPECTIVE new time_left (after this tick's time passes),
			# not the current one - "how much of the total cost SHOULD be
			# left once we reach that point in the build."
			var new_time_left = max(0.0, job.time_left - effective_delta)
			var expected_fraction = new_time_left / max(0.001, job.total_time)
			var expected_remaining_metal = job.total_cost_metal * expected_fraction
			var expected_remaining_crystal = job.total_cost_crystal * expected_fraction
			var draw_metal = int(round(max(0.0, job.remaining_cost_metal - expected_remaining_metal)))
			var draw_crystal = int(round(max(0.0, job.remaining_cost_crystal - expected_remaining_crystal)))
			if not skirmish.spend(team, draw_metal, draw_crystal):
				continue # NO progress this tick - pause, not a slowdown; time_left/remaining_cost both stay exactly where they were
			job.remaining_cost_metal -= draw_metal
			job.remaining_cost_crystal -= draw_crystal
			job.time_left = new_time_left

			if job.time_left <= 0.0:
				var factory = skirmish.get_team_factory(team, tier)
				# RTS_CORE_ROADMAP.md C4: OpenRA's blocked-exit handling -
				# a finished job stays `done` (time_left clamped at 0, not
				# popped) and retries next tick if something's sitting on
				# the exit, instead of spawning a new unit on top of it.
				# Blockers get a real nudge (notify_blocker) rather than
				# just being silently phased through.
				if factory and is_instance_valid(factory) and factory.has_method("get_exit_blockers"):
					var blockers = factory.get_exit_blockers()
					if not blockers.is_empty():
						job.time_left = 0.0
						var exit_pos = factory.get_exit_position()
						for u in blockers:
							if u.has_method("notify_blocker"):
								u.notify_blocker(exit_pos)
						continue
				q.pop_front()
				if factory and is_instance_valid(factory):
					factory.spawn_from_queue(job.blueprint)
					if team == skirmish._local_team() and skirmish.get_node_or_null("/root/AudioManager"):
						skirmish.get_node("/root/AudioManager").play_sfx("construct")
