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
	# Armor phase / Traits B3 built fixed_wing_engine and naval_propeller as
	# generic mechanics usable by any hull, but nothing in the actual enemy
	# roster used them - the new strafing/surface-lock AI only ever ran in
	# synthetic tests, never a real AI-controlled Skirmish unit. These two
	# bundled blueprints (data/enemy/raptor_striker.json, tide_corvette.json)
	# close that gap.
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

	var corvette_data = bp_manager.load_blueprint("res://data/enemy/tide_corvette.json")
	if corvette_data.is_empty():
		print("  [FAIL] tide_corvette.json failed to parse")
		bp_manager.queue_free()
		return false
	var corvette = CharacterBody3D.new()
	corvette.set_script(BattleUnitScript)
	root.add_child(corvette)
	corvette.global_position = Vector3(30, 5.0, 30) # start above the waterline
	corvette.setup(corvette_data, 1, bp_manager)
	if not corvette.is_naval:
		print("  [FAIL] tide_corvette should derive is_naval from its naval_propeller locomotion trait")
		corvette.queue_free()
		bp_manager.queue_free()
		return false
	for i in range(30):
		corvette._physics_process(0.1)
	if abs(corvette.global_position.y - 0.3) > 1.0:
		print("  [FAIL] tide_corvette should settle to the surface waterline regardless of its spawn height, got y=", corvette.global_position.y)
		corvette.queue_free()
		bp_manager.queue_free()
		return false
	corvette.queue_free()

	bp_manager.queue_free()
	print("  [PASS] New enemy roster entries (fixed-wing raptor, naval corvette) reconstruct correctly and exercise the new movement traits.")
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

func test_win_condition() -> bool:
	print("Running Test Suite 11: Win/Lose Condition...")

	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	# Destroy the enemy HQ outright
	skirmish.enemy_hq.take_damage(999999.0, "explosive")
	await tree.process_frame

	var won = skirmish.game_over
	skirmish.queue_free()
	await tree.process_frame

	if won:
		print("  [PASS] Destroying the enemy HQ triggers game over (victory).")
		return true
	print("  [FAIL] Game over not triggered by HQ destruction.")
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

func test_fog_of_war_hides_reveals_and_never_hides_own_team() -> bool:
	print("Running Test Suite: Fog-of-War - Hides Unscouted Enemies, Reveals Scouted Ones, Never Hides Own Team...")
	await tree.process_frame

	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var enemy = CharacterBody3D.new()
	enemy.set_script(BattleUnitScript)
	skirmish.add_child(enemy)
	enemy.team = skirmish.ENEMY_TEAM
	enemy.set_meta("team", skirmish.ENEMY_TEAM)
	enemy.add_to_group("units")
	enemy.add_to_group("damageable")
	enemy.vision_range = 5.0
	enemy.global_position = Vector3(200, 0, 200) # far from any existing base/unit

	var far_player = CharacterBody3D.new()
	far_player.set_script(BattleUnitScript)
	skirmish.add_child(far_player)
	far_player.team = skirmish.PLAYER_TEAM
	far_player.set_meta("team", skirmish.PLAYER_TEAM)
	far_player.add_to_group("units")
	far_player.add_to_group("damageable")
	far_player.vision_range = 10.0
	far_player.global_position = Vector3(-200, 0, -200) # nowhere near the enemy

	skirmish._recalc_fog_of_war()
	if far_player.fog_hidden:
		print("  [FAIL] The player's own unit should never be fog_hidden, regardless of distance from any enemy")
		skirmish.queue_free()
		return false
	if not enemy.fog_hidden or enemy.visible:
		print("  [FAIL] An enemy far from every player construct should be fog_hidden and invisible, got fog_hidden=", enemy.fog_hidden, " visible=", enemy.visible)
		skirmish.queue_free()
		return false

	# Bring a player construct within the enemy's own vicinity (vision_range
	# is the OBSERVER's, not the observed's, so what matters is a player
	# unit's own vision_range reaching the enemy, not the enemy's).
	var near_player = CharacterBody3D.new()
	near_player.set_script(BattleUnitScript)
	skirmish.add_child(near_player)
	near_player.team = skirmish.PLAYER_TEAM
	near_player.set_meta("team", skirmish.PLAYER_TEAM)
	near_player.add_to_group("units")
	near_player.add_to_group("damageable")
	near_player.vision_range = 20.0
	near_player.global_position = Vector3(205, 0, 200) # within 20 units of the enemy at (200,0,200)

	skirmish._recalc_fog_of_war()
	if enemy.fog_hidden or not enemy.visible:
		print("  [FAIL] An enemy scouted by a nearby player unit should become visible, got fog_hidden=", enemy.fog_hidden, " visible=", enemy.visible)
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Fog-of-war hides unscouted enemies, reveals them once a player construct's vision reaches them, and never hides the player's own units.")
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

func test_elevation_combat_and_vision_bonus() -> bool:
	print("Running Test Suite: Multi-Map Terrain - Elevation Grants Real Vision + Combat Bonuses...")
	var DamageResolverScript = preload("res://scripts/damage_resolver.gd")

	# Combat: shooting down from meaningfully higher ground should lower
	# the defender's effective threshold (easier to pierce) vs an
	# identical shot from level ground.
	var defender = Node3D.new()
	root.add_child(defender)
	defender.global_position = Vector3(0, 0, 0)
	var level_shot = DamageResolverScript.resolve(null, [], "kinetic", defender, Vector3(0, 0, -5))
	var elevated_shot = DamageResolverScript.resolve(null, [], "kinetic", defender, Vector3(0, 5, -5))
	defender.queue_free()
	if not (elevated_shot.x < level_shot.x):
		print("  [FAIL] A shot from meaningfully higher ground should lower the defender's threshold (easier to pierce), level=", level_shot.x, " elevated=", elevated_shot.x)
		return false

	# Vision: a real Skirmish match, one player unit standing on a hill
	# should see further than an identical unit on flat ground - verified
	# by overriding current_map with a synthetic map that has one "hills"
	# feature (RTS_CORE_ROADMAP.md B6 retired elevation_zones; "hills" is
	# the still-supported analytic primitive terrain_height_at() reads via
	# height_at() for a map with no heightmap), then comparing effective
	# vision via _recalc_fog_of_war()'s own real reveal/hide behavior.
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame
	skirmish.current_map = {
		"map_half_extents": 80.0, "water_areas": [], "obstacles": [],
		"hills": [{"center": Vector3(0, 0, 0), "radius": 10.0, "height": 10.0, "falloff": 5.0}],
	}

	# Use battle_unit.gd instances (real vision_range + team + fog API) so
	# this exercises the actual code path, not a stand-in.
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var bp = {
		"version": 1.0, "hull_type": "medium_hull", "hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "tracked_treads", "settings": {"width": 1.0}}, "modules": [],
	}
	var scout_ground = CharacterBody3D.new()
	scout_ground.set_script(BattleUnitScript)
	skirmish.add_child(scout_ground)
	scout_ground.setup(bp, skirmish.PLAYER_TEAM, skirmish.bp_manager)
	# Every position here is expressed as a multiple of the unit's own
	# vision_range rather than as a fixed number of units. It used to park the
	# control scout at a literal (-40, 0, -40): that sat outside a ~20-unit
	# vision radius, but ModuleCatalog.VISION_SCALE moved the whole vision band
	# up to anchor the range tiers, and at 1.9x the control scout could see the
	# enemy by itself - so the "no elevation bonus means hidden" assertion
	# failed for a reason that had nothing to do with elevation. Scaling the
	# parking spot keeps the geometry of the test intact at any vision scale.
	var vision: float = scout_ground.vision_range
	var park := Vector3(-vision * 2.0, 0, -vision * 2.0)
	scout_ground.global_position = park

	var scout_hill = CharacterBody3D.new()
	scout_hill.set_script(BattleUnitScript)
	skirmish.add_child(scout_hill)
	scout_hill.global_position = Vector3(0, 10, 0)
	scout_hill.setup(bp, skirmish.PLAYER_TEAM, skirmish.bp_manager)

	var enemy_unit = CharacterBody3D.new()
	enemy_unit.set_script(BattleUnitScript)
	skirmish.add_child(enemy_unit)
	# Distance chosen to sit just outside a flat unit's base vision_range but
	# inside the elevated unit's boosted range (elevation bonus at height 10 =
	# 1 + 10*0.02 = 1.2x).
	var enemy_dist = vision * 1.08
	enemy_unit.global_position = Vector3(0, 0, -enemy_dist)
	enemy_unit.setup(bp, skirmish.ENEMY_TEAM, skirmish.bp_manager)

	skirmish._recalc_fog_of_war()
	await tree.process_frame

	if enemy_unit.fog_hidden:
		print("  [FAIL] Setup sanity check failed - enemy should be within the hill-standing scout's boosted vision range for this test to mean anything, but it's hidden")
		skirmish.queue_free()
		return false

	# Move the hill scout down to flat ground at the same XZ distance from
	# the enemy and re-check - should now be hidden (loses the bonus).
	scout_hill.global_position = park
	skirmish._recalc_fog_of_war()
	await tree.process_frame
	if not enemy_unit.fog_hidden:
		print("  [FAIL] Without the elevation bonus (scout moved to flat ground, same base vision_range), the enemy at this distance should no longer be visible")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Elevated ground gives a real, measurable combat threshold reduction and vision range boost, not just a cosmetic hill.")
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

func test_enemy_ai_counter_picks_the_players_composition() -> bool:
	print("Running Test Suite: Enemy AI Counter-Picking - Scouts The Player's Composition (FABLE_REVIEW 2.1)...")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	var ai = skirmish.get_node_or_null("EnemyAI")
	if not ai:
		print("  [FAIL] Skirmish should have an EnemyAI child node")
		skirmish.queue_free()
		return false

	# Pure classifier check first, no production side effects.
	if ai._scout_player_threat() != "":
		print("  [FAIL] With no player units at all, there should be no counter signal, got '", ai._scout_player_threat(), "'")
		skirmish.queue_free()
		return false

	var flyers = []
	for i in range(3):
		var u = CharacterBody3D.new()
		u.set_script(BattleUnitScript)
		root.add_child(u)
		u.team = 0
		u.is_flying = true
		u.add_to_group("units")
		flyers.append(u)
	await tree.process_frame

	if ai._scout_player_threat() != "air":
		print("  [FAIL] 3 flying player units should read as an 'air' threat signal, got '", ai._scout_player_threat(), "'")
		for u in flyers: u.queue_free()
		skirmish.queue_free()
		return false

	# End-to-end: give the enemy team ample resources and confirm _try_produce()
	# actually queues an anti-air-carrying design instead of whatever plain
	# round-robin would have picked next.
	skirmish.economy[skirmish.ENEMY_TEAM].metal = 100000
	skirmish.economy[skirmish.ENEMY_TEAM].crystal = 100000
	ai._try_produce()

	var queued_counter = false
	for b in skirmish.get_team_buildings(1):
		if not ("production_queue" in b): continue
		for job in b.production_queue:
			for mod in job.blueprint.get("modules", []):
				if mod.get("type_id", "") in ai.ANTI_AIR_WEAPONS:
					queued_counter = true
	if not queued_counter:
		print("  [FAIL] Facing an all-air player force, the enemy AI's next build should be an anti-air-carrying design, but none was found in any factory queue")
		for u in flyers: u.queue_free()
		skirmish.queue_free()
		return false

	for u in flyers: u.queue_free()
	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Enemy AI reads the player's live composition (air/armor majority) and biases its next build toward a design that actually answers it, falling back to round-robin otherwise.")
	return true

func test_enemy_intel_readout_respects_fog_of_war() -> bool:
	print("Running Test Suite: Enemy Composition Intel Readout - Fog-Gated, Not Omniscient (FABLE_REVIEW 2.1)...")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	if not skirmish.intel_label:
		print("  [FAIL] Skirmish should have created an intel_label in its UI setup")
		skirmish.queue_free()
		return false
	if not "No enemies sighted" in skirmish.intel_label.text:
		print("  [FAIL] With nothing scouted yet, the intel readout should say no enemies are sighted, got '", skirmish.intel_label.text, "'")
		skirmish.queue_free()
		return false

	# A far, unscouted flying enemy - should NOT show up in the readout at
	# all (fog-gated, not omniscient - the whole point of 2.1's other half).
	var far_enemy = CharacterBody3D.new()
	far_enemy.set_script(BattleUnitScript)
	skirmish.add_child(far_enemy)
	far_enemy.team = skirmish.ENEMY_TEAM
	far_enemy.set_meta("team", skirmish.ENEMY_TEAM)
	far_enemy.add_to_group("units")
	far_enemy.add_to_group("damageable")
	far_enemy.is_flying = true
	far_enemy.global_position = Vector3(300, 0, 300)

	skirmish._recalc_fog_of_war()
	if not "No enemies sighted" in skirmish.intel_label.text:
		print("  [FAIL] An unscouted enemy far from any player construct should not appear in the intel readout, got '", skirmish.intel_label.text, "'")
		far_enemy.queue_free()
		skirmish.queue_free()
		return false

	# Bring a player scout within vision range - the flying enemy should now
	# be sighted and categorized correctly.
	var scout = CharacterBody3D.new()
	scout.set_script(BattleUnitScript)
	skirmish.add_child(scout)
	scout.team = skirmish.PLAYER_TEAM
	scout.set_meta("team", skirmish.PLAYER_TEAM)
	scout.add_to_group("units")
	scout.add_to_group("damageable")
	scout.vision_range = 20.0
	scout.global_position = Vector3(295, 0, 300)

	skirmish._recalc_fog_of_war()
	if far_enemy.fog_hidden:
		print("  [FAIL] Test setup: the enemy should be visible to the nearby scout for this check to mean anything")
		scout.queue_free(); far_enemy.queue_free()
		skirmish.queue_free()
		return false
	if "No enemies sighted" in skirmish.intel_label.text or not "1" in skirmish.intel_label.text or not "air" in skirmish.intel_label.text:
		print("  [FAIL] A sighted flying enemy should show up in the intel readout as an air contact, got '", skirmish.intel_label.text, "'")
		scout.queue_free(); far_enemy.queue_free()
		skirmish.queue_free()
		return false

	scout.queue_free()
	far_enemy.queue_free()
	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Enemy composition intel readout stays empty until something is actually scouted, then correctly categorizes what's currently visible (fog-gated, not omniscient).")
	return true

# RTS_CORE_ROADMAP.md 1.3, item 3: "place defenses near the HQ under attack" -
# the enemy roster previously had zero defense (foundation-hull) blueprints
# at all (res://data/enemy/ was combat-vehicle-only), so this also depends on
# data/enemy/gatling_pillbox.json existing now. Damages the enemy HQ (a
# realistic partial hit, not a kill) after seeding the AI's own baseline HP
# reading, then proves _defend_hq_if_under_attack() queues and places a real
# defense near it.
func test_1_3_ai_places_a_defense_when_its_hq_takes_damage() -> bool:
	print("Running Test Suite: 1.3 - Enemy AI Places A Defense When Its HQ Takes Damage (UNIFIED_ROADMAP.md 1.3)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	var ai = skirmish.get_node("EnemyAI")
	if ai._defense_roster().is_empty():
		print("  [FAIL] Test setup: enemy_roster should have at least one legal defense entry (data/enemy/gatling_pillbox.json)")
		skirmish.queue_free()
		return false

	# Seed the AI's baseline HQ-hp reading with a full-health check BEFORE
	# any damage, exactly like a real match's first 8s window would - the
	# very first call only seeds _last_hq_hp (see the function's own
	# sentinel-guard comment), it can't detect damage that hasn't happened yet.
	ai._defend_hq_if_under_attack()
	if ai._last_hq_hp != skirmish.enemy_hq.hp:
		print("  [FAIL] Test setup: the first check should have seeded _last_hq_hp at full HQ health")
		skirmish.queue_free()
		return false

	skirmish.enemy_hq.take_damage(500.0, "explosive") # a real hit, well short of a kill
	if skirmish.enemy_hq.is_dead:
		print("  [FAIL] Test setup: 500 damage should not have killed the HQ (max_hp 3000)")
		skirmish.queue_free()
		return false

	skirmish.add_resources(skirmish.ENEMY_TEAM, 5000, 5000)
	var defense_count_before = 0
	for b in skirmish.get_team_buildings(skirmish.ENEMY_TEAM):
		if b.kind == "defense":
			defense_count_before += 1

	var built = false
	for i in range(3000):
		ai._physics_process(1.0 / 60.0)
		skirmish.production.tick(1.0 / 60.0)
		skirmish._physics_process(1.0 / 60.0)
		var count = 0
		for b in skirmish.get_team_buildings(skirmish.ENEMY_TEAM):
			if b.kind == "defense":
				count += 1
		if count > defense_count_before:
			built = true
			break
	if not built:
		print("  [FAIL] The AI should have placed a defense in response to its HQ taking damage within the simulated time budget")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] The AI queues and places a real defense near its HQ once the HQ visibly takes damage.")
	return true

