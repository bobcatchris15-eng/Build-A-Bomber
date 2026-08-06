class_name Order
extends RefCounted
# An order is DATA. It carries what was asked for and nothing about how to do it.
#
# WHY THIS IS A TYPE AND NOT THREE VARIABLES ON THE UNIT. The old runtime spread
# intent across `order: OrderType`, `move_target: Vector3`, `attack_target:
# Node3D`, `harvest_node: Node3D` and `harvest_timer` as parallel fields on
# battle_unit.gd (battle_unit.gd:121-133). Anything could write any of them, in
# any combination, and several combinations were meaningless - an ATTACK with a
# stale move_target, a HARVEST whose node had been depleted two orders ago. There
# was also nowhere to put a SECOND order, which is why shift-queueing never
# existed: there was no object to put in a list.
#
# Making intent one immutable-ish value fixes both. A unit holds a current Order
# and a queue of pending ones; shift-queueing is `append` and cancelling is
# `clear`. OrderService is the only thing that constructs these.
#
# FORMATION SLOTS RIDE ALONG. `position` is where THIS unit goes, already offset
# by FormationService - not the group's destination. Keeping the resolved
# position on the order rather than a (destination, offset) pair means the unit
# never needs to know it was part of a group, and a formation move replays
# identically if the order is re-issued.

enum Type {
	# No intent. Distinct from HOLD: an idle unit may auto-engage after a delay,
	# a holding one never leaves its post.
	IDLE,
	# Go to `position`. Inviolable - a unit under a move order finishes the move
	# even if it is shot at. This is Chris's standing rule from battle_unit.gd's
	# auto-engage comment (battle_unit.gd:145-154) and it survives the rewrite.
	MOVE,
	# Advance to `position`, but stop and engage anything hostile encountered on
	# the way, resuming once it is dead. The order every RTS needs and this one
	# never had - the only approximation was Ctrl+right-click attack-ground.
	ATTACK_MOVE,
	# Engage `target` until it dies, closing to weapon range as needed.
	ATTACK,
	# Fire on `position` regardless of whether anything is there. Suppression,
	# shelling a chokepoint you cannot see into, and placing smoke.
	ATTACK_GROUND,
	# Work `target` as a resource node, hauling to a refinery. Harvester only.
	HARVEST,
	# Stay put. Weapons stay free; the unit does not pursue.
	HOLD,
}

var type: Type = Type.IDLE
var position: Vector3 = Vector3.ZERO
var target: Node3D = null

# Set when this order came from a group command, purely so the HUD and the
# movement layer can tell "30 units were sent here together" from "30 units each
# happened to be sent here". FlowField keys its cache on this in Phase 1.
var group_id: int = 0

# Where the PLAYER clicked, as opposed to `position`, which is this unit's own
# formation slot near it.
#
# Both are needed and they are not interchangeable. The flow field is built for
# the clicked point and shared by the whole group, so a unit following the field
# has to know it; the slot is what the unit finally steers to on arrival. Keeping
# only the slot would mean a field per unit, which is the entire cost the field
# exists to avoid. Defaults to `position` for a single-unit order, where they
# genuinely are the same point.
var group_destination: Vector3 = Vector3.ZERO

# How far this unit was from `group_destination` WHEN THE ORDER WAS ISSUED.
#
# The flow field's minimum-trip gate has to ask "is this journey long enough to
# be worth one shared search", which is a property of the journey and therefore
# fixed at issue time. Asking the live remaining distance instead - which is what
# the gate did originally - gets the question wrong in a way that reintroduces
# exactly the hard switch the blend exists to remove: on a 200 m trip the field
# would vanish the instant the unit came within MIN_TRIP_DISTANCE, which is still
# well outside the blend band, so field influence dropped from full to nothing in
# one frame. Recording it once here makes field_weight() the only thing that
# governs the handover, and it ramps.
var trip_length: float = 0.0

static func move(to: Vector3, group: int = 0, group_to: Variant = null) -> Order:
	var o := Order.new()
	o.type = Type.MOVE
	o.position = to
	o.group_id = group
	o.group_destination = to if group_to == null else group_to
	return o

static func attack_move(to: Vector3, group: int = 0, group_to: Variant = null) -> Order:
	var o := Order.new()
	o.type = Type.ATTACK_MOVE
	o.position = to
	o.group_id = group
	o.group_destination = to if group_to == null else group_to
	return o

static func attack(what: Node3D) -> Order:
	var o := Order.new()
	o.type = Type.ATTACK
	o.target = what
	return o

static func attack_ground(where: Vector3) -> Order:
	var o := Order.new()
	o.type = Type.ATTACK_GROUND
	o.position = where
	return o

static func harvest(node: Node3D) -> Order:
	var o := Order.new()
	o.type = Type.HARVEST
	o.target = node
	return o

static func hold() -> Order:
	var o := Order.new()
	o.type = Type.HOLD
	return o

static func idle() -> Order:
	return Order.new()


# True when the order names a destination the unit has to travel to. Used by the
# movement layer to decide whether it has anything to do at all, and by
# FormationService to decide whether a slot offset is even meaningful.
func has_destination() -> bool:
	return type == Type.MOVE or type == Type.ATTACK_MOVE


# True when the order is finished and the unit should advance its queue. A target
# that has been freed counts as complete rather than as an error - the thing the
# order was about is gone, which is the same outcome as succeeding at it.
func is_complete(unit_position: Vector3, arrive_distance: float) -> bool:
	match type:
		Type.IDLE, Type.HOLD:
			return false
		Type.MOVE, Type.ATTACK_MOVE:
			return unit_position.distance_to(position) <= arrive_distance
		Type.ATTACK, Type.HARVEST:
			return not is_instance_valid(target)
		Type.ATTACK_GROUND:
			return false
	return false
