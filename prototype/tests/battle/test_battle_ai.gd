extends "res://tests/suite_base.gd"
# Phase 3: the opponent's decision-making.
#
# decide() is a pure function of a state dictionary, which is the whole reason
# the commander reads the world once into `read_state()` rather than querying it
# mid-scoring. Every test here hands it a hand-built state and asserts what it
# picks - no match, no navmesh, no opponent.
#
# THE BUGS THESE PIN WERE ALL DEADLOCKS, and every one of them looked like sound
# design when written. A utility AI fails quietly: it does not crash, it just
# picks something impossible forever while its considerations all read as
# reasonable in isolation.

const CommanderScript = preload("res://scripts/battle/ai/commander.gd")
const C = preload("res://scripts/battle/ai/considerations.gd")
const SquadScript = preload("res://scripts/battle/ai/squad.gd")


# A plausible mid-game state, which individual tests perturb one field at a time.
func _state(overrides: Dictionary = {}) -> Dictionary:
	var base := {
		"metal": 500,
		"crystal": 100,
		"harvesters": 2,
		"combat_units": 3,
		"refineries": 1,
		"manufactories": 1,
		"low_power": false,
		"enemy_seen": 4,
		"enemy_air_share": 0.0,
		"enemy_armour_share": 0.0,
		"base_threatened": false,
		"can_build_harvester": true,
		"defences": 0,
		"combat": [],
	}
	for k in overrides:
		base[k] = overrides[k]
	return base


func _commander() -> Commander:
	return CommanderScript.new()


# --- Considerations ----------------------------------------------------------

# Every consideration must land in 0..1. The weighted sum depends on it: a curve
# returning 1.5 silently outranks its own weight and the personality table stops
# describing the AI's priorities.
func test_considerations_stay_normalised() -> bool:
	print("Running Test Suite: AI - considerations stay in 0..1...")
	for x in [-1000.0, -1.0, 0.0, 0.5, 1.0, 50.0, 1e9]:
		for pair in [[0.0, 1.0], [10.0, 20.0], [5.0, 5.0]]:
			for v in [C.ramp(x, pair[0], pair[1]), C.falloff(x, pair[0], pair[1])]:
				if v < 0.0 or v > 1.0:
					print("  [FAIL] value %f out of range for x=%f" % [v, x])
					return false
	for n in [-1.0, 0.0, 0.5, 1.0, 2.0]:
		var v := C.curve(n, 1.6)
		if v < 0.0 or v > 1.0:
			print("  [FAIL] curve(%f) = %f is out of range" % [n, v])
			return false
	# share() must answer the empty case rather than dividing by zero - "what
	# fraction of their army is airborne" with no army must read as no threat.
	if not is_zero_approx(C.share(0.0, 0.0)) or not is_zero_approx(C.share(5.0, 0.0)):
		print("  [FAIL] share() with a zero whole should be 0")
		return false
	# A degenerate ramp must not divide by zero either.
	if C.ramp(5.0, 3.0, 3.0) != 1.0 or C.ramp(1.0, 3.0, 3.0) != 0.0:
		print("  [FAIL] a zero-width ramp misbehaves")
		return false
	print("  [PASS] considerations normalised")
	return true


# Any consideration at zero kills the action outright. That is the veto, and it
# is what stops a high threat score keeping an impossible action at the top of
# the list forever.
func test_a_zero_consideration_vetoes_the_action() -> bool:
	print("Running Test Suite: AI - a zero consideration is a veto...")
	if not is_zero_approx(C.score(10.0, [1.0, 0.0, 1.0])):
		print("  [FAIL] a zero consideration did not veto the action")
		return false
	if C.score(1.0, [1.0, 1.0]) <= 0.0:
		print("  [FAIL] an all-positive action scored zero")
		return false

	# THE AVERAGE, NOT THE SUM. Score must not grow just because an action has
	# more boxes to tick, or the weight table stops ordering anything - which is
	# exactly how DEFEND (the highest weight) lost to EXPAND_ECONOMY while the
	# base was being raided.
	if not is_equal_approx(C.score(1.0, [1.0, 1.0, 1.0]), C.score(1.0, [1.0])):
		print("  [FAIL] consideration COUNT changes the score - weights stop meaning anything")
		return false
	# Weight is what orders actions, at equal satisfaction.
	if C.score(2.0, [1.0, 1.0]) <= C.score(1.0, [1.0, 1.0]):
		print("  [FAIL] a heavier action did not outscore a lighter one")
		return false
	# And a fully-satisfied heavy action beats a half-satisfied one.
	if C.score(1.0, [1.0, 1.0]) <= C.score(1.0, [1.0, 0.5]):
		print("  [FAIL] better-satisfied considerations did not raise the score")
		return false
	if not is_zero_approx(C.score(1.0, [])):
		print("  [FAIL] an action with no considerations should score zero")
		return false
	print("  [PASS] veto semantics")
	return true


# --- The openings that deadlocked --------------------------------------------

# THE OPENING DEADLOCK. With no factory and no harvesters, the AI must decide to
# build production. Both of the obvious ways to write these considerations
# produce an AI that never does anything:
#
#   * EXPAND_ECONOMY outscores everything, then fails silently for want of a
#     factory, and wins again next tick - forever.
#   * ADD_PRODUCTION gated on "only expand production once the economy is
#     running" is vetoed at zero harvesters, which is exactly when it is needed.
#
# Measured: the AI sat on its opening 400 metal for the entire match.
func test_opening_move_is_not_a_deadlock() -> bool:
	print("Running Test Suite: AI - the opening move breaks the chicken-and-egg...")
	var commander := _commander()
	var opening := _state({
		"harvesters": 0, "manufactories": 0, "combat_units": 0,
		"metal": 400, "can_build_harvester": false,
	})
	var choice: int = commander.decide(opening)
	if choice < 0:
		print("  [FAIL] every action scored zero - the AI cannot open at all")
		return false
	if choice != CommanderScript.Action.ADD_PRODUCTION:
		print("  [FAIL] opening move was %s, expected ADD_PRODUCTION"
			% commander.action_name(choice))
		return false

	# And it must NOT pick the thing it cannot do.
	var scores: Dictionary = commander.score_all(opening)
	if scores[CommanderScript.Action.EXPAND_ECONOMY] > 0.0:
		print("  [FAIL] the AI wants a harvester it has no way to build")
		return false
	print("  [PASS] opening is ADD_PRODUCTION")
	return true


# "Can I build one" is not "do I own a factory". The AI's only harvester design
# is a MEDIUM hull, so owning a light manufactory and a harvester design still
# means it cannot build one - and it starved at 86 metal deciding to.
func test_harvester_wanting_tracks_buildability_not_factory_count() -> bool:
	print("Running Test Suite: AI - harvester demand tracks buildability...")
	var commander := _commander()
	var owns_wrong_factory := _state({
		"harvesters": 0, "manufactories": 1, "can_build_harvester": false,
	})
	var scores: Dictionary = commander.score_all(owns_wrong_factory)
	if scores[CommanderScript.Action.EXPAND_ECONOMY] > 0.0:
		print("  [FAIL] wants a harvester while unable to build one")
		return false
	if commander.decide(owns_wrong_factory) != CommanderScript.Action.ADD_PRODUCTION:
		print("  [FAIL] should be fixing production, chose %s"
			% commander.action_name(commander.decide(owns_wrong_factory)))
		return false

	# Once it CAN build one, it should want one.
	var able := _state({"harvesters": 0, "manufactories": 1, "can_build_harvester": true})
	if commander.score_all(able)[CommanderScript.Action.EXPAND_ECONOMY] <= 0.0:
		print("  [FAIL] will not build a harvester even when it can")
		return false
	print("  [PASS] buildability gating")
	return true


# --- Responsiveness ----------------------------------------------------------

# The point of utility scoring over the old timers: the choice must change with
# the situation. Air in the field should pull the AI toward anti-air, and a raid
# on the base should outrank building anything at all.
func test_decisions_respond_to_the_battlefield() -> bool:
	print("Running Test Suite: AI - decisions track the situation...")
	var commander := _commander()

	var calm := _state()
	var air := _state({"enemy_air_share": 0.9})
	if commander.score_all(air)[CommanderScript.Action.BUILD_ANTI_AIR] \
			<= commander.score_all(calm)[CommanderScript.Action.BUILD_ANTI_AIR]:
		print("  [FAIL] an air-heavy enemy did not raise the anti-air score")
		return false

	var armour := _state({"enemy_armour_share": 0.9})
	if commander.score_all(armour)[CommanderScript.Action.BUILD_ANTI_ARMOR] \
			<= commander.score_all(calm)[CommanderScript.Action.BUILD_ANTI_ARMOR]:
		print("  [FAIL] an armour-heavy enemy did not raise the anti-armour score")
		return false

	# A curve, not a step. A lone scout flyer must not trigger a full pivot -
	# that step-function behaviour is what made the old counter-picking read as
	# either oblivious or clairvoyant with nothing in between.
	var trickle := _state({"enemy_air_share": 0.1})
	var s_trickle: float = commander.score_all(trickle)[CommanderScript.Action.BUILD_ANTI_AIR]
	var s_flood: float = commander.score_all(air)[CommanderScript.Action.BUILD_ANTI_AIR]
	if s_trickle <= 0.0 or s_trickle >= s_flood:
		print("  [FAIL] anti-air is a step, not a ramp (%.2f vs %.2f)" % [s_trickle, s_flood])
		return false

	# Defence outranks everything while the base is actually being hit.
	var raided := _state({"base_threatened": true})
	if commander.decide(raided) != CommanderScript.Action.DEFEND:
		print("  [FAIL] did not defend a threatened base, chose %s"
			% commander.action_name(commander.decide(raided)))
		return false
	# And a squad must not walk out of a base that is under attack.
	if commander.score_all(raided)[CommanderScript.Action.PUSH] > 0.0:
		print("  [FAIL] wants to attack while its own base is being raided")
		return false

	# Low power throttles the production queues, so fixing it outranks new units.
	var brownout := _state({"low_power": true})
	if commander.score_all(brownout)[CommanderScript.Action.ADD_POWER] <= 0.0:
		print("  [FAIL] a brownout did not make power worth building")
		return false
	print("  [PASS] situational response")
	return true


# An army attacks together or not at all. The old runtime ordered every live unit
# at the enemy HQ on a timer, which fed units into a meat grinder a few at a time.
func test_push_requires_a_real_army() -> bool:
	print("Running Test Suite: AI - no attacking in dribs...")
	var commander := _commander()
	for n in range(0, CommanderScript.MIN_PUSH_SQUAD):
		var thin := _state({"combat_units": n})
		if commander.score_all(thin)[CommanderScript.Action.PUSH] > 0.0:
			print("  [FAIL] willing to attack with only %d units" % n)
			return false
	var army := _state({"combat_units": CommanderScript.MIN_PUSH_SQUAD + 4})
	if commander.score_all(army)[CommanderScript.Action.PUSH] <= 0.0:
		print("  [FAIL] will not attack even with a full squad")
		return false
	print("  [PASS] push threshold")
	return true


# --- Role matching -----------------------------------------------------------

# Roles are read off what a design actually MOUNTS, so a design the player built
# counts as anti-air if it carries a CIWS. The AI needs no curated list of its
# own units, which is what lets a drafted roster work later.
func test_roles_are_read_from_mounted_modules() -> bool:
	print("Running Test Suite: AI - design roles come from modules...")
	var aa := {"modules": [{"type_id": "ciws"}]}
	var at := {"modules": [{"type_id": "gauss_railgun"}]}
	var truck := {"modules": [{"type_id": "resource_harvester"}]}
	var plain := {"modules": [{"type_id": "autocannon"}]}

	if not CommanderScript.design_fills_role(aa, "anti_air"):
		print("  [FAIL] a CIWS design is not recognised as anti-air")
		return false
	if CommanderScript.design_fills_role(plain, "anti_air"):
		print("  [FAIL] an autocannon design counted as anti-air")
		return false
	if not CommanderScript.design_fills_role(at, "anti_armor"):
		print("  [FAIL] a railgun design is not recognised as anti-armour")
		return false
	if not CommanderScript.design_fills_role(truck, "harvester"):
		print("  [FAIL] a harvester module design is not recognised as a harvester")
		return false
	if CommanderScript.design_fills_role(plain, "harvester"):
		print("  [FAIL] a gun design counted as a harvester")
		return false
	# Anything at all fills "general", including an empty design - that is the
	# fallback role and must never be empty-handed.
	if not CommanderScript.design_fills_role({}, "general"):
		print("  [FAIL] nothing fills the general role")
		return false
	print("  [PASS] role matching")
	return true


# --- Squad behaviour ---------------------------------------------------------

# The retreat and regroup thresholds must not be equal, for the same reason the
# fog needed a hysteresis dead zone: a squad sitting on one shared threshold
# oscillates in and out of the fight instead of committing to either.
func test_squad_retreat_and_regroup_have_a_dead_zone() -> bool:
	print("Running Test Suite: AI - squad retreat/regroup hysteresis...")
	if SquadScript.REGROUP_HEALTH_FRACTION <= SquadScript.RETREAT_HEALTH_FRACTION:
		print("  [FAIL] regroup (%.2f) must be strictly above retreat (%.2f)"
			% [SquadScript.REGROUP_HEALTH_FRACTION, SquadScript.RETREAT_HEALTH_FRACTION])
		return false

	# An empty squad is spent and must not be ticked into doing anything.
	var squad = SquadScript.new()
	squad.setup(null, null, 1, [], Vector3.ZERO)
	if not squad.is_spent():
		print("  [FAIL] a squad with no units is not spent")
		return false
	# health_fraction on an empty squad must answer, not divide by zero.
	if squad.health_fraction() != 1.0:
		print("  [FAIL] an empty squad reports health %.2f" % squad.health_fraction())
		return false
	# Ticking a spent squad must be a no-op rather than an error.
	squad.tick(0.1)
	print("  [PASS] squad thresholds")
	return true


# Reinforcing must RAISE the bar the squad is judged against.
#
# The peak is what health_fraction() measures against, so a squad that gains
# fresh units without raising it reads as fully healthy while its original
# members are nearly dead - and then never retreats. Pinned because the obvious
# way to reinforce (assign `units` directly) silently reintroduces exactly that.
func test_reinforcing_raises_the_health_bar() -> bool:
	print("Running Test Suite: AI - reinforcing raises the peak...")
	var wounded := _fake_unit(20.0, 100.0)
	var squad = SquadScript.new()
	squad.setup(null, null, 1, [wounded], Vector3.ZERO)

	# One unit at 20/100, and the peak was taken at 20 - so it reads as healthy.
	# That is correct: the squad has not lost anything since it formed.
	if not is_equal_approx(squad.health_fraction(), 1.0):
		print("  [FAIL] a squad that has lost nothing should read as whole, got %.2f"
			% squad.health_fraction())
		wounded.free()
		return false

	var fresh := _fake_unit(100.0, 100.0)
	squad.reinforce([wounded, fresh])
	# Now the peak is 120. Losing the fresh unit must drop the fraction well below
	# 1.0 rather than being masked.
	if not is_equal_approx(squad.health_fraction(), 1.0):
		print("  [FAIL] right after reinforcing the squad should be at full, got %.2f"
			% squad.health_fraction())
		wounded.free()
		fresh.free()
		return false
	fresh.hp = 0.0
	fresh.is_dead = true
	var after := squad.health_fraction()
	if after >= 0.9:
		print("  [FAIL] losing the reinforcement barely moved health (%.2f) - the peak did not rise"
			% after)
		wounded.free()
		fresh.free()
		return false
	wounded.free()
	fresh.free()
	print("  [PASS] reinforce raises the peak")
	return true


# A squad only ever reads hp / max_hp / is_dead / attack_range off its members,
# so a node carrying those is a faithful stand-in and needs no blueprint, physics
# or navmesh.
class FakeUnit extends Node3D:
	var hp: float = 100.0
	var max_hp: float = 100.0
	var is_dead: bool = false
	var attack_range: float = 20.0


func _fake_unit(hp: float, max_hp: float) -> FakeUnit:
	var u := FakeUnit.new()
	u.hp = hp
	u.max_hp = max_hp
	u.set_meta("team", 1)
	root.add_child(u)
	return u
