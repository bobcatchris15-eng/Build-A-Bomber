extends RefCounted
# THE PLAYER'S OWN FACTION, REPLACING THE TEN PREMADE ONES.
#
# faction_catalog.gd used to hold 10 hand-authored factions, each pairing a
# fixed visual identity with a mechanical passive (-20% armor weight, +15%
# vision, ...). Both halves are gone. What replaces them is this: a livery the
# player authors themselves, which is PURELY COSMETIC. There is no longer any
# such thing as a faction bonus, so two identical designs fight identically no
# matter whose colours they wear - every stat now comes from what the player
# actually built, which is the premise of the whole game.
#
# FIVE ZONES, chosen so a livery reads at RTS camera distance rather than
# rewarding pixel-peeping:
#   hull_lower    - the hull below the belt line
#   hull_upper    - the hull above it (the face the top-down camera sees most)
#   hull_stripe   - a stripe/pattern overlay running across the hull
#   weapon_action - receivers, breeches, mounts, turret bodies
#   weapon_barrel - barrels, muzzles, launch tubes
# Weapons split from the hull because a weapon is the part a player looks at
# when identifying what a unit DOES, and letting it carry its own two-tone is
# what makes "same chassis, different gun" readable across a battle line.
#
# Each zone carries a COLOUR and a FINISH. The finish is the PBR half - a
# colour alone cannot tell matte primer from anodised metal, and that
# difference is most of what makes a livery look authored rather than tinted.

const SAVE_PATH := "user://livery.json"

# GLOSS IS CAPPED IN THE SATIN RANGE for dielectrics to prevent blown-out mirror reflections.
const SATIN_ROUGHNESS_FLOOR := 0.35

# Surface types for procedural micro-normal synthesis:
# 0 = standard/smooth
# 1 = carbon_fibre (2x2 twill weave normal + anisotropic sheen)
# 2 = hammered (crater dimples / peened armor)
# 3 = cast_iron (rough granular sand-cast)
# 4 = galvanised (voronoi crystal zinc spangle flakes)
# 5 = brushed (directional linear grain streaks)
# 6 = cerakote / matte_primer (micro-stipple chalk diffuse absorption)
# 7 = rubberised (soft-fresnel velvety polymer)
# 8 = fiberglass (woven fiber strand bump)
# 9 = anodised (ultra-smooth high-chroma metallic sheen)

const FINISHES = {
	# --- Dielectric, very matte ---
	"cerakote":         {"name": "Cerakote",                "metallic": 0.00, "roughness": 0.98, "surface_type": 6},
	"matte_primer":     {"name": "Matte Primer",            "metallic": 0.00, "roughness": 0.95, "surface_type": 6},
	"ghillie":          {"name": "Ghillie Netting",         "metallic": 0.00, "roughness": 0.92, "surface_type": 8,
		"albedo_tint": Color(0.42, 0.48, 0.30)},
	"powdercoat":       {"name": "Powdercoat",              "metallic": 0.00, "roughness": 0.92, "surface_type": 6},
	"rubberised":       {"name": "Rubberised",              "metallic": 0.00, "roughness": 0.90, "surface_type": 7},
	"weathered_enamel": {"name": "Weathered Enamel",        "metallic": 0.10, "roughness": 0.86, "surface_type": 0},
	"phosphate":        {"name": "Phosphate (Parkerized)",  "metallic": 0.30, "roughness": 0.85, "surface_type": 3,
		"albedo_tint": Color(0.32, 0.30, 0.28)},
	# --- Dielectric with tooth, mid-matte ---
	"cast_iron":        {"name": "Cast Iron",               "metallic": 0.45, "roughness": 0.80, "surface_type": 3},
	"hammered":         {"name": "Hammered Metal",          "metallic": 0.55, "roughness": 0.72, "surface_type": 2},
	"fiberglass":       {"name": "Fiberglass",              "metallic": 0.00, "roughness": 0.65, "surface_type": 8,
		"albedo_tint": Color(0.78, 0.74, 0.66)},
	"eggshell":         {"name": "Eggshell",                "metallic": 0.05, "roughness": 0.68, "surface_type": 0},
	# --- Metal, satin & textured ---
	"galvanised":       {"name": "Galvanised Zinc",         "metallic": 0.72, "roughness": 0.62, "surface_type": 4},
	"gunmetal":         {"name": "Gunmetal",                "metallic": 0.78, "roughness": 0.58, "surface_type": 5},
	"brushed_steel":    {"name": "Brushed Steel",           "metallic": 0.74, "roughness": 0.52, "surface_type": 5},
	"carbon_fibre":     {"name": "Carbon Fibre",            "metallic": 0.42, "roughness": 0.50, "surface_type": 1},
	"brushed_alloy":    {"name": "Brushed Alloy",           "metallic": 0.66, "roughness": 0.48, "surface_type": 5},
	"satin_enamel":     {"name": "Satin Enamel",            "metallic": 0.08, "roughness": 0.48, "surface_type": 0},
	# --- Metal, glossiest satin ---
	"anodised":         {"name": "Anodised Aluminum",       "metallic": 0.82, "roughness": 0.40, "surface_type": 9},
}

# 13 Procedural pattern types
const PATTERNS := {
	"none":           {"name": "Solid / Clean Split",     "id_int": 0,  "desc": "Clean two-tone hull without overlay pattern"},
	"stripe":         {"name": "Centerline Stripe",       "id_int": 1,  "desc": "Single bold racing stripe down the center"},
	"dual_stripe":    {"name": "Dual Racing Stripes",     "id_int": 2,  "desc": "Twin parallel Le Mans rally stripes"},
	"offset_stripe":  {"name": "Offset Rally Stripe",     "id_int": 3,  "desc": "Asymmetric single stripe on port flank"},
	"chevrons":       {"name": "Assault Chevrons",        "id_int": 4,  "desc": "Forward-pointing tactical V-stripes"},
	"hazard":         {"name": "Hazard Caution Bands",    "id_int": 5,  "desc": "Industrial 45° diagonal warning chevrons"},
	"hex_grid":       {"name": "Hex Tactical Grid",       "id_int": 6,  "desc": "High-tech honeycomb armor lattice"},
	"digital_camo":   {"name": "Digital Pixel Camo",      "id_int": 7,  "desc": "Multi-tone digital block camouflage"},
	"splinter_camo":  {"name": "Splinter Dazzle Camo",   "id_int": 8,  "desc": "Angular geometric military camouflage"},
	"tiger_camo":     {"name": "Tiger Wave Camo",         "id_int": 9,  "desc": "Organic disruptive predator wave camouflage"},
	"nose_dip":       {"name": "Dipped Nose / Cowl",      "id_int": 10, "desc": "Front cowl / nose accent blocking"},
	"half_split":     {"name": "Longitudinal Split",      "id_int": 11, "desc": "High-contrast port/starboard color split"},
	"gradient":       {"name": "Airbrush Gradient Fade",  "id_int": 12, "desc": "Smooth continuous transition along the hull"},
}

# 10 Insignia icons
const MASCOT_SHAPES: Array = [
	"gear", "hex", "star_compass", "cross", "blade",
	"star_snowflake", "star_sunburst", "diamond", "leaf", "star_propeller",
]

# Curated themed presets
const PRESETS := {
	"apex_motorsport": {
		"name": "Apex Motorsport",
		"pattern_type": "dual_stripe",
		"pattern_scale": 1.0,
		"pattern_angle": 0.0,
		"pattern_softness": 0.012,
		"weathering": 0.05,
		"decal_icon": "star_propeller",
		"decal_badge": "circle",
		"hull_upper": {"color": Color(0.92, 0.93, 0.95), "finish": "satin_enamel"},
		"hull_lower": {"color": Color(0.12, 0.14, 0.18), "finish": "carbon_fibre"},
		"hull_stripe": {"color": Color(0.98, 0.38, 0.05), "finish": "anodised"},
		"weapon_action": {"color": Color(0.20, 0.22, 0.25), "finish": "brushed_steel"},
		"weapon_barrel": {"color": Color(0.12, 0.12, 0.14), "finish": "gunmetal"},
	},
	"desert_nomad": {
		"name": "Desert Nomad",
		"pattern_type": "digital_camo",
		"pattern_scale": 1.4,
		"pattern_angle": 0.0,
		"pattern_softness": 0.005,
		"weathering": 0.65,
		"decal_icon": "star_compass",
		"decal_badge": "none",
		"hull_upper": {"color": Color(0.76, 0.65, 0.48), "finish": "cerakote"},
		"hull_lower": {"color": Color(0.42, 0.34, 0.24), "finish": "matte_primer"},
		"hull_stripe": {"color": Color(0.28, 0.52, 0.50), "finish": "weathered_enamel"},
		"weapon_action": {"color": Color(0.35, 0.30, 0.24), "finish": "cast_iron"},
		"weapon_barrel": {"color": Color(0.18, 0.16, 0.14), "finish": "phosphate"},
	},
	"arctic_phantom": {
		"name": "Arctic Phantom",
		"pattern_type": "splinter_camo",
		"pattern_scale": 1.2,
		"pattern_angle": 0.0,
		"pattern_softness": 0.008,
		"weathering": 0.25,
		"decal_icon": "star_snowflake",
		"decal_badge": "circle",
		"hull_upper": {"color": Color(0.92, 0.95, 0.98), "finish": "galvanised"},
		"hull_lower": {"color": Color(0.22, 0.28, 0.35), "finish": "cerakote"},
		"hull_stripe": {"color": Color(0.30, 0.68, 0.88), "finish": "anodised"},
		"weapon_action": {"color": Color(0.30, 0.35, 0.42), "finish": "brushed_alloy"},
		"weapon_barrel": {"color": Color(0.15, 0.18, 0.22), "finish": "gunmetal"},
	},
	"heavy_hazard": {
		"name": "Heavy Industrial",
		"pattern_type": "hazard",
		"pattern_scale": 1.5,
		"pattern_angle": 45.0,
		"pattern_softness": 0.010,
		"weathering": 0.75,
		"decal_icon": "gear",
		"decal_badge": "circle",
		"hull_upper": {"color": Color(0.92, 0.72, 0.08), "finish": "powdercoat"},
		"hull_lower": {"color": Color(0.18, 0.18, 0.19), "finish": "cast_iron"},
		"hull_stripe": {"color": Color(0.10, 0.10, 0.10), "finish": "hammered"},
		"weapon_action": {"color": Color(0.25, 0.24, 0.22), "finish": "cast_iron"},
		"weapon_barrel": {"color": Color(0.12, 0.12, 0.12), "finish": "phosphate"},
	},
	"royal_vanguard": {
		"name": "Royal Vanguard",
		"pattern_type": "chevrons",
		"pattern_scale": 1.1,
		"pattern_angle": 0.0,
		"pattern_softness": 0.012,
		"weathering": 0.10,
		"decal_icon": "star_sunburst",
		"decal_badge": "circle",
		"hull_upper": {"color": Color(0.55, 0.08, 0.12), "finish": "satin_enamel"},
		"hull_lower": {"color": Color(0.12, 0.10, 0.14), "finish": "carbon_fibre"},
		"hull_stripe": {"color": Color(0.88, 0.72, 0.25), "finish": "anodised"},
		"weapon_action": {"color": Color(0.22, 0.20, 0.24), "finish": "brushed_steel"},
		"weapon_barrel": {"color": Color(0.65, 0.52, 0.18), "finish": "anodised"},
	},
	"covert_ops": {
		"name": "Covert Ops",
		"pattern_type": "hex_grid",
		"pattern_scale": 1.3,
		"pattern_angle": 0.0,
		"pattern_softness": 0.008,
		"weathering": 0.30,
		"decal_icon": "hex",
		"decal_badge": "none",
		"hull_upper": {"color": Color(0.16, 0.18, 0.20), "finish": "carbon_fibre"},
		"hull_lower": {"color": Color(0.08, 0.09, 0.10), "finish": "rubberised"},
		"hull_stripe": {"color": Color(0.12, 0.65, 0.75), "finish": "anodised"},
		"weapon_action": {"color": Color(0.14, 0.15, 0.16), "finish": "cerakote"},
		"weapon_barrel": {"color": Color(0.08, 0.08, 0.09), "finish": "gunmetal"},
	},
	"jungle_strike": {
		"name": "Jungle Strike",
		"pattern_type": "tiger_camo",
		"pattern_scale": 1.2,
		"pattern_angle": 0.0,
		"pattern_softness": 0.015,
		"weathering": 0.55,
		"decal_icon": "leaf",
		"decal_badge": "none",
		"hull_upper": {"color": Color(0.24, 0.38, 0.20), "finish": "matte_primer"},
		"hull_lower": {"color": Color(0.20, 0.18, 0.14), "finish": "cerakote"},
		"hull_stripe": {"color": Color(0.12, 0.18, 0.10), "finish": "weathered_enamel"},
		"weapon_action": {"color": Color(0.22, 0.24, 0.20), "finish": "phosphate"},
		"weapon_barrel": {"color": Color(0.12, 0.13, 0.11), "finish": "gunmetal"},
	},
	"stealth_prototype": {
		"name": "Stealth Prototype",
		"pattern_type": "gradient",
		"pattern_scale": 1.0,
		"pattern_angle": 0.0,
		"pattern_softness": 0.20,
		"weathering": 0.0,
		"decal_icon": "blade",
		"decal_badge": "circle",
		"hull_upper": {"color": Color(0.18, 0.20, 0.22), "finish": "carbon_fibre"},
		"hull_lower": {"color": Color(0.06, 0.06, 0.07), "finish": "rubberised"},
		"hull_stripe": {"color": Color(0.85, 0.12, 0.18), "finish": "anodised"},
		"weapon_action": {"color": Color(0.15, 0.16, 0.18), "finish": "brushed_alloy"},
		"weapon_barrel": {"color": Color(0.08, 0.08, 0.09), "finish": "gunmetal"},
	},
}

# Zone order is the order the editor lists them in
const ZONES: Array = [
	{"id": "hull_upper",    "name": "Hull - Upper"},
	{"id": "hull_lower",    "name": "Hull - Lower"},
	{"id": "hull_stripe",   "name": "Pattern Accent"},
	{"id": "weapon_action", "name": "Weapon - Action"},
	{"id": "weapon_barrel", "name": "Weapon - Barrel"},
]

const HUE_POOL: Array = [
	0.02, 0.06, 0.10, 0.13, 0.17, 0.28, 0.33, 0.45, 0.52, 0.58, 0.63, 0.72, 0.82, 0.92,
]

static func finish_ids() -> Array:
	return FINISHES.keys()

static func get_finish(finish_id: String) -> Dictionary:
	return FINISHES.get(finish_id, FINISHES["matte_primer"])

static func finish_name(finish_id: String) -> String:
	return get_finish(finish_id).get("name", finish_id)

static func finish_surface_type(finish_id: String) -> int:
	return int(get_finish(finish_id).get("surface_type", 0))

static func finish_roughness(finish_id: String) -> float:
	return maxf(SATIN_ROUGHNESS_FLOOR, float(get_finish(finish_id).get("roughness", 0.8)))

static func finish_metallic(finish_id: String) -> float:
	return clampf(float(get_finish(finish_id).get("metallic", 0.0)), 0.0, 1.0)

static func pattern_ids() -> Array:
	return PATTERNS.keys()

static func pattern_name(pattern_id: String) -> String:
	return PATTERNS.get(pattern_id, PATTERNS["stripe"]).get("name", pattern_id)

static func pattern_id_int(pattern_id: String) -> int:
	return int(PATTERNS.get(pattern_id, PATTERNS["stripe"]).get("id_int", 1))

# A complete livery: every zone gets a colour and a finish, plus pattern, weathering, and decal parameters.
static func random_livery(livery_seed: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = livery_seed if livery_seed != 0 else randi()

	var base_hue: float = HUE_POOL[rng.randi() % HUE_POOL.size()]
	var accent_hue: float = fmod(base_hue + rng.randf_range(0.35, 0.65), 1.0)
	var ids := finish_ids()
	var pat_keys := pattern_ids()
	var chosen_pattern: String = pat_keys[rng.randi() % pat_keys.size()]

	var out := {
		"pattern": {
			"type": chosen_pattern,
			"scale": rng.randf_range(0.8, 1.6),
			"angle": rng.randf_range(-45.0, 45.0) if rng.randf() > 0.5 else 0.0,
			"softness": rng.randf_range(0.008, 0.025),
		},
		"weathering": rng.randf_range(0.05, 0.70),
		"decal": {
			"icon": MASCOT_SHAPES[rng.randi() % MASCOT_SHAPES.size()],
			"badge": "circle" if rng.randf() > 0.3 else "none",
			"serial": str(100 + (rng.randi() % 900)),
			"show_hazard": rng.randf() > 0.3,
		}
	}
	for zone in ZONES:
		var zid: String = zone["id"]
		var hue := base_hue
		var sat := rng.randf_range(0.35, 0.75)
		var val := rng.randf_range(0.45, 0.80)
		match zid:
			"hull_lower":
				val *= 0.6
			"hull_stripe":
				hue = accent_hue
				sat = rng.randf_range(0.6, 0.95)
				val = rng.randf_range(0.7, 0.95)
			"weapon_action":
				sat *= 0.5
				val *= 0.55
			"weapon_barrel":
				hue = accent_hue
				sat *= 0.35
				val *= 0.5
		out[zid] = {
			"color": Color.from_hsv(hue, clampf(sat, 0.0, 1.0), clampf(val, 0.05, 1.0)),
			"finish": ids[rng.randi() % ids.size()],
		}
	return out

static func default_livery() -> Dictionary:
	return random_livery()

# ---------------------------------------------------------------------------
# PERSISTENCE
# ---------------------------------------------------------------------------

static func to_json(livery: Dictionary) -> Dictionary:
	var out := {}
	for zone in ZONES:
		var zid: String = zone["id"]
		var z: Dictionary = livery.get(zid, {})
		var c: Color = z.get("color", Color(0.5, 0.5, 0.5))
		out[zid] = {"color": [c.r, c.g, c.b], "finish": str(z.get("finish", "matte_primer"))}
	
	# Extended properties
	var pat: Dictionary = livery.get("pattern", {})
	out["pattern"] = {
		"type": str(pat.get("type", "stripe")),
		"scale": float(pat.get("scale", 1.0)),
		"angle": float(pat.get("angle", 0.0)),
		"softness": float(pat.get("softness", 0.015)),
	}
	out["weathering"] = float(livery.get("weathering", 0.2))
	var dec: Dictionary = livery.get("decal", {})
	out["decal"] = {
		"icon": str(dec.get("icon", "gear")),
		"badge": str(dec.get("badge", "circle")),
		"serial": str(dec.get("serial", "101")),
		"show_hazard": bool(dec.get("show_hazard", true)),
	}
	return out

static func from_json(data: Dictionary) -> Dictionary:
	var out := {}
	for zone in ZONES:
		var zid: String = zone["id"]
		var z = data.get(zid, null)
		if typeof(z) != TYPE_DICTIONARY:
			out[zid] = random_livery(hash(zid))[zid]
			continue
		var rgb = z.get("color", [0.5, 0.5, 0.5])
		var col := Color(0.5, 0.5, 0.5)
		if typeof(rgb) == TYPE_ARRAY and rgb.size() >= 3:
			col = Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
		var fin := str(z.get("finish", "matte_primer"))
		if not FINISHES.has(fin):
			fin = "matte_primer"
		out[zid] = {"color": col, "finish": fin}
	
	# Pattern
	var pat_data = data.get("pattern", {})
	var pat_type = "stripe"
	var pat_scale = 1.0
	var pat_angle = 0.0
	var pat_softness = 0.015
	if typeof(pat_data) == TYPE_DICTIONARY:
		pat_type = str(pat_data.get("type", "stripe"))
		if not PATTERNS.has(pat_type):
			pat_type = "stripe"
		pat_scale = float(pat_data.get("scale", 1.0))
		pat_angle = float(pat_data.get("angle", 0.0))
		pat_softness = float(pat_data.get("softness", 0.015))
	out["pattern"] = {
		"type": pat_type,
		"scale": pat_scale,
		"angle": pat_angle,
		"softness": pat_softness,
	}

	# Weathering
	out["weathering"] = clampf(float(data.get("weathering", 0.2)), 0.0, 1.0)

	# Decal
	var dec_data = data.get("decal", {})
	var dec_icon = "gear"
	var dec_badge = "circle"
	var dec_serial = "101"
	var dec_hazard = true
	if typeof(dec_data) == TYPE_DICTIONARY:
		dec_icon = str(dec_data.get("icon", "gear"))
		if not MASCOT_SHAPES.has(dec_icon):
			dec_icon = "gear"
		dec_badge = str(dec_data.get("badge", "circle"))
		dec_serial = str(dec_data.get("serial", "101"))
		dec_hazard = bool(dec_data.get("show_hazard", true))
	out["decal"] = {
		"icon": dec_icon,
		"badge": dec_badge,
		"serial": dec_serial,
		"show_hazard": dec_hazard,
	}

	return out

static func save_player(livery: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Livery: could not write " + SAVE_PATH)
		return
	f.store_string(JSON.stringify(to_json(livery), "\t"))
	f.close()

static func load_player() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return random_livery()
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return random_livery()
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return random_livery()
	return from_json(parsed)

# ---------------------------------------------------------------------------
# RESOLUTION BY ID
# ---------------------------------------------------------------------------
const PLAYER_ID := "player"
const NO_LIVERY := ""

static var _cache: Dictionary = {}

static func for_id(livery_id: String) -> Dictionary:
	if _cache.has(livery_id):
		return _cache[livery_id]
	var l: Dictionary
	if livery_id == PLAYER_ID:
		l = load_player()
	else:
		l = random_livery(hash(livery_id))
	_cache[livery_id] = l
	return l

static func invalidate(livery_id: String = PLAYER_ID) -> void:
	_cache.erase(livery_id)

static func zone_color(livery_id: String, zone_id: String) -> Color:
	var z: Dictionary = for_id(livery_id).get(zone_id, {})
	return z.get("color", Color(0.5, 0.5, 0.55))

static func zone_finish(livery_id: String, zone_id: String) -> String:
	var z: Dictionary = for_id(livery_id).get(zone_id, {})
	return str(z.get("finish", "matte_primer"))

static func pattern_type(livery_id: String) -> String:
	var p: Dictionary = for_id(livery_id).get("pattern", {})
	return str(p.get("type", "stripe"))

static func pattern_type_int(livery_id: String) -> int:
	return pattern_id_int(pattern_type(livery_id))

static func pattern_scale(livery_id: String) -> float:
	var p: Dictionary = for_id(livery_id).get("pattern", {})
	return float(p.get("scale", 1.0))

static func pattern_angle(livery_id: String) -> float:
	var p: Dictionary = for_id(livery_id).get("pattern", {})
	return float(p.get("angle", 0.0))

static func pattern_softness(livery_id: String) -> float:
	var p: Dictionary = for_id(livery_id).get("pattern", {})
	return float(p.get("softness", 0.015))

static func weathering(livery_id: String) -> float:
	return float(for_id(livery_id).get("weathering", 0.2))

static func decal_icon(livery_id: String) -> String:
	var d: Dictionary = for_id(livery_id).get("decal", {})
	return str(d.get("icon", "gear"))

static func decal_badge(livery_id: String) -> String:
	var d: Dictionary = for_id(livery_id).get("decal", {})
	return str(d.get("badge", "circle"))

static func decal_serial(livery_id: String) -> String:
	var d: Dictionary = for_id(livery_id).get("decal", {})
	return str(d.get("serial", "101"))

static func decal_show_hazard(livery_id: String) -> bool:
	var d: Dictionary = for_id(livery_id).get("decal", {})
	return bool(d.get("show_hazard", true))
