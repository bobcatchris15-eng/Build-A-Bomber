extends SceneTree
# Test suite for AI Overhaul: ThreatAnalyzer, SquadManager, Micro, Doctrines, and CounterDraft.
#
# Run: ./Godot_v4.7.1-stable_win64_console.exe --headless --path . --script tools/probe_ai_overhaul_suite.gd --quit

const ThreatAnalyzer = preload("res://scripts/battle/ai/threat_analyzer.gd")
const CommanderScript = preload("res://scripts/battle/ai/commander.gd")
const CounterDraftScript = preload("res://scripts/battle/ai/counter_draft.gd")
const SquadManagerScript = preload("res://scripts/battle/ai/squad_manager.gd")
const SquadScript = preload("res://scripts/battle/ai/squad.gd")
const MicroScript = preload("res://scripts/battle/ai/micro.gd")
const DamageResolverScript = preload("res://scripts/damage_resolver.gd")


func _init():
	print("=================================================================")
	print("                 AI OVERHAUL TEST SUITE                          ")
	print("=================================================================")

	var passed := 0
	var failed := 0

	# 1. Threat Analyzer tests
	print("\n--- 1. ThreatAnalyzer Tests ---")
	if test_threat_analyzer_weakness():
		print("  [PASS] test_threat_analyzer_weakness")
		passed += 1
	else:
		print("  [FAIL] test_threat_analyzer_weakness")
		failed += 1

	if test_threat_analyzer_profile():
		print("  [PASS] test_threat_analyzer_profile")
		passed += 1
	else:
		print("  [FAIL] test_threat_analyzer_profile")
		failed += 1

	if test_threat_analyzer_threat_tags():
		print("  [PASS] test_threat_analyzer_threat_tags")
		passed += 1
	else:
		print("  [FAIL] test_threat_analyzer_threat_tags")
		failed += 1

	# 2. Ammo & Armor Adaptation
	print("\n--- 2. Ammo & Armor Adaptation Tests ---")
	if test_ammo_adaptation():
		print("  [PASS] test_ammo_adaptation")
		passed += 1
	else:
		print("  [FAIL] test_ammo_adaptation")
		failed += 1

	if test_armor_adaptation():
		print("  [PASS] test_armor_adaptation")
		passed += 1
	else:
		print("  [FAIL] test_armor_adaptation")
		failed += 1

	# 3. Doctrine System
	print("\n--- 3. Doctrine System Tests ---")
	if test_doctrines():
		print("  [PASS] test_doctrines")
		passed += 1
	else:
		print("  [FAIL] test_doctrines")
		failed += 1

	# 4. Multi-Squad & Tactical Micro
	print("\n--- 4. Multi-Squad & Tactical Micro Tests ---")
	if test_squad_manager_roles():
		print("  [PASS] test_squad_manager_roles")
		passed += 1
	else:
		print("  [FAIL] test_squad_manager_roles")
		failed += 1

	if test_micro_kiting_and_flanking():
		print("  [PASS] test_micro_kiting_and_flanking")
		passed += 1
	else:
		print("  [FAIL] test_micro_kiting_and_flanking")
		failed += 1

	# 5. Counter-Draft with 6+ Threat Axes
	print("\n--- 5. Counter-Draft Tests ---")
	if test_counter_draft_expanded():
		print("  [PASS] test_counter_draft_expanded")
		passed += 1
	else:
		print("  [FAIL] test_counter_draft_expanded")
		failed += 1

	print("\n=================================================================")
	print("Results: %d Passed, %d Failed" % [passed, failed])
	print("=================================================================")

	quit(0 if failed == 0 else 1)


func test_threat_analyzer_weakness() -> bool:
	# Steel weakest vs thermal (5.0 threshold)
	if ThreatAnalyzer.weakest_class_against("hardened_steel") != "thermal":
		return false
	# Reactive armor weakest vs energy (8.0 threshold)
	if ThreatAnalyzer.weakest_class_against("reactive_armor") != "energy":
		return false
	# Ceramic weakest vs kinetic (8.0 threshold)
	if ThreatAnalyzer.weakest_class_against("ablative_ceramic") != "kinetic":
		return false
	# Energy shielding weakest vs kinetic (10.0 threshold)
	if ThreatAnalyzer.weakest_class_against("energy_shielding") != "kinetic":
		return false
	return true


func test_threat_analyzer_profile() -> bool:
	var dummy_bp := {
		"hull_type": "brenntal_heavy_a",
		"armor_material": "hardened_steel",
		"armor_thickness": 1.5,
		"locomotion": {"type_id": "tracked_treads"},
		"modules": [
			{
				"type_id": "basic_cannon",
				"stats": {"dps": 40.0, "range": 38.0},
				"tweaks": {"ammo": "standard"}
			}
		]
	}
	var prof: Dictionary = ThreatAnalyzer.profile(dummy_bp)
	if prof["dominant_damage"] != "kinetic":
		return false
	if prof["armor_material"] != "hardened_steel":
		return false
	if prof["armor_weakness"] != "thermal":
		return false
	return true


func test_threat_analyzer_threat_tags() -> bool:
	var air_bp := {
		"hull_type": "kestrel_scout_a",
		"armor_material": "hardened_steel",
		"locomotion": {"type_id": "fixed_wing_engine"},
		"modules": [
			{"type_id": "rotary_cannon", "stats": {"dps": 105.0}}
		]
	}
	var tags: Array = ThreatAnalyzer.threats_of(air_bp)
	if "air" not in tags:
		return false
	if "kinetic_heavy" not in tags:
		return false
	if "wears_hardened_steel" not in tags:
		return false
	return true


func test_ammo_adaptation() -> bool:
	var bp := {
		"hull_type": "brenntal_medium_a",
		"armor_material": "hardened_steel",
		"modules": [
			{
				"type_id": "basic_cannon",
				"stats": {"dps": 40.0},
				"tweaks": {"ammo": "standard"}
			}
		]
	}
	# Against hardened steel, weakness is thermal -> incendiary ammo
	var adapted: Dictionary = ThreatAnalyzer.adapt_ammo(bp, "hardened_steel", ["tech_lab"])
	var m: Dictionary = adapted["modules"][0]
	if m.get("tweaks", {}).get("ammo", "") != "incendiary":
		return false
	return true


func test_armor_adaptation() -> bool:
	var bp := {
		"hull_type": "brenntal_medium_a",
		"armor_material": "hardened_steel",
		"modules": []
	}
	# Against energy heavy enemy, best material is energy_shielding
	var adapted: Dictionary = ThreatAnalyzer.adapt_armor(bp, "energy", [])
	if adapted["armor_material"] != "energy_shielding":
		return false
	return true


func test_doctrines() -> bool:
	var cmd := CommanderScript.new()
	cmd.doctrine = "blitz"
	if cmd._min_push_squad() != 3:
		return false
	if cmd._get_weight(CommanderScript.Action.PUSH) != 1.2:
		return false

	cmd.doctrine = "fortress"
	if cmd._defence_target() != 6:
		return false
	if cmd._get_weight(CommanderScript.Action.PUSH) != 0.4:
		return false
	return true


func test_squad_manager_roles() -> bool:
	var sm := SquadManagerScript.new()
	sm.setup(null, null, 1, Vector3.ZERO, Vector3(100, 0, 100))

	# Create dummy fast and slow units
	var units := []
	for i in range(3):
		var fast_u = {"move_speed": 15.0, "hp": 100.0, "max_hp": 100.0, "is_dead": false}
		units.append(fast_u)
	for i in range(4):
		var slow_u = {"move_speed": 7.0, "hp": 400.0, "max_hp": 400.0, "is_dead": false}
		units.append(slow_u)

	sm.assign_units(units)
	var all_squads: Dictionary = sm.get_all_squads()
	if not all_squads.has(SquadManagerScript.SquadRole.MAIN_BATTLE_GROUP):
		return false
	if not all_squads.has(SquadManagerScript.SquadRole.RAIDER) and not all_squads.has(SquadManagerScript.SquadRole.SCOUT):
		return false
	return true


func test_micro_kiting_and_flanking() -> bool:
	# Test kiting condition logic
	var should_kite := MicroScript._should_kite(60.0, 15.0, 25.0, 8.0, 30.0)
	if not should_kite:
		return false

	var should_not_kite := MicroScript._should_kite(25.0, 8.0, 60.0, 15.0, 30.0)
	if should_not_kite:
		return false
	return true


func test_counter_draft_expanded() -> bool:
	var history := [
		{"player_threats": ["wears_hardened_steel", "kinetic_heavy"]},
		{"player_threats": ["wears_hardened_steel", "air"]},
	]
	var profile: Dictionary = CounterDraftScript.threat_profile(history)
	if not profile.has("wears_hardened_steel"):
		return false

	var roles: Array = CounterDraftScript.wanted_roles(profile)
	if "counter_armor" not in roles and "anti_air" not in roles:
		return false
	return true
