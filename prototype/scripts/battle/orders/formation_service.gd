class_name FormationService
extends RefCounted
# Turns "these 20 units go there" into 20 distinct destinations.
#
# THE PROBLEM IT SOLVES. The old runtime issued every selected unit the same
# Vector3, so a group order meant twenty units converging on one point, arriving,
# and then shoving each other off it forever - each one inside its neighbour's
# arrival radius, none able to stop. Formations are usually described as a
# presentation feature. They are not: they are what makes a group order have a
# well-defined answer at all.
#
# EVERYTHING HERE IS PURE. Positions in, positions out, no nodes. Headless Godot
# cannot drive a real drag-select, so this has to be assertable directly.
#
# CO-ORDINATE CONVENTION. Slots are built in formation-local space as Vector2:
#   x = RIGHT of the direction of travel
#   y = ALONG the direction of travel, NEGATIVE being behind the destination
# so the front rank sits on the destination and the rest trail back toward where
# the group came from. Marching the front rank past the ordered point to make
# room behind it would overshoot the thing the player actually clicked on.

# Group sizes at which the shape changes. A handful of units abreast reads as a
# deliberate line; the same line with thirty units is a wall wider than most
# chokepoints, so it folds into a box.
const LINE_MAX := 4
const WEDGE_MAX := 12

# Fallback spacing when the caller does not measure its units. Roughly a medium
# hull plus clearance.
const DEFAULT_SPACING := 4.5


# Slot offsets in formation-local space, front rank first.
#
# The ordering is load-bearing: assign() pairs sorted units against slots in
# THIS order, so index 0 must be the slot nearest the enemy/destination and the
# list must run front-to-back, left-to-right within a rank.
static func build_slots(count: int, spacing: float = DEFAULT_SPACING) -> Array:
	if count <= 0:
		return []
	if count == 1:
		# A single unit goes exactly where it was told. No offset, or a lone unit
		# would refuse to stand on the point the player clicked.
		return [Vector2.ZERO]
	if count <= LINE_MAX:
		return _line_slots(count, spacing)
	if count <= WEDGE_MAX:
		return _wedge_slots(count, spacing)
	return _box_slots(count, spacing)


# Abreast, centred on the destination.
static func _line_slots(count: int, spacing: float) -> Array:
	var slots: Array = []
	var half := (float(count) - 1.0) * 0.5
	for i in range(count):
		slots.append(Vector2((float(i) - half) * spacing, 0.0))
	return slots


# A V with its apex on the destination, arms trailing back. Each successive pair
# sits one rank further back and one column wider, which is what makes it read as
# a wedge rather than as a triangle of loose units.
static func _wedge_slots(count: int, spacing: float) -> Array:
	var slots: Array = [Vector2.ZERO]
	var rank := 1
	while slots.size() < count:
		var back := -float(rank) * spacing * 0.75
		var out := float(rank) * spacing * 0.85
		slots.append(Vector2(-out, back))
		if slots.size() < count:
			slots.append(Vector2(out, back))
		rank += 1
	return slots


# A rectangle, as close to square as the count allows, with the front rank on the
# destination. Ranks fill left-to-right so assign()'s pairing stays stable.
static func _box_slots(count: int, spacing: float) -> Array:
	var columns := int(ceil(sqrt(float(count))))
	var slots: Array = []
	var half := (float(columns) - 1.0) * 0.5
	var index := 0
	while index < count:
		var row := int(index / columns)
		var col := index % columns
		slots.append(Vector2((float(col) - half) * spacing, -float(row) * spacing))
		index += 1
	return slots


# Rotates local slots into the world, around `destination`, facing `yaw`.
#
# `yaw` is the direction the formation FACES, normally the heading the group
# travelled in to get there - so a group ordered north arrives facing north with
# its ranks running east-west, rather than in whatever orientation it set off in.
static func to_world(local_slots: Array, destination: Vector3, yaw: float) -> Array:
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	# Right-hand perpendicular of forward on the XZ plane.
	var right := Vector3(forward.z, 0.0, -forward.x)
	var out: Array = []
	for s in local_slots:
		out.append(destination + right * s.x + forward * s.y)
	return out


# Pairs units to slots without crossings, returning slot index per unit (parallel
# to `unit_positions`).
#
# WHY NOT NEAREST-SLOT-PER-UNIT. The obvious greedy pass - walk the units, give
# each its closest free slot - produces crossed paths whenever two units are
# closer to each other's slot than to their own, and crossing paths in a group
# move is exactly the shoving the formation was supposed to prevent.
#
# Instead both lists are sorted in the SAME frame (along the direction of travel,
# then across it) and paired in order. A unit on the left of the group gets a slot
# on the left; a unit already at the front gets a front slot. It is not the
# optimal assignment - that would be Hungarian, O(n^3), for a difference nobody
# can see - but it is monotone, which is the property that actually matters.
static func assign(unit_positions: Array, world_slots: Array, yaw: float) -> Array:
	var n: int = mini(unit_positions.size(), world_slots.size())
	if n <= 0:
		return []

	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(forward.z, 0.0, -forward.x)

	var units := _ranked(unit_positions, forward, right)
	var slots := _ranked(world_slots, forward, right)

	var result: Array = []
	result.resize(unit_positions.size())
	result.fill(-1)
	for i in range(n):
		result[units[i]] = slots[i]
	return result


# Indices of `points`, sorted along `forward` (furthest ahead first) then across
# by `right`. The quantisation on the forward axis is what keeps a rank together:
# without it, two units in the same rank a few centimetres apart sort into
# different ranks and the across-axis ordering stops meaning anything.
static func _ranked(points: Array, forward: Vector3, right: Vector3) -> Array:
	var keyed: Array = []
	for i in range(points.size()):
		var p: Vector3 = points[i]
		keyed.append({
			"i": i,
			"f": snappedf(p.dot(forward), 2.0),
			"r": p.dot(right),
		})
	keyed.sort_custom(func(a, b):
		if not is_equal_approx(a["f"], b["f"]):
			return a["f"] > b["f"]
		return a["r"] < b["r"])
	var out: Array = []
	for k in keyed:
		out.append(k["i"])
	return out


# The whole job in one call: where should each of these units actually go?
#
# Returns a world position per unit, parallel to `unit_positions`. The facing is
# derived from the group's own centroid rather than passed in, because the
# direction the group is travelling IS the direction it should arrive facing, and
# making the caller compute that invites two call sites to disagree.
static func destinations_for(unit_positions: Array, destination: Vector3,
		spacing: float = DEFAULT_SPACING) -> Array:
	if unit_positions.is_empty():
		return []
	if unit_positions.size() == 1:
		return [destination]

	var centroid := Vector3.ZERO
	for p in unit_positions:
		centroid += p
	centroid /= float(unit_positions.size())

	var travel := destination - centroid
	travel.y = 0.0
	# A group ordered onto its own centroid has no travel direction to speak of.
	# Keep the existing world axes rather than deriving a yaw from noise.
	var yaw := 0.0 if travel.length_squared() < 0.01 else atan2(-travel.x, -travel.z)

	var slots := to_world(build_slots(unit_positions.size(), spacing), destination, yaw)
	var pairing := assign(unit_positions, slots, yaw)

	var out: Array = []
	for i in range(unit_positions.size()):
		var slot_index: int = pairing[i]
		out.append(slots[slot_index] if slot_index >= 0 else destination)
	return out
