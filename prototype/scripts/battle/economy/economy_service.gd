class_name EconomyService
extends RefCounted
# The per-team ledger: metal, crystal, and base power.
#
# WHY IT IS ITS OWN OBJECT. In the old runtime the ledger was three dictionaries
# and eleven methods on skirmish.gd, interleaved with fog of war and the minimap.
# Anything that wanted to know whether a team could afford something had to hold
# a reference to the whole match controller, so the production queue took
# `skirmish` as a constructor argument and called back into it - which is why
# production could not be tested without building a match.
#
# BASE POWER IS NOT VEHICLE ENERGY. These are two separate resources and
# conflating them was a real bug in the old runtime (fixed 2026-07-18, and worth
# not reintroducing): base power comes from the HQ and power plants and gates
# production speed; a vehicle's own energy comes from generator modules mounted
# on that vehicle and powers its own energy weapons. A generator on a tank must
# never feed the base - "put a fusion_generator on a tank so your factories build
# faster, then lose the tank and lose the base's power" is not a mechanic anyone
# designed.

signal resources_changed(team: int)

# RA's own low_power_modifier: 300 means a build takes three times as long, i.e.
# progress runs at a third rate. Low and Critical are identical for production,
# so one boolean covers both.
const LOW_POWER_MODIFIER := 300.0

# Baseline capacity every HQ provides, before any power plant.
const HQ_BASELINE_CAPACITY := 16.0
# What each live static structure draws.
const UPKEEP_PER_STRUCTURE := 3.0

var _ledger: Dictionary = {}


func add_team(team: int, metal: int = 0, crystal: int = 0) -> void:
	_ledger[team] = {
		"metal": metal,
		"crystal": crystal,
		"capacity": 0.0,
		"draw": 0.0,
	}


func has_team(team: int) -> bool:
	return _ledger.has(team)


func metal(team: int) -> int:
	return _ledger.get(team, {}).get("metal", 0)


func crystal(team: int) -> int:
	return _ledger.get(team, {}).get("crystal", 0)


func can_afford(team: int, cost_metal: int, cost_crystal: int) -> bool:
	if not _ledger.has(team):
		return false
	return _ledger[team].metal >= cost_metal and _ledger[team].crystal >= cost_crystal


# Deducts only if the whole cost is available. A partial spend would let a team
# go into negative on one resource while the other covered it, which the drip-fed
# production model would then compound every tick.
func spend(team: int, cost_metal: int, cost_crystal: int) -> bool:
	if cost_metal <= 0 and cost_crystal <= 0:
		return true
	if not can_afford(team, cost_metal, cost_crystal):
		return false
	_ledger[team].metal -= cost_metal
	_ledger[team].crystal -= cost_crystal
	resources_changed.emit(team)
	return true


func credit(team: int, add_metal: int, add_crystal: int) -> void:
	if not _ledger.has(team):
		return
	_ledger[team].metal += add_metal
	_ledger[team].crystal += add_crystal
	resources_changed.emit(team)


# --- Power ------------------------------------------------------------------

# Recomputed from the live structure list rather than adjusted incrementally on
# every construction and death. Incremental bookkeeping needs every add and every
# remove to fire exactly once, and a single missed death leaves a team
# permanently powered by a building that no longer exists.
func recalculate_power(team: int, structures: Array) -> void:
	if not _ledger.has(team):
		return
	var capacity := 0.0
	var draw := 0.0
	for s in structures:
		if not is_instance_valid(s) or s.is_dead or s.team != team:
			continue
		if s.kind == "hq":
			capacity += HQ_BASELINE_CAPACITY
		capacity += BuildingCatalog.get_stat(s.kind, "energy_capacity", 0.0)
		draw += UPKEEP_PER_STRUCTURE
	_ledger[team].capacity = capacity
	_ledger[team].draw = draw


func power_capacity(team: int) -> float:
	return _ledger.get(team, {}).get("capacity", 0.0)


func power_draw(team: int) -> float:
	return _ledger.get(team, {}).get("draw", 0.0)


func is_low_power(team: int) -> bool:
	return power_draw(team) > power_capacity(team)


# How much of a tick's delta actually counts toward production for this team.
# Live rather than baked in at queue time, so recovering power speeds an
# in-progress build back up - OpenRA's real tick-skip, not a one-shot multiplier.
func production_rate(team: int) -> float:
	return (100.0 / LOW_POWER_MODIFIER) if is_low_power(team) else 1.0
