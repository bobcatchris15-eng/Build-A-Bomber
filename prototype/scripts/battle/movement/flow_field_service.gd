class_name FlowFieldService
extends RefCounted
# Decides when a flow field is worth building, and keeps the ones that are.
#
# THE GATE MATTERS AS MUCH AS THE FIELD. A field is one search shared by many
# units; below a handful of units it is strictly more expensive than letting each
# one path for itself, because the search covers the whole reachable map rather
# than one corridor. So a field is built only for group moves at or above
# FIELD_MIN_UNITS, and everything else keeps its NavigationAgent3D.
#
# HOW IT COMPOSES WITH FORMATIONS. These look like they conflict - a field drives
# every unit to ONE destination, a formation gives every unit a DIFFERENT one -
# and resolving that is the whole design:
#
#   far from the destination : follow the field toward the group's clicked point
#   near it                  : steer directly to your own formation slot
#
# The field does the long haul, where all the units genuinely want to go the same
# way and the pathfinding cost is real. The slot does the arrival, where they
# want to spread out and the distances are short enough that direct steering is
# correct. The handover radius is HANDOVER_DISTANCE below.

const FlowFieldScript = preload("res://scripts/battle/movement/flow_field.gd")

# Below this, per-unit agents are cheaper and just as good.
const FIELD_MIN_UNITS := 8

# Distance from the group destination at which a unit is entirely on its own
# slot and ignoring the field.
const HANDOVER_DISTANCE := 28.0

# Over this band above HANDOVER_DISTANCE, field influence ramps from none to
# full. A HARD SWITCH WAS MEASURABLY WORSE THAN NO FIELD AT ALL, and the numbers
# are worth recording because the failure is counter-intuitive:
#
#   pure agents (field silently broken)  median 2.1 m from slot, 11/12 arrived
#   hard switch to a working field       median 49 m from slot,  3/12 arrived,
#                                        closest pair 0.90 m - stacked
#
# The reason is that a field gives every unit in a cell the IDENTICAL direction.
# That is the whole point when the goal is one point, and exactly wrong once
# formations have given each unit its own slot: the field collapses twelve
# distinct destinations back onto one line and they jam, with separation and the
# field pushing against each other in equilibrium.
#
# Blending keeps what the field is actually for - one search instead of N, and a
# route that already knows where the terrain is - while never letting it fully
# override the fact that these units are going to different places.
const BLEND_BAND := 45.0

# Below this trip length a field is not built at all. Its benefit is amortising
# one search across many units on a LONG haul; over a short hop the search covers
# the whole reachable map to save twelve corridor searches that were cheap
# anyway, and the convergence cost is paid for nothing.
const MIN_TRIP_DISTANCE := 90.0


# How much the field should govern, from 0 (entirely the unit's own slot) to 1
# (entirely the field), given how far the unit still is from the group's
# destination. Pure function so the ramp can be asserted directly.
static func field_weight(distance_to_group_destination: float) -> float:
	if distance_to_group_destination <= HANDOVER_DISTANCE:
		return 0.0
	return clampf((distance_to_group_destination - HANDOVER_DISTANCE) / BLEND_BAND, 0.0, 1.0)

# Fields are keyed on the destination snapped to this, so a dozen orders clicked
# at nearly the same spot share one field instead of building a dozen.
const KEY_SNAP := 8.0

# Cheap ceiling. Each field is a few hundred KB at most and they are only built
# on a group order, so this is really just a guard against a long match
# accumulating hundreds of stale ones.
const MAX_CACHED := 12

var _nav_map: RID
var _map_half_extents: float = 80.0
var _fields: Dictionary = {}
var _order: Array = []


func setup(nav_map: RID, map_half_extents: float) -> void:
	_nav_map = nav_map
	_map_half_extents = map_half_extents


static func should_use_field(unit_count: int) -> bool:
	return unit_count >= FIELD_MIN_UNITS


# The field for `destination`, building it if this is the first ask. Returns null
# when fields are switched off for this group size, so callers can treat "no
# field" and "small group" identically.
func field_for(destination: Vector3, unit_count: int, trip_distance: float = INF) -> FlowField:
	if not should_use_field(unit_count) or trip_distance < MIN_TRIP_DISTANCE:
		return null
	var key := _key(destination)
	if _fields.has(key):
		return _fields[key]

	var field: FlowField = FlowFieldScript.build(_nav_map, _map_half_extents, destination)
	_fields[key] = field
	_order.append(key)
	while _order.size() > MAX_CACHED:
		_fields.erase(_order.pop_front())
	return field


# Every cached field is invalidated when the navmesh changes - a building going
# up or coming down alters exactly the passability the fields were sampled from,
# and a stale field routes units straight through the new structure. Called from
# the same place that repaths live agents, for the same reason.
func invalidate() -> void:
	_fields.clear()
	_order.clear()


func _key(destination: Vector3) -> Vector2i:
	return Vector2i(
		int(round(destination.x / KEY_SNAP)),
		int(round(destination.z / KEY_SNAP)))
