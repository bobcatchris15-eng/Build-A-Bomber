extends "res://tests/suite_base.gd"
# Counter-drafting: does the opponent actually adapt?
#
# The plan's own acceptance test is here verbatim - feed a log of all-air and
# assert the drafted roster gains anti-air - plus the failure modes that make an
# adaptive AI worse than a static one: over-reacting to a single scout, throwing
# away its economy to chase a counter, and countering an army the player has
# already abandoned.

const CounterDraftScript = preload("res://scripts/battle/ai/counter_draft.gd")
const CommanderScript = preload("res://scripts/battle/ai/commander.gd")
const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")


func _pool() -> Array:
	var bp = BlueprintManagerScript.new()
	root.add_child(bp)
	var out: Array = []
	for path in ["res://data/loadout/magpie_ore_hauler.json",
			"res://data/loadout/bulwark_mbt.json",
			"res://data/loadout/rattler_scout.json",
			"res://data/loadout/warden_aa.json",
			"res://data/loadout/breaker_td.json"]:
		var design: Dictionary = bp.load_blueprint(path)
		if not design.is_empty():
			out.append(design)
	bp.queue_free()
	return out


func _round(threats: Array) -> Dictionary:
	return {"player_threats": threats, "player_designs": [], "enemy_designs": []}


func _index_of_role(pool: Array, role: String) -> int:
	for i in range(pool.size()):
		if CommanderScript.design_fills_role(pool[i], role):
			return i
	return -1


# Classification is the foundation - every other suite here is meaningless if a
# fighter does not read as air. Locomotion is a TOP-LEVEL blueprint key, not a
# module, and scanning `modules` for it (the obvious wrong guess) classifies
# every aircraft in the game as ground.
func test_counter_draft_classifies_real_designs() -> bool:
	print("Running Test Suite: Counter-draft - threats read off real designs...")
	var bp = BlueprintManagerScript.new()
	root.add_child(bp)
	var ok := true

	var cases := {
		"res://data/loadout/raptor_striker.json": "air",
		"res://data/loadout/bulwark_mbt.json": "armor",
	}
	for path in cases:
		var design: Dictionary = bp.load_blueprint(path)
		if design.is_empty():
			print("  [FAIL] Could not load ", path)
			ok = false
			continue
		var threats: Array = CounterDraftScript.threats_of(design)
		if not cases[path] in threats:
			print("  [FAIL] '", design.get("name", "?"), "' should read as ",
				cases[path], ", got ", threats)
			ok = false

	# And the negative: a light wheeled scout is neither, or "armor" means
	# nothing and every roster counts as an armoured push.
	var scout: Dictionary = bp.load_blueprint("res://data/loadout/rattler_scout.json")
	if not scout.is_empty() and not CounterDraftScript.threats_of(scout).is_empty():
		print("  [FAIL] A light wheeled scout car registered as a threat: ",
			CounterDraftScript.threats_of(scout))
		ok = false

	bp.queue_free()
	if ok:
		print("  [PASS] Fighter reads as air, MBT as armour, scout car as neither.")
	return ok


# THE PLAN'S ACCEPTANCE TEST: feed a log of all-air, assert the drafted roster
# gains anti-air.
func test_counter_draft_answers_an_air_force() -> bool:
	print("Running Test Suite: Counter-draft - an all-air log draws anti-air...")
	var pool: Array = _pool()
	if pool.size() < 4:
		print("  [FAIL] Could not load the bundled designs this needs (got ", pool.size(), ")")
		return false

	var ok := true
	var before: int = _index_of_role(pool, "anti_air")
	var history: Array = [_round(["air", "air"]), _round(["air", "air", "air"])]
	var drafted: Array = CounterDraftScript.order_roster(pool, history)
	var after: int = _index_of_role(drafted, "anti_air")

	if after < 0:
		print("  [FAIL] The drafted roster has no anti-air design at all")
		ok = false
	elif after >= before and before >= 0:
		print("  [FAIL] Anti-air did not move up the roster: index %d -> %d" % [before, after])
		ok = false

	# It has to be reachable by the thing that consumes the order:
	# ai_design_for_role() takes the FIRST match, so anti-air must outrank every
	# other combat design, not merely have moved.
	var first_combat := -1
	for i in range(drafted.size()):
		if not CommanderScript.design_fills_role(drafted[i], "harvester"):
			first_combat = i
			break
	if first_combat >= 0 and not CommanderScript.design_fills_role(drafted[first_combat], "anti_air"):
		print("  [FAIL] The first combat design drafted is '",
			drafted[first_combat].get("name", "?"), "', not an anti-air one")
		ok = false

	# LOSSLESS. Every design must still be there - an AI that drops designs to
	# make room for counters loses capabilities it will need later.
	if drafted.size() != pool.size():
		print("  [FAIL] Roster changed size: %d -> %d" % [pool.size(), drafted.size()])
		ok = false

	# DEDICATION, not just qualification. The Culverin SPG mounts a CIWS alongside
	# its artillery piece, so design_fills_role() honestly says yes - but a howitzer with
	# point defence bolted on is not the answer to an air force, and taking the
	# first qualifying design in pool order fielded exactly that.
	var bp = BlueprintManagerScript.new()
	root.add_child(bp)
	var warden: Dictionary = bp.load_blueprint("res://data/loadout/warden_aa.json")
	var spg: Dictionary = bp.load_blueprint("res://data/loadout/culverin_spg.json")
	if not warden.is_empty() and not spg.is_empty():
		var w: float = CounterDraftScript.role_strength(warden, "anti_air")
		var s: float = CounterDraftScript.role_strength(spg, "anti_air")
		if w <= s:
			print("  [FAIL] A dedicated AA platform (%.2f) does not outrank an SPG with a CIWS (%.2f)"
				% [w, s])
			ok = false
		# And through the real ordering, with the SPG placed FIRST in the pool so
		# a first-match-wins implementation would pick it.
		var stacked: Array = [spg, warden]
		var ordered: Array = CounterDraftScript.order_roster(stacked, history)
		if str(ordered[0].get("name", "")) != str(warden.get("name", "")):
			print("  [FAIL] With the SPG listed first, the draft still led with '",
				ordered[0].get("name", "?"), "'")
			ok = false
	bp.queue_free()

	if ok:
		print("  [PASS] Anti-air moved from index %d to %d, leads the combat designs, and the dedicated platform outranks an incidental CIWS."
			% [before, after])
	return ok


# Economy is not a counter-pick. An AI that promoted three flak trucks above its
# only ore hauler would answer the player's air force by starving to death.
func test_counter_draft_never_demotes_the_harvester() -> bool:
	print("Running Test Suite: Counter-draft - the harvester stays first...")
	var pool: Array = _pool()
	if pool.is_empty():
		print("  [FAIL] No designs loaded")
		return false

	var ok := true
	for history in [[_round(["air", "air"])], [_round(["armor", "armor", "armor"])],
			[_round(["air", "armor"]), _round(["air", "air"])]]:
		var drafted: Array = CounterDraftScript.order_roster(pool, history)
		if drafted.is_empty():
			continue
		if not CommanderScript.design_fills_role(drafted[0], "harvester"):
			print("  [FAIL] After a ", history, " log the roster leads with '",
				drafted[0].get("name", "?"), "', not a harvester")
			ok = false

	if ok:
		print("  [PASS] Every counter-draft still opens with a harvester.")
	return ok


# One scout aircraft in twenty units is not an air force. An AI that rebuilds
# itself around a single sighting has been baited, and baiting it would be the
# dominant strategy.
func test_counter_draft_ignores_a_token_threat() -> bool:
	print("Running Test Suite: Counter-draft - a single scout is not an air force...")
	var ok := true

	# One air among nine ground: 10%, under THREAT_FLOOR.
	var token: Array = ["air"]
	for _i in range(9):
		token.append("armor")
	var roles: Array = CounterDraftScript.wanted_roles(
		CounterDraftScript.threat_profile([_round(token)]))
	if "anti_air" in roles:
		print("  [FAIL] A 10% air presence pulled the roster toward anti-air: ", roles)
		ok = false
	if not "anti_armor" in roles:
		print("  [FAIL] A 90% armour presence did NOT draw anti-armour: ", roles)
		ok = false

	# Round one has no history, so there is nothing to counter and the pool must
	# come back untouched rather than arbitrarily reordered.
	var pool: Array = _pool()
	var unchanged: Array = CounterDraftScript.order_roster(pool, [])
	if unchanged.size() != pool.size():
		print("  [FAIL] An empty history changed the roster size")
		ok = false
	else:
		for i in range(pool.size()):
			if unchanged[i].get("name", "") != pool[i].get("name", ""):
				print("  [FAIL] An empty history reordered the roster at index ", i)
				ok = false
				break

	if ok:
		print("  [PASS] Token threats are ignored, and round one is a no-op.")
	return ok


# The player re-drafts too. Countering the army they have already abandoned is
# worse than not countering at all, so recent rounds have to outweigh old ones.
func test_counter_draft_weights_recent_engagements() -> bool:
	print("Running Test Suite: Counter-draft - recency beats history...")
	var ok := true

	# Three rounds of armour, then one of air. Raw counting says armour 3:1;
	# with recency the most recent round has to be able to win.
	var history: Array = [
		_round(["armor", "armor"]),
		_round(["armor", "armor"]),
		_round(["armor", "armor"]),
		_round(["air", "air", "air", "air"]),
	]
	var profile: Dictionary = CounterDraftScript.threat_profile(history)
	if float(profile.get("air", 0.0)) <= float(profile.get("armor", 0.0)):
		print("  [FAIL] Four aircraft last round did not outweigh older armour: ", profile)
		ok = false

	# But not so aggressively that history stops counting at all - armour seen
	# three rounds running must still clear the floor.
	if float(profile.get("armor", 0.0)) < CounterDraftScript.THREAT_FLOOR:
		print("  [FAIL] Three rounds of armour decayed below the threat floor: ", profile)
		ok = false

	# The profile is a set of shares, so it has to sum to 1.
	var total := 0.0
	for key in profile:
		total += float(profile[key])
	if not is_equal_approx(total, 1.0):
		print("  [FAIL] Threat shares sum to ", total, ", expected 1.0")
		ok = false

	if ok:
		print("  [PASS] air=%.2f armour=%.2f - the recent round wins, the old one still counts."
			% [profile.get("air", 0.0), profile.get("armor", 0.0)])
	return ok
