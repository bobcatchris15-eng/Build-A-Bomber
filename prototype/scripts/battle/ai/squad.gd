class_name Squad
extends RefCounted
# A group of units executing one intent. The AI's tactical layer.
#
# WHY A BEHAVIOUR TREE AND NOT MORE UTILITY SCORING. Utility is right for the
# commander, which compares unlike options - is another harvester worth more than
# another tank. A squad's job is a sequence with fallbacks: if hurt, retreat;
# else if a target is in reach, engage it; else advance. That is a priority
# selector, and expressing it as competing scores would obscure the ordering that
# IS the behaviour.
#
# WHAT THIS REPLACES. enemy_ai.gd's _launch_wave() ordered every live unit to
# attack the player HQ, on a timer, regardless of how many there were or what
# stood between. There was no notion of a group with a state, so there was
# nowhere to put "we are losing, pull back" - the AI could only ever commit.
#
# EVERY ORDER GOES THROUGH OrderService. Squads are the only thing on the AI side
# that touches it, and they use the same move/attack/attack_move vocabulary the
# player's mouse produces. An AI that could not express a command in the player's
# own grammar would be an AI the player cannot read.

const StanceScript = preload("res://scripts/battle/orders/stance.gd")

enum State {
	# Moving to the objective, engaging what it meets on the way.
	ADVANCING,
	# Committed to a specific target.
	ENGAGING,
	# Below the health floor, heading home.
	RETREATING,
	# Home, holding, healing. Rejoins when strong enough.
	REGROUPING,
}

# Fraction of the squad's starting health pool below which it breaks off. A squad
# that fights to the last unit trades badly: the survivors of a withdrawal are
# the core of the next push, and the old AI never had any.
const RETREAT_HEALTH_FRACTION := 0.4
# And the fraction it must recover to before committing again. The gap between
# the two is deliberate - equal thresholds make a squad oscillate at the boundary
# for the same reason the fog needed a hysteresis dead zone.
const REGROUP_HEALTH_FRACTION := 0.75

# How close to the objective counts as arrived.
const ARRIVE_DISTANCE := 12.0
# Re-issue orders no more often than this. Every re-issue rebuilds formation
# slots and restarts the flow field's trip, so spamming them each tick makes a
# squad stutter in place.
const ORDER_INTERVAL := 3.0

var team: int = 1
var state: State = State.ADVANCING
var units: Array = []
var objective: Vector3 = Vector3.ZERO
var rally: Vector3 = Vector3.ZERO

var _orders = null
var _world = null
var _order_timer: float = 0.0
var _peak_health: float = 0.0


func setup(world, orders, squad_team: int, squad_units: Array, rally_point: Vector3) -> void:
	_world = world
	_orders = orders
	team = squad_team
	units = squad_units
	rally = rally_point
	_peak_health = total_health()
	# Aggressive: a squad on the attack should take targets of opportunity. The
	# player's own units default to RETURN_FIRE, which is right for units you are
	# steering by hand and wrong for ones acting on their own.
	if _orders != null:
		_orders.set_stance(units, StanceScript.Kind.AGGRESSIVE)


func prune() -> void:
	var alive: Array = []
	for u in units:
		if is_instance_valid(u) and not u.is_dead:
			alive.append(u)
	units = alive


func is_spent() -> bool:
	return units.is_empty()


func total_health() -> float:
	var hp := 0.0
	for u in units:
		if is_instance_valid(u) and not u.is_dead:
			hp += u.hp
	return hp


# Take command of a new roster, keeping this squad's state.
#
# MUST be used instead of assigning `units` directly. The peak is what
# health_fraction() judges against, and a squad that gains three fresh tanks
# without raising it reads as fully healthy - clamped to 1.0 - while its original
# members are all nearly dead. That is the exact failure the peak exists to
# prevent, reintroduced by the convenience of a plain assignment.
func reinforce(new_units: Array) -> void:
	units = new_units
	_peak_health = maxf(_peak_health, total_health())


# Health as a fraction of the most this squad has ever had. Measured against the
# PEAK rather than against max_hp so reinforcing a squad raises the bar it is
# judged by, instead of a fresh unit masking that everyone else is nearly dead.
func health_fraction() -> float:
	if _peak_health <= 0.0:
		return 1.0
	return clampf(total_health() / _peak_health, 0.0, 1.0)


func centroid() -> Vector3:
	if units.is_empty():
		return rally
	var sum := Vector3.ZERO
	var n := 0
	for u in units:
		if is_instance_valid(u) and not u.is_dead:
			sum += u.global_position
			n += 1
	return rally if n == 0 else sum / float(n)


# --- The tree ----------------------------------------------------------------
#
# A priority selector, evaluated top to bottom. The ORDER is the behaviour:
# survival outranks engagement, engagement outranks advancing.

func tick(delta: float) -> void:
	prune()
	if is_spent():
		return
	_order_timer += delta

	var next := _evaluate()
	# A state change is always worth an order immediately; otherwise orders are
	# rate-limited, because re-issuing rebuilds formations and restarts the trip.
	var changed := next != state
	state = next
	if changed or _order_timer >= ORDER_INTERVAL:
		_order_timer = 0.0
		_act()


func _evaluate() -> State:
	var health := health_fraction()
	if state == State.REGROUPING:
		# Only rejoin once genuinely recovered - the gap to the retreat threshold
		# is what stops a squad bouncing in and out of the fight.
		return State.ADVANCING if health >= REGROUP_HEALTH_FRACTION else State.REGROUPING
	if health < RETREAT_HEALTH_FRACTION:
		return State.RETREATING
	if state == State.RETREATING:
		return State.REGROUPING if centroid().distance_to(rally) <= ARRIVE_DISTANCE \
			else State.RETREATING
	if _priority_target() != null:
		return State.ENGAGING
	return State.ADVANCING


func _act() -> void:
	if _orders == null:
		return
	match state:
		State.ADVANCING:
			# ATTACK-MOVE, not MOVE. A squad crossing the map should stop and fight
			# what it meets rather than driving past it to a point on the ground.
			_orders.attack_move(units, objective)
		State.ENGAGING:
			var target = _priority_target()
			if target != null:
				_orders.attack(units, target)
			else:
				_orders.attack_move(units, objective)
		State.RETREATING:
			_orders.move(units, rally)
		State.REGROUPING:
			_orders.move(units, rally)


# What the squad should shoot first.
#
# FOCUS FIRE IS THE POINT. Twelve units each picking their own nearest target
# spread damage across twelve health bars and kill nothing; the same twelve on
# one target remove a shooter from the fight. Everything below is about choosing
# that one target well.
#
# Production structures outrank units, and a wounded target outranks a healthy
# one at similar range - finishing something is worth more than starting
# something.
func _priority_target():
	if _world == null or units.is_empty():
		return null
	var from := centroid()
	var best = null
	var best_score := -INF
	var reach := _squad_reach()
	for c in _candidates(from, reach):
		var distance: float = from.distance_to(c.global_position)
		var score := -distance
		# Wounded things first, scaled so it can outweigh a modest distance
		# difference but never send the squad across the map.
		if "max_hp" in c and c.max_hp > 0.0:
			score += (1.0 - c.hp / c.max_hp) * 40.0
		if "kind" in c:
			score += 25.0
		if score > best_score:
			best_score = score
			best = c
	return best


func _candidates(from: Vector3, reach: float) -> Array:
	var out: Array = []
	if not _world.has_method("get_nearby_damageable"):
		return out
	for c in _world.get_nearby_damageable(from, reach):
		if not is_instance_valid(c) or c.is_dead:
			continue
		var other: int = c.get_meta("team") if c.has_meta("team") else -1
		if other == team or other < 0:
			continue
		# Fog applies to the AI exactly as it does to the player. An unscouted
		# target is not a target.
		if _world.has_method("is_visible_to_team") and not _world.is_visible_to_team(c, team):
			continue
		out.append(c)
	return out


# The squad engages within its own weapons' reach, not an arbitrary radius, so a
# long-range squad picks targets earlier than a brawling one.
func _squad_reach() -> float:
	var longest := 0.0
	for u in units:
		if is_instance_valid(u):
			longest = maxf(longest, u.attack_range)
	return maxf(longest, ARRIVE_DISTANCE) * 1.5
