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
#   hull_stripe   - a stripe running the length of the hull's centreline
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

# GLOSS IS CAPPED IN THE SATIN RANGE, deliberately, and this is the single
# most important number in this file.
#
# Roughness below ~0.35 combines with the hull shader's anisotropic specular
# term into a blown-out near-mirror streak on every upward-facing panel - the
# exact "whole game looks glossy" regression hull_material_builder.gd's
# ARMOR_PBR comment records being root-caused and fixed once already, at a
# time when only four authored materials could trigger it. Handing the player
# a free roughness slider would hand them that bug back, on every zone of
# every unit, with no way to tell them why the result looks like wet plastic.
#
# So the palette does not expose roughness at all: it exposes twelve NAMED
# finishes whose roughness is authored, and none of them is allowed below this
# floor. Satin is where a real vehicle finish tops out anyway - gloss show-car
# paint is not what a machine that fights looks like.
const SATIN_ROUGHNESS_FLOOR := 0.35

# Twelve finishes spanning matte -> satin and dielectric -> metal, which are
# the two axes that actually change how a surface reads. Ordered dullest to
# most reflective so the picker reads as a ramp.
#
# 2026-08-10: the five glossiest finishes (galvanised, gunmetal,
# brushed_steel, brushed_alloy, anodised) had roughness in [0.38, 0.62] and
# metallic in [0.62, 0.85]. Under the hull shader's toon specular blob
# (0.5) and the cool shadow tint, that range rendered as chrome - every
# ship looked wet, the painted finish was lost behind the reflection.
# Roughness bumped +0.06..+0.08 on each, metallic trimmed where it was
# over 0.7. All stays above SATIN_ROUGHNESS_FLOOR (0.35). Net effect: the
# same five names still read as the "shiny" end of the ramp, just not
# chrome.
#
# 2026-08-10: six additions (powdercoat, cerakote, phosphate, carbon_fibre,
# fiberglass, ghillie) - the names are real military / industrial
# finishes that don't have a PBR-only representation. The table now also
# carries optional `normal_path` and `albedo_tint` fields so Phase 3 can
# add the visual identity (weave normal, fiber bumps, camo overlay) without
# touching the call sites that read this table.
const FINISHES = {
	# --- Dielectric, very matte ---
	"cerakote":         {"name": "Cerakote",          "metallic": 0.00, "roughness": 0.98},
	"matte_primer":     {"name": "Matte Primer",      "metallic": 0.00, "roughness": 0.95},
	"ghillie":          {"name": "Ghillie Netting",   "metallic": 0.00, "roughness": 0.92,
		"albedo_tint": Color(0.42, 0.48, 0.30)},  # placeholder; Phase 3 camo overlay replaces this
	"powdercoat":       {"name": "Powdercoat",        "metallic": 0.00, "roughness": 0.92},
	"rubberised":       {"name": "Rubberised",        "metallic": 0.00, "roughness": 0.90},
	"weathered_enamel": {"name": "Weathered Enamel",  "metallic": 0.10, "roughness": 0.86},
	"phosphate":        {"name": "Phosphate (Parkerized)", "metallic": 0.30, "roughness": 0.85,
		"albedo_tint": Color(0.32, 0.30, 0.28)},  # dark gun-metal grey
	# --- Dielectric with tooth, mid-matte ---
	"cast_iron":        {"name": "Cast Iron",         "metallic": 0.45, "roughness": 0.80},
	"hammered":         {"name": "Hammered",          "metallic": 0.55, "roughness": 0.72},
	"fiberglass":       {"name": "Fiberglass",        "metallic": 0.00, "roughness": 0.65,
		"albedo_tint": Color(0.78, 0.74, 0.66)},  # cream / off-white; Phase 3 adds fiber normal
	"eggshell":         {"name": "Eggshell",          "metallic": 0.05, "roughness": 0.68},
	# --- Metal, satin ---
	"galvanised":       {"name": "Galvanised",        "metallic": 0.62, "roughness": 0.70},
	"gunmetal":         {"name": "Gunmetal",          "metallic": 0.72, "roughness": 0.64},
	"brushed_steel":    {"name": "Brushed Steel",     "metallic": 0.66, "roughness": 0.56},
	"carbon_fibre":     {"name": "Carbon Fibre",      "metallic": 0.45, "roughness": 0.55,
		"normal_path": "res://assets/textures/finish/carbon_fibre_normal.png"},  # Phase 3 — currently absent
	"brushed_alloy":    {"name": "Brushed Alloy",     "metallic": 0.55, "roughness": 0.52},
	"satin_enamel":     {"name": "Satin Enamel",      "metallic": 0.08, "roughness": 0.50},
	# --- Metal, glossiest satin (still capped above the floor) ---
	"anodised":         {"name": "Anodised",          "metallic": 0.68, "roughness": 0.46},
}

# Zone order is the order the editor lists them in, and it is deliberate:
# largest visual area first, so the first choice a player makes is the one
# that most changes the unit.
const ZONES: Array = [
	{"id": "hull_upper",    "name": "Hull - Upper"},
	{"id": "hull_lower",    "name": "Hull - Lower"},
	{"id": "hull_stripe",   "name": "Hull - Stripe"},
	{"id": "weapon_action", "name": "Weapon - Action"},
	{"id": "weapon_barrel", "name": "Weapon - Barrel"},
]

# Sampled rather than fully random across RGB. A uniform random colour is
# usually a muddy mid-grey-brown, and three of them together look like an
# accident rather than a scheme - which is a bad first impression given
# "defaults to random" is what every new player sees. These are hues that read
# as deliberate machine paint, and the roll below varies value/saturation
# around them so two random liveries are still clearly different.
const HUE_POOL: Array = [
	0.02, 0.06, 0.10, 0.13, 0.17, 0.28, 0.33, 0.45, 0.52, 0.58, 0.63, 0.72, 0.82, 0.92,
]


static func finish_ids() -> Array:
	return FINISHES.keys()


static func get_finish(finish_id: String) -> Dictionary:
	return FINISHES.get(finish_id, FINISHES["matte_primer"])


static func finish_name(finish_id: String) -> String:
	return get_finish(finish_id).get("name", finish_id)


# The roughness a finish actually renders at. Every read goes through here
# rather than touching FINISHES["roughness"] directly, so the satin cap is
# enforced at the point of USE and cannot be bypassed by a future finish
# authored (or modded) below the floor.
static func finish_roughness(finish_id: String) -> float:
	return maxf(SATIN_ROUGHNESS_FLOOR, float(get_finish(finish_id).get("roughness", 0.8)))


static func finish_metallic(finish_id: String) -> float:
	return clampf(float(get_finish(finish_id).get("metallic", 0.0)), 0.0, 1.0)


# A complete livery: every zone gets a colour and a finish. Seeded so a given
# id always rolls the same scheme - that is what lets an AI team's colours be
# derived from its team number and stay stable for the whole match without
# anything having to store them.
static func random_livery(livery_seed: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = livery_seed if livery_seed != 0 else randi()

	# One base hue for the unit, with the stripe and barrel pushed away from
	# it. A scheme built from one hue plus a deliberate contrast reads as
	# designed; five independent hues reads as a paint spill.
	var base_hue: float = HUE_POOL[rng.randi() % HUE_POOL.size()]
	var accent_hue: float = fmod(base_hue + rng.randf_range(0.35, 0.65), 1.0)
	var ids := finish_ids()

	var out := {}
	for zone in ZONES:
		var zid: String = zone["id"]
		var hue := base_hue
		var sat := rng.randf_range(0.35, 0.75)
		var val := rng.randf_range(0.45, 0.80)
		match zid:
			"hull_lower":
				# Reads as the shadowed underside even before lighting.
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
# user:// rather than res://, same as blueprint_manager.gd's saved designs -
# this is player-authored content and has to survive an export where res:// is
# a read-only .pck.

static func to_json(livery: Dictionary) -> Dictionary:
	var out := {}
	for zone in ZONES:
		var zid: String = zone["id"]
		var z: Dictionary = livery.get(zid, {})
		var c: Color = z.get("color", Color(0.5, 0.5, 0.5))
		out[zid] = {"color": [c.r, c.g, c.b], "finish": str(z.get("finish", "matte_primer"))}
	return out


static func from_json(data: Dictionary) -> Dictionary:
	var out := {}
	for zone in ZONES:
		var zid: String = zone["id"]
		var z = data.get(zid, null)
		if typeof(z) != TYPE_DICTIONARY:
			# A partial/corrupt file fills the missing zones from a fresh roll
			# rather than failing to load - a livery is cosmetic, and refusing
			# to start because one zone is malformed would be absurd.
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
	return out


static func save_player(livery: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Livery: could not write " + SAVE_PATH)
		return
	f.store_string(JSON.stringify(to_json(livery), "\t"))
	f.close()


# "Defaults to random selections" - a player who has never opened the livery
# editor still gets a coherent, distinctly-coloured army rather than a
# placeholder grey one, and the roll is NOT saved here. Not saving is the
# point: until the player actually commits a choice, every fresh install
# rolls something new, and the editor opens on a random suggestion rather
# than on whatever the last roll happened to be.
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
# Every unit, building and hull already carries a string identity in the slot
# that used to hold a faction id (hull_node's "faction" meta, blueprint JSON's
# faction_name, battle_unit's team plumbing). That slot is KEPT and re-pointed
# at liveries rather than being ripped out, because it is threaded through
# ~29 files and its shape - "a string naming who this belongs to" - is exactly
# what a livery needs too. Only its VALUES change:
#
#   PLAYER_ID  - the player's authored livery, from user://livery.json
#   anything else - a deterministic random livery seeded from the id string
#
# That second rule is what gives AI teams their colours (Chris's call: random
# per enemy team). "ai_2" always rolls the same scheme, so an enemy's colours
# are stable across the whole match and across a save/reload, without anything
# having to persist them - and two AI teams in the same match get visibly
# different schemes because they hash differently.
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
		# hash() of the id, not randi(): the same enemy team must roll the
		# same colours every time it is asked, from any call site, without
		# ordering mattering.
		l = random_livery(hash(livery_id))
	_cache[livery_id] = l
	return l


# Call after the player commits an edit in the livery editor, so live units
# and every subsequent material build pick the new scheme up.
static func invalidate(livery_id: String = PLAYER_ID) -> void:
	_cache.erase(livery_id)


static func zone_color(livery_id: String, zone_id: String) -> Color:
	var z: Dictionary = for_id(livery_id).get(zone_id, {})
	return z.get("color", Color(0.5, 0.5, 0.55))


static func zone_finish(livery_id: String, zone_id: String) -> String:
	var z: Dictionary = for_id(livery_id).get(zone_id, {})
	return str(z.get("finish", "matte_primer"))
