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

	# Genuinely different play pattern from lake_crossing: no water, no
	# elevation, no obstacles - fully open, slightly tighter map (70 vs 80
	# half-extents) with resources pulled in closer to the center. Nothing
	# to detour around means fights happen in the open rather than being
	# funneled - a deliberately different pacing/tempo, not just a palette
	# swap.
	#
	# Terrain variety task: also the natural home for the 4 surface-speed-
	# multiplier zones (marsh/rocky/snow_mud/sand) - this map had zero
	# water/obstacles/elevation before, so there's real room out toward the
	# edges (|x|>=39) without disturbing the existing resource cluster
	# (which stays within |x|<=26) or either base. Positioned as two
	# diagonal pairs so the OVERALL arrangement is 180-degree point-
	# symmetric (matching this map's existing fairness convention) while
	# each player still has one of every terrain type within reach, not
	# just a mirrored copy of one type.
	"open_plains": {
		"name": "Open Plains",
		"description": "Fully open, no water or high ground - a tighter map with contested resources near the center, plus marsh/rocky/snow-mud/sand patches further out that reward the right locomotion choice. Fast, aggressive, few chokepoints to hide behind.",
		"map_half_extents": 70.0,
		"ground_color": Color(0.28, 0.26, 0.16),
		"water_areas": [],
		"obstacles": [],
		"elevation_zones": [],
		"surface_zones": [
			{"center": Vector3(48, 0, 30), "half_extents": Vector2(9, 9), "surface_type": "marsh"},
			{"center": Vector3(-48, 0, -30), "half_extents": Vector2(9, 9), "surface_type": "sand"},
			{"center": Vector3(-48, 0, 30), "half_extents": Vector2(9, 9), "surface_type": "rocky"},
			{"center": Vector3(48, 0, -30), "half_extents": Vector2(9, 9), "surface_type": "snow_mud"},
		],
		"resource_nodes": [
			{"position": Vector3(-20, 0, 20), "type": "metal", "amount": 1100},
			{"position": Vector3(20, 0, -20), "type": "metal", "amount": 1100},
			{"position": Vector3(-26, 0, 8), "type": "metal", "amount": 900},
			{"position": Vector3(26, 0, -8), "type": "metal", "amount": 900},
			{"position": Vector3(-14, 0, -6), "type": "crystal", "amount": 700},
			{"position": Vector3(14, 0, 6), "type": "crystal", "amount": 700},
			{"position": Vector3(-8, 0, 14), "type": "metal", "amount": 800},
			{"position": Vector3(8, 0, -14), "type": "metal", "amount": 800},
			{"position": Vector3(0, 0, 0), "type": "crystal", "amount": 850},
		],
		"player_start": {
			"hq": Vector3(0, 0, 26), "factory": Vector3(-9, 0, 22), "refinery": Vector3(8, 0, 20),
			"harvester": Vector3(5, 0.5, 17),
		},
		"enemy_start": {
			"hq": Vector3(0, 0, -26), "factory": Vector3(9, 0, -22), "refinery": Vector3(-8, 0, -20),
			"harvester": Vector3(-5, 0.5, -17),
		},
	},

	# A third genuinely different play pattern: landlocked (no water at
	# all - the "some maps with no water" case), dominated by one large
	# contested hill dead center with rock walls flanking it on both
	# sides. The hill gets TWO elevation_zones sharing the same footprint
	# (one ramp each, north and south) rather than one zone with a single
	# ramp, so both teams get equally fair access to the high ground -
	# the schema only supports one ramp per zone entry, but nothing stops
	# two zones occupying the same footprint (the duplicate plateau-top
	# geometry is harmless, Recast just merges the coincident quads).
	# The rock walls aren't decoration - they narrow the map to two ~12-
	# unit lanes flanking the hill, so an army either fights through a
	# lane or commits to taking the hill itself.
	"highland_chokepoint": {
		"name": "Highland Chokepoint",
		"description": "A single dominant hill splits the map, flanked by rock walls that narrow the approach to two lanes. No water. Hold the hill for real vision and combat advantages, or fight through the flanks.",
		"map_half_extents": 75.0,
		"ground_color": Color(0.24, 0.24, 0.2),
		"water_areas": [],
		"obstacles": [
			{"center": Vector3(-28, 0, 0), "half_extents": Vector2(6, 22)},
			{"center": Vector3(28, 0, 0), "half_extents": Vector2(6, 22)},
		],
		"elevation_zones": [
			{"center": Vector3(0, 0, 0), "half_extents": Vector2(10, 10), "height": 8.0, "ramp_side": "south", "ramp_width": 8.0},
			{"center": Vector3(0, 0, 0), "half_extents": Vector2(10, 10), "height": 8.0, "ramp_side": "north", "ramp_width": 8.0},
		],
		"resource_nodes": [
			{"position": Vector3(-30, 0, 24), "type": "metal", "amount": 1100},
			{"position": Vector3(30, 0, -24), "type": "metal", "amount": 1100},
			{"position": Vector3(-20, 0, 30), "type": "metal", "amount": 900},
			{"position": Vector3(20, 0, -30), "type": "metal", "amount": 900},
			{"position": Vector3(-16, 0, 14), "type": "crystal", "amount": 700},
			{"position": Vector3(16, 0, -14), "type": "crystal", "amount": 700},
			{"position": Vector3(16, 0, 14), "type": "metal", "amount": 800},
			{"position": Vector3(-16, 0, -14), "type": "metal", "amount": 800},
		],
		# Pushed further back (z=~35-44) than the other maps' bases - the
		# hill's ramp footprint (including its grid-snap padding, see
		# terrain_builder.gd's RAMP_PAD) reaches out to about z=29, closer
		# to center than the raw ramp_width/height numbers alone would
		# suggest, and a base built ON a ramp is exactly what
		# is_position_blocked() exists to prevent.
		"player_start": {
			"hq": Vector3(0, 0, 40), "factory": Vector3(-10, 0, 36), "refinery": Vector3(9, 0, 34),
			"harvester": Vector3(6, 0.5, 31),
		},
		"enemy_start": {
			"hq": Vector3(0, 0, -40), "factory": Vector3(10, 0, -36), "refinery": Vector3(-9, 0, -34),
			"harvester": Vector3(-6, 0.5, -31),
		},
	},

	# The fourth genuinely different play pattern: coastal, not lake-
	# centric - water runs the full length of one edge (the east side)
	# rather than sitting in the middle, so naval units get a real
	# coastline to patrol instead of a landlocked pond, and ground combat
	# happens along a one-sided frontier rather than around a central
	# obstacle. Fairness comes from mirroring north/south (Z) rather than
	# the 180-degree point-symmetry the other maps use, since the map
	# itself isn't symmetric east-west (water only borders one side) -
	# both teams get equal distance to the same coastline and the same
	# obstacle layout, just facing each other across it. Also the
	# obstacle-densest of the four maps (3 rock clusters inland,
	# including one that sits on the direct HQ-to-HQ line) without going
	# as far as Highland Chokepoint's full corridor walls.
	"coastal_strand": {
		"name": "Coastal Strand",
		"description": "Water runs the full eastern coastline instead of sitting in the middle - naval units get real open water to work with, though the shallow shelf right at the shore keeps deep-draught cruisers further out. Rocky outcrops inland, including one squarely between the two bases.",
		"map_half_extents": 80.0,
		"ground_color": Color(0.26, 0.28, 0.22),
		"water_areas": [
			{"center": Vector3(55, 0, 0), "half_extents": Vector2(25, 80)},
		],
		# Terrain variety task: a shallow coastal shelf along the immediate
		# shoreline (the water zone's western edge, x=[30,40], nearest
		# land) - real bathymetry logic (shallow near shore, deep further
		# out). heavy_cruiser_hull (deep draught) is blocked from this
		# strip entirely and has to stay past x=40; small_boat_hull/
		# naval_hull/amphibious screw_drive can work right up to the beach.
		"shallow_water_areas": [
			{"center": Vector3(35, 0, 0), "half_extents": Vector2(5, 78)},
		],
		"obstacles": [
			{"center": Vector3(-18, 0, 30), "half_extents": Vector2(6, 6)},
			{"center": Vector3(-18, 0, -30), "half_extents": Vector2(6, 6)},
			{"center": Vector3(0, 0, 5), "half_extents": Vector2(7, 7)},
		],
		"elevation_zones": [],
		"resource_nodes": [
			{"position": Vector3(-30, 0, 24), "type": "metal", "amount": 1100},
			{"position": Vector3(-30, 0, -24), "type": "metal", "amount": 1100},
			{"position": Vector3(24, 0, 20), "type": "crystal", "amount": 700},
			{"position": Vector3(24, 0, -20), "type": "crystal", "amount": 700},
			{"position": Vector3(-15, 0, 45), "type": "metal", "amount": 900},
			{"position": Vector3(-15, 0, -45), "type": "metal", "amount": 900},
			{"position": Vector3(10, 0, 18), "type": "metal", "amount": 800},
			{"position": Vector3(10, 0, -18), "type": "metal", "amount": 800},
		],
		"player_start": {
			"hq": Vector3(0, 0, 32), "factory": Vector3(-9, 0, 28), "refinery": Vector3(8, 0, 26),
			"harvester": Vector3(5, 0.5, 23),
		},
		"enemy_start": {
			"hq": Vector3(0, 0, -32), "factory": Vector3(9, 0, -28), "refinery": Vector3(-8, 0, -26),
			"harvester": Vector3(-5, 0.5, -23),
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
