class_name ResourceCatalog
extends RefCounted
# The gatherable resources, what they are worth, and how they sit on the map.
#
# WHERE THIS IS GOING. Chris's direction, 2026-08-07: several resource types that
# all funnel into a single "credits" pool the player spends. The `credits` value
# below IS that number and is already the single source of truth for what a unit
# of each resource is worth.
#
# WHERE IT IS TODAY. The economy still has two pools, metal and crystal, so each
# resource declares which one it pays into via `pool`. That mapping is
# SCAFFOLDING and is the only thing the credits pass has to delete - every other
# consumer already reads `credits`. Chris chose to prototype the fields first and
# convert to credits after, accepting exactly this temporary home.
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
		"pool": "metal",
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
		"pool": "metal",
		"color": Color(0.9, 0.75, 0.5),
		"field_nodes": 7,
		"field_radius": 9.0,
		"respawn_seconds": 35.0,
	},
	"crystal": {
		"label": "CRYSTAL",
		"credits": 3.0,
		"pool": "crystal",
		"color": Color(0.5, 0.85, 1.0),
		"field_nodes": 5,
		"field_radius": 8.0,
		"respawn_seconds": 50.0,
	},
	"oil": {
		"label": "OIL",
		"credits": 4.0,
		"pool": "metal",
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


# Which of the two current pools this resource pays into, and how much. Cargo is
# counted in RAW UNITS and converted here, so a truck full of oil is worth far
# more than a truck full of lumber without the hopper needing to know why.
#
# THE ONE FUNCTION THE CREDITS PASS REPLACES: it becomes
# `credits(type) * amount` into a single pool and every caller stays as it is.
static func deliver_value(type_id: String, amount: int) -> Vector2i:
	var data := get_data(type_id)
	var value: float = float(amount) * float(data["credits"])
	if str(data["pool"]) == "crystal":
		# HALVED ON THE WAY INTO THE CRYSTAL POOL, and this is not a fudge.
		#
		# Build costs weight crystal at 2x metal (build_time_for_cost is
		# `metal + 2*crystal`), so a unit of crystal already buys twice what a
		# unit of metal does. Paying `amount * credits` into that pool would apply
		# the value multiplier TWICE, which is exactly what happened when this was
		# first written: measured income leapt to 76 cost-units/s against a 32
		# target, two thirds of it phantom.
		#
		# Dividing by the pool's own weighting makes one credit worth one
		# cost-unit whatever it was gathered as, so the intermediate two-pool
		# economy already behaves like the credits economy it is becoming - and
		# the balance target stays a single honest number across the transition.
		return Vector2i(0, int(round(value / 2.0)))
	return Vector2i(int(round(value)), 0)


static func field_nodes(type_id: String) -> int:
	return int(get_data(type_id)["field_nodes"])


static func field_radius(type_id: String) -> float:
	return float(get_data(type_id)["field_radius"])


static func respawn_seconds(type_id: String) -> float:
	return float(get_data(type_id)["respawn_seconds"])
