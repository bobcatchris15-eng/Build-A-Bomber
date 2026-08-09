extends "res://tests/suite_base.gd"
# ai and win suites, split out of the former single-file
# run_tests.gd. Registration order lives in run_tests.gd's SUITE_ORDER,
# not here - the runner drives that manifest so execution order is
# identical to the pre-split single file.

func test_ai_flanking_targets_weakest_facet() -> bool:
	print("Running Test Suite: AI Flanking - Approaches the Target's Weakest Facet (Armor phase 5)...")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var target = CharacterBody3D.new()
	target.set_script(BattleUnitScript)
	root.add_child(target)
	target.global_position = Vector3(20, 0, 20) # away from the attacker's default facet-relative math
	target.attack_range = 10.0

	var target_hull = Node3D.new()
	target_hull.name = "Hull"
	target_hull.set_meta("armor_material", "hardened_steel")
	target_hull.set_meta("armor_thickness", 1.0)
	target.add_child(target_hull)
	target.hull_node = target_hull

	# Heavily armor the front specifically, leaving back/left/right at baseline.
	var front_plate = Node3D.new()
	front_plate.set_meta("facet", "front")
	var plate_data = ModuleData.new()
	plate_data.type_id = "armor_plating"
	plate_data.category = "armor"
	plate_data.base_hp = 500.0
	front_plate.set_meta("module_data", plate_data)
	target_hull.add_child(front_plate)

	var attacker = CharacterBody3D.new()
	attacker.set_script(BattleUnitScript)
	root.add_child(attacker)
	attacker.attack_range = 10.0

	var weak_normal = attacker._weakest_facet_normal(target)
	# front is FACET_NORMALS["front"] = (0,0,-1); the heavily-armored front
	# must NOT be picked as the weak facet.
	if weak_normal.is_equal_approx(Vector3(0, 0, -1)):
		print("  [FAIL] The heavily-armored front facet should not be selected as the weakest, got normal ", weak_normal)
		attacker.queue_free()
		target.queue_free()
		return false
	if weak_normal == Vector3.ZERO:
		print("  [FAIL] Should have resolved SOME weak facet normal for a target with a real hull_node")
		attacker.queue_free()
		target.queue_free()
		return false

	# The resulting flank point should sit on the opposite side of the
	# target from the armored front, not just be the target's raw position
	# (which is what the old straight-line approach used).
	var flank_point = attacker._compute_flank_point(target)
	if flank_point.distance_to(target.global_position) < 1.0:
		print("  [FAIL] Flank point should be offset from the target, not collapse to the target's own position")
		attacker.queue_free()
		target.queue_free()
		return false
	var to_flank = (flank_point - target.global_position).normalized()
	if to_flank.dot(Vector3(0, 0, -1)) > 0.3: # not biased toward the armored front
		print("  [FAIL] Flank point should be biased away from the armored front, got direction ", to_flank)
		attacker.queue_free()
		target.queue_free()
		return false

	attacker.queue_free()
	target.queue_free()
	print("  [PASS] Attacking units compute a flank point toward the target's weakest facet, not a straight line to its armored front.")
	return true

func test_enemy_roster_new_movement_archetypes() -> bool:
	print("Running Test Suite: Enemy Roster - New Movement Archetypes Exercised By Real AI Units...")
	# Armor phase / Traits B3 built fixed_wing_engine as a generic mechanic
	# usable by any hull, but nothing in the actual enemy roster used it -
	# the new strafing AI only ever ran in synthetic tests, never a real
	# AI-controlled Skirmish unit. This bundled blueprint
	# (data/enemy/raptor_striker.json) closes that gap.
	#
	# tide_corvette.json (naval_propeller, is_naval/surface-lock) was removed
	# along with the naval locomotors - naval units never got real design
	# attention, so its half of this test went with it.
	var bp_manager = preload("res://scripts/blueprint_manager.gd").new()
	bp_manager.name = "BlueprintManager"
	root.add_child(bp_manager)
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var raptor_data = bp_manager.load_blueprint("res://data/enemy/raptor_striker.json")
	if raptor_data.is_empty():
		print("  [FAIL] raptor_striker.json failed to parse")
		bp_manager.queue_free()
		return false
	var raptor = CharacterBody3D.new()
	raptor.set_script(BattleUnitScript)
	root.add_child(raptor)
	raptor.global_position = Vector3(50, 4, 50)
	raptor.setup(raptor_data, 1, bp_manager)
	if not raptor.is_fixed_wing:
		print("  [FAIL] raptor_striker should derive is_fixed_wing from its fixed_wing_engine locomotion trait")
		raptor.queue_free()
		bp_manager.queue_free()
		return false
	for i in range(10):
		raptor._physics_process(0.1)
	var raptor_speed = Vector2(raptor.velocity.x, raptor.velocity.z).length()
	if raptor_speed < 1.0:
		print("  [FAIL] A fixed-wing enemy unit should be cruising (never stopped) after a few physics ticks, got speed ", raptor_speed)
		raptor.queue_free()
		bp_manager.queue_free()
		return false
	raptor.queue_free()

	bp_manager.queue_free()
	print("  [PASS] The fixed-wing enemy roster entry (raptor_striker) reconstructs correctly and exercises the strafing movement trait.")
	return true

func test_team_targeting() -> bool:
	print("Running Test Suite 8: Team-Aware Weapon Targeting...")

	# Friendly construct with a weapon
	var friendly = Node3D.new()
	friendly.set_meta("team", 0)
	friendly.add_to_group("damageable")
	root.add_child(friendly)

	var weapon = Node3D.new()
	weapon.set_script(load("res://scripts/auto_weapon.gd"))
	friendly.add_child(weapon)
	var w_data = ModuleData.new()
	w_data.type_id = "basic_cannon" # 360-degree traverse
	w_data.base_weight = 80.0
	w_data.base_dps = 40.0
	weapon.set_meta("module_data", w_data)
	weapon._ready()

	# An allied construct nearby (must NOT be targeted)
	var ally = StaticBody3D.new()
	ally.set_script(TargetDummyScript)
	var ally_mesh = MeshInstance3D.new()
	ally_mesh.name = "MeshInstance3D"
	ally.add_child(ally_mesh)
	root.add_child(ally)
	ally.set_meta("team", 0)
	ally.add_to_group("damageable")
	ally.global_position = weapon.global_position + Vector3(3, 0, 0)

	# A hostile construct in range (MUST be targeted)
	var hostile = StaticBody3D.new()
	hostile.set_script(TargetDummyScript)
	var hostile_mesh = MeshInstance3D.new()
	hostile_mesh.name = "MeshInstance3D"
	hostile.add_child(hostile_mesh)
	root.add_child(hostile)
	hostile.set_meta("team", 1)
	hostile.add_to_group("damageable")
	hostile.global_position = weapon.global_position + Vector3(0, 0, -6)

	weapon._find_nearest_target()
	var targeted_hostile = (weapon.target == hostile)

	# Remove the hostile: weapon should now have no target (never the ally)
	hostile.remove_from_group("damageable")
	weapon.target = null
	weapon._find_nearest_target()
	var no_friendly_fire = (weapon.target == null)

	friendly.queue_free()
	ally.queue_free()
	hostile.queue_free()

	if targeted_hostile and no_friendly_fire:
		print("  [PASS] Weapons target hostiles and never allies in team mode.")
		return true
	print("  [FAIL] Team targeting. Hostile targeted: ", targeted_hostile, " No friendly fire: ", no_friendly_fire)
	return false

func test_vision_range_computation() -> bool:
	print("Running Test Suite: Fog-of-War - Vision Range (hull base + sensor_suite bonus + Technocrats passive)...")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var bp_manager = preload("res://scripts/blueprint_manager.gd").new()
	root.add_child(bp_manager)

	var bp_no_sensor = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"faction": "industrialists",
		"locomotion": {"type_id": "tracked_treads", "settings": {"width": 1.0}},
		"modules": []
	}
	var unit_no_sensor = CharacterBody3D.new()
	unit_no_sensor.set_script(BattleUnitScript)
	root.add_child(unit_no_sensor)
	unit_no_sensor.setup(bp_no_sensor, 0, bp_manager)
	var base_only = unit_no_sensor.vision_range
	if base_only <= 0.0:
		print("  [FAIL] medium_hull should carry a nonzero base vision range even with no sensor_suite, got ", base_only)
		bp_manager.queue_free()
		return false
	unit_no_sensor.queue_free()

	var bp_with_sensor = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"faction": "industrialists",
		"locomotion": {"type_id": "tracked_treads", "settings": {"width": 1.0}},
		"modules": [
			{"type_id": "sensor_suite", "name": "Radar Mast", "position": {"x": 0.0, "y": 1.0, "z": 0.0}, "rotation": {"x": 0.0, "y": 0.0, "z": 0.0}, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "yaw_offset": 0.0, "tweaks": {}}
		]
	}
	var unit_with_sensor = CharacterBody3D.new()
	unit_with_sensor.set_script(BattleUnitScript)
	root.add_child(unit_with_sensor)
	unit_with_sensor.setup(bp_with_sensor, 0, bp_manager)
	if unit_with_sensor.vision_range <= base_only:
		print("  [FAIL] A mounted sensor_suite should raise vision_range above the hull's base alone (base=", base_only, ", with sensor=", unit_with_sensor.vision_range, ")")
		unit_with_sensor.queue_free(); bp_manager.queue_free()
		return false
	unit_with_sensor.queue_free()

	# Technocrats passive: +15% vision (Factions_and_Buildings.md) - was
	# unimplementable before this pass since no vision system existed.
	var bp_technocrat = bp_no_sensor.duplicate(true)
	bp_technocrat["faction"] = "technocrats"
	var unit_technocrat = CharacterBody3D.new()
	unit_technocrat.set_script(BattleUnitScript)
	root.add_child(unit_technocrat)
	unit_technocrat.setup(bp_technocrat, 0, bp_manager)
	var expected = base_only * 1.15
	if abs(unit_technocrat.vision_range - expected) > 0.5:
		print("  [FAIL] Technocrats should get +15% vision range, expected ~", expected, " got ", unit_technocrat.vision_range)
		unit_technocrat.queue_free(); bp_manager.queue_free()
		return false

	unit_technocrat.queue_free()
	bp_manager.queue_free()
	print("  [PASS] Hulls carry a base vision range; sensor_suite modules extend it; Technocrats get their +15% passive.")
	return true

func test_fog_hidden_excluded_from_targeting() -> bool:
	print("Running Test Suite: Fog-of-War - Hidden Enemies Can't Be Auto-Targeted...")
	await tree.process_frame
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var shooter = CharacterBody3D.new()
	shooter.set_script(BattleUnitScript)
	root.add_child(shooter)
	shooter.team = 0
	shooter.set_meta("team", 0)
	shooter.add_to_group("damageable")

	var weapon = Node3D.new()
	weapon.set_script(load("res://scripts/auto_weapon.gd"))
	shooter.add_child(weapon)
	var w_data = ModuleData.new()
	w_data.type_id = "basic_cannon" # 360-degree traverse, no arc filtering to worry about
	w_data.base_weight = 80.0
	w_data.base_dps = 40.0
	weapon.set_meta("module_data", w_data)
	weapon._ready()

	var hidden_enemy = CharacterBody3D.new()
	hidden_enemy.set_script(BattleUnitScript)
	root.add_child(hidden_enemy)
	hidden_enemy.team = 1
	hidden_enemy.set_meta("team", 1)
	hidden_enemy.add_to_group("damageable")
	hidden_enemy.global_position = weapon.global_position + Vector3(3, 0, 0)
	hidden_enemy.fog_hidden = true

	weapon._find_nearest_target()
	if weapon.target == hidden_enemy:
		print("  [FAIL] A fog_hidden enemy should never be auto-targeted")
		shooter.queue_free(); hidden_enemy.queue_free()
		return false

	# Once scouted (fog_hidden cleared), it becomes a valid target again.
	hidden_enemy.fog_hidden = false
	weapon._find_nearest_target()
	if weapon.target != hidden_enemy:
		print("  [FAIL] Once no longer fog_hidden, the enemy should be a valid target again, got ", weapon.target)
		shooter.queue_free(); hidden_enemy.queue_free()
		return false

	shooter.queue_free()
	hidden_enemy.queue_free()
	print("  [PASS] fog_hidden enemies are excluded from auto-targeting; becoming visible makes them targetable again.")
	return true

func test_long_range_weapon_needs_a_team_spotter() -> bool:
	print("Running Test Suite: Long-Range Weapons Fire On Team-Spotted Targets...")
	var w_script = load("res://scripts/auto_weapon.gd")

	# The mechanic Chris asked for: "the artillery can make use of a spotter,
	# and engage anything visible in weapons range, and that visibility can be
	# a global thing per team, so if a scout can see something, then it can be
	# targeted by distant long-range weapons."
	#
	# Before this, visibility was a single fog_hidden flag describing only the
	# LOCAL team's knowledge, which meant it could not answer "can MY side see
	# that" for any other team, and the AI side had no visibility gate at all.
	#
	# The stand-in controller below implements just is_visible_to_team(), which
	# is the contract auto_weapon.gd duck-types against - the same approach
	# test fixtures already use for is_allied()/get_nearby_damageable().
	var Controller = GDScript.new()
	Controller.source_code = """
extends Node
var visible_ids: Dictionary = {}
var asked_teams: Array = []
func is_visible_to_team(c, team: int) -> bool:
	asked_teams.append(team)
	return visible_ids.has(c.get_instance_id())
"""
	Controller.reload()

	# current_scene must be a direct child of the tree's real root, not root
	# itself - same constraint the repair-beam and drone-swarm suites document.
	var controller = Controller.new()
	root.add_child(controller)
	var prev_scene = current_scene
	current_scene = controller

	var cleanup = func():
		current_scene = prev_scene
		controller.queue_free()

	# An artillery piece at the origin, and a hostile 90 units away - inside
	# artillery's 140 reach but far outside any hull's own vision.
	var carrier = Node3D.new()
	carrier.set_meta("team", 0)
	# Must be in one of the groups get_vehicle_root() walks for, or the weapon
	# resolves no vehicle, get_team() returns -1, and _find_nearest_target()
	# skips the whole team-mode branch this suite is about.
	carrier.add_to_group("damageable")
	root.add_child(carrier)
	var gun = Node3D.new()
	gun.set_script(w_script)
	carrier.add_child(gun)
	var gun_data = ModuleData.new()
	gun_data.type_id = "artillery"
	gun_data.base_weight = ModuleCatalog.get_module_data("artillery").get("weight", 200.0)
	gun_data.base_dps = 50.0
	gun.set_meta("module_data", gun_data)
	gun._ready()

	if gun.fire_range < 90.0:
		print("  [FAIL] artillery should reach past 90 units; got ", gun.fire_range)
		cleanup.call()
		return false

	var enemy = CharacterBody3D.new()
	enemy.set_script(load("res://scripts/battle_unit.gd"))
	enemy.set_meta("team", 1)
	enemy.add_to_group("damageable")
	root.add_child(enemy)
	enemy.global_position = Vector3(0, 0, -90)

	# 1. Unspotted: the gun must NOT engage, even though the target is well
	# inside its reach. This is the constraint that makes a scout worth
	# building - without it, long range would simply be free.
	controller.visible_ids = {}
	gun.target = null
	gun._find_nearest_target()
	if gun.target != null:
		print("  [FAIL] artillery engaged an UNSPOTTED target at 90 units. Long range must not double as free vision.")
		cleanup.call()
		return false

	# 2. Spotted by the team: the same gun, the same target, the same distance -
	# the only thing that changed is that somebody on the team can see it.
	controller.visible_ids = {enemy.get_instance_id(): true}
	gun.target = null
	gun._find_nearest_target()
	if gun.target != enemy:
		print("  [FAIL] artillery did NOT engage a target its own TEAM had spotted at 90 units. Got target=", gun.target)
		cleanup.call()
		return false

	# 3. The question asked must be about the WEAPON's team, not a hardcoded
	# player team - otherwise the AI side is either ungated or permanently
	# blind, which is the asymmetry this replaced.
	if not (0 in controller.asked_teams):
		print("  [FAIL] visibility was never queried for the weapon's own team (0). asked=", controller.asked_teams)
		cleanup.call()
		return false

	# 4. Still bounded by reach. Spotting does not extend how far a gun shoots.
	enemy.global_position = Vector3(0, 0, -(gun.fire_range + 50.0))
	gun.target = null
	gun._find_nearest_target()
	if gun.target != null:
		print("  [FAIL] a spotted target beyond fire_range was engaged anyway - visibility must not extend reach.")
		cleanup.call()
		return false

	cleanup.call()
	print("  [PASS] A long-range weapon refuses an unspotted target inside its reach, engages that same target once the TEAM can see it, asks about its own team rather than a hardcoded one, and is still bounded by fire_range.")
	return true

func test_design_lab_reports_range_and_names_the_spotter_trade() -> bool:
	print("Running Test Suite: Design Lab Range Readout & Spotter Warning...")
	var WeaponRange = preload("res://scripts/weapon_range.gd")

	var make_hull = func(hull_type: String, mounts: Array) -> Node3D:
		var h = Node3D.new()
		h.set_meta("type_id", hull_type)
		root.add_child(h)
		for m in mounts:
			var node = Node3D.new()
			var cat = ModuleCatalog.get_module_data(m[0])
			var d = ModuleData.new()
			d.type_id = m[0]
			d.category = cat.get("category", "weapon")
			d.base_weight = cat.get("weight", 100.0)
			d.base_dps = cat.get("dps", 50.0)
			d.base_vision_bonus = cat.get("vision_bonus", 0.0)
			d.tweaks = m[1] if m.size() > 1 else {}
			node.set_meta("module_data", d)
			h.add_child(node)
		return h

	# 1. The lab's reach must be the SAME number combat uses. This is the
	# anti-drift assertion: the weight system's sidebar copy knew 4 locomotors
	# while combat's knew 6, and 11 expansion types were in neither, which is
	# why the range chain lives in one shared module now.
	var w_script = load("res://scripts/auto_weapon.gd")
	for case in [["basic_cannon", {}], ["artillery", {"barrel_length": 1.5}],
			["gauss_railgun", {"rail_length": 1.8}], ["anti_materiel_rifle", {"optic_power": 2.0}]]:
		var parent = Node3D.new()
		var weapon = Node3D.new()
		weapon.set_script(w_script)
		parent.add_child(weapon)
		root.add_child(parent)
		var wd = ModuleData.new()
		wd.type_id = case[0]
		wd.base_weight = ModuleCatalog.get_module_data(case[0]).get("weight", 100.0)
		wd.base_dps = 50.0
		wd.tweaks = case[1]
		weapon.set_meta("module_data", wd)
		weapon._ready()
		var combat_reach: float = weapon.fire_range
		var lab_reach: float = WeaponRange.compute(case[0], case[1], "industrialists")
		parent.queue_free()
		if absf(combat_reach - lab_reach) > 0.01:
			print("  [FAIL] the Design Lab and combat disagree on ", case[0], " reach: lab=", lab_reach, " combat=", combat_reach)
			return false

	# 2. A design whose weapons all sit inside its own vision must NOT be
	# warned. A warning that fires on everything says nothing.
	var brawler = make_hull.call("assault_hull", [["heavy_machine_gun"], ["flamethrower"]])
	var brawler_wr = WeaponRange.analyze(brawler)
	if not brawler_wr["has_weapons"]:
		print("  [FAIL] a hull with an HMG and a flamethrower should report weapons.")
		return false
	if not brawler_wr["spotter_required"].is_empty() or not brawler_wr["spotter_assisted"].is_empty():
		print("  [FAIL] a short-ranged brawler was flagged as spotter-dependent. reach ", brawler_wr["shortest"], "-", brawler_wr["longest"], " vs vision ", brawler_wr["vision"])
		return false
	brawler.queue_free()

	# 3. An artillery design must be warned, and the warning has to name the
	# TRADE (how much of its reach it cannot use alone), not merely announce a
	# state - the same standard the overweight panel is held to.
	var arty = make_hull.call("heavy_hull", [["artillery"]])
	var arty_wr = WeaponRange.analyze(arty)
	if arty_wr["spotter_required"].is_empty():
		print("  [FAIL] a bare artillery design should be flagged as needing a spotter. reach ", arty_wr["longest"], " vs vision ", arty_wr["vision"])
		return false
	if arty_wr["longest"] <= arty_wr["vision"] * 2.0:
		print("  [FAIL] artillery's reach ", arty_wr["longest"], " should be more than double its hull's vision ", arty_wr["vision"])
		return false
	var usable_fraction: float = arty_wr["vision"] / arty_wr["longest"]
	if usable_fraction >= 0.5:
		print("  [FAIL] expected an artillery design to be able to self-acquire well under half its reach; got ", usable_fraction * 100.0, "%")
		return false
	arty.queue_free()

	# 4. Mounting a sensor mast has to actually change the advice - otherwise
	# the warning is telling the player to do something that does not help.
	var arty_mast = make_hull.call("heavy_hull", [["artillery"], ["sensor_suite"]])
	var mast_wr = WeaponRange.analyze(arty_mast)
	if mast_wr["vision"] <= arty_wr["vision"]:
		print("  [FAIL] a radar mast should raise the design's vision. without=", arty_wr["vision"], " with=", mast_wr["vision"])
		return false
	if not mast_wr["spotter_required"].is_empty():
		print("  [FAIL] with its own mast the artillery should drop out of the hard spotter-required state into the softer warning. vision=", mast_wr["vision"], " reach=", mast_wr["longest"])
		return false
	arty_mast.queue_free()

	# 5. Zero-damage utility modules must not be counted as weapons - a smoke
	# discharger would otherwise peg the "shortest" figure on an otherwise
	# long-ranged design, and a smoke-only hull would claim to be armed.
	var smoke_only = make_hull.call("medium_hull", [["smoke_discharger"]])
	if WeaponRange.analyze(smoke_only)["has_weapons"]:
		print("  [FAIL] a design carrying only a zero-dps smoke discharger should not report weapon range.")
		return false
	smoke_only.queue_free()

	# 6. A long barrel is a real design decision with a visible consequence:
	# it can push a direct-fire gun into needing a spotter it did not need
	# before. That is the trade the readout exists to surface.
	var stock_cannon = make_hull.call("medium_hull", [["basic_cannon"]])
	var long_cannon = make_hull.call("medium_hull", [["basic_cannon", {"barrel_length": 2.5}]])
	var stock_wr = WeaponRange.analyze(stock_cannon)
	var long_wr = WeaponRange.analyze(long_cannon)
	if long_wr["longest"] <= stock_wr["longest"]:
		print("  [FAIL] a 2.5x barrel should extend the design's reach. stock=", stock_wr["longest"], " long=", long_wr["longest"])
		return false
	if not stock_wr["spotter_required"].is_empty():
		print("  [FAIL] a stock cannon on a medium hull should not need a spotter.")
		return false
	if long_wr["spotter_required"].is_empty():
		print("  [FAIL] a 2.5x-barrel cannon reaching ", long_wr["longest"], " past a vision of ", long_wr["vision"], " should be flagged as spotter-dependent.")
		return false
	stock_cannon.queue_free()
	long_cannon.queue_free()

	print("  [PASS] The Design Lab reports the same reach combat uses, stays silent on designs that can see their own targets, names how much reach a spotter-dependent design cannot use alone, credits a radar mast for changing that, ignores zero-damage utility modules, and surfaces a long barrel pushing a gun into spotter dependence.")
	return true

