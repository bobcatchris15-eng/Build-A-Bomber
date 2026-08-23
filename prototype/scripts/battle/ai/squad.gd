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
const MicroScript = preload("res://scripts/battle/ai/micro.gd")
# SquadManager owns the SquadRole enum (MBG, RAIDER, BASE_GUARD, SCOUT). Pulled
# in here so the role checks below name the role rather than a magic int —
# reordering the enum would silently flip Scout and Base Guard on the same line.
const SquadManagerScript = preload("res://scripts/battle/ai/squad_manager.gd")

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

# Fraction of the squad's starting health pool below which it breaks off.
const RETREAT_HEALTH_FRACTION := 0.4
# And the fraction it must recover to before committing again.
const REGROUP_HEALTH_FRACTION := 0.75

# How close to the objective counts as arrived.
const ARRIVE_DISTANCE := 12.0
# Re-issue orders no more often than this.
const ORDER_INTERVAL := 3.0

var team: int = 1
var state: State = State.ADVANCING
var units: Array = []
var objective: Vector3 = Vector3.ZERO
var rally: Vector3 = Vector3.ZERO
var role: int = 0  # SquadManager.SquadRole (0: MBG, 1: RAIDER, 2: BASE_GUARD, 3: SCOUT)

var _orders = null
var _world = null
var _order_timer: float = 0.0
var _peak_health: float = 0.0


func set_role(squad_role: int) -> void:
	role = squad_role


func setup(world, orders, squad_team: int, squad_units: Array, rally_point: Vector3) -> void:
	_world = world
	_orders = orders
	team = squad_team
	units = squad_units
	rally = rally_point
	_peak_health = total_health()
	# RETURN_FIRE is the squad baseline: a squad that scatters after every
	# passing target is worse than one that needs to be told to attack. The
	# previous hardcoded AGGRESSIVE here was the entire reason a RETREATING
	# squad would break formation to chase something at 3x weapon range -
	# `pursuit_range_multiplier(AGGRESSIVE) = 3.0` is the chassis that drove
	# the failure, and it stays out of the squad unless `_act()` explicitly
	# turns it on for ADVANCING / ENGAGING.
	if _orders != null:
		_orders.set_stance(units, StanceScript.Kind.RETURN_FIRE)


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
	# Scout role: flees on contact, never commits to engagement
	if role == SquadManagerScript.SquadRole.SCOUT:
		var candidates: Array = _candidates(centroid(), 35.0)
		if not candidates.is_empty():
			return State.RETREATING
		return State.ADVANCING

	# Raider role: breaks off earlier at 60% health
	var retreat_thresh: float = 0.6 if role == SquadManagerScript.SquadRole.RAIDER else RETREAT_HEALTH_FRACTION

	if state == State.REGROUPING:
		return State.ADVANCING if health >= REGROUP_HEALTH_FRACTION else State.REGROUPING
	if health < retreat_thresh:
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
			# AGGRESSIVE on the way to the objective: targets of opportunity
			# are exactly what the squad should pick up on the way in.
			_orders.set_stance(units, StanceScript.Kind.AGGRESSIVE)
			_orders.attack_move(units, objective)
		State.ENGAGING:
			_orders.set_stance(units, StanceScript.Kind.AGGRESSIVE)
			var target = _priority_target()
			if target != null:
				# Apply per-unit tactical micro behaviors
				for u in units:
					if not is_instance_valid(u) or u.is_dead:
						continue
					var micro_decision: Dictionary = MicroScript.evaluate(u, target, units, _world)
					var m_type: String = micro_decision.get("type", "close")
					# The micro decision names its OWN target. Peel needs this:
					# a brawler that broke off to save an artillery piece must
					# shoot the threat to that piece, not the squad's priority
					# target. Defaulting to the squad target keeps "close" and
					# the no-decision path honest.
					var micro_target: Node3D = micro_decision.get("target", target)
					if m_type in ["kite", "flank"] and micro_decision.has("position"):
						# Kite wants a plain MOVE: ATTACK_MOVE engages anything
						# in the way, which defeats the whole point of backing up
						# to maintain a range advantage. Flank keeps attack_move
						# because the unit is moving into a side arc, not
						# retreating - engagements on the way are fine.
						if m_type == "kite":
							_orders.move([u], micro_decision["position"])
						else:
							_orders.attack_move([u], micro_decision["position"])
					else:
						_orders.attack([u], micro_target)
			else:
				_orders.attack_move(units, objective)
		State.RETREATING:
			# RETURN_FIRE keeps the squad's guns live for whatever is on its
			# tail but caps the chase at 1.25x weapon range, so a retreating
			# squad does not break formation to run down a flanking scout
			# (which is what AGGRESSIVE's 3.0x multiplier would have caused).
			_orders.set_stance(units, StanceScript.Kind.RETURN_FIRE)
			_orders.move(units, rally)
		State.REGROUPING:
			_orders.set_stance(units, StanceScript.Kind.RETURN_FIRE)
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
