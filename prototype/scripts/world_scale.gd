class_name WorldScale
# Single source of truth for the "environment scaled up, units untouched"
# miniature-scale pass (see CORE_DESIGN_LANGUAGE.md §3.2 once written).
#
# WHY UNITS DON'T MOVE: the intuitive implementation is shrinking units to
# a literal 1:16 scale inside today's maps. That is the one version the
# engine actively refuses - Recast voxel count scales as
# (extent / cell_size)^2, and terrain_builder.gd's own header records that
# cell_size 0.25 on a 480-unit map already bakes a 1920x1920 grid in
# ~1585ms, with an outright segfault past a further threshold. A unit
# shrunk to ~0.4m would need a cell size around 0.06 to stay resolvable -
# roughly 256x the voxels of a setting already measured as unshippable.
#
# So instead the ENVIRONMENT (terrain extents, greebles, texel density,
# derived grids) is multiplied by this factor, and units/blueprints/combat
# math are left exactly as they are. Same picture, same 16x more
# battlefield in unit-lengths, no navmesh/physics precision cliff.
#
# Phase 1-2 of this pass (see the plan) wired every consumer of this class
# in its OWN commit before this default ever moved off 1.0, so "did the
# refactor break it" and "did the new scale break it" stayed two separate
# bisects. This is that flip: 4.0 is the proving ground before 16.0 (the
# real target) - it exercises every path at a scale the existing non-
# streamed navmesh/flow-field/vision bakers can still survive, so Phase 3's
# streaming work starts from a known-good baseline instead of debugging
# scale bugs and streaming bugs at once. See the plan's Chunk 19/25.
const DEFAULT_WORLD_SCALE: float = 4.0

# Per-map override key. Cheap insurance for outlier maps - scattered_peaks
# at 550 half-extent becomes 8800 at a flat 16x, which may end up wanting
# its own smaller number rather than inheriting the global default.
const MAP_SCALE_KEY: String = "world_scale"

# Returns the world scale that should apply to map_def - the map's own
# "world_scale" field if it declared one, otherwise DEFAULT_WORLD_SCALE.
# Takes the already-decoded map dictionary (or {} / null for "no map
# context", which just returns the default) rather than a map_id, so
# callers that already have the dict in hand (the common case - nearly
# every caller in terrain_builder.gd/match_director.gd works off map_def,
# not map_id) don't need an extra MapCatalog round-trip.
static func for_map(map_def) -> float:
	if map_def is Dictionary and map_def.has(MAP_SCALE_KEY):
		var v = map_def[MAP_SCALE_KEY]
		if (v is float or v is int) and v > 0.0:
			return float(v)
	return DEFAULT_WORLD_SCALE

static func scaled_f(value: float, map_def = null) -> float:
	return value * for_map(map_def)
