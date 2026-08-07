class_name PlacementService
extends RefCounted
# Where a structure may legally go - for the player's ghost AND for the AI's
# siting, through one function.
#
# WHY THIS IS ONE FUNCTION AND NOT TWO. The old runtime got this right and it is
# worth not losing: skirmish.gd deliberately factored `_placement_validity_for()`
# out of the player's ghost so the AI could ask the identical question, and said
# so in a comment. The rebuilt battle layer had drifted off that - the AI sited
# through `_site_is_clear()`, which checked bounds, water and structure overlap
# and nothing else, while the player had no placement path at all. Adding one for
# the player separately would have produced two rule sets that agree until
# somebody edits one, which is the exact asymmetry the whole rebuild exists to
# remove.
#
# WHAT WAS BEING SKIPPED. BuildingCatalog already carries
# `gives_buildable_area`, `requires_buildable_area` and `adjacent_m` for every
# structure - ported faithfully from the old PREFAB_STATS and then read by
# nothing. So the AI could drop a power plant six rings out in open field, which
# no player would be allowed to do. The data was already here; only its enforcer
# was missing.
#
# NOT A NODE. It takes the world it is asking about, like ProductionService does,
# so placement legality can be asserted against a stub instead of a live match.

const BuildingCatalogScript = preload("res://scripts/battle/economy/building_catalog.gd")

# Clearance ON TOP of both footprints, so buildings never end up flush against
# each other with no lane between them for a unit to path down. Matches the
# director's own BUILDING_CLEARANCE doubling, which this replaces.
const CLEARANCE := 1.5

# How far inside the map edge a building must sit. A structure on the boundary is
# a structure whose dock bays and factory exit are off the navmesh - the same
# class of bug the refinery bays hit twice.
const EDGE_MARGIN := 12.0

# Resource nodes are not buildable ground. Walling a node in with a power plant
# would let a player deny an ore patch with a building, and it strands the
# harvesters already routed to it.
const NODE_EXCLUSION := 6.0

# Reasons, so the ghost can say WHY it is red rather than just being red. The
# old runtime's ghost gave no reason and "why can't I build here" was a question
# players had to guess at.
const OK := ""
const OUT_OF_BOUNDS := "OUTSIDE THE MAP"
const ON_WATER := "ON WATER"
const OVERLAPS := "TOO CLOSE TO A BUILDING"
const ON_RESOURCE := "ON A RESOURCE NODE"
const NOT_ADJACENT := "TOO FAR FROM YOUR BASE"


# The whole rule set, as one answer. `world` needs `current_map`,
# `terrain_height_at()` and the scene tree groups; that is the same narrow
# surface ProductionService takes.
#
# Returns {"valid": bool, "reason": String}.
static func validity(world, team: int, at: Vector3, kind: String,
		blueprint: Dictionary = {}) -> Dictionary:
	var footprint := footprint_for(kind, blueprint)
	var half: float = maxf(footprint.x, footprint.z) * 0.5

	var extent: float = world.current_map.get("map_half_extents", 80.0)
	if absf(at.x) > extent - EDGE_MARGIN or absf(at.z) > extent - EDGE_MARGIN:
		return _no(OUT_OF_BOUNDS)

	if TerrainBuilder.is_water_at(world.current_map, at.x, at.z):
		return _no(ON_WATER)

	# Explicitly typed, not inferred: `world` is duck-typed, so `:=` has nothing to
	# infer from and the file fails to parse.
	var tree: SceneTree = world.get_tree()

	for n in tree.get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(n):
			continue
		if at.distance_to(n.global_position) < half + NODE_EXCLUSION:
			return _no(ON_RESOURCE)

	# Adjacency is measured against structures that GIVE buildable area, and only
	# this team's - you may not build off the enemy's base. Checked before the
	# overlap loop reports success so the two reasons stay distinguishable.
	var near_base := not requires_area(kind, blueprint)
	var reach := adjacency_for(kind, blueprint)

	for s in tree.get_nodes_in_group("structures"):
		if not is_instance_valid(s) or s.is_dead or not s.is_inside_tree():
			continue
		var other_half: float = maxf(s.footprint.x, s.footprint.z) * 0.5
		var distance: float = at.distance_to(s.global_position)
		if distance < half + other_half + CLEARANCE * 2.0:
			return _no(OVERLAPS)
		# EDGE TO EDGE, counting BOTH footprints - the same way the overlap test
		# above measures. Measuring adjacency from the anchor's edge only made the
		# legal band the difference between two differently-derived numbers: a
		# power plant beside an HQ had to land between 8.75 m (overlap) and 11.5 m
		# (adjacency), a 2.75 m ring that is unusable with a ghost on a cursor and
		# which a larger building could close entirely.
		if not near_base and s.team == team \
				and BuildingCatalogScript.get_stat(s.kind, "gives_buildable_area", false) \
				and distance <= half + other_half + reach:
			near_base = true

	if not near_base:
		return _no(NOT_ADJACENT)
	return {"valid": true, "reason": OK}


static func _no(reason: String) -> Dictionary:
	return {"valid": false, "reason": reason}


# A defence design's footprint comes from its own foundation hull, not from the
# catalog - a bunker and a gun turret are both "defense" and are not the same
# size. Falls back to the catalog for prefab kinds.
static func footprint_for(kind: String, blueprint: Dictionary = {}) -> Vector3:
	if not blueprint.is_empty():
		var sc: Dictionary = blueprint.get("hull_scale", {"x": 1.0, "y": 1.0, "z": 1.0})
		var base := Vector3(5.0, 3.0, 5.0)
		return Vector3(base.x * float(sc.get("x", 1.0)), base.y * float(sc.get("y", 1.0)),
			base.z * float(sc.get("z", 1.0)))
	return BuildingCatalogScript.get_stat(kind, "size", Vector3(5, 3, 5))


static func requires_area(kind: String, blueprint: Dictionary = {}) -> bool:
	if not blueprint.is_empty():
		# A defence still has to connect to the base, just on a much longer leash -
		# picketing forward is the point of a turret.
		return true
	return BuildingCatalogScript.get_stat(kind, "requires_buildable_area", true)


static func adjacency_for(kind: String, blueprint: Dictionary = {}) -> float:
	if not blueprint.is_empty():
		return BuildingCatalogScript.DEFENSE_ADJACENT_M
	return BuildingCatalogScript.get_stat(kind, "adjacent_m",
		BuildingCatalogScript.DEFAULT_ADJACENT_M)


# --- Siting -------------------------------------------------------------------

# An outward ring search from `home` for the first legal spot, which is how the
# AI picks a site. A ring rather than a scatter so a base grows outward as a base
# instead of sprawling, and the first valid ring keeps new buildings close enough
# to defend together.
#
# It resolves through validity() above, so the AI is held to the player's rules -
# including the buildable-area adjacency it was previously ignoring.
const RING_STEP := 9.0
const RINGS := 8
const SAMPLES := 12


static func find_site(world, team: int, home: Vector3, kind: String,
		blueprint: Dictionary = {}) -> Vector3:
	for ring in range(1, RINGS + 1):
		var radius := RING_STEP * float(ring)
		for i in range(SAMPLES):
			var angle := TAU * float(i) / float(SAMPLES)
			var candidate := home + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			candidate.y = world.terrain_height_at(candidate)
			if validity(world, team, candidate, kind, blueprint)["valid"]:
				return candidate
	return Vector3.INF
