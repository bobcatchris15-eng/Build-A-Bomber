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

# The threats worth answering, and the role that answers each. Deliberately
# short: a counter-draft that models eight threat axes on five rounds of data is
# fitting noise.
const COUNTERS := {
	"air": "anti_air",
	"armor": "anti_armor",
}

# How much a design seen LAST round outweighs one seen four rounds ago. Recency
# matters because the player re-drafts too - countering the army they have
# already abandoned is worse than not countering at all.
const RECENCY_FALLOFF := 0.6

# Below this share of the observed force, a threat is not worth bending the
# roster around. One scout aircraft in twenty units is not an air force, and an
# AI that rebuilds itself around it has been baited.
const THREAT_FLOOR := 0.2


# What threats does this design pose? Tags, not a single class: a flying gunship
# with a railgun is both.
static func threats_of(blueprint: Dictionary) -> Array:
	var out: Array = []
	var hull: String = str(blueprint.get("hull_type", "brenntal_medium_a"))
	# Locomotion is a TOP-LEVEL key on the blueprint, not an entry in `modules`.
	# Scanning the module list for it finds nothing and quietly classifies every
	# aircraft in the game as ground.
	var loco: String = str(blueprint.get("locomotion", {}).get("type_id", ""))

	# "airborne" is the trait the unit runtime's is_flying branch reads, so this
	# is the same definition the game uses rather than a second list of flying
	# locomotion ids to keep in sync with it.
	if "airborne" in ModuleCatalogScript.get_traits(hull, loco):
		out.append("air")

	# Armour is about what it takes to kill, so it is the hull's own class OR how
	# heavily it is plated - a medium hull under thick composite is an
	# anti-armour problem whatever the catalog calls its chassis.
	#
	# The class comes off the hull's own sidecar, NOT off its slug. This used to
	# read `hull.begins_with("heavy") or hull.begins_with("assault")`, which was
	# true of the old catalogue's names (heavy_*, assault_*) and is true of
	# nothing at all under the family slugs the 81-hull rebuild introduced -
	# every heavy hull is now named <manufacturer>_heavy_<variant>, so the class
	# is the middle token and the prefix test silently never fired. Every design
	# that still classified as armour after the rename did so on thickness alone.
	#
	# Deliberately the DECLARED class and not get_hull_size_tier(), which folds
	# Transport and Oddball into its "heavy" tier for production-cost purposes.
	# That is right for costing and wrong here: an ore hauler on a transport
	# chassis is not an anti-armour problem.
	#
	# The thickness arm stays at 1.5 and is now the exception rather than the
	# rule: it exists for a medium chassis a player has plated up past what its
	# class implies. Bundled mobile armour runs 0.5-1.4 and is caught by class.
	# Foundations sit higher still but are buildings, and a static turret is not
	# a threat the AI answers by drafting anti-armour units.
	var hull_class: String = str(
		ModuleCatalogScript.get_module_data(hull).get("hull_class", "")).to_lower()
	var thickness: float = float(blueprint.get("armor_thickness", 0.0))
	if hull_class == "heavy" or thickness >= 1.5:
		out.append("armor")

	return out


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
#
# 1.0 is a purpose-built platform; a low score is a design that merely carries
# something which qualifies. The Warden AA (flak cannon + CIWS, 2/2) has to
# outrank the Culverin SPG (artillery + CIWS, 1/2) when the player brings
# aircraft, and pool order alone will not do that.
static func role_strength(blueprint: Dictionary, role: String) -> float:
	var wanted: Array = CommanderScript.ANTI_AIR_WEAPONS if role == "anti_air" \
		else CommanderScript.ANTI_ARMOR_WEAPONS
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


# The reordered pool.
#
# STABLE, AND LOSSLESS. Every design goes in exactly once and none is dropped -
# the AI keeps its full pool and only changes what it reaches for first, which is
# what ai_design_for_role() actually consumes. Dropping designs instead would
# quietly cost the AI its harvester the first time the player fielded aircraft.
static func order_roster(pool: Array, history: Array) -> Array:
	var roles: Array = wanted_roles(threat_profile(history))
	if roles.is_empty() or pool.is_empty():
		return pool.duplicate()

	var out: Array = []
	var taken: Dictionary = {}

	# HARVESTERS FIRST, ALWAYS. Economy is not a counter-pick, and an AI that
	# promoted three flak trucks above its only ore hauler would counter the
	# player's air force by starving to death.
	for i in range(pool.size()):
		if CommanderScript.design_fills_role(pool[i], "harvester"):
			out.append(pool[i])
			taken[i] = true

	for role in roles:
		# Sorted by how much of the design is actually devoted to the role, not
		# merely whether it qualifies. design_fills_role() answers a yes/no
		# question honestly - the Culverin SPG really does mount a CIWS and really
		# can shoot at aircraft - but a howitzer with point defence bolted on is
		# not the answer to an air force, and taking the first qualifying design
		# in pool order fielded exactly that.
		var candidates: Array = []
		for i in range(pool.size()):
			if taken.has(i):
				continue
			if CommanderScript.design_fills_role(pool[i], role):
				candidates.append({"index": i, "strength": role_strength(pool[i], role)})
		candidates.sort_custom(func(a, b): return a["strength"] > b["strength"])
		for entry in candidates:
			out.append(pool[entry["index"]])
			taken[entry["index"]] = true

	for i in range(pool.size()):
		if not taken.has(i):
			out.append(pool[i])
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
