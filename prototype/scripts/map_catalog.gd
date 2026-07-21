extends Node
class_name MapCatalog
# Skirmish map library (data-driven, same "plain static Dictionary" convention
# as module_catalog.gd - a MapDefinition Resource type would be more
# "properly Godot," but this codebase already leans on Dictionaries for every
# other piece of catalog/blueprint data, and staying consistent means new
# maps are trivially diffable/testable the same way new modules already are.
#
# Field shapes:
#   water_areas: [{center: Vector3, half_extents: Vector2}, ...]
#     (rectangular XZ footprints, Y ignored - flat-ground features)
#   obstacles: [{center, half_extents, type: "rock"/"building", building_height (opt)}, ...]
#     "type" defaults to "rock" (a jumbled boulder cluster) if omitted;
#     "building" is a single boxy structure with a flat roof and window
#     greebles - both are equally real cover (StaticBody3D on collision
#     layer 1), which is what makes them block weapon LOS (auto_weapon.gd)
#     and vision LOS (TerrainBuilder/skirmish.gd's _has_line_of_sight())
#     alike, not just movement.
#   elevation_zones: [{center, half_extents, height, ramp_side, ramp_width}, ...]
#     a raised rectangular plateau with ONE ramp on the given side
#     ("north"/"south"/"east"/"west" = +Z/-Z/+X/-X ground-level approach).
#     Ramp run length is derived (TerrainBuilder.RAMP_RUN_PER_HEIGHT), not
#     authored per-zone, to keep map data terse and every ramp's slope angle
#     consistently walkable.
#   bridges: [{center, half_extents, deck_height (opt)}, ...]
#     a rectangular strip carved through a water_areas hole, walkable for
#     ground/legged locomotion ONLY (not naval/amphibious, which don't need
#     it - see TerrainBuilder._collect_bridges()) - flanked by water on
#     both sides that ISN'T carved, so it's a genuine narrow chokepoint, not
#     a way to remove the water. Deliberately does not block water_map/
#     deep_water_map - naval units still float and pass freely underneath,
#     same as a real bridge over a river. A bridge's footprint should
#     always fully span a water_areas rect along the crossing axis (so
#     there's dry land - or at least the water's edge - on both ends);
#     nothing enforces this automatically, it's a map-authoring convention.
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
		"map_half_extents": 240,
		"ground_color": Color(0.2, 0.26, 0.21),
		# Heightmap terrain pilot (Skirmish refinement pass): an organic
		# water_blob replaces the old rectangular water_areas entry - same
		# center/rough size as before, but a real irregular coastline
		# instead of a square lake. See terrain_builder.gd's height_at()
		# header comment for the full water_blobs schema.
		"water_blobs": [
			{"center": Vector3(54, 0, 0), "radius": 22, "irregularity": 0.3, "depth": 1.3, "shore_blend": 8},
		],
		"obstacles": [],
		"elevation_zones": [],
		"resource_nodes": [
			{"position": Vector3(-66, 0, 54), "type": "metal", "amount": 1200},
			{"position": Vector3(-84, 0, 36), "type": "metal", "amount": 1000},
			{"position": Vector3(66, 0, -54), "type": "metal", "amount": 1200},
			{"position": Vector3(84, 0, -36), "type": "metal", "amount": 1000},
			{"position": Vector3(0, 0, 0), "type": "crystal", "amount": 800},
			{"position": Vector3(-90, 0, -75), "type": "crystal", "amount": 700},
			{"position": Vector3(90, 0, 75), "type": "crystal", "amount": 700},
			{"position": Vector3(-15, 0, -24), "type": "metal", "amount": 900},
			{"position": Vector3(15, 0, 24), "type": "metal", "amount": 900},
		],
		"player_start": {
			"hq": Vector3(0, 0, 102), "factory": Vector3(-30, 0, 90), "refinery": Vector3(27, 0, 84),
			"harvester": Vector3(18, 1.5, 72),
		},
		"enemy_start": {
			"hq": Vector3(0, 0, -102), "factory": Vector3(30, 0, -90), "refinery": Vector3(-27, 0, -84),
			"harvester": Vector3(-18, 1.5, -72),
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
		"map_half_extents": 210,
		"ground_color": Color(0.28, 0.26, 0.16),
		"water_areas": [],
		"obstacles": [],
		"elevation_zones": [],
		"surface_zones": [
			{"center": Vector3(144, 0, 90), "half_extents": Vector2(27, 27), "surface_type": "marsh"},
			{"center": Vector3(-144, 0, -90), "half_extents": Vector2(27, 27), "surface_type": "sand"},
			{"center": Vector3(-144, 0, 90), "half_extents": Vector2(27, 27), "surface_type": "rocky"},
			{"center": Vector3(144, 0, -90), "half_extents": Vector2(27, 27), "surface_type": "snow_mud"},
		],
		"resource_nodes": [
			{"position": Vector3(-60, 0, 60), "type": "metal", "amount": 1100},
			{"position": Vector3(60, 0, -60), "type": "metal", "amount": 1100},
			{"position": Vector3(-78, 0, 24), "type": "metal", "amount": 900},
			{"position": Vector3(78, 0, -24), "type": "metal", "amount": 900},
			{"position": Vector3(-42, 0, -18), "type": "crystal", "amount": 700},
			{"position": Vector3(42, 0, 18), "type": "crystal", "amount": 700},
			{"position": Vector3(-24, 0, 42), "type": "metal", "amount": 800},
			{"position": Vector3(24, 0, -42), "type": "metal", "amount": 800},
			{"position": Vector3(0, 0, 0), "type": "crystal", "amount": 850},
		],
		"player_start": {
			"hq": Vector3(0, 0, 78), "factory": Vector3(-27, 0, 66), "refinery": Vector3(24, 0, 60),
			"harvester": Vector3(15, 1.5, 51),
		},
		"enemy_start": {
			"hq": Vector3(0, 0, -78), "factory": Vector3(27, 0, -66), "refinery": Vector3(-24, 0, -60),
			"harvester": Vector3(-15, 1.5, -51),
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
		"map_half_extents": 225,
		"ground_color": Color(0.24, 0.24, 0.2),
		"water_areas": [],
		"obstacles": [
			{"center": Vector3(-84, 0, 0), "half_extents": Vector2(18, 66)},
			{"center": Vector3(84, 0, 0), "half_extents": Vector2(18, 66)},
		],
		"elevation_zones": [
			{"center": Vector3(0, 0, 0), "half_extents": Vector2(30, 30), "height": 24, "ramp_side": "south", "ramp_width": 24},
			{"center": Vector3(0, 0, 0), "half_extents": Vector2(30, 30), "height": 24, "ramp_side": "north", "ramp_width": 24},
		],
		"resource_nodes": [
			{"position": Vector3(-90, 0, 72), "type": "metal", "amount": 1100},
			{"position": Vector3(90, 0, -72), "type": "metal", "amount": 1100},
			{"position": Vector3(-60, 0, 90), "type": "metal", "amount": 900},
			{"position": Vector3(60, 0, -90), "type": "metal", "amount": 900},
			{"position": Vector3(-48, 0, 42), "type": "crystal", "amount": 700},
			{"position": Vector3(48, 0, -42), "type": "crystal", "amount": 700},
			{"position": Vector3(48, 0, 42), "type": "metal", "amount": 800},
			{"position": Vector3(-48, 0, -42), "type": "metal", "amount": 800},
		],
		# Pushed further back (z=~35-44) than the other maps' bases - the
		# hill's ramp footprint (including its grid-snap padding, see
		# terrain_builder.gd's RAMP_PAD) reaches out to about z=29, closer
		# to center than the raw ramp_width/height numbers alone would
		# suggest, and a base built ON a ramp is exactly what
		# is_position_blocked() exists to prevent.
		"player_start": {
			"hq": Vector3(0, 0, 120), "factory": Vector3(-30, 0, 108), "refinery": Vector3(27, 0, 102),
			"harvester": Vector3(18, 1.5, 93),
		},
		"enemy_start": {
			"hq": Vector3(0, 0, -120), "factory": Vector3(30, 0, -108), "refinery": Vector3(-27, 0, -102),
			"harvester": Vector3(-18, 1.5, -93),
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
		"map_half_extents": 240,
		"ground_color": Color(0.26, 0.28, 0.22),
		"water_areas": [
			{"center": Vector3(165, 0, 0), "half_extents": Vector2(75, 240)},
		],
		# Terrain variety task: a shallow coastal shelf along the immediate
		# shoreline (the water zone's western edge, x=[30,40], nearest
		# land) - real bathymetry logic (shallow near shore, deep further
		# out). heavy_cruiser_hull (deep draught) is blocked from this
		# strip entirely and has to stay past x=40; small_boat_hull/
		# naval_hull/amphibious screw_drive can work right up to the beach.
		"shallow_water_areas": [
			{"center": Vector3(105, 0, 0), "half_extents": Vector2(15, 234)},
		],
		"obstacles": [
			{"center": Vector3(-54, 0, 90), "half_extents": Vector2(18, 18)},
			{"center": Vector3(-54, 0, -90), "half_extents": Vector2(18, 18)},
			{"center": Vector3(0, 0, 15), "half_extents": Vector2(21, 21)},
		],
		"elevation_zones": [],
		"resource_nodes": [
			{"position": Vector3(-90, 0, 72), "type": "metal", "amount": 1100},
			{"position": Vector3(-90, 0, -72), "type": "metal", "amount": 1100},
			{"position": Vector3(72, 0, 60), "type": "crystal", "amount": 700},
			{"position": Vector3(72, 0, -60), "type": "crystal", "amount": 700},
			{"position": Vector3(-45, 0, 135), "type": "metal", "amount": 900},
			{"position": Vector3(-45, 0, -135), "type": "metal", "amount": 900},
			{"position": Vector3(30, 0, 54), "type": "metal", "amount": 800},
			{"position": Vector3(30, 0, -54), "type": "metal", "amount": 800},
		],
		"player_start": {
			"hq": Vector3(0, 0, 96), "factory": Vector3(-27, 0, 84), "refinery": Vector3(24, 0, 78),
			"harvester": Vector3(15, 1.5, 69),
		},
		"enemy_start": {
			"hq": Vector3(0, 0, -96), "factory": Vector3(27, 0, -84), "refinery": Vector3(-24, 0, -78),
			"harvester": Vector3(-15, 1.5, -69),
		},
	},

	# Map variety batch: the LARGER map (100 vs the existing 70-80 range),
	# and the home for the new bridge mechanism. A river runs the map's
	# full width (edge to edge - no way around it at all) with exactly two
	# bridges carved through it, well apart from each other - a genuine
	# multi-lane bottleneck (fight for either crossing, or split forces
	# between both) rather than the single central chokepoint highland_
	# chokepoint already covers. Economy stays entirely on each side of the
	# river (no resource requires a crossing to reach), same convention
	# lake_crossing/coastal_strand already use - the bridges matter for
	# military movement, not harvesting.
	"twin_bridges": {
		"name": "Twin Bridges",
		"description": "A river spans the entire map with exactly two bridges crossing it, well apart - fight for one crossing or split your force across both. The largest map in the roster; resources stay on your own bank, but taking a bridge means taking the fight to the enemy's.",
		"map_half_extents": 300,
		"ground_color": Color(0.22, 0.25, 0.2),
		"water_areas": [
			{"center": Vector3(0, 0, 0), "half_extents": Vector2(300, 30)},
		],
		"bridges": [
			{"center": Vector3(-120, 0, 0), "half_extents": Vector2(21, 30)},
			{"center": Vector3(120, 0, 0), "half_extents": Vector2(21, 30)},
		],
		"obstacles": [],
		"elevation_zones": [],
		"resource_nodes": [
			{"position": Vector3(-75, 0, 180), "type": "metal", "amount": 1200},
			{"position": Vector3(75, 0, 180), "type": "metal", "amount": 1200},
			{"position": Vector3(-135, 0, 120), "type": "metal", "amount": 900},
			{"position": Vector3(135, 0, 120), "type": "metal", "amount": 900},
			{"position": Vector3(0, 0, 90), "type": "crystal", "amount": 800},
			{"position": Vector3(-45, 0, 225), "type": "crystal", "amount": 700},
			{"position": Vector3(45, 0, 225), "type": "crystal", "amount": 700},
			{"position": Vector3(75, 0, -180), "type": "metal", "amount": 1200},
			{"position": Vector3(-75, 0, -180), "type": "metal", "amount": 1200},
			{"position": Vector3(135, 0, -120), "type": "metal", "amount": 900},
			{"position": Vector3(-135, 0, -120), "type": "metal", "amount": 900},
			{"position": Vector3(0, 0, -90), "type": "crystal", "amount": 800},
			{"position": Vector3(45, 0, -225), "type": "crystal", "amount": 700},
			{"position": Vector3(-45, 0, -225), "type": "crystal", "amount": 700},
		],
		"player_start": {
			"hq": Vector3(0, 0, 240), "factory": Vector3(-36, 0, 222), "refinery": Vector3(30, 0, 216),
			"harvester": Vector3(18, 1.5, 198),
		},
		"enemy_start": {
			"hq": Vector3(0, 0, -240), "factory": Vector3(36, 0, -222), "refinery": Vector3(-30, 0, -216),
			"harvester": Vector3(-18, 1.5, -198),
		},
	},

	# Map variety batch: "two contested points" as its own genuinely
	# different pattern from highland_chokepoint's single dominant hill.
	# Rather than one hill both teams must equally fight over, this map
	# has TWO separate hills, each sitting closer to one team's own
	# territory - each team can grab their own quickly, but holding both
	# means pushing into the enemy's half. The overall layout stays
	# 180-degree point-symmetric (each hill's position/ramp direction
	# mirrors the other's under (x,z)->(-x,-z), same as every other
	# point-symmetric map here), so despite each individual hill being
	# off-center, the map as a whole is fair. No water. Single ramp per
	# hill (not highland's dual-ramp trick) facing the open central lane,
	# since a separate hill doesn't need to be equally approachable from
	# both the north AND south the way ONE shared hill does.
	"twin_summits": {
		"name": "Twin Summits",
		"description": "Two hills, not one - each sits closer to one side's own territory. Grab yours quickly, then decide whether to contest the other deep in enemy ground. No water; open lanes connect everything.",
		"map_half_extents": 234,
		"ground_color": Color(0.25, 0.24, 0.19),
		"water_areas": [],
		"obstacles": [],
		"elevation_zones": [
			{"center": Vector3(-84, 0, 54), "half_extents": Vector2(27, 27), "height": 21, "ramp_side": "east", "ramp_width": 24},
			{"center": Vector3(84, 0, -54), "half_extents": Vector2(27, 27), "height": 21, "ramp_side": "west", "ramp_width": 24},
		],
		"resource_nodes": [
			{"position": Vector3(-114, 0, 30), "type": "metal", "amount": 900},
			{"position": Vector3(-114, 0, 78), "type": "crystal", "amount": 700},
			{"position": Vector3(114, 0, -30), "type": "metal", "amount": 900},
			{"position": Vector3(114, 0, -78), "type": "crystal", "amount": 700},
			{"position": Vector3(-45, 0, 150), "type": "metal", "amount": 1100},
			{"position": Vector3(45, 0, 150), "type": "metal", "amount": 1100},
			{"position": Vector3(0, 0, 165), "type": "crystal", "amount": 800},
			{"position": Vector3(45, 0, -150), "type": "metal", "amount": 1100},
			{"position": Vector3(-45, 0, -150), "type": "metal", "amount": 1100},
			{"position": Vector3(0, 0, -165), "type": "crystal", "amount": 800},
		],
		"player_start": {
			"hq": Vector3(0, 0, 180), "factory": Vector3(-30, 0, 165), "refinery": Vector3(27, 0, 159),
			"harvester": Vector3(18, 1.5, 144),
		},
		"enemy_start": {
			"hq": Vector3(0, 0, -180), "factory": Vector3(30, 0, -165), "refinery": Vector3(-27, 0, -159),
			"harvester": Vector3(-18, 1.5, -144),
		},
	},

	# Map variety batch: the SMALLER map (45 vs the existing 70-100 range),
	# and a genuine 3-lane bottleneck - two parallel rock-wall obstacles
	# split the map into west/center/east corridors, distinct from
	# highland_chokepoint's 2-lane hill-flanking design (a hill in the
	# middle vs. two walls with three gaps). Deliberately sparse on
	# resources (7 nodes vs. the other maps' 9-14) - a tight, fast map is
	# about early aggression along 3 real chokepoints, not a long
	# economic buildup.
	"close_quarters": {
		"name": "Close Quarters",
		"description": "A tight, small map - two rock walls split it into three lanes (west/center/east). No room for a long buildup; whoever controls the lanes controls the fight. A single contested resource sits exactly at the map's center.",
		"map_half_extents": 135,
		"ground_color": Color(0.24, 0.22, 0.2),
		"water_areas": [],
		"obstacles": [
			{"center": Vector3(-36, 0, 0), "half_extents": Vector2(12, 54)},
			{"center": Vector3(36, 0, 0), "half_extents": Vector2(12, 54)},
		],
		"elevation_zones": [],
		"resource_nodes": [
			{"position": Vector3(-75, 0, 66), "type": "metal", "amount": 1000},
			{"position": Vector3(75, 0, 66), "type": "metal", "amount": 1000},
			{"position": Vector3(0, 0, 45), "type": "crystal", "amount": 700},
			{"position": Vector3(75, 0, -66), "type": "metal", "amount": 1000},
			{"position": Vector3(-75, 0, -66), "type": "metal", "amount": 1000},
			{"position": Vector3(0, 0, -45), "type": "crystal", "amount": 700},
			{"position": Vector3(0, 0, 0), "type": "crystal", "amount": 900},
		],
		"player_start": {
			"hq": Vector3(0, 0, 96), "factory": Vector3(-24, 0, 84), "refinery": Vector3(21, 0, 78),
			"harvester": Vector3(15, 1.5, 66),
		},
		"enemy_start": {
			"hq": Vector3(0, 0, -96), "factory": Vector3(24, 0, -84), "refinery": Vector3(-21, 0, -78),
			"harvester": Vector3(-15, 1.5, -66),
		},
	},

	# Map variety batch: the urban/city map. A loose street grid of
	# "building" obstacles (see terrain_builder.gd's _spawn_building_
	# obstacle()) fills the central band between the two bases - real
	# cover that blocks both movement (navmesh hole, same as any obstacle)
	# and sightlines (skirmish.gd's new _has_line_of_sight() raycast,
	# since buildings are StaticBody3D on the same collision layer 1 every
	# obstacle already uses). 10-unit streets between every building (>=
	# 2 grid cells, comfortable navmesh room) so the grid is a genuine
	# maze of corridors, not a solid unwalkable block. The center row
	# deliberately skips x=0 (an open plaza) so there's always at least
	# one direct lane through the middle, and a resource node sits in
	# that plaza specifically BECAUSE it's not visible from either base
	# past the surrounding buildings - has to be scouted/fought for, the
	# actual point of the sightline-blocking mechanic.
	"urban_sprawl": {
		"name": "Urban Sprawl",
		"description": "A city block grid fills the middle of the map - real buildings that block movement AND sightlines, not just decoration. Fight street to street; a contested resource sits in the central plaza, hidden from both bases until someone scouts it.",
		"map_half_extents": 204,
		"ground_color": Color(0.2, 0.2, 0.22),
		"water_areas": [],
		"elevation_zones": [],
		"obstacles": [
			{"center": Vector3(-60, 0, -60), "half_extents": Vector2(15, 15), "type": "building", "building_height": 6.0},
			{"center": Vector3(0, 0, -60), "half_extents": Vector2(15, 15), "type": "building", "building_height": 7.0},
			{"center": Vector3(60, 0, -60), "half_extents": Vector2(15, 15), "type": "building", "building_height": 5.0},
			{"center": Vector3(-60, 0, 0), "half_extents": Vector2(15, 15), "type": "building", "building_height": 8.0},
			{"center": Vector3(60, 0, 0), "half_extents": Vector2(15, 15), "type": "building", "building_height": 6.0},
			{"center": Vector3(-60, 0, 60), "half_extents": Vector2(15, 15), "type": "building", "building_height": 5.0},
			{"center": Vector3(0, 0, 60), "half_extents": Vector2(15, 15), "type": "building", "building_height": 7.0},
			{"center": Vector3(60, 0, 60), "half_extents": Vector2(15, 15), "type": "building", "building_height": 6.0},
		],
		"resource_nodes": [
			{"position": Vector3(-45, 0, 165), "type": "metal", "amount": 1100},
			{"position": Vector3(45, 0, 165), "type": "metal", "amount": 1100},
			{"position": Vector3(0, 0, 180), "type": "crystal", "amount": 800},
			{"position": Vector3(45, 0, -165), "type": "metal", "amount": 1100},
			{"position": Vector3(-45, 0, -165), "type": "metal", "amount": 1100},
			{"position": Vector3(0, 0, -180), "type": "crystal", "amount": 800},
			{"position": Vector3(0, 0, 0), "type": "crystal", "amount": 900},
		],
		"player_start": {
			"hq": Vector3(0, 0, 150), "factory": Vector3(-30, 0, 132), "refinery": Vector3(27, 0, 126),
			"harvester": Vector3(18, 1.5, 108),
		},
		"enemy_start": {
			"hq": Vector3(0, 0, -150), "factory": Vector3(30, 0, -132), "refinery": Vector3(-27, 0, -126),
			"harvester": Vector3(-18, 1.5, -108),
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
