class_name SquadManager
extends RefCounted
# Distributes combat units across multiple squads with distinct tactical roles.
#
# WHAT THIS REPLACES. The commander used to dump every combat unit into one
# monolithic squad that either advanced or retreated in lockstep. That gave the
# AI exactly one move (push) and exactly one counter (retreat), which reads as
# either brain-dead aggression or total passivity with nothing between.
#
# THE MODEL. Up to four squads, each with a role that determines its objective,
# composition preferences, and behavior thresholds:
#
#   MAIN_BATTLE_GROUP — the push force. Attacks the enemy HQ/objectives.
#   RAIDER            — fast units that harass economy (harvesters, refineries).
#   BASE_GUARD        — holds the home base. Defensive, never chases far.
#   SCOUT             — one expendable fast unit probing fog of war.
#
# EXPLOITABLE PATTERNS. Each role creates a readable behavior the player can
# learn and counter:
#   - MBG takes the direct path to the enemy HQ → set ambushes on the route
#   - Raider targets economy → build PD turrets at refineries
#   - Base Guard is static → bait it out, then hit the real target
#   - Scout takes predictable patrol routes → trap it or hide tech
#
# These are features, not bugs. An AI that is beatable by smart play is one
# whose patterns are readable. An AI with no patterns is one the player can
# only out-stat, which is the design this codebase exists to prevent.

const SquadScript = preload("res://scripts/battle/ai/squad.gd")
const ModuleCatalogScript = preload("res://scripts/module_catalog.gd")

enum SquadRole {
	MAIN_BATTLE_GROUP,
	RAIDER,
	BASE_GUARD,
	SCOUT,
}

# How many units the raider squad wants. More than this and the excess
# reinforces the MBG — raiders are a scalpel, not a second army.
const RAIDER_MAX_SIZE := 4
const RAIDER_MIN_SIZE := 2

# Base guard keeps this many units. Wounded MBG units rotate into it.
const BASE_GUARD_TARGET := 3

# Speed threshold (m/s) for a unit to qualify as "fast" (raider/scout material).
# Derived from the locomotion table: wheels top out at 15, hover at 16,
# tracked at 9. Anything above 11 is clearly meant to be mobile.
const FAST_SPEED_THRESHOLD := 11.0

# Below this number of total combat units, don't bother splitting into
# squads — just run one MBG. Splitting 3 units into 3 squads is worse
# than keeping them together.
const MIN_UNITS_TO_SPLIT := 5

var _squads: Dictionary = {}  # SquadRole -> Squad
var _world = null
var _orders = null
var _team: int = 1
var _rally: Vector3 = Vector3.ZERO
var _enemy_hq_pos: Vector3 = Vector3.ZERO
var _map_quadrants: Array = []  # For scout patrol
var _scout_quadrant_index: int = 0


func setup(world, orders, ai_team: int, rally_point: Vector3,
		enemy_hq: Vector3, map_bounds: Rect2 = Rect2()) -> void:
	_world = world
	_orders = orders
	_team = ai_team
	_rally = rally_point
	_enemy_hq_pos = enemy_hq

	# Build scout patrol quadrants from map bounds
	if map_bounds.size.length() > 0.0:
		var cx: float = map_bounds.position.x + map_bounds.size.x * 0.5
		var cy: float = map_bounds.position.y + map_bounds.size.y * 0.5
		_map_quadrants = [
			Vector3(map_bounds.position.x + map_bounds.size.x * 0.25, 0,
				map_bounds.position.y + map_bounds.size.y * 0.25),
			Vector3(map_bounds.position.x + map_bounds.size.x * 0.75, 0,
				map_bounds.position.y + map_bounds.size.y * 0.25),
			Vector3(map_bounds.position.x + map_bounds.size.x * 0.75, 0,
				map_bounds.position.y + map_bounds.size.y * 0.75),
			Vector3(map_bounds.position.x + map_bounds.size.x * 0.25, 0,
				map_bounds.position.y + map_bounds.size.y * 0.75),
		]
	else:
		_map_quadrants = [_enemy_hq_pos]


# --- Assignment ----------------------------------------------------------------
#
# Called when the AI gains new combat units (fresh from production or reinforced).
# Distributes them into squads based on role fitness.

func assign_units(all_combat_units: Array) -> void:
	if all_combat_units.size() < MIN_UNITS_TO_SPLIT:
		# Too few to split — everyone goes into MBG
		_ensure_squad(SquadRole.MAIN_BATTLE_GROUP, all_combat_units, _enemy_hq_pos)
		# Disband other squads
		for role in [SquadRole.RAIDER, SquadRole.BASE_GUARD, SquadRole.SCOUT]:
			if _squads.has(role):
				_squads.erase(role)
		return

	var fast_units: Array = []
	var slow_units: Array = []
	var all_units: Array = all_combat_units.duplicate()

	for u in all_units:
		if u is Dictionary:
			if u.get("is_dead", false):
				continue
		elif not is_instance_valid(u) or u.is_dead:
			continue
		if _is_fast_unit(u):
			fast_units.append(u)
		else:
			slow_units.append(u)

	# --- Scout: 1 fast unit ---
	var scout_unit = null
	if fast_units.size() > 0:
		# Pick the fastest unit for scouting
		var best_speed := 0.0
		var best_idx := 0
		for i in range(fast_units.size()):
			var spd: float = _unit_speed(fast_units[i])
			if spd > best_speed:
				best_speed = spd
				best_idx = i
		scout_unit = fast_units[best_idx]
		fast_units.remove_at(best_idx)

	# --- Raider: up to RAIDER_MAX_SIZE fast units ---
	var raider_units: Array = []
	while fast_units.size() > 0 and raider_units.size() < RAIDER_MAX_SIZE:
		raider_units.append(fast_units.pop_front())

	# Remaining fast units go to MBG
	var mbg_units: Array = slow_units.duplicate()
	mbg_units.append_array(fast_units)

	# --- Base Guard: peel off some units from MBG ---
	var guard_units: Array = []
	# Prefer wounded units for guard duty — they need time to repair/regroup
	mbg_units.sort_custom(func(a, b):
		var ha: float = float(a["hp"]) / float(a["max_hp"]) if a is Dictionary and a.get("max_hp", 0.0) > 0.0 else (a.hp / a.max_hp if "max_hp" in a and a.max_hp > 0.0 else 1.0)
		var hb: float = float(b["hp"]) / float(b["max_hp"]) if b is Dictionary and b.get("max_hp", 0.0) > 0.0 else (b.hp / b.max_hp if "max_hp" in b and b.max_hp > 0.0 else 1.0)
		return ha < hb)
	while guard_units.size() < BASE_GUARD_TARGET and mbg_units.size() > MIN_PUSH_SQUAD_SIZE():
		guard_units.append(mbg_units.pop_front())

	# --- Wire up squads ---
	if scout_unit != null:
		var scout_objective: Vector3 = _next_scout_target()
		_ensure_squad(SquadRole.SCOUT, [scout_unit], scout_objective)
	elif _squads.has(SquadRole.SCOUT):
		_squads.erase(SquadRole.SCOUT)

	if raider_units.size() >= RAIDER_MIN_SIZE:
		var raider_target: Vector3 = _find_raider_target()
		_ensure_squad(SquadRole.RAIDER, raider_units, raider_target)
	elif _squads.has(SquadRole.RAIDER):
		# Not enough raiders — fold them back into MBG
		for u in raider_units:
			mbg_units.append(u)
		_squads.erase(SquadRole.RAIDER)

	if not guard_units.is_empty():
		_ensure_squad(SquadRole.BASE_GUARD, guard_units, _rally)
	elif _squads.has(SquadRole.BASE_GUARD):
		_squads.erase(SquadRole.BASE_GUARD)

	_ensure_squad(SquadRole.MAIN_BATTLE_GROUP, mbg_units, _enemy_hq_pos)


# --- Tick (per-frame) ----------------------------------------------------------

func tick(delta: float) -> void:
	for role in _squads:
		var squad: Squad = _squads[role]
		squad.tick(delta)

	# Refresh scout target when it arrives
	if _squads.has(SquadRole.SCOUT):
		var scout: Squad = _squads[SquadRole.SCOUT]
		if not scout.is_spent() and scout.centroid().distance_to(scout.objective) < 15.0:
			scout.objective = _next_scout_target()


# --- Commander interface -------------------------------------------------------
#
# These methods let the commander issue high-level orders that the squad manager
# translates into per-squad commands.

func push(target: Vector3) -> void:
	if _squads.has(SquadRole.MAIN_BATTLE_GROUP):
		_squads[SquadRole.MAIN_BATTLE_GROUP].objective = target
		_squads[SquadRole.MAIN_BATTLE_GROUP].state = SquadScript.State.ADVANCING

func defend() -> void:
	# MBG returns to base
	if _squads.has(SquadRole.MAIN_BATTLE_GROUP):
		var mbg: Squad = _squads[SquadRole.MAIN_BATTLE_GROUP]
		mbg.objective = _rally
		mbg.state = SquadScript.State.RETREATING

func raid(target: Vector3) -> void:
	if _squads.has(SquadRole.RAIDER):
		_squads[SquadRole.RAIDER].objective = target

func get_squad(role: SquadRole) -> Squad:
	return _squads.get(role)

func get_all_squads() -> Dictionary:
	return _squads

func total_combat_strength() -> int:
	var n := 0
	for role in _squads:
		n += _squads[role].units.size()
	return n

func mbg_size() -> int:
	if _squads.has(SquadRole.MAIN_BATTLE_GROUP):
		return _squads[SquadRole.MAIN_BATTLE_GROUP].units.size()
	return 0


# --- Internals -----------------------------------------------------------------

func _ensure_squad(role: SquadRole, units: Array, objective: Vector3) -> void:
	if not _squads.has(role):
		var s := Squad.new()
		s.setup(_world, _orders, _team, units, _rally)
		s.objective = objective
		s.set_role(role)
		_squads[role] = s
	else:
		_squads[role].reinforce(units)
		_squads[role].objective = objective


func _is_fast_unit(unit) -> bool:
	return _unit_speed(unit) >= FAST_SPEED_THRESHOLD


func _unit_speed(unit) -> float:
	if unit is Dictionary:
		return float(unit.get("move_speed", unit.get("top_speed", 0.0)))
	if not is_instance_valid(unit):
		return 0.0
	# Units expose their computed top speed from Drivetrain
	if "move_speed" in unit:
		return float(unit.move_speed)
	if "top_speed" in unit:
		return float(unit.top_speed)
	return 0.0


func _next_scout_target() -> Vector3:
	if _map_quadrants.is_empty():
		return _enemy_hq_pos
	_scout_quadrant_index = (_scout_quadrant_index + 1) % _map_quadrants.size()
	return _map_quadrants[_scout_quadrant_index]


func _find_raider_target() -> Vector3:
	# Target enemy economy: refineries first, then harvesters, then HQ
	if _world == null:
		return _enemy_hq_pos
	var enemy_team := 0
	# Look for visible enemy structures (refineries)
	if _world.has_method("get_team_structures"):
		for s in _world.get_team_structures(enemy_team):
			if not is_instance_valid(s) or s.is_dead:
				continue
			if _world.has_method("is_visible_to_team") \
					and not _world.is_visible_to_team(s, _team):
				continue
			if s.kind == "refinery":
				return s.global_position
	# Look for visible enemy harvesters
	if _world.has_method("get_team_units"):
		for u in _world.get_team_units(enemy_team):
			if not is_instance_valid(u) or u.is_dead:
				continue
			if not u.is_harvester:
				continue
			if _world.has_method("is_visible_to_team") \
					and not _world.is_visible_to_team(u, _team):
				continue
			return u.global_position
	return _enemy_hq_pos


# Minimum MBG size before we peel units off for guard duty. Must leave enough
# to actually push. Uses MIN_PUSH_SQUAD from commander as the floor.
static func MIN_PUSH_SQUAD_SIZE() -> int:
	return 4
