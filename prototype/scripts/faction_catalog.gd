extends RefCounted
class_name FactionCatalog
# Single source of truth for all 10 factions: visual identity (paint color +
# wear/patina level, consumed by hull_material_builder.gd's shader and the
# UI brushed-aluminum theme) and mechanical passive bonuses (consumed by
# whichever gameplay system each bonus touches). Replaces the old pattern of
# scattered `if faction == "technocrats": ...` branches copy-pasted across
# battle_unit.gd/battlefield.gd/building.gd/skirmish.gd/stat_calculator.gd -
# every one of those now reads get_passive() instead, which is also what
# lets 7 new factions plug in without new branches anywhere.
#
# Passive keys (a faction only sets the ones it actually uses; get_passive()
# returns the given default for any key a faction doesn't set):
#   armor_weight_mult   - hull armor weight multiplier (Design Lab stat + real weight)
#   vision_mult         - unit/building vision_range multiplier
#   speed_mult          - unit move_speed multiplier
#   hp_mult             - unit max_hp multiplier
#   dps_mult            - weapon dps multiplier
#   range_mult          - weapon fire_range multiplier
#   harvest_rate_mult   - harvester per-tick extraction multiplier
#   build_time_mult     - factory build-time multiplier
#   metal_cost_mult     - roster build cost (metal) multiplier
#   energy_capacity_mult- team Energy pool capacity multiplier
#   energy_upkeep_exempt- bool, static buildings skip Energy upkeep entirely
#   hq_trickle_metal / hq_trickle_crystal - flat resources/tick regardless of captured nodes

const FACTIONS = {
	"industrialists": {
		"name": "Heavy Industrialists",
		"passive_summary": "-20% armor weight",
		"color": Color(0.62, 0.24, 0.09),
		"wear_color": Color(0.22, 0.18, 0.15),
		"wear_amount": 0.4,
		"armor_weight_mult": 0.8,
	},
	"technocrats": {
		"name": "Technocrats",
		"passive_summary": "+15% vision, +5% speed",
		"color": Color(0.12, 0.55, 0.78),
		"wear_color": Color(0.18, 0.26, 0.32),
		"wear_amount": 0.1,
		"vision_mult": 1.15,
		"speed_mult": 1.05,
	},
	"expansionists": {
		"name": "Expansionists",
		"passive_summary": "Static buildings exempt from Energy upkeep + slow HQ trickle",
		"color": Color(0.44, 0.46, 0.2),
		"wear_color": Color(0.24, 0.22, 0.15),
		"wear_amount": 0.3,
		"energy_upkeep_exempt": true,
		"hq_trickle_metal": 8,
		"hq_trickle_crystal": 2,
	},
	"scavengers": {
		"name": "Scavengers",
		"passive_summary": "-10% metal cost on everything built",
		"color": Color(0.45, 0.32, 0.16),
		"wear_color": Color(0.18, 0.16, 0.12),
		"wear_amount": 0.6,
		"metal_cost_mult": 0.9,
	},
	"zealots": {
		"name": "Zealots",
		"passive_summary": "+10% weapon DPS, -10% max HP",
		"color": Color(0.58, 0.04, 0.07),
		"wear_color": Color(0.14, 0.09, 0.09),
		"wear_amount": 0.08,
		"dps_mult": 1.1,
		"hp_mult": 0.9,
	},
	"nomads": {
		"name": "Nomads",
		"passive_summary": "+15% harvest rate",
		"color": Color(0.68, 0.56, 0.32),
		"wear_color": Color(0.28, 0.33, 0.3),
		"wear_amount": 0.35,
		"harvest_rate_mult": 1.15,
	},
	"cartel": {
		"name": "The Cartel",
		"passive_summary": "+8% weapon range",
		"color": Color(0.33, 0.09, 0.44),
		"wear_color": Color(0.12, 0.1, 0.14),
		"wear_amount": 0.15,
		"range_mult": 1.08,
	},
	"engineers": {
		"name": "Engineers",
		"passive_summary": "-15% factory build time",
		"color": Color(0.78, 0.68, 0.08),
		"wear_color": Color(0.28, 0.28, 0.25),
		"wear_amount": 0.22,
		"build_time_mult": 0.85,
	},
	"berserkers": {
		"name": "Berserkers",
		"passive_summary": "+10% move speed, -10% vision",
		"color": Color(0.4, 0.04, 0.04),
		"wear_color": Color(0.14, 0.11, 0.09),
		"wear_amount": 0.55,
		"speed_mult": 1.1,
		"vision_mult": 0.9,
	},
	"cybernetics": {
		"name": "Cybernetics",
		"passive_summary": "+20% Energy capacity",
		"color": Color(0.04, 0.58, 0.85),
		"wear_color": Color(0.08, 0.14, 0.2),
		"wear_amount": 0.05,
		"energy_capacity_mult": 1.2,
	},
}

const DEFAULT_FACTION: String = "industrialists"

static func get_ids() -> Array:
	var ids = FACTIONS.keys()
	ids.sort()
	return ids

static func get_faction(faction_id: String) -> Dictionary:
	return FACTIONS.get(faction_id, FACTIONS[DEFAULT_FACTION])

static func get_faction_name(faction_id: String) -> String:
	return get_faction(faction_id).get("name", faction_id)

static func get_passive(faction_id: String, key: String, default_value):
	return FACTIONS.get(faction_id, {}).get(key, default_value)

static func get_visual_color(faction_id: String) -> Color:
	return get_faction(faction_id).get("color", Color(0.6, 0.6, 0.65))

static func get_visual_wear_color(faction_id: String) -> Color:
	return get_faction(faction_id).get("wear_color", Color(0.3, 0.28, 0.25))

static func get_visual_wear_amount(faction_id: String) -> float:
	return get_faction(faction_id).get("wear_amount", 0.3)
