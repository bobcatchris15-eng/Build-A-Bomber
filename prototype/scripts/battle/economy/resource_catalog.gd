class_name ResourceCatalog
extends RefCounted
# The gatherable resources, what they are worth, and how they sit on the map.
#
# ONE POOL. Chris's direction, 2026-08-07: several gathered resource types all
# funnelling into a single "credits" pool the player spends. `credits` below is
# the exchange rate for each, and is the single source of truth for what a unit
# of anything is worth - on the way in from a field, and on the way out as the
# price of a design.
#
# THE FOUR TYPES DIFFER BY VALUE DENSITY AND BY WHERE THEY SIT - not by needing
# special gatherers or special buildings. Any harvester can work any field. The
# decision the player makes is where to send trucks, not what to build to reach
# it:
#
#   lumber   cheap, close to base, regrows fastest. The safe opening income.
#   ore      the staple. Middling value, middling distance.
#   crystal  scarcer and further out.
#   oil      the prize. Neutral wells, few and scattered, worth contesting.

# `metal` is the historical id for ore and every bundled map still uses it, so it
# is an alias rather than a rename - a map file that says "metal" keeps working.
const ALIASES := {"metal": "ore"}

const TYPES := {
	"lumber": {
		"label": "LUMBER",
		"credits": 1.0,
		"color": Color(0.36, 0.52, 0.24),
		# Collectibles per field, and how far they scatter from the centre. A
		# forest stand is many small trees close together.
		"field_nodes": 9,
		"field_radius": 11.0,
		# Seconds to respawn one depleted collectible. Lumber regrows fastest -
		# it is the resource you can rely on without holding ground.
		"respawn_seconds": 20.0,
	},
	"ore": {
		"label": "ORE",
		"credits": 1.5,
		"color": Color(0.9, 0.75, 0.5),
		"field_nodes": 7,
		"field_radius": 9.0,
		"respawn_seconds": 35.0,
	},
	"crystal": {
		"label": "CRYSTAL",
		"credits": 3.0,
		"color": Color(0.5, 0.85, 1.0),
		"field_nodes": 5,
		"field_radius": 8.0,
		"respawn_seconds": 50.0,
	},
	"oil": {
		"label": "OIL",
		"credits": 4.0,
		"color": Color(0.14, 0.13, 0.16),
		# A well is a single point, not a field - that is what makes it
		# contestable ground rather than an area you spread out over.
		"field_nodes": 1,
		"field_radius": 0.0,
		"respawn_seconds": 25.0,
	},
}

const FALLBACK := "ore"


# Resolves aliases. Every lookup goes through here so "metal" and "ore" can never
# diverge into two half-supported spellings.
static func canonical(type_id: String) -> String:
	var id := str(type_id)
	if ALIASES.has(id):
		return str(ALIASES[id])
	return id if TYPES.has(id) else FALLBACK


static func get_data(type_id: String) -> Dictionary:
	return TYPES[canonical(type_id)]


static func ids() -> Array:
	return TYPES.keys()


static func label(type_id: String) -> String:
	return str(get_data(type_id)["label"])


static func color(type_id: String) -> Color:
	return get_data(type_id)["color"]


static func credits(type_id: String) -> float:
	return float(get_data(type_id)["credits"])


# What a hopper of `type_id` is worth at the refinery door.
static func deliver_credits(type_id: String, amount: int) -> int:
	return int(round(float(amount) * credits(type_id)))


# --- Costs -------------------------------------------------------------------
#
# What a unit of crystal is worth in credits. This IS the old build-cost
# weighting - build_time_for_cost() was `metal + 2 * crystal` long before any of
# this - promoted from an implicit constant buried in a time formula to the
# actual exchange rate of the economy.
#
# THE CATALOG STILL AUTHORS COSTS AS METAL AND CRYSTAL, deliberately. Those two
# numbers carry design intent a single figure would flatten: crystal is the
# "advanced" material and the module tweaks lean on that - optic_power scales
# crystal 1.60x against metal 1.20x, which is what makes the anti-materiel rifle
# the roster's most crystal-hungry non-energy weapon. Converting the DATA would
# throw that authoring signal away.
#
# Converting at the till keeps it, and delivers exactly what Chris asked for:
# advanced technology drives up your price per unit, instead of gating you on a
# resource the map may not even offer.
const CRYSTAL_TO_CREDITS := 2.0


# The one place materials become money.
static func credits_from_materials(materials: Vector2i) -> int:
	return int(round(float(materials.x) + float(materials.y) * CRYSTAL_TO_CREDITS))


static func field_nodes(type_id: String) -> int:
	return int(get_data(type_id)["field_nodes"])


static func field_radius(type_id: String) -> float:
	return float(get_data(type_id)["field_radius"])


static func respawn_seconds(type_id: String) -> float:
	return float(get_data(type_id)["respawn_seconds"])
