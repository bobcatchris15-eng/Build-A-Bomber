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
# DELIBERATELY INERT AT 1.0. Every consumer of this class is wired in its
# own commit before the multiplier itself changes, so "did the refactor
# break it" and "did the new scale break it" stay two separate bisects.
const DEFAULT_WORLD_SCALE: float = 1.0

# Per-map override key. Cheap insurance for outlier maps - scattered_peaks
# at 550 half-extent becomes 8800 at a flat 16x, which may end up wanting
# its own smaller number rather than inheriting the global default.
const MAP_SCALE_KEY: String = "world_scale"

# Returns the world scale that should apply to map_def - the map's own
# "world_scale" field if it declared one, otherwise DEFAULT_WORLD_SCALE.
# Takes the already-decoded map dictionary (or {} / null for "no map
# context", which just returns the default) rather than a map_id, so
# callers that already have the dict in hand (the common case - nearly
# every caller in terrain_builder.gd/skirmish.gd/match_director.gd works
# off map_def, not map_id) don't need an extra MapCatalog round-trip.
static func for_map(map_def) -> float:
	if map_def is Dictionary and map_def.has(MAP_SCALE_KEY):
		var v = map_def[MAP_SCALE_KEY]
		if (v is float or v is int) and v > 0.0:
			return float(v)
	return DEFAULT_WORLD_SCALE

static func scaled_f(value: float, map_def = null) -> float:
	return value * for_map(map_def)

static func scaled_v2(value: Vector2, map_def = null) -> Vector2:
	return value * for_map(map_def)

static func scaled_v3(value: Vector3, map_def = null) -> Vector3:
	return value * for_map(map_def)
