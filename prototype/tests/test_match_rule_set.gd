extends "res://tests/suite_base.gd"
# MatchRuleSet suites - the per-mode rule set the unification plan
# (Phase 1) introduces. The lock-in point for the action-availability
# matrix: every (mode, order_type) pair is asserted here so the rules
# cannot silently drift before Phase 2 wires OrderService.issue_order()
# to consult is_order_legal().
#
# Registration order lives in run_tests.gd's SUITE_ORDER, not here - the
# runner drives that manifest so execution order is identical to the
# pre-split single file. Do not reorder.

# The rule set class. Preloaded rather than class_name-resolved so a typo
# in the class name surfaces at the call site of `MatchRuleSet.new()`
# rather than as a parse error on first read.
const RuleSetScript = preload("res://scripts/match_rule_set.gd")


# A bare Node stand-in for the `unit` parameter. The current
# is_order_legal does not read any unit metadata, but the signature is
# future-proof; this prevents a future "harvester-only" branch from
# having to be tested with a real BattleUnitV2 in Phase 2.
func _stub_unit() -> Node:
	return Node.new()


func test_skirmish_factory_sets_required_fields() -> bool:
	print("Running Test Suite: MatchRuleSet.skirmish() sets required fields...")
	var rs := RuleSetScript.skirmish("open_plains", "industrialists",
			"technocrats", ["res://data/loadout/bulwark_mbt.json"], "hard")
	if rs.mode != RuleSetScript.Mode.SKIRMISH:
		print("  [FAIL] mode should be SKIRMISH, got ", rs.mode)
		return false
	if rs.map_id != "open_plains":
		print("  [FAIL] map_id should be 'open_plains', got '", rs.map_id, "'")
		return false
	if rs.player_faction != "industrialists":
		print("  [FAIL] player_faction should be 'industrialists'")
		return false
	if rs.enemy_faction != "technocrats":
		print("  [FAIL] enemy_faction should be 'technocrats'")
		return false
	if rs.selected_blueprint_paths.size() != 1 \
			or rs.selected_blueprint_paths[0] != "res://data/loadout/bulwark_mbt.json":
		print("  [FAIL] selected_blueprint_paths not set correctly: ", rs.selected_blueprint_paths)
		return false
	if rs.ai_difficulty != "hard":
		print("  [FAIL] ai_difficulty should be 'hard'")
		return false
	# Skirmish keeps the defaults - economy on, AI on, fog on, full HUD.
	if not rs.enable_economy or not rs.enable_ai or not rs.enable_fog_of_war:
		print("  [FAIL] Skirmish should have all defaults on (economy, AI, fog)")
		return false
	if not rs.enable_minimap or not rs.enable_production_hud or not rs.enable_admin_menu:
		print("  [FAIL] Skirmish should have all HUD defaults on")
		return false
	if rs.camera_mode != RuleSetScript.CameraMode.RTS:
		print("  [FAIL] Skirmish should be RTS camera")
		return false
	print("  [PASS] Skirmish factory sets required fields and preserves defaults.")
	return true


func test_operations_factory_sets_campaign_fields() -> bool:
	print("Running Test Suite: MatchRuleSet.operations() sets campaign fields...")
	var rs := RuleSetScript.operations("lake_crossing", "expansionists",
			"industrialists", [], "normal", "op-2026-08-10-abc", 2)
	if rs.mode != RuleSetScript.Mode.OPERATIONS:
		print("  [FAIL] mode should be OPERATIONS")
		return false
	if rs.operation_id != "op-2026-08-10-abc":
		print("  [FAIL] operation_id not threaded through factory: '", rs.operation_id, "'")
		return false
	if rs.stage_index != 2:
		print("  [FAIL] stage_index not threaded through factory: ", rs.stage_index)
		return false
	if rs.win_condition != RuleSetScript.WinCondition.DESTROY_HQ:
		print("  [FAIL] Operations should default to DESTROY_HQ win condition")
		return false
	if rs.after_match_action != RuleSetScript.AfterMatchAction.SHOW_AAR:
		print("  [FAIL] Operations should default to SHOW_AAR after match")
		return false
	print("  [PASS] Operations factory sets campaign fields and defaults.")
	return true


func test_test_range_factory_flips_economy_and_hud_off() -> bool:
	print("Running Test Suite: MatchRuleSet.test_range() flips economy + HUD off...")
	var rs := RuleSetScript.test_range(
		"res://data/loadout/bulwark_mbt.json",
		["res://data/loadout/rattler_scout.json",
		 "res://data/loadout/wasp_rocket_buggy.json"])
	if rs.mode != RuleSetScript.Mode.TEST_RANGE:
		print("  [FAIL] mode should be TEST_RANGE")
		return false
	if rs.player_blueprint_path != "res://data/loadout/bulwark_mbt.json":
		print("  [FAIL] player_blueprint_path not set")
		return false
	if rs.enemy_blueprint_paths.size() != 2:
		print("  [FAIL] enemy_blueprint_paths should have 2 entries, got ",
			rs.enemy_blueprint_paths.size())
		return false
	# The whole point of Test Range as a "rules off" mode.
	if rs.enable_economy:
		print("  [FAIL] Test Range should have economy off")
		return false
	if rs.enable_production:
		print("  [FAIL] Test Range should have production off")
		return false
	if rs.enable_player_build:
		print("  [FAIL] Test Range should have player build off")
		return false
	if rs.enable_ai:
		print("  [FAIL] Test Range should have AI off")
		return false
	if rs.enable_fog_of_war:
		print("  [FAIL] Test Range should have fog of war off")
		return false
	# HUD: only the battle HUD is on.
	if rs.enable_minimap or rs.enable_production_hud or rs.enable_admin_menu:
		print("  [FAIL] Test Range should have minimap / production / admin off")
		return false
	if not rs.enable_battle_hud:
		print("  [FAIL] Test Range should keep battle HUD on (HP bars, selection rings)")
		return false
	# 2026-08-11: the camera_mode assertion that used to sit here (CHASE) is
	# gone. Commit 6c5652f deliberately switched Test Range back to the RTS
	# camera so WASD panning works while you drive the design around, so the
	# factory now sets CameraMode.RTS and the old assertion was asserting the
	# opposite of shipped behaviour. Not replaced with an RTS assertion: RTS is
	# the field's declared default, so a test for it would pass even if
	# test_range() stopped setting camera_mode at all - it would guard nothing.
	# The rest of this suite (mode, blueprint paths, economy/production/AI/fog
	# off, HUD flags, win condition, after-match action) is untouched.
	if rs.win_condition != RuleSetScript.WinCondition.KILL_ALL_DUMMIES:
		print("  [FAIL] Test Range should default to KILL_ALL_DUMMIES")
		return false
	if rs.after_match_action != RuleSetScript.AfterMatchAction.RETURN_TO_LAB:
		print("  [FAIL] Test Range should return to the Lab on match end")
		return false
	print("  [PASS] Test Range factory flips economy / production / AI / fog / HUD off.")
	return true


func test_is_order_legal_allows_movement_in_every_mode() -> bool:
	print("Running Test Suite: is_order_legal() allows movement orders in all modes...")
	var unit := _stub_unit()
	var modes := [
		RuleSetScript.skirmish("open_plains", "industrialists", "technocrats", []),
		RuleSetScript.operations("open_plains", "industrialists", "technocrats", [],
			"normal", "op-1", 0),
		RuleSetScript.test_range("res://data/loadout/bulwark_mbt.json", []),
	]
	var move_orders := [Order.Type.MOVE, Order.Type.ATTACK_MOVE,
			Order.Type.ATTACK, Order.Type.ATTACK_GROUND]
	for rs in modes:
		for t in move_orders:
			if not rs.is_order_legal(unit, t):
				print("  [FAIL] movement/combat order type ", t,
					" should be legal in mode ", rs.mode)
				unit.free()
				return false
	unit.free()
	print("  [PASS] Movement + combat orders are legal in all three modes.")
	return true


func test_is_order_legal_allows_idle_and_hold_always() -> bool:
	print("Running Test Suite: is_order_legal() allows IDLE + HOLD in all modes...")
	var unit := _stub_unit()
	var modes := [
		RuleSetScript.skirmish("open_plains", "industrialists", "technocrats", []),
		RuleSetScript.operations("open_plains", "industrialists", "technocrats", [],
			"normal", "op-1", 0),
		RuleSetScript.test_range("res://data/loadout/bulwark_mbt.json", []),
	]
	for rs in modes:
		if not rs.is_order_legal(unit, Order.Type.IDLE):
			print("  [FAIL] IDLE should be legal in mode ", rs.mode)
			unit.free()
			return false
		if not rs.is_order_legal(unit, Order.Type.HOLD):
			print("  [FAIL] HOLD should be legal in mode ", rs.mode)
			unit.free()
			return false
	unit.free()
	print("  [PASS] IDLE and HOLD are always legal (the do-nothing escape hatch).")
	return true


func test_is_order_legal_blocks_harvest_in_test_range() -> bool:
	print("Running Test Suite: is_order_legal() blocks HARVEST in Test Range...")
	var unit := _stub_unit()
	var sk := RuleSetScript.skirmish("open_plains", "industrialists", "technocrats", [])
	var op := RuleSetScript.operations("open_plains", "industrialists", "technocrats", [],
		"normal", "op-1", 0)
	var tr := RuleSetScript.test_range("res://data/loadout/bulwark_mbt.json", [])
	# Skirmish and Operations have harvest.
	if not sk.is_order_legal(unit, Order.Type.HARVEST):
		print("  [FAIL] HARVEST should be legal in Skirmish")
		unit.free()
		return false
	if not op.is_order_legal(unit, Order.Type.HARVEST):
		print("  [FAIL] HARVEST should be legal in Operations")
		unit.free()
		return false
	# Test Range does not - no resource fields, no refinery, no economy.
	if tr.is_order_legal(unit, Order.Type.HARVEST):
		print("  [FAIL] HARVEST should be ILLEGAL in Test Range (no economy)")
		unit.free()
		return false
	unit.free()
	print("  [PASS] HARVEST is gated on enable_economy (off in Test Range).")
	return true


func test_is_order_legal_blocks_unknown_order_types() -> bool:
	print("Running Test Suite: is_order_legal() fails closed on unknown order types...")
	# A future Order.Type value added without a branch in is_order_legal
	# should be REJECTED, not silently accepted (per minimax.md §2.6
	# 'no silent fallbacks' and the SettingsService.get() posture). The
	# test uses -1 as a not-a-valid-Order-Type sentinel; passing it
	# directly to the function should return false in every mode.
	var unit := _stub_unit()
	var modes := [
		RuleSetScript.skirmish("open_plains", "industrialists", "technocrats", []),
		RuleSetScript.operations("open_plains", "industrialists", "technocrats", [],
			"normal", "op-1", 0),
		RuleSetScript.test_range("res://data/loadout/bulwark_mbt.json", []),
	]
	for rs in modes:
		if rs.is_order_legal(unit, -1):
			print("  [FAIL] Unknown order type -1 should be ILLEGAL in mode ", rs.mode)
			unit.free()
			return false
		# 999 is also outside Order.Type's 0..6 enum range.
		if rs.is_order_legal(unit, 999):
			print("  [FAIL] Unknown order type 999 should be ILLEGAL in mode ", rs.mode)
			unit.free()
			return false
	unit.free()
	print("  [PASS] Unknown order types fail closed in every mode.")
	return true


func test_factory_does_not_alias_input_array() -> bool:
	print("Running Test Suite: factory() duplicates input arrays (no caller-side aliasing)...")
	# Mutating the caller's array after passing it in must not affect the
	# rule set. Skirmish and Operations both duplicate; Test Range does
	# the same with enemy_blueprint_paths. A factory that captured the
	# caller's array by reference would let one screen's mutating of the
	# roster accidentally rewrite another match's roster.
	var bps: Array = ["res://data/loadout/bulwark_mbt.json",
			"res://data/loadout/rattler_scout.json"]
	var sk := RuleSetScript.skirmish("open_plains", "industrialists", "technocrats", bps)
	bps.append("res://data/loadout/magpie_ore_hauler.json")
	if sk.selected_blueprint_paths.size() != 2:
		print("  [FAIL] Skirmish should have duplicated the input array; got size ",
			sk.selected_blueprint_paths.size(), " after caller mutation")
		return false
	var dummies: Array = ["res://data/loadout/bulwark_mbt.json"]
	var tr := RuleSetScript.test_range("res://data/loadout/magpie_ore_hauler.json", dummies)
	dummies.clear()
	if tr.enemy_blueprint_paths.size() != 1:
		print("  [FAIL] Test Range should have duplicated enemy_blueprint_paths; got size ",
			tr.enemy_blueprint_paths.size(), " after caller mutation")
		return false
	print("  [PASS] Factories duplicate input arrays (no caller-side aliasing).")
	return true


func test_to_dict_round_trip_preserves_fields() -> bool:
	print("Running Test Suite: to_dict() preserves the fields a future save path will need...")
	# Today to_dict is a stub used by tests only; in Phase 2 the
	# Operations save path will need it. Asserting the fields it writes
	# today means the save format has a lock-in point before any
	# operation writes a campaign file in the new shape.
	var rs := RuleSetScript.operations("open_plains", "expansionists",
			"technocrats", ["res://data/loadout/magpie_ore_hauler.json"], "hard",
			"op-test-001", 3)
	rs.spawn_resource_fields = [
		{"type": "metal", "position": Vector3(10, 0, 10), "amount": 1000},
	]
	rs.spawn_player_buildings = [
		{"type_id": "refinery", "position": Vector3(0, 0, 0)},
	]
	var d := rs.to_dict()
	if d.get("mode") != RuleSetScript.Mode.OPERATIONS:
		print("  [FAIL] to_dict() mode lost: ", d.get("mode"))
		return false
	if d.get("map_id") != "open_plains":
		print("  [FAIL] to_dict() map_id lost: ", d.get("map_id"))
		return false
	if d.get("operation_id") != "op-test-001":
		print("  [FAIL] to_dict() operation_id lost: ", d.get("operation_id"))
		return false
	if d.get("stage_index") != 3:
		print("  [FAIL] to_dict() stage_index lost: ", d.get("stage_index"))
		return false
	if d.get("ai_difficulty") != "hard":
		print("  [FAIL] to_dict() ai_difficulty lost: ", d.get("ai_difficulty"))
		return false
	if d.get("enable_economy") != true:
		print("  [FAIL] to_dict() enable_economy lost (should be true for Operations)")
		return false
	# Critical: spawn lists are deep-duplicated so a save file cannot
	# accidentally share a reference with the live rule set and have
	# later match changes rewrite the save.
	var saved_fields = d.get("spawn_resource_fields", [])
	if saved_fields.size() != 1 or saved_fields[0].get("type") != "metal":
		print("  [FAIL] to_dict() spawn_resource_fields lost or shallow-copied")
		return false
	var saved_buildings = d.get("spawn_player_buildings", [])
	if saved_buildings.size() != 1 or saved_buildings[0].get("type_id") != "refinery":
		print("  [FAIL] to_dict() spawn_player_buildings lost or shallow-copied")
		return false
	# Mutating the rule set after the dict was written must not rewrite
	# the dict (deep-copy).
	rs.spawn_resource_fields.clear()
	if d.get("spawn_resource_fields", []).size() != 1:
		print("  [FAIL] to_dict() should deep-copy spawn lists (caller mutation leaked)")
		return false
	print("  [PASS] to_dict() preserves every field Operations will need to save.")
	return true
