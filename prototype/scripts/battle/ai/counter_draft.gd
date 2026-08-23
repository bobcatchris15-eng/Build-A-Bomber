class_name CounterDraft
extends RefCounted
# What the AI brings to the next engagement, given what beat it in the last one.
#
# THE PREMISE. An operation is only a campaign if the opponent adapts. Without
# this, match_director._load_roster() builds enemy_roster from the bundled
# defaults in the same order every round, so the AI fields an identical army in
# round 6 as in round 1 no matter what the player did to it - and the player's
# own re-drafting has nothing to push against.
#
# THIS IS NOT NEW AI. Commander.design_fills_role() already reads roles off a
# design's mounted modules, and ai_design_for_role() already picks the FIRST
# design in enemy_roster matching a role. So the entire counter-draft is a
# REORDERING of that pool. Nothing downstream changes, and an AI that has been
# handed a badly-ordered roster still plays exactly as well as it ever did.
#
# HONEST INFORMATION ONLY. This reads the combat log - what was actually fielded
# in engagements already fought - not the player's current blueprint library and
# not their draft for the round about to start. The AI counters what it has
# seen, the same way a player would, and re-drafting after seeing the opponent
# is a move both sides get to make.

const CommanderScript = preload("res://scripts/battle/ai/commander.gd")
const ModuleCatalogScript = preload("res://scripts/module_catalog.gd")
const ThreatAnalyzer = preload("res://scripts/battle/ai/threat_analyzer.gd")

# The threats worth answering, and the role that answers each.
# Expanded in the AI Overhaul to include armor types, missile spam, and artillery/indirect.
const COUNTERS := {
	"air": "anti_air",
	"armor": "anti_armor",
	"wears_hardened_steel": "counter_armor",
	"wears_titanium_plate": "counter_armor",
	"wears_energy_shielding": "counter_armor",
	"wears_ablative_ceramic": "counter_armor",
	"wears_reactive_armor": "counter_armor",
	"wears_carbon_fiber": "counter_armor",
	"missile_spam": "point_defense",
	"indirect": "counter_armor",
}

# How much a design seen LAST round outweighs one seen four rounds ago. Recency
# matters because the player re-drafts too - countering the army they have
# already abandoned is worse than not countering at all.
const RECENCY_FALLOFF := 0.6

# Below this share of the observed force, a threat is not worth bending the
# roster around. One scout aircraft in twenty units is not an air force, and an
# AI that rebuilds itself around it has been baited.
const THREAT_FLOOR := 0.2


# What threats does this design pose? Tags, not a single class.
# Delegates to ThreatAnalyzer.threats_of() for full damage-type and locomotion analysis.
static func threats_of(blueprint: Dictionary) -> Array:
	return ThreatAnalyzer.threats_of(blueprint)


# The observed threat mix, as shares of 1.0, weighted toward recent rounds.
#
# `history` is OperationsManager.fielded_history() - entries carrying
# `player_threats`, recorded at the time each engagement ended.
static func threat_profile(history: Array) -> Dictionary:
	var weights: Dictionary = {}
	var total := 0.0
	# Newest last, so the exponent counts backwards from the end.
	for i in range(history.size()):
		var age: int = history.size() - 1 - i
		var weight: float = pow(RECENCY_FALLOFF, float(age))
		for tag in (history[i].get("player_threats", []) as Array):
			var key := str(tag)
			weights[key] = float(weights.get(key, 0.0)) + weight
			total += weight
	if total <= 0.0:
		return {}
	var profile: Dictionary = {}
	for key in weights:
		profile[key] = float(weights[key]) / total
	return profile


# The roles worth prioritising, strongest threat first. Empty when nothing seen
# clears THREAT_FLOOR, which is the correct answer for round one.
static func wanted_roles(profile: Dictionary) -> Array:
	var scored: Array = []
	for threat in COUNTERS:
		var share: float = float(profile.get(threat, 0.0))
		if share >= THREAT_FLOOR:
			scored.append({"role": str(COUNTERS[threat]), "share": share})
	scored.sort_custom(func(a, b): return a["share"] > b["share"])
	var out: Array = []
	for entry in scored:
		out.append(entry["role"])
	return out


# How much of this design is devoted to `role`, as a share of its weapons.
static func role_strength(blueprint: Dictionary, role: String) -> float:
	var wanted: Array = []
	if role == "anti_air":
		wanted = CommanderScript.ANTI_AIR_WEAPONS
	elif role == "point_defense":
		wanted = CommanderScript.POINT_DEFENSE_WEAPONS
	elif role == "indirect":
		wanted = CommanderScript.INDIRECT_WEAPONS
	elif role == "counter_armor":
		wanted = CommanderScript.ANTI_ARMOR_WEAPONS
	else:
		wanted = CommanderScript.ANTI_ARMOR_WEAPONS

	var weapons := 0
	var matching := 0
	for m in blueprint.get("modules", []):
		var type_id: String = str(m.get("type_id", ""))
		if not ModuleCatalogScript.needs_combat_script(type_id):
			continue
		weapons += 1
		if type_id in wanted:
			matching += 1
	if weapons <= 0:
		return 0.0
	return float(matching) / float(weapons)


# The reordered and adapted pool for Operations.
#
# STABLE, AND LOSSLESS. Every design goes in exactly once and none is dropped -
# the AI keeps its full pool and only changes what it reaches for first.
# AI OVERHAUL: Also applies ammo and armor adaptations to counter observed
# player damage types and armor choices in Operations!
static func order_roster(pool: Array, history: Array, unlocked_techs: Array = []) -> Array:
	var prof: Dictionary = threat_profile(history)
	var roles: Array = wanted_roles(prof)
	if roles.is_empty() or pool.is_empty():
		return pool.duplicate()

	# Find observed dominant player armor & damage class for adaptations
	var dominant_armor := ""
	var dominant_dmg := ""
	var highest_armor_share := 0.0
	var highest_dmg_share := 0.0
	for tag in prof:
		var s: float = float(prof[tag])
		if tag.begins_with("wears_") and s > highest_armor_share:
			highest_armor_share = s
			dominant_armor = tag.trim_prefix("wears_")
		elif tag.ends_with("_heavy") and s > highest_dmg_share:
			highest_dmg_share = s
			dominant_dmg = tag.trim_suffix("_heavy")

	var out: Array = []
	var taken: Dictionary = {}

	# HARVESTERS FIRST, ALWAYS.
	for i in range(pool.size()):
		if CommanderScript.design_fills_role(pool[i], "harvester"):
			out.append(pool[i])
			taken[i] = true

	for role in roles:
		var candidates: Array = []
		for i in range(pool.size()):
			if taken.has(i):
				continue
			if CommanderScript.design_fills_role(pool[i], role, dominant_armor):
				candidates.append({"index": i, "strength": role_strength(pool[i], role)})
		candidates.sort_custom(func(a, b): return a["strength"] > b["strength"])
		for entry in candidates:
			var picked_design: Dictionary = pool[entry["index"]]
			# Operations adaptation: adapt ammo and armor if applicable!
			if not dominant_armor.is_empty():
				picked_design = ThreatAnalyzer.adapt_ammo(picked_design, dominant_armor, unlocked_techs)
			if not dominant_dmg.is_empty():
				picked_design = ThreatAnalyzer.adapt_armor(picked_design, dominant_dmg, unlocked_techs)

			out.append(picked_design)
			taken[entry["index"]] = true

	for i in range(pool.size()):
		if not taken.has(i):
			var remaining_design: Dictionary = pool[i]
			if not dominant_armor.is_empty():
				remaining_design = ThreatAnalyzer.adapt_ammo(remaining_design, dominant_armor, unlocked_techs)
			if not dominant_dmg.is_empty():
				remaining_design = ThreatAnalyzer.adapt_armor(remaining_design, dominant_dmg, unlocked_techs)
			out.append(remaining_design)
	return out


# A one-line account of what the AI decided and why, for the draft screen and
# for the log. An adaptive opponent the player cannot perceive adapting reads as
# an inconsistent one.
static func explain(history: Array) -> String:
	var profile: Dictionary = threat_profile(history)
	var roles: Array = wanted_roles(profile)
	if roles.is_empty():
		return "No dominant threat observed - fielding a balanced force."
	var parts: Array = []
	for threat in COUNTERS:
		if COUNTERS[threat] in roles:
			parts.append("%s (%.0f%% of what you fielded)"
				% [threat, float(profile.get(threat, 0.0)) * 100.0])
	return "Answering " + ", ".join(PackedStringArray(parts)) + "."
