class_name Commander
extends RefCounted
# The AI's macro brain: what to spend on next.
#
# WHAT REPLACES WHAT. enemy_ai.gd was four fixed-interval timers - produce every
# 14 s, wave every 55 s, check structures every 8 s, trickle resources - driving
# imperative rules. Nothing was ever weighed against anything else, so the AI
# could not be behind on economy and know it, and its "counter-picking" was a
# single boolean bias in front of a round-robin cycle. Waves were not a plan
# either: _launch_wave() ordered EVERY live unit to attack the HQ, so the AI had
# exactly one tactic and used it on a timer regardless of whether it could win.
#
# THE MODEL. Every tick, score a fixed list of actions with
# U(a) = sum of w_i * c_i(x_i) and take the best one that is affordable. The
# weights are the personality; the considerations are in considerations.gd.
#
# WHAT IT MAY NOT DO. It reads the same EconomyService and VisionService the
# player's HUD does, and it issues orders through OrderService like the player.
# It has no privileged knowledge: if it cannot see a unit, it cannot count it.
# That is enforced by construction - there is no other way in here - rather than
# by discipline, which is the whole reason the AI was rebuilt on the services
# instead of beside them.
#
# The one concession is a difficulty-scaled income trickle, which the old AI
# already had as PITY_METAL/PITY_CRYSTAL. It is honest about being a handicap
# rather than pretending to be intelligence.

const C = preload("res://scripts/battle/ai/considerations.gd")
const BuildingCatalogScript = preload("res://scripts/battle/economy/building_catalog.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")

# Reused verbatim from enemy_ai.gd:109-118. The CLASSIFICATION was sound - these
# really are the roster's answers to air and to armour - it was only its consumer
# that was weak. Rewriting the lists would throw away roster knowledge that has
# nothing to do with why the old AI was bad.
#
# sam_launcher ADDED. The original list predates the roster expansion, so the
# one purpose-built surface-to-air weapon in the game was not recognised as an
# answer to air - an AI holding a SAM turret design would keep scoring "build
# anti-air" and pick something else.
const ANTI_AIR_WEAPONS := ["ciws", "flak_cannon", "pd_laser", "sam_launcher"]
const ANTI_ARMOR_WEAPONS := ["gauss_railgun", "artillery", "ion_cannon", "tesla_coil",
	"coil_gun", "recoilless_rifle", "ballista", "anti_materiel_rifle"]

enum Action {
	EXPAND_ECONOMY,   # another harvester
	ADD_REFINERY,
	ADD_POWER,
	ADD_PRODUCTION,   # another manufactory: faster queue, not a second one
	BUILD_ANTI_AIR,
	BUILD_ANTI_ARMOR,
	BUILD_GENERAL,
	DEFEND,           # pull squads home
	BUILD_DEFENSE,    # a turret, which holds ground a squad would have to stand on
	PUSH,             # commit to an attack
}

# How long a decision stands before it is re-scored. Not a cooldown on acting -
# it is the tick rate of thinking. Fast enough to react to a raid, slow enough
# that the AI does not thrash between two near-equal actions every frame.
const DECISION_INTERVAL := 2.0

# Below this the AI will not commit to an attack no matter how good the target
# looks. An army that attacks in dribs is an army that dies in dribs, and the old
# runtime's every-unit-attacks-on-a-timer is exactly that failure.
const MIN_PUSH_SQUAD := 4

# Personality. These are the numbers to move to make an AI greedy, turtly or
# aggressive; nothing else about it needs to change.
const WEIGHTS := {
	Action.EXPAND_ECONOMY: 1.0,
	Action.ADD_REFINERY: 0.9,
	Action.ADD_POWER: 1.2,
	Action.ADD_PRODUCTION: 0.8,
	Action.BUILD_ANTI_AIR: 1.1,
	Action.BUILD_ANTI_ARMOR: 1.1,
	Action.BUILD_GENERAL: 0.6,
	Action.DEFEND: 1.6,
	Action.BUILD_DEFENSE: 1.0,
	Action.PUSH: 0.7,
}

# Turrets the AI will put up before it stops seeing the point. A base ringed with
# static defence is a base that has spent its economy on ground it already holds.
const DEFENCE_TARGET := 3

# Target harvester count, PER REFINERY.
#
# Three because a refinery has exactly three dock bays: a fourth truck cannot
# unload any sooner than the queue lets it, so it costs a unit's worth of metal
# to add nothing. The old value of 4 had the AI spending its entire income on a
# truck that would only orbit - measured, it reached three harvesters and never
# once fielded a combat unit, because every credit went into the next harvester
# before anything else could compete.
const HARVESTERS_PER_REFINERY := 3

# How far ahead an affordability decision looks, in seconds.
#
# THE BUG THIS FIXES, because it is not obvious from the constant. Every action
# below gates on a metal ramp with a floor of 100-200. Production draws its cost
# gradually across the build, so a team with anything queued sits at ~0 metal for
# the entire build - which means every one of those ramps read zero, score() vetoes
# on any zero consideration, and the commander returned "no action at all".
#
# Measured before this change: `decision=NOTHING, scores: all zero` unbroken from
# tick 3600 to 19800 of a match that ended at 27447. The AI still grew, but only
# on the momentum of units queued in the first two seconds - it was not deciding
# anything for two thirds of the match. It looked like a stalled economy and was
# really a commander that had blinded itself by asking the wrong question.
#
# 30 s because that is roughly one build: the question worth asking is "can I pay
# for this by the time it would finish", not "can I pay for it this instant".
const PLANNING_HORIZON := 30.0

var team: int = 1
var difficulty: String = "normal"

var _world = null
var _timer: float = 0.0
var _last_action: int = -1


func setup(world, ai_team: int, ai_difficulty: String = "normal") -> void:
	_world = world
	team = ai_team
	difficulty = ai_difficulty


func tick(delta: float) -> void:
	if _world == null:
		return
	_timer += delta
	if _timer < DECISION_INTERVAL:
		return
	_timer = 0.0
	var state := read_state()
	var choice := decide(state)
	_last_action = choice
	if choice >= 0:
		_execute(choice, state)


# --- Perception --------------------------------------------------------------

# Everything the commander is allowed to know, gathered once so scoring is a pure
# function of a dictionary. That is what makes decide() testable without a match:
# hand it a state, assert what it picks.
#
# ENEMY COUNTS ARE FOG-GATED. is_visible_to_team() is the same call the player's
# minimap uses, so an unscouted army is an unknown army to the AI too.
func read_state() -> Dictionary:
	var economy = _world.economy
	var own_units: Array = _world.get_team_units(team)
	var own_structures: Array = _world.get_team_structures(team)

	var harvesters := 0
	var combat: Array = []
	for u in own_units:
		if u.is_harvester:
			harvesters += 1
		else:
			combat.append(u)

	# IN-FLIGHT PRODUCTION COUNTS. This is the difference between an AI that
	# builds an economy and one that never builds an army.
	#
	# Reading only LIVE harvesters means a truck that is paid for and 90% built
	# does not exist yet, so EXPAND_ECONOMY keeps scoring highest and keeps
	# queueing more. The queue depth cap (AI_MAX_QUEUE_DEPTH = 2) then fills
	# permanently with harvesters, and every ai_build_unit() call for a COMBAT
	# design is refused at the door because that queue is full.
	#
	# Measured before this: the medium queue sat at depth 2 with an Ore Trucker at
	# its head for the entire match, the commander chose BUILD_GENERAL 3,702 times,
	# and ZERO combat units were ever enqueued - let alone produced. It looked like
	# an economy problem and survived the economy being fixed.
	harvesters += _queued_harvesters()

	var enemy_air := 0
	var enemy_armour := 0
	var enemy_seen := 0
	for enemy_team in [0]:
		for u in _world.get_team_units(enemy_team):
			if not is_instance_valid(u) or u.is_dead:
				continue
			if _world.has_method("is_visible_to_team") and not _world.is_visible_to_team(u, team):
				continue
			enemy_seen += 1
			if u.is_flying:
				enemy_air += 1
			if is_instance_valid(u.hull_node) and u.hull_node.has_meta("armor_thickness") \
					and u.hull_node.get_meta("armor_thickness") >= 2.0:
				enemy_armour += 1

	return {
		"credits": economy.credits(team),
		# What the affordability considerations below actually read. See
		# PLANNING_HORIZON - cash-on-hand is the wrong number under drip-fed
		# production, and reading it was why this commander scored every action at
		# zero for four minutes of a seven-minute match.
		"budget": economy.budget(team, PLANNING_HORIZON),
		"income_rate": economy.income_rate(team),
		"harvesters": harvesters,
		"combat_units": combat.size(),
		"refineries": _count_kind(own_structures, "refinery"),
		"manufactories": _count_manufactories(own_structures),
		"low_power": economy.is_low_power(team),
		"enemy_seen": enemy_seen,
		"enemy_air_share": C.share(enemy_air, enemy_seen),
		"enemy_armour_share": C.share(enemy_armour, enemy_seen),
		"base_threatened": _base_threatened(),
		"can_build_harvester": _world.ai_can_build_role(team, "harvester"),
		"defences": _count_kind(own_structures, "defense"),
		"combat": combat,
	}


func _count_kind(structures: Array, kind: String) -> int:
	var n := 0
	for s in structures:
		if s.kind == kind:
			n += 1
	return n


# Harvesters already paid for and moving through a production queue.
#
# Matched on the job's blueprint rather than on its label, so a design the PLAYER
# built and the AI happened to draft still counts - the same "roles come from
# modules" rule design_fills_role() follows everywhere else.
func _queued_harvesters() -> int:
	if _world == null or _world.production == null:
		return 0
	var n := 0
	for queue_name in BuildingCatalogScript.QUEUES:
		for job in _world.production.queue(team, queue_name):
			var bp: Dictionary = job.get("blueprint", {})
			if not bp.is_empty() and design_fills_role(bp, "harvester"):
				n += 1
	return n


func _count_manufactories(structures: Array) -> int:
	var n := 0
	for s in structures:
		if s.kind.ends_with("manufactory"):
			n += 1
	return n


# Anything hostile and VISIBLE near a building the AI owns. Fog-gated like
# everything else: an AI that reacts to an attack it cannot see is cheating, and
# a raid that goes unnoticed until the first structure burns is correct.
func _base_threatened() -> bool:
	const THREAT_RADIUS := 45.0
	for s in _world.get_team_structures(team):
		for u in _world.get_team_units(0):
			if not is_instance_valid(u) or u.is_dead or u.is_harvester:
				continue
			if _world.has_method("is_visible_to_team") and not _world.is_visible_to_team(u, team):
				continue
			if u.global_position.distance_to(s.global_position) <= THREAT_RADIUS:
				return true
	return false


# --- Scoring -----------------------------------------------------------------

# The whole decision, as a pure function. No side effects, no world access.
func decide(state: Dictionary) -> int:
	var scores := score_all(state)
	var best := -1
	var best_score := 0.0
	for action in scores:
		if scores[action] > best_score:
			best_score = scores[action]
			best = action
	return best


func score_all(state: Dictionary) -> Dictionary:
	var out := {}
	for action in WEIGHTS:
		out[action] = _score(action, state)
	return out


func _score(action: int, state: Dictionary) -> float:
	var w: float = WEIGHTS[action]
	match action:
		Action.EXPAND_ECONOMY:
			# Wants harvesters early and stops caring once the refinery is
			# saturated. Gated on somewhere to deliver AND the ability to actually
			# build one: without the second veto this outscores everything from the
			# opening tick, fails silently for want of the right factory, and
			# re-wins next tick - an AI that spends the whole match deciding to
			# build a harvester it has no way to build.
			return C.score(w, [
				C.falloff(state["harvesters"], 0.0,
					float(maxi(1, state["refineries"]) * HARVESTERS_PER_REFINERY)),
				C.ramp(state["budget"], 100.0, 400.0),
				1.0 if state["refineries"] > 0 else 0.0,
				# "Can I build one", not "do I own a factory". Owning a light
				# manufactory while the only harvester design is a medium hull is
				# exactly the state that starved it at 86 metal.
				1.0 if state["can_build_harvester"] else 0.0,
			])
		Action.ADD_REFINERY:
			# One is enough until there are trucks queueing for it.
			return C.score(w, [
				C.falloff(state["refineries"], 0.0, 2.0),
				C.ramp(state["harvesters"], 2.0, 5.0),
				C.ramp(state["budget"], 200.0, 500.0),
			])
		Action.ADD_POWER:
			# A veto in reverse: worthless at full power, urgent in a brownout.
			# Low power throttles the production queues, so this outranks almost
			# everything while it is true.
			return C.score(w, [
				1.0 if state["low_power"] else 0.0,
				C.ramp(state["budget"], 100.0, 300.0),
			])
		Action.ADD_PRODUCTION:
			# More manufactories make the ONE queue faster (the RA speed table),
			# so this saturates where that table does rather than growing forever.
			#
			# DELIBERATELY NOT GATED ON HAVING HARVESTERS. The obvious "only expand
			# production once the economy is running" consideration reads as sense
			# and is a deadlock: at zero harvesters it vetoes this to nothing, while
			# EXPAND_ECONOMY cannot run without a factory, so the AI sits on its
			# opening money forever. The first manufactory is what breaks the
			# chicken-and-egg, so nothing may veto it.
			#
			# URGENT while the economy cannot start. Being unable to build a
			# harvester is the one genuinely unrecoverable state - there is no
			# income to dig out of it with - so it outranks the ordinary "more
			# factories is nice" reading by a wide margin.
			var blocked: float = 0.0 if state["can_build_harvester"] else 1.0
			return C.score(w, [
				maxf(C.falloff(state["manufactories"], 1.0, 4.0), blocked),
				maxf(C.ramp(state["budget"], 150.0, 700.0), blocked),
			]) + blocked * w * 2.0
		Action.BUILD_ANTI_AIR:
			# Curved hard: a scout flyer should not trigger a full AA pivot, but a
			# real air army should outrank general production decisively.
			return C.score(w, [
				C.curve(state["enemy_air_share"], 1.6),
				C.ramp(state["budget"], 150.0, 400.0),
				1.0 if state["manufactories"] > 0 else 0.0,
			])
		Action.BUILD_ANTI_ARMOR:
			return C.score(w, [
				C.curve(state["enemy_armour_share"], 1.6),
				C.ramp(state["budget"], 150.0, 400.0),
				1.0 if state["manufactories"] > 0 else 0.0,
			])
		Action.BUILD_GENERAL:
			# The floor. Deliberately low-weighted so it loses to anything with an
			# actual reason, and wins when nothing else has one.
			# The metal floor is deliberately BELOW what EXPAND_ECONOMY needs, so
			# once the economy is running this can win a tick rather than being
			# perpetually outbid by the next harvester.
			return C.score(w, [
				C.ramp(state["budget"], 120.0, 400.0),
				1.0 if state["manufactories"] > 0 else 0.0,
			])
		Action.DEFEND:
			# Highest weight in the table, and vetoed unless the base is genuinely
			# under threat. Losing production to a raid costs more than any build.
			return C.score(w, [
				1.0 if state["base_threatened"] else 0.0,
				C.ramp(state["combat_units"], 1.0, 4.0),
			])
		Action.BUILD_DEFENSE:
			# Wanted once the AI has SEEN something, and more so while its base is
			# being hit - a turret holds ground that would otherwise cost a squad
			# standing on it. Saturates at DEFENCE_TARGET so it does not turtle its
			# whole economy into concrete.
			return C.score(w, [
				C.falloff(state["defences"], 0.0, float(DEFENCE_TARGET)),
				C.ramp(state["budget"], 200.0, 500.0),
				maxf(C.share(state["enemy_seen"], 4.0), 1.0 if state["base_threatened"] else 0.0),
			])
		Action.PUSH:
			# Needs a real army AND something worth walking to. The MIN_PUSH_SQUAD
			# floor is what stops the old trickle-attack behaviour.
			return C.score(w, [
				1.0 if state["combat_units"] >= MIN_PUSH_SQUAD else 0.0,
				C.ramp(state["combat_units"], float(MIN_PUSH_SQUAD), 10.0),
				0.0 if state["base_threatened"] else 1.0,
			])
	return 0.0


func last_action() -> int:
	return _last_action


func action_name(action: int) -> String:
	if action < 0:
		return "NOTHING"
	return Action.keys()[action]


# --- Execution ---------------------------------------------------------------
#
# Deliberately thin. Everything the AI does goes through the same services the
# player's UI calls - ProductionService to build, OrderService to command - so
# there is no second path where AI-only behaviour could accumulate.

func _execute(action: int, state: Dictionary) -> void:
	match action:
		Action.EXPAND_ECONOMY:
			_world.ai_build_unit(team, "harvester")
		Action.ADD_REFINERY:
			_world.ai_build_structure(team, "refinery")
		Action.ADD_POWER:
			_world.ai_build_structure(team, "power_plant")
		Action.ADD_PRODUCTION:
			# The director picks WHICH manufactory - it knows about hull tiers and
			# this does not need to.
			_world.ai_build_production(team)
		Action.BUILD_ANTI_AIR:
			_world.ai_build_unit(team, "anti_air")
		Action.BUILD_ANTI_ARMOR:
			_world.ai_build_unit(team, "anti_armor")
		Action.BUILD_GENERAL:
			_world.ai_build_unit(team, "general")
		Action.DEFEND:
			_world.ai_defend(team, state["combat"])
		Action.BUILD_DEFENSE:
			_world.ai_build_defence(team)
		Action.PUSH:
			_world.ai_push(team, state["combat"])


# Does this design answer `role`? The blueprint's own module list is the source
# of truth, so a design the PLAYER built counts as anti-air if it mounts a CIWS -
# the AI does not need a curated list of its own units.
static func design_fills_role(blueprint: Dictionary, role: String) -> bool:
	if role == "harvester":
		for m in blueprint.get("modules", []):
			if m.get("type_id", "") == "resource_harvester":
				return true
		return false
	if role == "general":
		# "General" is the fallback COMBAT role, and a harvester is not a combat
		# unit. It used to return true for literally anything, which was harmless
		# only because the bundled roster happened to list the ore trucker eighth -
		# the moment anything reordered that pool, BUILD_GENERAL started producing
		# harvesters and the AI built an economy it had no army to protect.
		# Found by the counter-draft promoting harvesters to the front for a
		# completely different (and correct) reason.
		return not design_fills_role(blueprint, "harvester")
	var wanted: Array = ANTI_AIR_WEAPONS if role == "anti_air" else ANTI_ARMOR_WEAPONS
	for m in blueprint.get("modules", []):
		if m.get("type_id", "") in wanted:
			return true
	return false
