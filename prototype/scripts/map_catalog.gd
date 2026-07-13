extends Node
class_name MapCatalog
# Skirmish map library (data-driven, same "plain static Dictionary" convention
# as module_catalog.gd - a MapDefinition Resource type would be more
# "properly Godot," but this codebase already leans on Dictionaries for every
# other piece of catalog/blueprint data, and staying consistent means new
# maps are trivially diffable/testable the same way new modules already are.
#
# Field shapes:
#   water_areas / obstacles: [{center: Vector3, half_extents: Vector2}, ...]
#     (rectangular XZ footprints, Y ignored - both are flat-ground features)
#   elevation_zones: [{center, half_extents, height, ramp_side, ramp_width}, ...]
#     a raised rectangular plateau with ONE ramp on the given side
#     ("north"/"south"/"east"/"west" = +Z/-Z/+X/-X ground-level approach).
#     Ramp run length is derived (TerrainBuilder.RAMP_RUN_PER_HEIGHT), not
#     authored per-zone, to keep map data terse and every ramp's slope angle
#     consistently walkable.
#   resource_nodes: [{position: Vector3, type: "metal"/"crystal", amount: int}, ...]
#   player_start / enemy_start: {hq, factory, refinery, harvester: Vector3}

const MAPS = {
	# The original (and only) map before this pass, kept byte-for-byte
	# identical to the old hardcoded skirmish.gd constants/spots so it stays
	# the default map and every pre-existing lake-geometry test keeps passing
	# unchanged. See DECISIONS_NEEDED.md for why this one was chosen as the
	# compatibility anchor rather than retrofitting the tests instead.
	"lake_crossing": {
		"name": "Lake Crossing",
		"description": "A single lake splits the map roughly in two - ground units detour around it, naval units are confined to it. No high ground.",
		"map_half_extents": 80.0,
		"ground_color": Color(0.2, 0.26, 0.21),
		"water_areas": [
			{"center": Vector3(18, 0, 0), "half_extents": Vector2(7, 7)},
		],
		"obstacles": [],
		"elevation_zones": [],
		"resource_nodes": [
			{"position": Vector3(-22, 0, 18), "type": "metal", "amount": 1200},
			{"position": Vector3(-28, 0, 12), "type": "metal", "amount": 1000},
			{"position": Vector3(22, 0, -18), "type": "metal", "amount": 1200},
			{"position": Vector3(28, 0, -12), "type": "metal", "amount": 1000},
			{"position": Vector3(0, 0, 0), "type": "crystal", "amount": 800},
			{"position": Vector3(-30, 0, -25), "type": "crystal", "amount": 700},
			{"position": Vector3(30, 0, 25), "type": "crystal", "amount": 700},
			{"position": Vector3(-5, 0, -8), "type": "metal", "amount": 900},
			{"position": Vector3(5, 0, 8), "type": "metal", "amount": 900},
		],
		"player_start": {
			"hq": Vector3(0, 0, 34), "factory": Vector3(-10, 0, 30), "refinery": Vector3(9, 0, 28),
			"harvester": Vector3(6, 0.5, 24),
		},
		"enemy_start": {
			"hq": Vector3(0, 0, -34), "factory": Vector3(10, 0, -30), "refinery": Vector3(-9, 0, -28),
			"harvester": Vector3(-6, 0.5, -24),
		},
	},
}

const DEFAULT_MAP_ID: String = "lake_crossing"

static func get_map_ids() -> Array:
	var ids = MAPS.keys()
	ids.sort()
	return ids

static func get_map(map_id: String) -> Dictionary:
	return MAPS.get(map_id, MAPS[DEFAULT_MAP_ID])

static func get_map_name(map_id: String) -> String:
	return get_map(map_id).get("name", map_id)
