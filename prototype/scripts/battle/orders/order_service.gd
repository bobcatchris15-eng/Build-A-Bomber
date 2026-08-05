class_name OrderService
extends RefCounted
# The ONLY thing that writes unit intent.
#
# WHY A CHOKEPOINT. In the old runtime anything could assign to a unit's `order`
# field - the input handler, the auto-engage timer, the harvester loop, the enemy
# AI, and the wave launcher, all writing the same five loose variables from five
# files. Nothing could be added centrally because there was no centre: shift-
# queueing, formations and group ids each would have had to be re-implemented at
# every write site, so none of them were implemented at all.
#
# Routing every command through here means:
#   * formations apply to every group move, including the AI's
#   * shift-queueing is one branch, not five
#   * the AI is bound to the same command vocabulary the player has, which is
#     what stops it from cheating by construction rather than by discipline
#
# It holds no state beyond the group counter, so it is safe to call from anywhere
# and cheap to construct in a test.

const FormationScript = preload("res://scripts/battle/orders/formation_service.gd")
const OrderScript = preload("res://scripts/battle/orders/order.gd")
const StanceScript = preload("res://scripts/battle/orders/stance.gd")

# Group moves get formation slots; anything at or below this goes to the exact
# point asked for. One or two units spreading into a "formation" reads as the
# game ignoring the click.
const FORMATION_MIN_UNITS := 3

var _next_group_id: int = 1


# Send `units` to `destination`, spread across a formation.
#
# `queued` appends instead of replacing, which is the shift-click behaviour that
# was impossible before orders were a type - there was no object to put in a list.
func move(units: Array, destination: Vector3, queued: bool = false) -> int:
	return _destination_order(units, destination, queued, false)


# Advance to `destination`, engaging anything hostile met on the way.
func attack_move(units: Array, destination: Vector3, queued: bool = false) -> int:
	return _destination_order(units, destination, queued, true)


func _destination_order(units: Array, destination: Vector3, queued: bool, aggressive: bool) -> int:
	var live := _live(units)
	if live.is_empty():
		return 0

	var group := _next_group_id
	_next_group_id += 1

	var targets: Array = []
	if live.size() >= FORMATION_MIN_UNITS:
		var positions: Array = []
		for u in live:
			positions.append(u.global_position)
		targets = FormationScript.destinations_for(positions, destination, _spacing_for(live))
	else:
		for _u in live:
			targets.append(destination)

	for i in range(live.size()):
		# The clicked point rides along beside the slot so the movement layer can
		# follow a shared flow field for the journey and switch to the slot for
		# the arrival - see flow_field_service.gd for why that split exists.
		var order: Order = OrderScript.attack_move(targets[i], group, destination) if aggressive \
			else OrderScript.move(targets[i], group, destination)
		_give(live[i], order, queued)
	return group


func attack(units: Array, target: Node3D, queued: bool = false) -> void:
	if not is_instance_valid(target):
		return
	for u in _live(units):
		_give(u, OrderScript.attack(target), queued)


func attack_ground(units: Array, where: Vector3, queued: bool = false) -> void:
	for u in _live(units):
		_give(u, OrderScript.attack_ground(where), queued)


func harvest(units: Array, node: Node3D, queued: bool = false) -> void:
	if not is_instance_valid(node):
		return
	for u in _live(units):
		# Only harvesters can work a node. Silently skipping a combat unit is
		# right here: right-clicking an ore patch with a mixed selection should
		# send the trucks to work, not reject the whole order.
		if u.get("is_harvester"):
			_give(u, OrderScript.harvest(node), queued)


# Cancel everything and stand still. Distinct from HOLD: stop clears the queue
# but leaves the stance alone.
func stop(units: Array) -> void:
	for u in _live(units):
		u.order_queue.clear()
		u.current_order = null


func hold(units: Array) -> void:
	for u in _live(units):
		u.order_queue.clear()
		u.current_order = OrderScript.hold()
		u.stance = StanceScript.Kind.HOLD_POSITION


func set_stance(units: Array, kind: int) -> void:
	for u in _live(units):
		u.stance = kind


func _give(unit, order: Order, queued: bool) -> void:
	if queued and unit.current_order != null:
		unit.order_queue.append(order)
	else:
		unit.order_queue.clear()
		unit.current_order = order


func _live(units: Array) -> Array:
	var out: Array = []
	for u in units:
		if is_instance_valid(u) and not u.is_dead:
			out.append(u)
	return out


# Formation spacing from the widest unit in the group, so a column of super-heavy
# hulls does not get the spacing of a scout and spawn its ranks inside each other.
func _spacing_for(units: Array) -> float:
	var widest := 0.0
	for u in units:
		var proxy: Node = u.get_node_or_null("SelectionProxy")
		if proxy == null:
			continue
		var shape: CollisionShape3D = proxy.get_child(0) if proxy.get_child_count() > 0 else null
		if shape and shape.shape is BoxShape3D:
			var size: Vector3 = shape.shape.size
			widest = maxf(widest, maxf(size.x, size.z))
	if widest <= 0.0:
		return FormationScript.DEFAULT_SPACING
	# Half again the widest hull: enough that neighbours are not touching, tight
	# enough that a formation still reads as one body.
	return widest * 1.5
