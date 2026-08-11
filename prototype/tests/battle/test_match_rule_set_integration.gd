extends "res://tests/suite_base.gd"
# Battle-system unification (Phase 2): the smoke test for the read-side
# wiring in match_director.gd. The 9 tests in test_match_rule_set.gd
# cover the rule set itself; this one covers whether match_director
# actually reads the rule set when it is present, with the legacy
# fallback path left intact for the per-map smoke tests that build
# Battle.tscn directly without ever touching MatchRuleSet.
#
# Heavier than the unit tests above because it instantiates Battle.tscn
# and waits for the world to build; the SUITE_ORDER keeps it well clear
# of the navmesh flakes (placed in the early slot the same way
# test_match_rule_set.gd's suites are - neither depends on shared state).

const BattleTscn = preload("res://scenes/Battle.tscn")
const MatchRuleSetScript = preload("res://scripts/match_rule_set.gd")
const MatchConfigScript = preload("res://scripts/match_config.gd")


# THE CORE GUARANTEE OF PHASE 2. When MatchConfig.rule_set is set before
# Battle.tscn mounts, the director's local vars (map_id, player_faction,
# enemy_faction) come from the rule set, not from the seven legacy
# fields. A test that instantiates Battle.tscn with both the legacy
# fields and the rule set set, with deliberately DIFFERENT values, and
# then asserts the rule set won, is the lock-in point.
func test_match_director_reads_map_id_from_rule_set() -> bool:
	print("Running Test Suite: Battle unification Phase 2 - map_id comes from rule_set...")
	var match_config = _ensure_match_config()

	# The rule set says lake_crossing; the legacy field says open_plains.
	# The rule set should win.
	match_config.selected_map_id = "open_plains"
	match_config.rule_set = MatchRuleSetScript.skirmish("lake_crossing",
		"industrialists", "technocrats", [], "normal")

	var battle = BattleTscn.instantiate()
	root.add_child(battle)
	var guard := 0
	while not battle.world_is_ready and guard < 3000:
		await tree.process_frame
		guard += 1
	if not battle.world_is_ready:
		print("  [FAIL] Battle.tscn never finished building (rule set path)")
		battle.queue_free()
		_cleanup(match_config)
		return false

	if battle.map_id != "lake_crossing":
		print("  [FAIL] map_id should come from rule_set ('lake_crossing'), got '",
			battle.map_id, "' - rule set override not applied")
		battle.queue_free()
		_cleanup(match_config)
		return false
	if battle.current_map.get("name", "") != "lake_crossing":
		print("  [FAIL] current_map.name should be 'lake_crossing', got '",
			battle.current_map.get("name", ""), "'")
		battle.queue_free()
		_cleanup(match_config)
		return false

	battle.queue_free()
	_cleanup(match_config)
	print("  [PASS] map_id was overridden by the rule set (legacy value was different).")
	return true


# Player faction override. The rule set says expansionists and the
# default player_faction the director starts with is "industrialists"
# (its own field, NOT a MatchConfig field - the seven legacy
# MatchConfig fields were retired in Phase 5). The rule set should win
# over the director's default.
func test_match_director_reads_player_faction_from_rule_set() -> bool:
	print("Running Test Suite: Battle unification Phase 2 - player_faction comes from rule_set...")
	var match_config = _ensure_match_config()

	match_config.rule_set = MatchRuleSetScript.skirmish("open_plains",
		"expansionists", "technocrats", [], "normal")

	var battle = BattleTscn.instantiate()
	battle.map_id = "open_plains"
	root.add_child(battle)
	var guard := 0
	while not battle.world_is_ready and guard < 3000:
		await tree.process_frame
		guard += 1
	if not battle.world_is_ready:
		print("  [FAIL] Battle.tscn never finished building (rule set faction path)")
		battle.queue_free()
		_cleanup(match_config)
		return false

	if battle.player_faction != "expansionists":
		print("  [FAIL] player_faction should come from rule_set ('expansionists'), got '",
			battle.player_faction, "' - rule set override not applied")
		battle.queue_free()
		_cleanup(match_config)
		return false
	if battle.enemy_faction != "technocrats":
		print("  [FAIL] enemy_faction should come from rule_set ('technocrats'), got '",
			battle.enemy_faction, "' - rule set override not applied")
		battle.queue_free()
		_cleanup(match_config)
		return false

	battle.queue_free()
	_cleanup(match_config)
	print("  [PASS] player_faction + enemy_faction were overridden by the rule set.")
	return true


# THE NULL-RULE-SET PATH. When MatchConfig.rule_set is null (the case
# for every per-map smoke test that builds Battle.tscn directly without
# going through a launcher), match_director.gd falls back to its own
# default fields (player_faction="industrialists", enemy_faction=
# "technocrats", etc.) and map_id comes from selected_map_id if set.
# This replaces the Phase 2 "legacy fallback" test, which was testing
# a path that Phase 5 retired - the seven legacy MatchConfig fields
# no longer exist. The contract this test now guards is: a Battle.tscn
# instantiated without a rule set still boots with the per-map smoke
# test's expectations, and never throws on a missing field.
func test_match_director_falls_back_to_defaults_when_rule_set_is_null() -> bool:
	print("Running Test Suite: Battle unification Phase 2 - default fallback when rule_set is null...")
	var match_config = _ensure_match_config()

	match_config.selected_map_id = "open_plains"
	# Explicitly no rule set.
	match_config.rule_set = null

	var battle = BattleTscn.instantiate()
	root.add_child(battle)
	var guard := 0
	while not battle.world_is_ready and guard < 3000:
		await tree.process_frame
		guard += 1
	if not battle.world_is_ready:
		print("  [FAIL] Battle.tscn never finished building (null rule-set path)")
		battle.queue_free()
		_cleanup(match_config)
		return false

	if battle.map_id != "open_plains":
		print("  [FAIL] map_id should come from selected_map_id 'open_plains', got '", battle.map_id, "'")
		battle.queue_free()
		_cleanup(match_config)
		return false
	if battle.player_faction != "industrialists":
		print("  [FAIL] player_faction should fall back to director default 'industrialists', got '",
			battle.player_faction, "'")
		battle.queue_free()
		_cleanup(match_config)
		return false
	if battle.enemy_faction != "technocrats":
		print("  [FAIL] enemy_faction should fall back to director default 'technocrats', got '",
			battle.enemy_faction, "'")
		battle.queue_free()
		_cleanup(match_config)
		return false

	battle.queue_free()
	_cleanup(match_config)
	print("  [PASS] When rule_set is null, the director uses its own defaults and selected_map_id for map_id.")
	return true


# Test Range's rule set has enable_ai=false. The director must skip
# Commander construction entirely - a Commander that ticks against
# zero units and no economy is harmless but wasteful, and a future
# test that asserts commander == null will catch a regression where
# the gate stops working.
func test_match_director_skips_commander_when_rule_set_disables_ai() -> bool:
	print("Running Test Suite: Battle unification Phase 2 - commander is skipped when enable_ai is false...")
	var match_config = _ensure_match_config()

	# The Test Range factory produces a rule set with enable_ai=false
	# and player_blueprint_path set. The other fields are the Test
	# Range defaults, not relevant to this assertion.
	match_config.rule_set = MatchRuleSetScript.test_range(
		"res://data/loadout/bulwark_mbt.json", [])

	var battle = BattleTscn.instantiate()
	battle.map_id = "open_plains"
	root.add_child(battle)
	var guard := 0
	while not battle.world_is_ready and guard < 3000:
		await tree.process_frame
		guard += 1
	if not battle.world_is_ready:
		print("  [FAIL] Battle.tscn never finished building (Test Range rule set path)")
		battle.queue_free()
		_cleanup(match_config)
		return false

	if battle.commander != null:
		print("  [FAIL] Test Range rule set (enable_ai=false) should leave commander null, got ",
			battle.commander)
		battle.queue_free()
		_cleanup(match_config)
		return false

	battle.queue_free()
	_cleanup(match_config)
	print("  [PASS] commander is null when the rule set disables AI (Test Range).")
	return true


# --- helpers ----------------------------------------------------------------

# Returns a MatchConfig autoload. Headless test paths have no autoloads
# registered, so we own one for the duration of the suite. The autoload
# is removed by _cleanup() so it does not leak into a later test.
func _ensure_match_config() -> Node:
	var existing = root.get_node_or_null("MatchConfig")
	if existing != null:
		# Per the operations_draft test pattern, the autoload outlives
		# the suite, so any prior suite that left a MatchConfig on /root
		# is reused. Reset it for this test. After Phase 5, MatchConfig
		# only carries `rule_set` and `selected_map_id` (display only) -
		# the six legacy fields are gone.
		existing.selected_map_id = ""
		existing.rule_set = null
		return existing
	var mc = Node.new()
	mc.name = "MatchConfig"
	mc.set_script(MatchConfigScript)
	root.add_child(mc)
	return mc


func _cleanup(match_config: Node) -> void:
	# A fresh boot path leaves a single MatchConfig on /root that the
	# next suite reuses. A test that owns the autoload (the boot path)
	# frees it so /root is clean for the next suite.
	if match_config and is_instance_valid(match_config) \
			and not match_config.is_inside_tree():
		return  # already freed
	var existing = root.get_node_or_null("MatchConfig")
	if existing != null:
		# Reset the fields rather than freeing the autoload. A later
		# suite that depends on the autoload being present would
		# otherwise need to re-create it. The same posture as
		# test_operations_setup.gd's reset_operation() pattern.
		# Phase 5: only the two surviving fields are reset.
		existing.selected_map_id = ""
		existing.rule_set = null
		existing.rule_set = null
	await tree.process_frame
