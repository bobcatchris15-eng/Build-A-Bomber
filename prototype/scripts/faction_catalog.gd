extends RefCounted
class_name FactionCatalog
# Single source of truth for all 10 factions: visual identity (built against
# VISUAL_ART_DIRECTION.md's 13-parameter shader model - base/accent/detail
# color, metallic/roughness/anisotropy/brush_scale, wear/grime, emissive,
# mottle) and mechanical passive bonuses. Every gameplay system that used to
# have a scattered `if faction == "technocrats": ...` branch now reads
# get_passive() instead, which is what lets 10 factions plug in with zero
# new branches anywhere.
#
# Passive keys (a faction only sets the ones it actually uses; get_passive()
# returns the given default for any key a faction doesn't set):
#   armor_weight_mult    - hull armor weight multiplier (Design Lab stat)
#   vision_mult          - unit/building vision_range multiplier
#   speed_mult           - unit move_speed multiplier
#   energy_upkeep_exempt - bool, static buildings skip Energy upkeep entirely
#   hq_trickle_metal / hq_trickle_crystal - flat resources/tick regardless of captured nodes
#   metal_cost_mult      - roster build cost (metal) multiplier
#   build_time_mult      - factory build-time multiplier
#   harvest_rate_mult    - harvester per-tick extraction multiplier
#   low_hp_dps_bonus_max - Crimson Concordat: extra DPS multiplier at 0% HP, scaling
#                          linearly to 0 at 100% HP (a desperation/berserk-rage curve)
#   terrain_penalty_reduction - Glacier Syndicate: how much of any terrain
#                          speed penalty (multiplier below 1.0) is negated (0=none, 1=all)
#   detection_range_mult - Bayou Irregulars: shrinks the distance at which
#                          OTHER teams' vision can spot this construct
#   air_speed_mult       - Aerodrome Cartel: move_speed multiplier, airborne units only

const FACTIONS = {
	"industrialists": {
		"name": "Heavy Industrialists",
		"passive_summary": "-20% armor weight",
		"base_color": Color(0.42, 0.42, 0.44), "accent_color": Color(0.85, 0.68, 0.12), "detail_color": Color(0.55, 0.3, 0.1),
		"metallic": 0.7, "anisotropy": 0.35, "brush_scale": 2.2,
		"wear_amount": 0.35, "wear_color": Color(0.62, 0.32, 0.12), "grime_amount": 0.3,
		"edge_highlight_strength": 0.5, "emissive_color": Color.BLACK, "emissive_strength": 0.0,
		"armor_weight_mult": 0.8,
	},
	"technocrats": {
		"name": "Technocrats",
		"passive_summary": "+15% vision, +5% speed",
		"base_color": Color(0.88, 0.9, 0.93), "accent_color": Color(0.1, 0.7, 0.95), "detail_color": Color(0.85, 0.87, 0.9),
		"metallic": 0.5, "anisotropy": 0.7, "brush_scale": 2.5,
		"wear_amount": 0.08, "wear_color": Color(0.7, 0.72, 0.75), "grime_amount": 0.03,
		"edge_highlight_strength": 0.3, "emissive_color": Color(0.15, 0.75, 1.0), "emissive_strength": 0.6,
		"vision_mult": 1.15, "speed_mult": 1.05,
	},
	"expansionists": {
		"name": "Expansionists",
		"passive_summary": "Static buildings exempt from Energy upkeep + slow HQ trickle",
		"base_color": Color(0.33, 0.35, 0.19), "accent_color": Color(0.55, 0.3, 0.14), "detail_color": Color(0.6, 0.5, 0.25),
		"metallic": 0.3, "anisotropy": 0.2, "brush_scale": 1.8,
		"wear_amount": 0.4, "wear_color": Color(0.58, 0.46, 0.24), "grime_amount": 0.5,
		"edge_highlight_strength": 0.4, "emissive_color": Color.BLACK, "emissive_strength": 0.0,
		"energy_upkeep_exempt": true, "hq_trickle_metal": 8, "hq_trickle_crystal": 2,
	},
	"salvage_union": {
		"name": "The Salvage Union",
		"passive_summary": "-10% metal cost on everything built",
		"base_color": Color(0.4, 0.4, 0.4), "accent_color": Color(0.35, 0.33, 0.28), "detail_color": Color(0.75, 0.72, 0.65),
		"metallic": 0.5, "anisotropy": 0.15, "brush_scale": 1.4,
		"wear_amount": 0.65, "wear_color": Color(0.15, 0.14, 0.13), "grime_amount": 0.65,
		"edge_highlight_strength": 0.2, "emissive_color": Color.BLACK, "emissive_strength": 0.0,
		"metal_cost_mult": 0.9,
	},
	"crimson_concordat": {
		"name": "The Crimson Concordat",
		"passive_summary": "Weapon DPS rises the closer this unit is to death",
		"base_color": Color(0.5, 0.03, 0.06), "accent_color": Color(0.75, 0.6, 0.2), "detail_color": Color(0.08, 0.08, 0.08),
		"metallic": 0.55, "anisotropy": 0.4, "brush_scale": 2.0,
		"wear_amount": 0.1, "wear_color": Color(0.2, 0.05, 0.05), "grime_amount": 0.05,
		"edge_highlight_strength": 0.35, "emissive_color": Color(0.75, 0.6, 0.2), "emissive_strength": 0.2,
		"low_hp_dps_bonus_max": 0.5,
	},
	"glacier_syndicate": {
		"name": "The Glacier Syndicate",
		"passive_summary": "Reduced terrain speed penalties",
		"base_color": Color(0.85, 0.88, 0.9), "accent_color": Color(0.4, 0.65, 0.85), "detail_color": Color(0.5, 0.52, 0.55),
		"metallic": 0.6, "anisotropy": 0.5, "brush_scale": 2.3,
		"wear_amount": 0.15, "wear_color": Color(0.92, 0.95, 0.97), "grime_amount": 0.08,
		"edge_highlight_strength": 0.4, "emissive_color": Color.BLACK, "emissive_strength": 0.0,
		"terrain_penalty_reduction": 0.5,
	},
	"dune_runners": {
		"name": "The Dune Runners",
		"passive_summary": "+15% harvest rate",
		"base_color": Color(0.68, 0.56, 0.32), "accent_color": Color(0.25, 0.55, 0.55), "detail_color": Color(0.4, 0.3, 0.2),
		"metallic": 0.25, "anisotropy": 0.1, "brush_scale": 1.6,
		"wear_amount": 0.4, "wear_color": Color(0.45, 0.38, 0.28), "grime_amount": 0.2,
		"edge_highlight_strength": 0.2, "emissive_color": Color.BLACK, "emissive_strength": 0.0,
		"harvest_rate_mult": 1.15,
	},
	"ledger_combine": {
		"name": "The Ledger Combine",
		"passive_summary": "-15% factory build time",
		"base_color": Color(0.14, 0.3, 0.55), "accent_color": Color(0.9, 0.9, 0.92), "detail_color": Color(0.2, 0.9, 0.35),
		"metallic": 0.65, "anisotropy": 0.6, "brush_scale": 2.6,
		"wear_amount": 0.05, "wear_color": Color(0.6, 0.62, 0.65), "grime_amount": 0.03,
		"edge_highlight_strength": 0.3, "emissive_color": Color(0.2, 0.9, 0.35), "emissive_strength": 0.3,
		"build_time_mult": 0.85,
	},
	"bayou_irregulars": {
		"name": "The Bayou Irregulars",
		"passive_summary": "Harder for enemies to spot",
		"base_color": Color(0.24, 0.3, 0.16), "accent_color": Color(0.32, 0.26, 0.15), "detail_color": Color(0.4, 0.42, 0.3),
		"metallic": 0.15, "anisotropy": 0.1, "brush_scale": 1.5, "mottle_amount": 0.85,
		"wear_amount": 0.45, "wear_color": Color(0.16, 0.2, 0.14), "grime_amount": 0.4,
		"edge_highlight_strength": 0.2, "emissive_color": Color.BLACK, "emissive_strength": 0.0,
		"detection_range_mult": 0.7,
	},
	"aerodrome_cartel": {
		"name": "The Aerodrome Cartel",
		"passive_summary": "Faster airborne units",
		"base_color": Color(0.9, 0.87, 0.78), "accent_color": Color(0.72, 0.48, 0.18), "detail_color": Color(0.1, 0.2, 0.4),
		"metallic": 0.55, "anisotropy": 0.55, "brush_scale": 2.1,
		"wear_amount": 0.12, "wear_color": Color(0.65, 0.42, 0.15), "grime_amount": 0.15,
		"edge_highlight_strength": 0.4, "emissive_color": Color.BLACK, "emissive_strength": 0.0,
		"air_speed_mult": 1.15,
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

# Full visual parameter set for hull_material_builder.gd's shader.
static func get_visual(faction_id: String) -> Dictionary:
	var f = get_faction(faction_id)
	return {
		"base_color": f.get("base_color", Color(0.6, 0.6, 0.65)),
		"accent_color": f.get("accent_color", Color(0.5, 0.5, 0.55)),
		"detail_color": f.get("detail_color", Color(0.8, 0.8, 0.8)),
		"anisotropy": f.get("anisotropy", 0.3),
		"brush_scale": f.get("brush_scale", 2.0),
		"wear_amount": f.get("wear_amount", 0.3),
		"wear_color": f.get("wear_color", Color(0.3, 0.28, 0.25)),
		"grime_amount": f.get("grime_amount", 0.2),
		"edge_highlight_strength": f.get("edge_highlight_strength", 0.4),
		"emissive_color": f.get("emissive_color", Color.BLACK),
		"emissive_strength": f.get("emissive_strength", 0.0),
		"mottle_amount": f.get("mottle_amount", 0.0),
	}

# Thin wrappers for the simpler 2D UI theme system (ui_theme.gd), which
# doesn't need the full 13-parameter hull model - just a tint + wear level.
static func get_visual_color(faction_id: String) -> Color:
	return get_faction(faction_id).get("base_color", Color(0.6, 0.6, 0.65))

static func get_visual_wear_color(faction_id: String) -> Color:
	return get_faction(faction_id).get("wear_color", Color(0.3, 0.28, 0.25))

static func get_visual_wear_amount(faction_id: String) -> float:
	return get_faction(faction_id).get("wear_amount", 0.3)
