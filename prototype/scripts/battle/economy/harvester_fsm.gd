class_name HarvesterFSM
extends RefCounted
# The harvest loop as an explicit state machine, with bay reservation.
#
# WHAT WAS WRONG BEFORE. The old loop was `_process_harvest()`, forty lines
# inside battle_unit.gd's order switch (battle_unit.gd:1363). It had no states -
# it inferred what to do each tick from whether cargo was full and whether the
# node still existed - and, critically, no notion of a refinery having a finite
# number of places to stand. Every harvester steered at the refinery's ORIGIN. So
# four harvesters returning together all drove at the same point, arrived inside
# each other, and shoved. That is the jam.
#
# THE FIX IS THE RESERVATION, NOT THE STATES. A harvester claims a numbered bay
# BEFORE it sets off for home, and drives to that bay. If every bay is taken it
# enters QUEUED and orbits a holding point clear of the refinery until one frees
# up. Two harvesters can now never be routed to the same square metre.
#
# The states are what makes that expressible: "I have a reservation and am
# travelling to it" is a different thing from "I am waiting for one", and the old
# implementation had no way to say either.

const HARVEST_TIME := 3.0
const UNLOAD_TIME := 2.0
# How close counts as being at the node / at the bay.
const WORK_DISTANCE := 3.0
const DOCK_DISTANCE := 2.0
# Where a harvester with no bay waits. Far enough out that the orbit never
# obstructs the bays themselves, which would deadlock the queue it is waiting in.
const HOLDING_RADIUS := 14.0

enum State {
	# Nothing to do: look for a node.
	SEARCHING,
	MOVING_TO_NODE,
	HARVESTING,
	# Full, holding a bay reservation, driving to it.
	MOVING_TO_BAY,
	# Full, no bay free. Orbiting the refinery until one is.
	QUEUED,
	UNLOADING,
}

var state: State = State.SEARCHING
var node: Node3D = null
var refinery: Node3D = null
var bay_index: int = -1
# Which position on the ore patch's ring this harvester works from. Same idea as
# a dock bay: without it, every harvester on a patch steers at its exact origin
# and they stand inside each other.
var node_slot: int = -1
var cargo_metal: int = 0
var cargo_crystal: int = 0
var capacity: int = 50

var _timer: float = 0.0
var _orbit_phase: float = 0.0

var _unit: Node3D = null
var _world = null


func setup(unit: Node3D, world) -> void:
	_unit = unit
	_world = world


func cargo() -> int:
	return cargo_metal + cargo_crystal


func is_full() -> bool:
	return cargo() >= capacity


# Releases any held reservation. Called on death and on being given a manual
# order - a bay held by a harvester that is never coming back is a bay
# permanently removed from the economy, and three of those stop a refinery dead.
func release() -> void:
	if refinery != null and is_instance_valid(refinery) and bay_index >= 0:
		refinery.release_bay(_unit)
	bay_index = -1
	refinery = null


# Both ends of the round trip hold reservations, so both have to be given back.
func release_all() -> void:
	release()
	_release_node()


func _release_node() -> void:
	if node != null and _world != null and node_slot >= 0:
		_world.release_node_slot(node, _unit)
	node_slot = -1


func tick(delta: float) -> void:
	if _unit == null or _world == null:
		return
	match state:
		State.SEARCHING:
			_search()
		State.MOVING_TO_NODE:
			_move_to_node()
		State.HARVESTING:
			_harvest(delta)
		State.MOVING_TO_BAY:
			_move_to_bay()
		State.QUEUED:
			_wait_for_bay(delta)
		State.UNLOADING:
			_unload(delta)


func _search() -> void:
	# Carrying something with nowhere to put it? Go home first. A harvester that
	# spawns full, or whose node is depleted mid-load, must not wander off to
	# find another node while holding cargo it could bank right now.
	if cargo() > 0:
		_head_home()
		return
	node = _world.nearest_resource_node(_unit.global_position, _unit)
	if node == null:
		return
	node_slot = _world.claim_node_slot(node, _unit)
	state = State.MOVING_TO_NODE
	_unit.set_internal_destination(_work_position())


# Where this harvester stands to work, which is a point on the patch's ring
# rather than the patch itself.
func _work_position() -> Vector3:
	if _world == null or node == null:
		return Vector3.ZERO
	return _world.node_slot_position(node, node_slot)


func _move_to_node() -> void:
	if not is_instance_valid(node) or node.amount <= 0:
		# Mined out from under us by someone else while we were in transit.
		_release_node()
		state = State.SEARCHING
		return
	if _unit.global_position.distance_to(_work_position()) <= WORK_DISTANCE:
		_unit.halt()
		state = State.HARVESTING
		_timer = 0.0


func _harvest(delta: float) -> void:
	if not is_instance_valid(node) or node.amount <= 0:
		if cargo() > 0:
			_head_home()
		else:
			_release_node()
			_to_searching()
		return
	_timer += delta
	if _timer < HARVEST_TIME:
		return
	_timer = 0.0
	var take: int = mini(10, mini(node.amount, capacity - cargo()))
	if take <= 0:
		_head_home()
		return
	node.amount -= take
	if node.resource_type == "crystal":
		cargo_crystal += take
	else:
		cargo_metal += take
	if is_full():
		_head_home()


# Claim a bay before setting off. The reservation is the whole point: without it
# this is the old behaviour with extra steps.
func _head_home() -> void:
	# Give the ore patch back on the way out. A slot held by a truck that is
	# halfway across the map is a slot removed from the economy for the whole
	# round trip.
	_release_node()
	refinery = _world.nearest_refinery(_unit.global_position, _unit.team)
	if refinery == null:
		# Nowhere to deliver. Sit on the cargo rather than dumping it - a
		# refinery may well be under construction right now.
		_unit.halt()
		state = State.SEARCHING
		return
	bay_index = refinery.reserve_bay(_unit)
	if bay_index < 0:
		state = State.QUEUED
		_orbit_phase = 0.0
		return
	state = State.MOVING_TO_BAY
	_unit.set_internal_destination(refinery.bay_position(bay_index))


func _move_to_bay() -> void:
	if not is_instance_valid(refinery):
		# Blown up in transit. Find another one; the cargo survives.
		bay_index = -1
		refinery = null
		_head_home()
		return
	var bay: Vector3 = refinery.bay_position(bay_index)
	if _unit.global_position.distance_to(bay) <= DOCK_DISTANCE:
		_unit.halt()
		state = State.UNLOADING
		_timer = 0.0
	else:
		_unit.set_internal_destination(bay)


# Orbit a holding point rather than pressing against the refinery. Pressing is
# what turns a queue into a scrum: waiting harvesters block the bays that the
# docked ones need to leave by.
func _wait_for_bay(delta: float) -> void:
	if not is_instance_valid(refinery):
		refinery = null
		_head_home()
		return
	bay_index = refinery.reserve_bay(_unit)
	if bay_index >= 0:
		state = State.MOVING_TO_BAY
		_unit.set_internal_destination(refinery.bay_position(bay_index))
		return
	_orbit_phase += delta * 0.6
	var centre: Vector3 = refinery.global_position
	_unit.set_internal_destination(centre + Vector3(
		cos(_orbit_phase) * HOLDING_RADIUS, 0.0, sin(_orbit_phase) * HOLDING_RADIUS))


func _unload(delta: float) -> void:
	if not is_instance_valid(refinery):
		# Destroyed while we were unloading. Whatever is left in the hopper is
		# lost with it.
		cargo_metal = 0
		cargo_crystal = 0
		bay_index = -1
		refinery = null
		_to_searching()
		return
	_timer += delta
	if _timer < UNLOAD_TIME:
		return
	_world.deliver(_unit.team, cargo_metal, cargo_crystal)
	cargo_metal = 0
	cargo_crystal = 0
	release()
	_to_searching()


func _to_searching() -> void:
	_release_node()
	state = State.SEARCHING
	node = null
	_timer = 0.0


# --- Death ------------------------------------------------------------------

# A loaded harvester detonates. Classic C&C, and a real tactical layer: it makes
# economic harassment worth timing, because killing a full harvester inside an
# enemy base does collateral damage rather than just denying income.
#
# Scales with what it was carrying, so an empty one is merely a dead truck.
func death_explosion_damage() -> float:
	if capacity <= 0:
		return 0.0
	return 60.0 * (float(cargo()) / float(capacity))


func death_explosion_radius() -> float:
	if cargo() <= 0:
		return 0.0
	return 6.0
