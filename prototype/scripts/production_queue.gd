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

# queues[team][tier] = Array of {blueprint: Dictionary, time_left: float, total_time: float}
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
# Returns {"queued": bool, "error": "no_factory"|"illegal"|"cant_afford"|"",
# "reason": <human string, only set for "illegal">, "tier": String} so a
# caller can surface a real status message without re-deriving why it failed.
func enqueue(team: int, blueprint: Dictionary, faction: String, cost_metal: int, cost_crystal: int) -> Dictionary:
	var hull_type = blueprint.get("hull_type", "medium_hull")
	var tier = ModuleCatalog.get_hull_size_tier(hull_type)
	if not skirmish.has_factory_of_tier(team, tier):
		return {"queued": false, "error": "no_factory", "reason": "", "tier": tier}
	var legality = ModuleCatalog.validate_build_legality(blueprint)
	if not legality.valid:
		return {"queued": false, "error": "illegal", "reason": legality.reason, "tier": tier}
	if not skirmish.can_afford(team, cost_metal, cost_crystal):
		return {"queued": false, "error": "cant_afford", "reason": "", "tier": tier}
	skirmish.spend(team, cost_metal, cost_crystal)
	var build_time = skirmish.build_time_for_cost(Vector2i(cost_metal, cost_crystal))
	build_time *= FactionCatalog.get_passive(faction, "build_time_mult", 1.0)
	if skirmish.is_energy_deficit(team):
		build_time *= 1.5
	get_queue(team, tier).append({"blueprint": blueprint, "time_left": build_time, "total_time": build_time})
	if team == skirmish._local_team() and skirmish.get_node_or_null("/root/AudioManager"):
		skirmish.get_node("/root/AudioManager").play_sfx("click")
	return {"queued": true, "error": "", "reason": "", "tier": tier}

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
			job.time_left -= effective_delta
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
