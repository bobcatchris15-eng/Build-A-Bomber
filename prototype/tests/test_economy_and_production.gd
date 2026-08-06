extends "res://tests/suite_base.gd"
# economy and production suites, split out of the former single-file
# run_tests.gd. Registration order lives in run_tests.gd's SUITE_ORDER,
# not here - the runner drives that manifest so execution order is
# identical to the pre-split single file.

# Resource field regrowth (Chris's own call, 2026-07-27, cribbed from
# C&C/Tiberium fields): a node left alone regrows gradually, whether it was
# merely picked at or fully depleted. Proves the real state machine: no
# regrowth while recently harvested, real regrowth once REGROW_DELAY has
# passed, capped at start_amount, and a fully-depleted node rejoins the
# "resource_nodes" group (re-harvestable) once it regrows above zero.
func test_resource_node_regrows_gradually_after_being_mined() -> bool:
	print("Running Test Suite: Resource Node Regrowth After Mining (C&C-style field regrowth)...")
	var ResourceNodeScript = preload("res://scripts/resource_node.gd")
	var node = StaticBody3D.new()
	node.set_script(ResourceNodeScript)
	root.add_child(node)
	node.setup("metal", 1000)
	await tree.process_frame

	node.harvest(600) # partial draw, 400 left
	if node.amount != 400:
		print("  [FAIL] Test setup: harvest(600) from 1000 should leave 400, got ", node.amount)
		node.queue_free()
		return false

	# Immediately after harvesting, no regrowth yet - still within REGROW_DELAY.
	for i in range(300): # 5 real seconds, well under the 15s delay
		node._physics_process(1.0 / 60.0)
	if node.amount != 400:
		print("  [FAIL] A recently-harvested node should not regrow yet, got ", node.amount)
		node.queue_free()
		return false

	# Push well past REGROW_DELAY - real regrowth should now accumulate.
	# (REGROW_DELAY is only crossed partway through this loop, so there
	# needs to be real time left AFTER crossing it for accumulation to
	# produce a whole unit, not just "5s + exactly 15s total".)
	for i in range(1200): # 20 more real seconds -> 25s total elapsed, 10s past the 15s delay
		node._physics_process(1.0 / 60.0)
	if node.amount <= 400:
		print("  [FAIL] A node left alone past REGROW_DELAY should have regrown some amount, stayed at ", node.amount)
		node.queue_free()
		return false
	if node.amount > node.start_amount:
		print("  [FAIL] Regrowth should never exceed start_amount, got ", node.amount, "/", node.start_amount)
		node.queue_free()
		return false

	# Fully deplete, confirm it leaves the harvestable group, then confirm
	# it eventually regrows back into it.
	node.harvest(node.amount)
	if node.amount != 0 or node.is_in_group("resource_nodes"):
		print("  [FAIL] A fully depleted node should read amount=0 and leave the resource_nodes group")
		node.queue_free()
		return false
	var regrew = false
	for i in range(6000): # 100 real seconds - comfortably enough at a 1%/s rate to regrow measurably
		node._physics_process(1.0 / 60.0)
		if node.amount > 0:
			regrew = true
			break
	if not regrew:
		print("  [FAIL] A fully-depleted node should eventually regrow given enough time")
		node.queue_free()
		return false
	if not node.is_in_group("resource_nodes"):
		print("  [FAIL] A regrown node should rejoin the resource_nodes group (re-harvestable again)")
		node.queue_free()
		return false

	node.queue_free()
	await tree.process_frame
	print("  [PASS] A resource node regrows gradually after a delay, whether merely picked at or fully depleted, and becomes re-harvestable again.")
	return true

func test_blueprint_cost_and_rosters() -> bool:
	print("Running Test Suite 9: Blueprint Costs & Bundled Rosters...")

	var skirmish_script = load("res://scripts/skirmish.gd")
	var skirmish = Node3D.new()
	skirmish.set_script(skirmish_script)
	# Don't add to tree (that would start the full game); test pure helpers.
	var bp_manager = preload("res://scripts/blueprint_manager.gd").new()
	root.add_child(bp_manager)
	skirmish.bp_manager = bp_manager

	var checked = 0
	for dir_path in ["res://data/loadout", "res://data/enemy"]:
		var dir = DirAccess.open(dir_path)
		if not dir:
			print("  [FAIL] Bundled blueprint dir missing: ", dir_path)
			return false
		dir.list_dir_begin()
		var fname = dir.get_next()
		while fname != "":
			if fname.ends_with(".json"):
				var data = bp_manager.load_blueprint(dir_path + "/" + fname)
				if data.is_empty():
					print("  [FAIL] Bundled blueprint failed to parse: ", fname)
					return false
				var cost = skirmish.blueprint_cost(data)
				if cost.x <= 0:
					print("  [FAIL] Blueprint has non-positive metal cost: ", fname)
					return false
				var t = skirmish.build_time_for_cost(cost)
				if t < 3.0 or t > 40.0:
					print("  [FAIL] Build time out of range for ", fname, ": ", t)
					return false
				checked += 1
			fname = dir.get_next()
		dir.list_dir_end()

	# Foundation classification
	if not ModuleCatalog.is_foundation("pillbox_foundation") or ModuleCatalog.is_foundation("medium_hull"):
		print("  [FAIL] Foundation classification incorrect.")
		return false

	bp_manager.queue_free()
	skirmish.free()
	print("  [PASS] ", checked, " bundled blueprints parse with valid costs; foundations classified.")
	return true

func test_skirmish_economy_and_production() -> bool:
	print("Running Test Suite 10: Skirmish Economy & Factory Production...")

	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	# Economy math - deliberately checked against ENEMY_TEAM (1), not
	# PLAYER_TEAM (0): Chris's infinite-resources testing cheat
	# (skirmish.gd's debug_infinite_resources, RTS_CORE_ROADMAP.md A2) clamps team 0's
	# economy back up to a floor after every spend, which is the whole
	# point of the cheat but means team 0 can no longer exercise a real
	# deduct-and-reject-overspend check. The underlying spend()/can_afford()
	# logic is team-agnostic, so testing it via team 1 still covers the
	# same code path without fighting the cheat.
	var start_metal = skirmish.economy[1].metal
	if not skirmish.spend(1, 100, 0):
		print("  [FAIL] Could not spend affordable amount.")
		skirmish.queue_free()
		return false
	if skirmish.economy[1].metal != start_metal - 100:
		print("  [FAIL] Spend did not deduct correctly.")
		skirmish.queue_free()
		return false
	if skirmish.spend(1, 999999, 0):
		print("  [FAIL] Overspend was allowed.")
		skirmish.queue_free()
		return false
	skirmish.add_resources(1, 100, 0)

	# Rosters loaded (bundled defaults guarantee at least 4 + 4)
	if skirmish.roster.size() < 4 or skirmish.enemy_roster.size() < 4:
		print("  [FAIL] Rosters not loaded. Player: ", skirmish.roster.size(), " Enemy: ", skirmish.enemy_roster.size())
		skirmish.queue_free()
		return false

	# Bases spawned
	if not is_instance_valid(skirmish.player_hq) or not is_instance_valid(skirmish.enemy_hq):
		print("  [FAIL] HQs not spawned.")
		skirmish.queue_free()
		return false

	# Factory production: queue a cheap unit with a tiny build time and confirm a unit spawns
	var factory = skirmish.get_team_factory(0)
	if not factory:
		print("  [FAIL] Player factory not found.")
		skirmish.queue_free()
		return false
	var entry = null
	for e in skirmish.roster:
		if not e.is_defense:
			entry = e
			break
	var units_before = skirmish.get_team_units(0).size()
	factory.queue_unit(entry.blueprint, 0.2)
	var ticks = 0
	var produced = false
	while ticks < 120:
		await tree.process_frame
		ticks += 1
		if skirmish.get_team_units(0).size() > units_before:
			produced = true
			break
	if not produced:
		print("  [FAIL] Factory did not produce a unit.")
		skirmish.queue_free()
		return false

	# Harvester auto-work: the starting harvester should pick a resource node
	var harvester = null
	for u in skirmish.get_team_units(0):
		if u.is_harvester:
			harvester = u
			break
	var harvester_ok = harvester != null

	skirmish.queue_free()
	await tree.process_frame

	if harvester_ok:
		print("  [PASS] Economy, rosters, base spawn, and factory production all verified.")
		return true
	print("  [FAIL] Starting harvester missing.")
	return false

func test_size_tiered_manufactories() -> bool:
	print("Running Test Suite: Base-Building - Size-Tiered Manufactories (Light/Medium/Heavy By Hull Weight, Not Domain)...")
	var ModuleCatalog = preload("res://scripts/module_catalog.gd")

	# The exact per-hull tier mapping logged in DECISIONS_NEEDED.md - spot-
	# check a few.
	var expectations = {
		"light_hull": "light", "roadster_hull": "light",
		"medium_hull": "medium", "airship_hull": "medium",
		"heavy_hull": "heavy", "assault_hull": "heavy",
		"cabover_truck_hull": "medium", "locomotive_hull": "heavy",
	}
	for hull_type in expectations:
		var got = ModuleCatalog.get_hull_size_tier(hull_type)
		if got != expectations[hull_type]:
			print("  [FAIL] ", hull_type, " should be tier '", expectations[hull_type], "', got '", got, "'")
			return false
	# Foundations (static defenses) aren't produced from a manufactory at all.
	if ModuleCatalog.get_hull_size_tier("pillbox_foundation") != "":
		print("  [FAIL] Foundation hulls should return an empty tier (never queued from a manufactory)")
		return false

	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	var ok = true
	# Every match should start with all 3 tiers already built, for both teams.
	for team in [skirmish.PLAYER_TEAM, skirmish.ENEMY_TEAM]:
		for tier in ["light", "medium", "heavy"]:
			if not skirmish.get_team_factory(team, tier):
				print("  [FAIL] Team ", team, " should start with a real ", tier, "_manufactory already built")
				ok = false
	# tier="" (backward-compatible "any tier") should still return something real.
	if not skirmish.get_team_factory(skirmish.PLAYER_TEAM):
		print("  [FAIL] get_team_factory(team) with no tier arg should still return a real manufactory (back-compat for generic callers like the map smoke test)")
		ok = false

	# Real tier-gating: queuing a heavy-tier design should use the Heavy
	# Manufactory specifically, not just whichever one's queue is emptiest.
	var heavy_manufactory = skirmish.get_team_factory(skirmish.PLAYER_TEAM, "heavy")
	var light_manufactory = skirmish.get_team_factory(skirmish.PLAYER_TEAM, "light")
	var heavy_blueprint = {
		"version": 1.0, "hull_type": "heavy_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "armor_thickness": 1.0,
		"locomotion": {"type_id": "tracked_treads", "settings": {"width": 1.0}},
		"modules": [
			{"type_id": "tracked_treads", "name": "Treads", "position": {"x": 0, "y": 0, "z": 0}, "rotation": {"x": 0, "y": 0, "z": 0}, "scale": {"x": 1, "y": 1, "z": 1}, "tweaks": {}},
			{"type_id": "basic_cannon", "name": "Cannon", "position": {"x": 0, "y": 0.75, "z": 0}, "rotation": {"x": 0, "y": 0, "z": 0}, "scale": {"x": 1, "y": 1, "z": 1}, "tweaks": {}},
		],
	}
	var heavy_entry = {"blueprint": heavy_blueprint, "name": "Test Heavy Unit", "cost_metal": 300, "cost_crystal": 60, "is_defense": false}
	skirmish.economy[skirmish.PLAYER_TEAM].metal = 5000
	skirmish.economy[skirmish.PLAYER_TEAM].crystal = 5000
	skirmish._queue_player_unit(heavy_entry)
	if heavy_manufactory.production_queue.is_empty():
		print("  [FAIL] A heavy_hull design should have been queued on the Heavy Manufactory")
		ok = false
	if not light_manufactory.production_queue.is_empty():
		print("  [FAIL] A heavy_hull design should NOT be queued on the Light Manufactory")
		ok = false

	# If the required tier's manufactory doesn't exist (destroyed mid-match),
	# queuing should fail gracefully rather than silently using another tier.
	heavy_manufactory.is_dead = true
	var units_before = skirmish.get_team_units(skirmish.PLAYER_TEAM).size()
	skirmish._queue_player_unit(heavy_entry)
	if heavy_manufactory.production_queue.size() > 1:
		print("  [FAIL] With the Heavy Manufactory marked dead, a second heavy_hull queue attempt should NOT have gone through")
		ok = false

	skirmish.queue_free()
	await tree.process_frame

	if ok:
		print("  [PASS] Hull size tiers map correctly across domains (a boat and a ground hull share a tier by weight), every match starts with all 3 manufactories built for both teams, and queuing genuinely routes to the matching tier - not just any available factory.")
	return ok

func test_energy_pool_and_generators() -> bool:
	print("Running Test Suite: Energy Resource - Base Pool + Generator Modules...")
	await tree.process_frame # let any deferred queue_free()s from prior tests actually clear
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var bp_manager = preload("res://scripts/blueprint_manager.gd").new()
	root.add_child(bp_manager)

	var bp_no_gen = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "tracked_treads", "settings": {"width": 1.0}},
		"modules": []
	}
	var unit_no_gen = CharacterBody3D.new()
	unit_no_gen.set_script(BattleUnitScript)
	root.add_child(unit_no_gen)
	unit_no_gen.setup(bp_no_gen, 0, bp_manager)
	var base_only = unit_no_gen.max_energy
	if base_only <= 0.0:
		print("  [FAIL] medium_hull should carry a nonzero base_energy pool even with no generators, got ", base_only)
		bp_manager.queue_free()
		return false
	unit_no_gen.queue_free()

	var bp_with_gen = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "tracked_treads", "settings": {"width": 1.0}},
		"modules": [
			{"type_id": "fusion_generator", "name": "Fusion Generator", "position": {"x": 0.0, "y": 0.5, "z": 0.0}, "rotation": {"x": 0.0, "y": 0.0, "z": 0.0}, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "yaw_offset": 0.0, "tweaks": {}}
		]
	}
	var unit_with_gen = CharacterBody3D.new()
	unit_with_gen.set_script(BattleUnitScript)
	root.add_child(unit_with_gen)
	unit_with_gen.setup(bp_with_gen, 0, bp_manager)
	if unit_with_gen.max_energy <= base_only:
		print("  [FAIL] A mounted fusion_generator should raise max_energy above the hull's base_energy alone (base=", base_only, ", with generator=", unit_with_gen.max_energy, ")")
		bp_manager.queue_free()
		return false

	unit_with_gen.current_energy = 0.0
	for i in range(20):
		unit_with_gen._physics_process(0.1)
	if unit_with_gen.current_energy <= 0.0:
		print("  [FAIL] Energy should regenerate over time from 0, got ", unit_with_gen.current_energy)
		bp_manager.queue_free()
		return false

	unit_with_gen.queue_free()
	bp_manager.queue_free()
	print("  [PASS] Hulls carry a base energy pool; generator modules raise max_energy above it; energy regenerates over time.")
	return true

func test_repair_array_heals_allies_only() -> bool:
	print("Running Test Suite: Repair Array - Real Ally-Targeting Heal (not damage)...")
	await tree.process_frame # let any deferred queue_free()s from prior tests actually clear
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var healer = CharacterBody3D.new()
	healer.set_script(BattleUnitScript)
	root.add_child(healer)
	healer.team = 0
	healer.set_meta("team", 0)
	healer.add_to_group("damageable")

	var weapon = Node3D.new()
	weapon.set_script(load("res://scripts/auto_weapon.gd"))
	healer.add_child(weapon)
	var w_data = ModuleData.new()
	w_data.type_id = "repair_array"
	w_data.base_weight = 70.0
	w_data.base_heal_rate = 30.0
	weapon.set_meta("module_data", w_data)
	weapon._ready()
	if weapon.heal_rate <= 0.0:
		print("  [FAIL] repair_array should have a nonzero heal_rate (dedicated stat, not dps), got ", weapon.heal_rate)
		healer.queue_free()
		return false
	if weapon.dps != 0.0:
		print("  [FAIL] repair_array should deal zero real damage now that heal_rate is its own stat, got dps=", weapon.dps)
		healer.queue_free()
		return false
	if not weapon.targets_allies:
		print("  [FAIL] repair_array should have targets_allies=true")
		healer.queue_free()
		return false

	var damaged_ally = CharacterBody3D.new()
	damaged_ally.set_script(BattleUnitScript)
	root.add_child(damaged_ally)
	damaged_ally.team = 0
	damaged_ally.set_meta("team", 0)
	damaged_ally.add_to_group("damageable")
	damaged_ally.max_hp = 200.0
	damaged_ally.hp = 100.0
	damaged_ally.global_position = weapon.global_position + Vector3(0, 0, -3) # -Z: within the weapon's default forward-facing traverse cone

	var enemy = CharacterBody3D.new()
	enemy.set_script(BattleUnitScript)
	root.add_child(enemy)
	enemy.team = 1
	enemy.set_meta("team", 1)
	enemy.add_to_group("damageable")
	enemy.max_hp = 200.0
	enemy.hp = 50.0 # also damaged, but hostile - must never be selected
	enemy.global_position = weapon.global_position + Vector3(0, 0, -1) # closer than the ally, same forward cone

	weapon._find_nearest_target()
	if weapon.target != damaged_ally:
		print("  [FAIL] repair_array should target the damaged ALLY, not the closer damaged enemy, got ", weapon.target)
		healer.queue_free(); damaged_ally.queue_free(); enemy.queue_free()
		return false

	weapon.target = damaged_ally
	# _fire_repair_array_beam() spawns cosmetic visuals via
	# get_tree().current_scene.add_child() - current_scene must be a direct
	# child of the tree's actual root, not root itself.
	var scene_stub = Node3D.new()
	root.add_child(scene_stub)
	current_scene = scene_stub
	var hp_before = damaged_ally.hp
	weapon._fire_repair_array_beam()
	if damaged_ally.hp <= hp_before:
		print("  [FAIL] repair_array's beam should have healed the ally, hp went from ", hp_before, " to ", damaged_ally.hp)
		healer.queue_free(); damaged_ally.queue_free(); enemy.queue_free()
		return false

	healer.queue_free()
	damaged_ally.queue_free()
	enemy.queue_free()
	print("  [PASS] repair_array targets same-team HP-deficit allies (never hostiles) and its beam actually heals.")
	return true

func test_energy_weapons_cost_and_drain() -> bool:
	print("Running Test Suite: Energy Weapons - Cost To Fire + Target Energy Drain...")
	await tree.process_frame # let any deferred queue_free()s from prior tests actually clear
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var shooter = CharacterBody3D.new()
	shooter.set_script(BattleUnitScript)
	root.add_child(shooter)
	shooter.team = 0
	shooter.set_meta("team", 0)
	shooter.add_to_group("damageable")
	shooter.max_energy = 100.0
	shooter.current_energy = 100.0
	shooter.energy_regen_rate = 0.0 # isolate the spend, no regen muddying the assertion

	var weapon = Node3D.new()
	weapon.set_script(load("res://scripts/auto_weapon.gd"))
	shooter.add_child(weapon)
	var w_data = ModuleData.new()
	w_data.type_id = "arc_projector"
	w_data.base_weight = 45.0
	w_data.base_dps = 40.0
	weapon.set_meta("module_data", w_data)
	weapon._ready()
	if weapon.energy_cost_per_shot <= 0.0:
		print("  [FAIL] An energy weapon should have a nonzero energy_cost_per_shot, got ", weapon.energy_cost_per_shot)
		shooter.queue_free()
		return false

	var target_unit = CharacterBody3D.new()
	target_unit.set_script(BattleUnitScript)
	root.add_child(target_unit)
	target_unit.team = 1
	target_unit.set_meta("team", 1)
	target_unit.add_to_group("damageable")
	target_unit.max_hp = 500.0
	target_unit.hp = 500.0
	target_unit.max_energy = 50.0
	target_unit.current_energy = 50.0
	target_unit.global_position = weapon.global_position + Vector3(0, 0, -5) # within the default forward-facing traverse cone, nonzero distance

	weapon.target = target_unit
	var scene_stub = Node3D.new()
	root.add_child(scene_stub)
	current_scene = scene_stub # _fire_arc_projector() spawns visuals via get_tree().current_scene.add_child()
	var energy_before = shooter.current_energy
	var target_energy_before = target_unit.current_energy
	weapon.time_since_last_shot = weapon.fire_rate # ready to fire immediately
	for i in range(30):
		weapon._physics_process(0.1)
		if shooter.current_energy < energy_before:
			break
	if shooter.current_energy >= energy_before:
		print("  [FAIL] Firing an energy weapon should spend the shooter's own current_energy, stayed at ", shooter.current_energy)
		shooter.queue_free(); target_unit.queue_free()
		return false
	if target_unit.current_energy >= target_energy_before:
		print("  [FAIL] arc_projector should drain the TARGET's energy pool, stayed at ", target_unit.current_energy)
		shooter.queue_free(); target_unit.queue_free()
		return false

	# Capacitor-empty gate: with current_energy forced to 0, the weapon must not fire.
	shooter.current_energy = 0.0
	var target_hp_before = target_unit.hp
	var target_energy_before2 = target_unit.current_energy
	weapon.time_since_last_shot = weapon.fire_rate
	weapon._physics_process(0.1)
	if target_unit.hp != target_hp_before or target_unit.current_energy != target_energy_before2:
		print("  [FAIL] An energy weapon with an empty capacitor should not be able to fire")
		shooter.queue_free(); target_unit.queue_free()
		return false

	shooter.queue_free()
	target_unit.queue_free()
	print("  [PASS] Energy weapons spend the shooter's own capacitor per shot, drain the target's energy pool, and can't fire with an empty capacitor.")
	return true

func test_no_energy_deficit_at_match_start() -> bool:
	print("Running Test Suite: No Automatic Energy Deficit At Match Start...")
	# Real bug found via the visual regression pass (skirmish_hud capture
	# showed "Energy: 0/0 (DEFICIT: builds slower!)" in the very first
	# frame of a match, before any real gameplay) - without a baseline HQ
	# contribution, every match started in automatic deficit (0 capacity
	# vs. 3 starting static buildings' upkeep), applying the factory
	# build-speed penalty before a player had any chance to build a
	# generator. Fixed with ENERGY_HQ_BASELINE_CAPACITY; this guards it
	# doesn't silently regress.
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	if skirmish.is_energy_deficit(skirmish.PLAYER_TEAM):
		print("  [FAIL] A freshly-started match should not begin in Energy deficit, got capacity=", skirmish.energy_pool[skirmish.PLAYER_TEAM].capacity)
		skirmish.queue_free()
		return false
	if skirmish.is_energy_deficit(skirmish.ENEMY_TEAM):
		print("  [FAIL] The enemy team should also not begin in Energy deficit")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Both teams start with a non-deficit Energy baseline (HQ's own power plant offsets default static-building upkeep).")
	return true

func test_energy_damage_class_reclassification() -> bool:
	print("Running Test Suite: heavy_laser/plasma_lobber/pd_laser Reclassified To Energy Damage (not capacitor-limited)...")
	# damage_resolver.gd previously had no "energy" row in ARMOR_TABLE at
	# all, so anything dealing damage_class=="energy" silently fell back to
	# resolving as EXPLOSIVE damage (row.get(damage_type, row["explosive"])) -
	# a real bug, not just a missing feature. Fixed with a genuine energy
	# row, then these three thematically-energy weapons were reclassified
	# for real (see DECISIONS_NEEDED.md for the concrete threshold-swing
	# numbers this changes against ablative_ceramic/energy_shielding).
	var AutoWeaponScript = load("res://scripts/auto_weapon.gd")

	# 1. A real energy row must exist and be genuinely distinct from explosive.
	var steel_energy = DamageResolverScript.get_material_threshold("hardened_steel", "energy", 1.0)
	var steel_explosive = DamageResolverScript.get_material_threshold("hardened_steel", "explosive", 1.0)
	if steel_energy == steel_explosive:
		print("  [FAIL] 'energy' damage_type should resolve to its own real threshold, not silently fall back to explosive, got ", steel_energy, " == ", steel_explosive)
		return false
	# energy_shielding should be the strongest defense specifically against
	# energy damage - its own name is the thematic justification.
	var shield_energy = DamageResolverScript.get_material_threshold("energy_shielding", "energy", 1.0)
	var steel_energy_thresh = steel_energy.x
	if shield_energy.x <= steel_energy_thresh:
		print("  [FAIL] energy_shielding should have a stronger energy threshold than hardened_steel, got shield=", shield_energy.x, " steel=", steel_energy_thresh)
		return false

	for type_id in ["heavy_laser", "plasma_lobber", "pd_laser"]:
		var weapon = Node3D.new()
		weapon.set_script(AutoWeaponScript)
		root.add_child(weapon)
		var w_data = ModuleData.new()
		w_data.type_id = type_id
		w_data.base_weight = 60.0
		w_data.base_dps = 20.0
		weapon.set_meta("module_data", w_data)
		weapon._ready()
		if weapon.damage_class != "energy":
			print("  [FAIL] ", type_id, " should be reclassified to damage_class 'energy', got '", weapon.damage_class, "'")
			weapon.queue_free()
			return false
		# Must NOT pick up the capacitor-cost/drain mechanic - that's
		# scoped to tesla_coil/arc_projector/ion_cannon only.
		if weapon.energy_cost_per_shot != 0.0:
			print("  [FAIL] ", type_id, " should NOT cost the shooter's own Energy pool to fire (that's only tesla_coil/arc_projector/ion_cannon), got cost=", weapon.energy_cost_per_shot)
			weapon.queue_free()
			return false
		weapon.queue_free()

	await tree.process_frame
	print("  [PASS] damage_resolver.gd has a real energy armor row; heavy_laser/plasma_lobber/pd_laser deal energy damage but stay capacitor-free.")
	return true

func test_d1_drip_fed_cost_pauses_when_broke_and_resumes_on_income() -> bool:
	print("Running Test Suite: D1 - Drip-Fed Cost Pauses On Broke, Resumes On Income, Completes (RTS_CORE_ROADMAP.md D1)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	# RTS_CORE_ROADMAP.md D1's own note: must explicitly disable the A2
	# infinite-resources toggle, or every assertion here passes vacuously.
	skirmish.debug_infinite_resources = false
	skirmish.economy[skirmish.PLAYER_TEAM].metal = 100
	skirmish.economy[skirmish.PLAYER_TEAM].crystal = 1000 # not the bottleneck being tested

	var result = skirmish.production.enqueue(skirmish.PLAYER_TEAM, _d1_test_blueprint(), skirmish.player_faction, 300, 0)
	if not result.queued:
		print("  [FAIL] Queuing a 300-cost item with only 100 metal banked should succeed (D1: no longer requires the full cost up front), got error: ", result.error, " ", result.reason)
		skirmish.queue_free()
		return false

	var tier = result.tier
	var q = skirmish.production.get_queue(skirmish.PLAYER_TEAM, tier)
	if q.size() != 1:
		print("  [FAIL] Expected exactly 1 queued item, got ", q.size())
		skirmish.queue_free()
		return false
	var job = q[0]

	# Drip-feed only 1/3 of the total_time worth of cost is affordable (100
	# of 300 metal) - tick well past that point (10s at 60fps) and confirm
	# it stalled rather than completing or overdrawing.
	for i in range(600):
		skirmish.production.tick(1.0 / 60.0)
	if skirmish.economy[skirmish.PLAYER_TEAM].metal != 0:
		print("  [FAIL] All 100 banked metal should have been drawn by now, got ", skirmish.economy[skirmish.PLAYER_TEAM].metal, " remaining")
		skirmish.queue_free()
		return false
	if job.time_left <= 0.0:
		print("  [FAIL] The build should still be incomplete (only 1/3 of its cost was ever affordable), but time_left=", job.time_left)
		skirmish.queue_free()
		return false
	var stalled_time_left = job.time_left

	# Broke and staying broke - ticking further should make ZERO progress,
	# not just slow progress (this is a pause, not a slowdown).
	for i in range(60):
		skirmish.production.tick(1.0 / 60.0)
	if job.time_left != stalled_time_left:
		print("  [FAIL] With no income, the stalled build should make exactly zero further progress, but time_left changed from ", stalled_time_left, " to ", job.time_left)
		skirmish.queue_free()
		return false

	# Income arrives - the build should resume and eventually complete (the
	# job leaves the queue and a real unit spawns).
	skirmish.add_resources(skirmish.PLAYER_TEAM, 300, 0)
	var completed = false
	for i in range(900):
		skirmish.production.tick(1.0 / 60.0)
		if skirmish.production.get_queue(skirmish.PLAYER_TEAM, tier).is_empty():
			completed = true
			break
	if not completed:
		print("  [FAIL] The build should have completed once income arrived, but the job is still in the queue after 15s of ticking")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] A drip-fed build correctly stalls when broke (making zero further progress, not slowed progress), then resumes and completes once income arrives.")
	return true

func test_d1_cancel_refunds_exact_progress_drawn() -> bool:
	print("Running Test Suite: D1 - Cancel Refunds Exactly What Was Drawn, Not The Full Cost (RTS_CORE_ROADMAP.md D1)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	skirmish.debug_infinite_resources = false
	skirmish.economy[skirmish.PLAYER_TEAM].metal = 1000
	skirmish.economy[skirmish.PLAYER_TEAM].crystal = 1000

	var result = skirmish.production.enqueue(skirmish.PLAYER_TEAM, _d1_test_blueprint(), skirmish.player_faction, 300, 0)
	if not result.queued:
		print("  [FAIL] Test setup: queuing should have succeeded, got error: ", result.error)
		skirmish.queue_free()
		return false
	var tier = result.tier
	var bank_after_queue = skirmish.economy[skirmish.PLAYER_TEAM].metal

	# Tick partway through the build (well short of completion) - some real
	# cost has been drawn, but not all of it.
	for i in range(150): # 2.5s of a build costing 15s total
		skirmish.production.tick(1.0 / 60.0)
	var bank_mid_build = skirmish.economy[skirmish.PLAYER_TEAM].metal
	var spent_so_far = bank_after_queue - bank_mid_build
	if spent_so_far <= 0 or spent_so_far >= 300:
		print("  [FAIL] Test setup: expected SOME but not ALL of the 300 cost drawn by now, got ", spent_so_far)
		skirmish.queue_free()
		return false

	var refund = skirmish.production.cancel(skirmish.PLAYER_TEAM, tier, 0)
	var bank_after_cancel = skirmish.economy[skirmish.PLAYER_TEAM].metal

	if refund.metal != spent_so_far:
		print("  [FAIL] cancel() should report refunding exactly what was drawn (", spent_so_far, "), got ", refund.metal)
		skirmish.queue_free()
		return false
	if bank_after_cancel != bank_mid_build + spent_so_far:
		print("  [FAIL] Bank should be credited exactly the refund amount - expected ", bank_mid_build + spent_so_far, ", got ", bank_after_cancel)
		skirmish.queue_free()
		return false
	if not skirmish.production.get_queue(skirmish.PLAYER_TEAM, tier).is_empty():
		print("  [FAIL] The cancelled item should be gone from the queue")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Cancelling a mid-build job refunds exactly the amount actually drawn so far (", spent_so_far, "), not the full cost, and removes it from the queue.")
	return true

func test_d2_build_bar_tabs_switch_visibility_and_pressed_state() -> bool:
	print("Running Test Suite: D2 - Build Bar Tabs Switch Visibility And Pressed State (RTS_CORE_ROADMAP.md D2)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	if skirmish.active_build_tab != "units":
		print("  [FAIL] Default active tab should be 'units', got ", skirmish.active_build_tab)
		skirmish.queue_free()
		return false
	for tab_name in ["structures", "defenses", "units"]:
		var scroll = skirmish.build_tab_containers[tab_name].get_parent()
		if scroll.visible != (tab_name == "units"):
			print("  [FAIL] Only the default 'units' tab's ScrollContainer should start visible, '", tab_name, "' visible=", scroll.visible)
			skirmish.queue_free()
			return false

	skirmish._set_active_build_tab("structures")
	if skirmish.active_build_tab != "structures":
		print("  [FAIL] active_build_tab should update to 'structures'")
		skirmish.queue_free()
		return false
	for tab_name in ["structures", "defenses", "units"]:
		var scroll = skirmish.build_tab_containers[tab_name].get_parent()
		if scroll.visible != (tab_name == "structures"):
			print("  [FAIL] After switching to 'structures', only its ScrollContainer should be visible, '", tab_name, "' visible=", scroll.visible)
			skirmish.queue_free()
			return false
		if skirmish.build_tab_buttons[tab_name].button_pressed != (tab_name == "structures"):
			print("  [FAIL] Only the 'structures' tab button should read pressed after switching to it")
			skirmish.queue_free()
			return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Switching build-bar tabs shows exactly one tab's ScrollContainer and updates the tab buttons' pressed state to match.")
	return true

func test_d2_unit_buttons_grey_out_without_a_live_manufactory_of_that_tier() -> bool:
	print("Running Test Suite: D2 - Unit Buttons Grey Out Without A Live Manufactory Of That Tier (RTS_CORE_ROADMAP.md D2)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame # let _physics_process()'s _refresh_tier_gated_buttons() run at least once

	var light_entries = []
	for entry in skirmish._tier_gated_buttons:
		if entry.tier == "light":
			light_entries.append(entry)
	if light_entries.is_empty():
		print("  [SKIP] No light-tier unit button in the bundled roster to test against.")
		skirmish.queue_free()
		return true
	for entry in light_entries:
		if entry.button.disabled:
			print("  [FAIL] A light-tier unit button should NOT be disabled while a light manufactory is alive")
			skirmish.queue_free()
			return false

	var light_manufactory = skirmish.get_team_factory(skirmish.PLAYER_TEAM, "light")
	light_manufactory.is_dead = true
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame

	for entry in light_entries:
		if not entry.button.disabled:
			print("  [FAIL] A light-tier unit button should be disabled once its manufactory dies")
			skirmish.queue_free()
			return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Unit buttons grey out the instant their tier's manufactory dies, not just after a doomed click.")
	return true

func test_d2_queue_strip_right_click_pauses_then_cancels() -> bool:
	print("Running Test Suite: D2 - Queue Strip Right-Click Pauses, Second Right-Click Cancels (RTS_CORE_ROADMAP.md D2)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	skirmish.debug_infinite_resources = false
	skirmish.economy[skirmish.PLAYER_TEAM].metal = 1000
	skirmish.economy[skirmish.PLAYER_TEAM].crystal = 1000
	var result = skirmish.production.enqueue(skirmish.PLAYER_TEAM, _d1_test_blueprint(), skirmish.player_faction, 300, 0)
	if not result.queued:
		print("  [FAIL] Test setup: queuing should have succeeded, got error: ", result.error)
		skirmish.queue_free()
		return false
	var tier = result.tier
	var q = skirmish.production.get_queue(skirmish.PLAYER_TEAM, tier)

	# Tick partway through first, so pausing/cancelling has some real
	# progress to interact with (drawn cost > 0) instead of the degenerate
	# "cancelled before a single tick ran" case D1's own tests already cover.
	for i in range(150):
		skirmish.production.tick(1.0 / 60.0)
	var bank_before_pause = skirmish.economy[skirmish.PLAYER_TEAM].metal
	if bank_before_pause >= 1000:
		print("  [FAIL] Test setup: expected some cost drawn before the first right-click, bank is still ", bank_before_pause)
		skirmish.queue_free()
		return false

	var right_click = InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true

	# First right-click: pauses (job stays in the queue).
	skirmish._on_queue_strip_input(tier, right_click)
	if not q[0].paused:
		print("  [FAIL] The first right-click on a queue strip should pause the front job")
		skirmish.queue_free()
		return false
	if q.size() != 1:
		print("  [FAIL] Pausing should not remove the job from the queue")
		skirmish.queue_free()
		return false

	var bank_before_cancel = skirmish.economy[skirmish.PLAYER_TEAM].metal

	# Second right-click (already paused): cancels and refunds.
	skirmish._on_queue_strip_input(tier, right_click)
	if not q.is_empty():
		print("  [FAIL] The second right-click on an already-paused queue strip should cancel the job")
		skirmish.queue_free()
		return false
	if skirmish.economy[skirmish.PLAYER_TEAM].metal <= bank_before_cancel:
		print("  [FAIL] Cancelling should have refunded the cost drawn before the pause back to the bank")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Right-clicking a queue strip pauses the front job; a second right-click while paused cancels and refunds it.")
	return true

func test_d3_second_manufactory_of_a_tier_gives_075x_build_time() -> bool:
	print("Running Test Suite: D3 - A Second Manufactory Of A Tier Gives 0.75x Build Time (RTS_CORE_ROADMAP.md D3)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	var heavy_factory = skirmish.get_team_factory(skirmish.PLAYER_TEAM, "heavy")
	if not heavy_factory:
		print("  [FAIL] No starting heavy manufactory found.")
		skirmish.queue_free()
		return false

	var base_time = skirmish.build_time_for_cost(Vector2i(300, 0))
	# _d1_test_blueprint() is medium-tier by default (medium_hull) - force
	# heavy tier for this test.
	var heavy_bp = _d1_test_blueprint()
	heavy_bp.hull_type = "heavy_hull"
	var result = skirmish.production.enqueue(skirmish.PLAYER_TEAM, heavy_bp, skirmish.player_faction, 300, 0)
	if not result.queued or result.tier != "heavy":
		print("  [FAIL] Test setup: expected a queued heavy-tier item, got ", result)
		skirmish.queue_free()
		return false
	var job_1 = skirmish.production.get_queue(skirmish.PLAYER_TEAM, "heavy")[0]
	if not is_equal_approx(job_1.total_time, base_time):
		print("  [FAIL] With only 1 heavy manufactory, build time should be the plain base time (", base_time, "), got ", job_1.total_time)
		skirmish.queue_free()
		return false
	skirmish.production.cancel(skirmish.PLAYER_TEAM, "heavy", 0)

	# Build a second heavy manufactory - now the tier has 2 live factories.
	var second_heavy = skirmish._spawn_prefab("heavy_manufactory", skirmish.PLAYER_TEAM, heavy_factory.global_position + Vector3(0, 0, 14), skirmish.player_faction)
	if skirmish.count_factories_of_tier(skirmish.PLAYER_TEAM, "heavy") != 2:
		print("  [FAIL] Test setup: expected exactly 2 live heavy manufactories, got ", skirmish.count_factories_of_tier(skirmish.PLAYER_TEAM, "heavy"))
		skirmish.queue_free()
		return false

	var result_2 = skirmish.production.enqueue(skirmish.PLAYER_TEAM, heavy_bp, skirmish.player_faction, 300, 0)
	if not result_2.queued:
		print("  [FAIL] Test setup: second enqueue should have succeeded, got ", result_2)
		skirmish.queue_free()
		return false
	var job_2 = skirmish.production.get_queue(skirmish.PLAYER_TEAM, "heavy")[0]
	if not is_equal_approx(job_2.total_time, base_time * 0.75):
		print("  [FAIL] With 2 live heavy manufactories, build time should be 0.75x the base (", base_time * 0.75, "), got ", job_2.total_time)
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] A second live manufactory of a tier gives new items on that tier a real 0.75x build time.")
	return true

func test_d3_destroying_a_manufactory_mid_job_leaves_the_timer_alone() -> bool:
	print("Running Test Suite: D3 - Destroying A Manufactory Mid-Job Leaves The In-Progress Timer Alone (RTS_CORE_ROADMAP.md D3)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	var heavy_factory = skirmish.get_team_factory(skirmish.PLAYER_TEAM, "heavy")
	var second_heavy = skirmish._spawn_prefab("heavy_manufactory", skirmish.PLAYER_TEAM, heavy_factory.global_position + Vector3(0, 0, 14), skirmish.player_faction)
	if skirmish.count_factories_of_tier(skirmish.PLAYER_TEAM, "heavy") != 2:
		print("  [FAIL] Test setup: expected exactly 2 live heavy manufactories, got ", skirmish.count_factories_of_tier(skirmish.PLAYER_TEAM, "heavy"))
		skirmish.queue_free()
		return false

	var heavy_bp = _d1_test_blueprint()
	heavy_bp.hull_type = "heavy_hull"
	var result = skirmish.production.enqueue(skirmish.PLAYER_TEAM, heavy_bp, skirmish.player_faction, 300, 0)
	if not result.queued:
		print("  [FAIL] Test setup: enqueue should have succeeded, got ", result)
		skirmish.queue_free()
		return false
	var job = skirmish.production.get_queue(skirmish.PLAYER_TEAM, "heavy")[0]
	var latched_total_time = job.total_time

	# Destroy the second manufactory mid-job - the ALREADY-QUEUED item's
	# timer must NOT change retroactively (D1/D3's own "total_time stays
	# latched" rule).
	second_heavy.is_dead = true
	skirmish.production.tick(1.0 / 60.0)
	if not is_equal_approx(job.total_time, latched_total_time):
		print("  [FAIL] Destroying a manufactory mid-job should NOT retroactively change an already-queued item's total_time - was ", latched_total_time, ", now ", job.total_time)
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Destroying a manufactory mid-job leaves the already-queued item's build-time multiplier untouched.")
	return true

func test_e1_power_state_derives_normal_low_and_critical_thresholds() -> bool:
	print("Running Test Suite: E1 - Power State Derives Normal/Low/Critical From Real Capacity Vs Upkeep (RTS_CORE_ROADMAP.md E1)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	skirmish._recalc_energy_economy()
	var pool = skirmish.energy_pool[skirmish.PLAYER_TEAM]
	if pool.power_state != "normal" or skirmish.is_low_power(skirmish.PLAYER_TEAM):
		print("  [FAIL] A fresh match's starting buildings (HQ + 3 starting manufactories) should breakeven at Normal power, got state '", pool.power_state, "' (capacity ", pool.capacity, " vs upkeep ", pool.upkeep, ")")
		skirmish.queue_free()
		return false

	# One extra static building tips capacity(16) below upkeep(18) but still
	# above upkeep/2(9) - OpenRA's Low band.
	var extras: Array = []
	extras.append(skirmish._spawn_prefab("light_manufactory", skirmish.PLAYER_TEAM, skirmish.player_hq.global_position + Vector3(30, 0, 0), skirmish.player_faction))
	await tree.process_frame
	skirmish._recalc_energy_economy()
	pool = skirmish.energy_pool[skirmish.PLAYER_TEAM]
	if pool.power_state != "low" or not skirmish.is_low_power(skirmish.PLAYER_TEAM):
		print("  [FAIL] Capacity below upkeep but above upkeep/2 should be Low power, got state '", pool.power_state, "' (capacity ", pool.capacity, " vs upkeep ", pool.upkeep, ")")
		for b in extras: b.queue_free()
		skirmish.queue_free()
		return false

	# Five more (six extra total) push upkeep(33) to at or above capacity's
	# double (16*2=32) - OpenRA's Critical band.
	for i in range(5):
		extras.append(skirmish._spawn_prefab("light_manufactory", skirmish.PLAYER_TEAM, skirmish.player_hq.global_position + Vector3(30, 0, 6.0 * (i + 1)), skirmish.player_faction))
	await tree.process_frame
	skirmish._recalc_energy_economy()
	pool = skirmish.energy_pool[skirmish.PLAYER_TEAM]
	if pool.power_state != "critical" or not skirmish.is_low_power(skirmish.PLAYER_TEAM):
		print("  [FAIL] Capacity at or below upkeep/2 should be Critical power, got state '", pool.power_state, "' (capacity ", pool.capacity, " vs upkeep ", pool.upkeep, ")")
		for b in extras: b.queue_free()
		skirmish.queue_free()
		return false

	for b in extras: b.queue_free()
	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Power state correctly derives Normal/Low/Critical from real capacity-vs-upkeep, matching OpenRA's own PowerManager thresholds.")
	return true

func test_e1_low_power_slows_production_live_per_tick_not_baked_in() -> bool:
	print("Running Test Suite: E1 - Low Power Slows An IN-PROGRESS Build Live, Every Tick (Not A One-Shot Multiplier Baked In At Queue Time) (RTS_CORE_ROADMAP.md E1)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	skirmish.debug_infinite_resources = false
	skirmish.economy[skirmish.PLAYER_TEAM].metal = 1000
	skirmish.economy[skirmish.PLAYER_TEAM].crystal = 1000

	skirmish._recalc_energy_economy()
	if skirmish.is_low_power(skirmish.PLAYER_TEAM):
		print("  [FAIL] Test setup: a fresh match should start at Normal power")
		skirmish.queue_free()
		return false

	var result = skirmish.production.enqueue(skirmish.PLAYER_TEAM, _d1_test_blueprint(), skirmish.player_faction, 300, 0)
	if not result.queued:
		print("  [FAIL] Test setup: queuing should have succeeded, got error: ", result.error)
		skirmish.queue_free()
		return false
	var tier = result.tier
	var job = skirmish.production.get_queue(skirmish.PLAYER_TEAM, tier)[0]
	var total_time = job.total_time

	# Baseline: 1 second of ticking at Normal power.
	for i in range(60):
		skirmish.production.tick(1.0 / 60.0)
	var normal_consumed = total_time - job.time_left
	if normal_consumed < 0.9 or normal_consumed > 1.05:
		print("  [FAIL] Test setup: 1 second of ticking at Normal power should consume ~1.0s of time_left, got ", normal_consumed)
		skirmish.queue_free()
		return false

	# Force the SAME team into Low power mid-build, purely by adding a real
	# extra static building - no test-only hook into production_queue.gd.
	var extra = skirmish._spawn_prefab("light_manufactory", skirmish.PLAYER_TEAM, skirmish.player_hq.global_position + Vector3(30, 0, 0), skirmish.player_faction)
	await tree.process_frame
	skirmish._recalc_energy_economy()
	if not skirmish.is_low_power(skirmish.PLAYER_TEAM):
		print("  [FAIL] Test setup: the extra static building should have tipped the team into Low power")
		extra.queue_free()
		skirmish.queue_free()
		return false

	var time_left_before_low = job.time_left
	for i in range(60):
		skirmish.production.tick(1.0 / 60.0)
	var low_consumed = time_left_before_low - job.time_left
	# RTS_CORE_ROADMAP.md E1: low_power_modifier=300 means 1/3 the normal rate.
	if abs(low_consumed - normal_consumed / 3.0) > 0.05:
		print("  [FAIL] The SAME in-progress job should now consume time_left at 1/3 the Normal rate while Low power, expected ~", normal_consumed / 3.0, ", got ", low_consumed)
		extra.queue_free()
		skirmish.queue_free()
		return false

	# Recover power mid-build (remove the extra building) - the key proof
	# this is a LIVE per-tick effect, not a total_time multiplier baked in
	# once at enqueue() (the old build_time *= 1.5 hack this chunk replaced).
	extra.queue_free()
	await tree.process_frame
	skirmish._recalc_energy_economy()
	if skirmish.is_low_power(skirmish.PLAYER_TEAM):
		print("  [FAIL] Test setup: removing the extra building should have restored Normal power")
		skirmish.queue_free()
		return false

	var time_left_before_recover = job.time_left
	for i in range(60):
		skirmish.production.tick(1.0 / 60.0)
	var recovered_consumed = time_left_before_recover - job.time_left
	if abs(recovered_consumed - normal_consumed) > 0.05:
		print("  [FAIL] The SAME job should speed back up to the full Normal rate the instant power recovers, expected ~", normal_consumed, ", got ", recovered_consumed)
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Production speed responds live to the team's power state changing mid-build (slows to 1/3 under Low power, speeds back up the instant power recovers) - not a one-shot multiplier baked in at queue time.")
	return true

func test_e1_low_power_disables_defense_weapon_and_dims_its_mesh() -> bool:
	print("Running Test Suite: E1 - Low Power Disables A Defense's Weapon And Dims Its Mesh (RTS_CORE_ROADMAP.md E1)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	# basic_cannon specifically (not heavy_machine_gun): its enclosed turret
	# gets full 360-degree traverse regardless of mount facet
	# (test_pintle_mounts_grant_full_traverse already proves this), so this
	# test's target placement isn't at the mercy of an unrelated narrow-arc
	# mount-style computation - the only thing under test here is the E1
	# power gate, same weapon module _d1_test_blueprint() already uses.
	var defense_bp = {
		"hull_type": "pillbox_foundation",
		"faction": "industrialists",
		"armor_material": "hardened_steel",
		"armor_thickness": 1.0,
		"locomotion": {"type_id": "", "settings": {}},
		"modules": [{"type_id": "basic_cannon", "position": {"x": 0, "y": 1.2, "z": 0}, "rotation": {"x": 0, "y": 0, "z": 0}, "scale": {"x": 1, "y": 1, "z": 1}, "tweaks": {}}]
	}
	var defense = skirmish.spawn_defense(defense_bp, skirmish.PLAYER_TEAM, skirmish.player_hq.global_position + Vector3(16, 0, 0))
	await tree.process_frame

	# The defense itself is a static building and owes its own +3 upkeep
	# (test_e1_power_state_derives... already proves that alone is enough to
	# tip a fresh match into Low) - a power_plant's real +20 capacity
	# compensates so this test can start from a genuine Normal baseline
	# before deliberately forcing Low below.
	var plant = skirmish._spawn_prefab("power_plant", skirmish.PLAYER_TEAM, skirmish.player_hq.global_position + Vector3(-16, 0, 0), skirmish.player_faction)
	await tree.process_frame

	var weapon = null
	for child in defense.defense_hull.get_children():
		if "target" in child:
			weapon = child
			break
	if weapon == null:
		print("  [FAIL] Test setup: the defense's heavy_machine_gun should have a real auto_weapon.gd child")
		defense.queue_free()
		skirmish.queue_free()
		return false

	var mesh = _e1_find_first_geometry_instance(defense)
	if mesh == null:
		print("  [FAIL] Test setup: the defense should have a real renderable mesh somewhere under it")
		defense.queue_free()
		skirmish.queue_free()
		return false

	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var target = CharacterBody3D.new()
	target.set_script(BattleUnitScript)
	root.add_child(target)
	target.team = 1
	target.set_meta("team", 1)
	target.add_to_group("damageable")
	target.global_position = defense.global_position + Vector3(5, 0, 0)
	await tree.process_frame
	# A real Skirmish scans _damageable_candidates() via a periodic spatial
	# grid (get_nearby_damageable()), not a live group scan - a manually
	# constructed target needs a forced rebuild rather than waiting out the
	# real grid_timer.
	skirmish._rebuild_damageable_grid()

	var free_all = func():
		defense.queue_free()
		target.queue_free()
		skirmish.queue_free()

	skirmish._recalc_energy_economy()
	if skirmish.is_low_power(skirmish.PLAYER_TEAM):
		print("  [FAIL] Test setup: the power_plant should have restored a genuine Normal baseline despite the defense's own upkeep")
		plant.queue_free()
		free_all.call()
		return false

	# _find_nearest_target() directly (delta=-1 sentinel) bypasses the
	# PERFORMANCE_PLAN.md P1a reacquire throttle - _ready() seeds
	# _reacquire_timer with a random [0, REACQUIRE_INTERVAL) value, so a
	# single _physics_process(delta) call here would flakily skip scanning
	# depending on that random seed (this isn't what's under test anyway;
	# the low-power GATE check below deliberately keeps _physics_process
	# since that's the real code path the gate itself lives in).
	weapon._find_nearest_target()
	if weapon.target == null:
		print("  [FAIL] Test setup: the weapon should acquire the hostile target under Normal power")
		plant.queue_free()
		free_all.call()
		return false
	if mesh.transparency > 0.01:
		print("  [FAIL] A defense's mesh should not be dimmed under Normal power, got transparency ", mesh.transparency)
		plant.queue_free()
		free_all.call()
		return false

	# Force Low power the same way test_e1_power_state_derives... proved a
	# bare defense alone does it - remove the compensating power_plant so the
	# defense's own upkeep is unmasked again.
	plant.queue_free()
	await tree.process_frame
	skirmish._recalc_energy_economy()
	if not skirmish.is_low_power(skirmish.PLAYER_TEAM):
		print("  [FAIL] Test setup: removing the power_plant should have tipped the team into Low power")
		free_all.call()
		return false

	weapon.target = null
	weapon._physics_process(1.0 / 60.0)
	if weapon.target != null:
		print("  [FAIL] A defense's weapon should be fully inert (no targeting) while its team is Low power")
		free_all.call()
		return false
	if mesh.transparency < 0.01:
		print("  [FAIL] A defense's mesh should visibly dim while its team is Low power, got transparency ", mesh.transparency)
		free_all.call()
		return false

	# Recover power - the SAME defense should un-dim and its weapon should
	# work again immediately.
	var plant2 = skirmish._spawn_prefab("power_plant", skirmish.PLAYER_TEAM, skirmish.player_hq.global_position + Vector3(-16, 0, 0), skirmish.player_faction)
	await tree.process_frame
	skirmish._recalc_energy_economy()
	if skirmish.is_low_power(skirmish.PLAYER_TEAM):
		print("  [FAIL] Test setup: rebuilding the power_plant should have restored Normal power")
		plant2.queue_free()
		free_all.call()
		return false

	weapon._find_nearest_target()
	if weapon.target == null:
		print("  [FAIL] Once power recovers, the SAME weapon should be able to acquire a target normally again")
		plant2.queue_free()
		free_all.call()
		return false
	if mesh.transparency > 0.01:
		print("  [FAIL] Once power recovers, the SAME defense's mesh should un-dim, got transparency ", mesh.transparency)
		plant2.queue_free()
		free_all.call()
		return false

	plant2.queue_free()
	free_all.call()
	await tree.process_frame
	print("  [PASS] A defense's weapon is fully inert and its mesh visibly dims while its team is Low/Critical power, and both recover the instant power is restored - real per-tick gating, not just a flag.")
	return true

func test_c1_buildings_block_movement_unit_detours_around_manufactory() -> bool:
	print("Running Test Suite: C1 - Buildings Block Movement, a Unit Detours Around a Real Manufactory (RTS_CORE_ROADMAP.md C1)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	# Place a real heavy_manufactory dead center in what will be the
	# unit's straight-line path - well clear of lake_crossing's lake/spawns/
	# resources (all near z ~= 0/+-90/+-102), so nothing else can be
	# blocking this route.
	var block_pos = Vector3(0, 0, -180)
	var building = skirmish._spawn_prefab("heavy_manufactory", skirmish.ENEMY_TEAM, block_pos, skirmish.enemy_faction)
	var half_x = building.footprint.x / 2.0
	var half_z = building.footprint.z / 2.0

	# _spawn_prefab() only FLAGS the rebake (RTS_CORE_ROADMAP.md C1's
	# one-frame debounce, see skirmish.gd's _physics_process) - awaiting a
	# few real frames here lets that debounced rebake actually run before
	# the unit's own nav_agent is set up, so it picks up the hole from the
	# start rather than needing a mid-flight repath to notice it.
	for i in range(5):
		await tree.process_frame
	if skirmish._nav_rebake_pending:
		print("  [FAIL] The navmesh rebake should have completed within a few frames of placing the building")
		skirmish.queue_free()
		return false

	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var bp = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "tracked_treads", "settings": {"width": 1.0}},
		"modules": [
			{"type_id": "tracked_treads", "name": "Tracked Treads", "position": {"x": 0.0, "y": -0.4, "z": 0.0}, "rotation": {"x": 0.0, "y": 0.0, "z": 0.0}, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "yaw_offset": 0.0, "tweaks": {}}
		]
	}
	var unit = CharacterBody3D.new()
	unit.set_script(BattleUnitScript)
	skirmish.add_child(unit)
	unit.global_position = Vector3(-40, 0.5, -180)
	unit.setup(bp, skirmish.PLAYER_TEAM, skirmish.bp_manager)
	if unit.move_speed <= 0.0:
		print("  [FAIL] Unit with a real locomotion module should have nonzero move_speed, got ", unit.move_speed)
		skirmish.queue_free()
		return false

	var start_pos = unit.global_position
	unit.order_move(Vector3(40, 0.5, -180))

	# medium_hull/tracked_treads' real move_speed is only ~7.2 u/s - budget
	# enough ticks for the full (slightly-detoured) 80-unit trip, not just
	# "moved at all" (this test cares whether it actually gets PAST the
	# building, not merely that it's not stuck against it). Generous
	# headroom over the ~600-650 ticks a clean run actually takes -
	# Recast's bake isn't perfectly deterministic tick-for-tick, and this
	# is a real detour around a real physical collider, not just a navmesh
	# path query, so some run-to-run variance in exact arrival time is
	# expected, not a bug.
	# DRIVEN ON REAL PHYSICS FRAMES, not by calling _physics_process() in a
	# tight loop.
	#
	# Both C1 movement tests used to advance the unit by calling
	# unit._physics_process(1/60) + move_and_slide() N times WITHOUT awaiting
	# anything, which made them the two flakiest tests in the suite - a
	# different one of the pair failed on each full run for no reason.
	#
	# The cause is that NavigationServer3D syncs its maps on real physics
	# steps. Inside a no-await loop the agent can never RECEIVE an updated
	# path, so every iteration steers on whichever corridor happened to be
	# cached when the loop started - and whether that corridor already knew
	# about the building was pure timing luck.
	#
	# Measured with scratch/probe_c1_repath_flake.gd, same scenario 6x each:
	#   manual ticks : 3/6 passed, final x = -23.5, 12.7, 8.2, 38.1, -9.8, 11.8
	#   real frames  : 6/6 passed, final x = 38.0, 38.1, 38.1, 38.1, 38.1, 38.1
	#
	# So the GAME was never flaky here - units route around a building
	# reliably, arriving within 0.1 units of the same spot every time. Only
	# the harness was. Awaiting physics_frame also means the unit's own
	# _physics_process runs the way it does in a match, rather than being
	# hand-cranked out of step with the servers it depends on.
	var entered_footprint = false
	for i in range(1200):
		await tree.physics_frame
		if abs(unit.global_position.x - block_pos.x) < half_x and abs(unit.global_position.z - block_pos.z) < half_z:
			entered_footprint = true

	if entered_footprint:
		print("  [FAIL] Unit's real movement path entered the manufactory's own footprint AABB instead of detouring around it")
		skirmish.queue_free()
		return false

	var moved_dist = start_pos.distance_to(unit.global_position)
	if moved_dist < 5.0:
		print("  [FAIL] Unit given order_move() straight at a building barely moved (", moved_dist, " units) - it may be stuck against the building instead of detouring")
		skirmish.queue_free()
		return false
	if unit.global_position.x < 15.0:
		print("  [FAIL] Unit should have made it past the building to the far side (x >= 15) within 700 ticks, got x=", unit.global_position.x)
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] A unit ordered straight at a real building detours around its navmesh hole (never entering its footprint AABB) and reaches the far side.")
	return true

func test_weapon_range_tiers_are_anchored_to_vision() -> bool:
	print("Running Test Suite: Weapon Range Tiers Are Anchored To Vision...")
	var WeaponRange = preload("res://scripts/weapon_range.gd")

	# The defect this suite exists for (Chris, 2026-08-03: "even the high range
	# weapons are engaging at about the same distance as everything else"): the
	# old band was 7-50, but 26 of 45 weapons out-ranged a standard hull's
	# 14-28 vision, and a weapon cannot target what fog hides. So every point
	# of reach past ~20 was unusable and the whole roster fought at one
	# distance. Range only means something relative to vision, so that is what
	# these assertions are written against.
	var nominal: float = ModuleCatalog.NOMINAL_VISION
	if absf(nominal - ModuleCatalog.get_base_vision("medium_hull")) > 0.01:
		print("  [FAIL] NOMINAL_VISION ", nominal, " should equal a plain medium_hull's real vision ", ModuleCatalog.get_base_vision("medium_hull"), " - the tiers are expressed against it, so a drift makes every tier boundary a lie.")
		return false

	# 1. Every weapon has an authored base range, and no weapon is left on the
	# catalog's fallback by accident.
	var weapons: Array = []
	for type_id in ModuleCatalog.get_catalog():
		if ModuleCatalog.get_module_data(type_id).get("category", "") == "weapon":
			weapons.append(type_id)
	if weapons.size() < 40:
		print("  [FAIL] expected the full weapon roster, found only ", weapons.size())
		return false
	for type_id in weapons:
		if not ModuleCatalog.WEAPON_FIRE_PROFILES.has(type_id):
			print("  [FAIL] ", type_id, " has no fire profile, so its range is the shared DEFAULT_FIRE_PROFILE fallback rather than an authored number.")
			return false
		if ModuleCatalog.get_base_range(type_id) <= 0.0:
			print("  [FAIL] ", type_id, " has a non-positive base range.")
			return false

	# 2. The band has to be wide enough that the tiers are distinguishable in
	# play, not just different in the table.
	var shortest: float = INF
	var longest: float = 0.0
	for type_id in weapons:
		var r: float = ModuleCatalog.get_base_range(type_id)
		shortest = minf(shortest, r)
		longest = maxf(longest, r)
	if longest / shortest < 10.0:
		print("  [FAIL] range band ", shortest, "-", longest, " is only a ", longest / shortest, "x spread; the old 7.1x band is what played as a single distance.")
		return false

	# 3. The point of the exercise: the longest-ranged weapons must reach well
	# past what a unit can see for itself, so a spotter has something to do.
	# Chris: "The longest ranged ones should absolutely be range-able out
	# beyond the units vision."
	var beyond_vision: Array = []
	var spotter_only: Array = []
	for type_id in weapons:
		var r: float = ModuleCatalog.get_base_range(type_id)
		if r > nominal:
			beyond_vision.append(type_id)
		if r > nominal * 2.0:
			spotter_only.append(type_id)
	if beyond_vision.size() < 8:
		print("  [FAIL] only ", beyond_vision.size(), " weapons out-reach nominal vision ", nominal, "; there is no overwatch tier to speak of.")
		return false
	if spotter_only.is_empty():
		print("  [FAIL] no weapon reaches past 2x vision, so nothing in the roster genuinely depends on a spotter - which is the mechanic being built.")
		return false
	if not ("artillery" in spotter_only):
		print("  [FAIL] artillery is the weapon Chris named for spotter use and it is not in the spotter-only set: reach ", ModuleCatalog.get_base_range("artillery"), " vs 2x vision ", nominal * 2.0)
		return false

	# 4. Short-ranged weapons must stay genuinely short - well inside vision -
	# or "point blank" is just a slightly smaller version of everything else.
	for close_id in ["flamethrower", "arc_projector", "aps_interceptor"]:
		var r: float = ModuleCatalog.get_base_range(close_id)
		if r > nominal * 0.4:
			print("  [FAIL] ", close_id, " reaches ", r, ", more than 0.4x vision ", nominal, " - it is supposed to be a weapon you have to close with.")
			return false

	# 5. Tier classification has to be monotonic in reach, since the Design Lab
	# label and the spotter warning both key off it.
	var ordered: Array = weapons.duplicate()
	ordered.sort_custom(func(a, b): return ModuleCatalog.get_base_range(a) < ModuleCatalog.get_base_range(b))
	var tier_order := ["point_blank", "close", "direct", "overwatch", "operational"]
	var last_idx := -1
	for type_id in ordered:
		var idx: int = tier_order.find(ModuleCatalog.get_range_tier(ModuleCatalog.get_base_range(type_id)))
		if idx < 0:
			print("  [FAIL] ", type_id, " classified into an unknown tier.")
			return false
		if idx < last_idx:
			print("  [FAIL] tier classification is not monotonic in reach: ", type_id, " at ", ModuleCatalog.get_base_range(type_id), " went backwards to tier ", tier_order[idx])
			return false
		last_idx = idx

	# 6. Barrel length is the headline modifier and must move reach, in the
	# direction Chris specified: "longer barrel = greater velocity and range".
	var cannon_stock: float = WeaponRange.compute("basic_cannon", {})
	var cannon_long: float = WeaponRange.compute("basic_cannon", {"barrel_length": 2.0})
	var cannon_short: float = WeaponRange.compute("basic_cannon", {"barrel_length": 0.5})
	if cannon_long <= cannon_stock or cannon_short >= cannon_stock:
		print("  [FAIL] barrel_length should raise and lower reach. short=", cannon_short, " stock=", cannon_stock, " long=", cannon_long)
		return false
	if absf(cannon_long - cannon_stock * 2.0) > 0.01:
		print("  [FAIL] a 2x barrel should double reach. expected=", cannon_stock * 2.0, " actual=", cannon_long)
		return false

	# 7. Stacked tweaks must not produce a weapon that covers an entire map -
	# every shipped map has map_half_extents of 550 or less.
	var absurd: float = WeaponRange.compute("artillery", {
		"barrel_length": 4.0, "elevation": 4.0, "caliber": 4.0})
	if absurd > WeaponRange.FIRE_RANGE_MAX + 0.01:
		print("  [FAIL] stacked range tweaks broke the FIRE_RANGE_MAX rail: ", absurd)
		return false

	print("  [PASS] Every weapon has an authored base range; the band is a %.0fx spread anchored to vision (%d weapons out-reach it, %d cannot self-acquire at all); tiers classify monotonically; barrel length scales reach proportionally; stacked tweaks stay under the map-width rail." % [longest / shortest, beyond_vision.size(), spotter_only.size(), ])
	return true

# Chris's ask: exceeding capacity should "light up a warning notification",
# the design must still be saveable and fieldable, and the player must be able
# to see "what they are trading". So the warning has to appear, has to name the
# cost in speed, and must not gate the save/test buttons.
func test_design_lab_overweight_warning_names_the_trade() -> bool:
	print("Running Test Suite: Design Lab Overweight Warning...")
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	for _i in range(8):
		await tree.process_frame

	var stats = scene.get_node_or_null("UI_StatBlock")
	var hull = scene.get_node_or_null("Hull")
	if stats == null or hull == null:
		print("  [FAIL] MainLab did not provide UI_StatBlock/Hull (stats=", stats, " hull=", hull, ")")
		scene.queue_free()
		return false

	var fail = func(msg: String) -> bool:
		print("  [FAIL] " + msg)
		scene.queue_free()
		return false

	# No locomotion yet: the load rows must stay hidden rather than showing a
	# full red bar on a hull the player has only just spawned.
	stats.update_stats(hull)
	if stats._load_bar != null and stats._load_bar.visible:
		return fail.call("A hull with no locomotion should not show a load bar at all.")
	if stats._overweight_panel != null and stats._overweight_panel.visible:
		return fail.call("A hull with no locomotion should not show the overweight warning.")

	scene.update_locomotion("wheels", {"wheel_size": 1.0, "num_axles": 4, "wheels_per_axle": 1})
	for _i in range(4):
		await tree.process_frame
	stats.update_stats(hull)

	if not stats._load_bar.visible:
		return fail.call("With locomotion placed, the load bar should be visible.")
	if stats._overweight_panel.visible:
		return fail.call("A wheeled hull carrying nothing should not be overweight.")
	var clean_speed_text: String = stats._speed_label.text

	# Pile on enough mass to go over capacity.
	for _i in range(12):
		var child = Node3D.new()
		var d = ModuleData.new()
		d.type_id = "artillery"
		d.category = "weapon"
		d.base_weight = 250.0
		child.set_meta("module_data", d)
		hull.add_child(child)
	stats.update_stats(hull)

	if not stats._overweight_panel.visible:
		return fail.call("A grossly overweight design must light up the overweight warning.")
	if not stats._overweight_title.text.contains("OVERWEIGHT"):
		return fail.call("The warning title should say OVERWEIGHT, got: " + stats._overweight_title.text)
	# "What they are trading": the detail line has to carry the speed cost,
	# not just the fact of being over.
	var detail: String = stats._overweight_detail.text
	if not detail.to_lower().contains("top speed"):
		return fail.call("The warning must name the speed cost, not just the overweight state. Got: " + detail)
	if not detail.contains("kg over"):
		return fail.call("The warning must say how far over capacity the design is. Got: " + detail)
	# The speed row itself has to show both figures so the trade is legible.
	if not stats._speed_label.text.contains("was"):
		return fail.call("While overloaded the speed row should show the penalised speed AND what it would otherwise be, got: " + stats._speed_label.text)
	if stats._speed_label.text == clean_speed_text:
		return fail.call("The speed readout did not change when the design went overweight.")

	# Explicitly allowed to be built and fielded, per the ask - the warning
	# informs, it does not gate.
	if stats.save_button != null and stats.save_button.disabled:
		return fail.call("An overweight design must still be saveable - the warning informs, it does not block.")
	if stats.test_button != null and stats.test_button.disabled:
		return fail.call("An overweight design must still be testable - the warning informs, it does not block.")

	scene.queue_free()
	print("  [PASS] The Design Lab hides load rows until locomotion exists, lights an OVERWEIGHT warning naming both the excess mass and the top-speed cost, shows the penalised and unpenalised speeds side by side, and still allows the design to be saved and tested.")
	return true
func test_hull_economy_and_scale_bounds() -> bool:
	print("Running Test Suite: FABLE review fixes - armor/hull economy (cost, weight, scale) and material rock-paper-scissors...")

	# --- Armor material/thickness now has a real price ---
	var c_baseline = ModuleCatalog.compute_hull_cost("medium_hull", 1.0, "hardened_steel", Vector3.ONE)
	var c_fortress = ModuleCatalog.compute_hull_cost("medium_hull", 3.0, "energy_shielding", Vector3.ONE)
	if c_fortress.x < int(c_baseline.x * 1.8) or c_fortress.y < c_baseline.y * 3:
		print("  [FAIL] A thickness-3.0 energy_shielding hull should cost far more than the baseline (got ", c_fortress, " vs ", c_baseline, ") - armor is still free power.")
		return false

	# Superlinear thickness curve: 1.0 -> 2.0 costs less than 2.0 -> 3.0
	var c1 = ModuleCatalog.compute_hull_cost("medium_hull", 1.0, "hardened_steel", Vector3.ONE)
	var c2 = ModuleCatalog.compute_hull_cost("medium_hull", 2.0, "hardened_steel", Vector3.ONE)
	var c3 = ModuleCatalog.compute_hull_cost("medium_hull", 3.0, "hardened_steel", Vector3.ONE)
	if (c3.x - c2.x) <= (c2.x - c1.x):
		print("  [FAIL] Thickness cost curve should be superlinear (step 2->3 pricier than 1->2), got ", c1.x, "/", c2.x, "/", c3.x)
		return false

	# --- Material rock-paper-scissors: energy_shielding no longer best-in-
	# every-class (kinetic is now its weakness; steel keeps the kinetic crown)
	var shield_k = DamageResolverScript.get_material_threshold("energy_shielding", "kinetic", 1.0).x
	var steel_k = DamageResolverScript.get_material_threshold("hardened_steel", "kinetic", 1.0).x
	if shield_k >= steel_k:
		print("  [FAIL] energy_shielding's kinetic threshold (", shield_k, ") should now be WEAKER than hardened_steel's (", steel_k, ").")
		return false

	# --- Hull scale drives real stats, and blueprint cost includes all of it ---
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	var small_bp = {
		"hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel",
		"armor_thickness": 1.0,
		"faction": "ledger_combine",
		"locomotion": {"type_id": "wheels", "settings": {"size": 1.0, "count": 4}},
		"modules": [{"type_id": "wheels", "position": {"x": 0, "y": -0.5, "z": 0}, "rotation": {"x": 0, "y": 0, "z": 0}, "scale": {"x": 1, "y": 1, "z": 1}, "tweaks": {}}]
	}
	var big_bp = small_bp.duplicate(true)
	big_bp["hull_scale"] = {"x": 2.0, "y": 1.0, "z": 2.0}

	var small_cost = skirmish.blueprint_cost(small_bp)
	var big_cost = skirmish.blueprint_cost(big_bp)
	if big_cost.x <= small_cost.x:
		print("  [FAIL] A 2x-footprint hull should cost more than the 1x baseline (got ", big_cost.x, " vs ", small_cost.x, ") - hull scale is still free real estate.")
		skirmish.queue_free()
		return false

	var small_unit = skirmish.spawn_unit(small_bp, 0, Vector3(0, 0, 0))
	var big_unit = skirmish.spawn_unit(big_bp, 0, Vector3(15, 0, 0))
	await tree.process_frame
	if big_unit.max_hp <= small_unit.max_hp:
		print("  [FAIL] A 2x-footprint hull should have more HP (got ", big_unit.max_hp, " vs ", small_unit.max_hp, ").")
		skirmish.queue_free()
		return false
	if big_unit.move_speed >= small_unit.move_speed:
		print("  [FAIL] A 2x-footprint hull on identical locomotion should be slower (got ", big_unit.move_speed, " vs ", small_unit.move_speed, ") - size still costs nothing.")
		skirmish.queue_free()
		return false

	# --- Gizmo hull-scale clamp (bounded scaling, concept-doc requirement) ---
	var gizmo = preload("res://scenes/Gizmo3D.tscn").instantiate()
	var clamp_hull = Node3D.new()
	clamp_hull.name = "Hull"
	clamp_hull.set_meta("base_hull_size", Vector3(4, 1, 6))
	clamp_hull.set_meta("hull_scale", Vector3.ONE)
	skirmish.add_child(clamp_hull)
	clamp_hull.add_child(gizmo)
	await tree.process_frame
	gizmo._apply_scale_to_node(clamp_hull, Vector3(9.0, 0.01, 9.0))
	var clamped = clamp_hull.get_meta("hull_scale")
	if clamped.x > ModuleCatalog.HULL_SCALE_MAX + 0.001 or clamped.y < ModuleCatalog.HULL_SCALE_MIN - 0.001:
		print("  [FAIL] Hull scale should clamp to [", ModuleCatalog.HULL_SCALE_MIN, ", ", ModuleCatalog.HULL_SCALE_MAX, "], got ", clamped)
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Armor material/thickness and hull scale all carry real cost/weight/HP consequences, the thickness cost curve is superlinear, materials form a genuine rock-paper-scissors, and hull scaling is bounded.")
	return true

func test_base_power_is_separate_from_vehicle_energy_budget() -> bool:
	print("Running Test Suite: Base Power Is Separate From A Vehicle's Own Energy Budget (FABLE_REVIEW 1.6)...")
	# Chris's explicit resolution: team/base power (energy_pool, feeds only
	# the production build-time penalty) comes from base infrastructure -
	# HQ baseline, power_plant, and generators mounted on static defense
	# buildings - NEVER from a generator module mounted on a mobile combat
	# unit. A vehicle that wants more of ITS OWN energy (for its own
	# energy-cost weapons) has to mount its own generator; that's a
	# completely separate resource (battle_unit.gd's max_energy) that never
	# feeds the team pool. This was previously backwards (a mobile unit's
	# generator DID raise team capacity) - exactly the review's "put a
	# fusion_generator on a tank so the base builds faster" complaint.
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame
	skirmish._recalc_energy_economy()
	var capacity_before = skirmish.energy_pool[skirmish.PLAYER_TEAM].capacity

	var bp_with_gen = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "tracked_treads", "settings": {"width": 1.0}},
		"modules": [
			{"type_id": "fusion_generator", "name": "Fusion Generator", "position": {"x": 0.0, "y": 0.5, "z": 0.0}, "rotation": {"x": 0.0, "y": 0.0, "z": 0.0}, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "yaw_offset": 0.0, "tweaks": {}}
		]
	}
	var unit = skirmish.spawn_unit(bp_with_gen, skirmish.PLAYER_TEAM, skirmish.player_hq.global_position + Vector3(20, 0, 0))
	await tree.process_frame
	skirmish._recalc_energy_economy()
	var capacity_after_unit_generator = skirmish.energy_pool[skirmish.PLAYER_TEAM].capacity

	if abs(capacity_after_unit_generator - capacity_before) > 0.01:
		print("  [FAIL] A generator module mounted on a mobile unit should NOT raise the team's base power capacity, went from ", capacity_before, " to ", capacity_after_unit_generator)
		unit.queue_free()
		skirmish.queue_free()
		return false
	if unit.max_energy <= 0.0:
		print("  [FAIL] Test assumption broken: the unit's OWN energy budget should still be real and nonzero (fusion_generator should have raised it), got ", unit.max_energy)
		unit.queue_free()
		skirmish.queue_free()
		return false

	# A power_plant BUILDING, by contrast, should raise team capacity - the
	# base/vehicle distinction is about WHERE the generator sits, not
	# whether generators matter at all.
	var plant = skirmish._spawn_prefab("power_plant", skirmish.PLAYER_TEAM, skirmish.player_hq.global_position + Vector3(-20, 0, 0), skirmish.player_faction)
	await tree.process_frame
	skirmish._recalc_energy_economy()
	var capacity_after_plant = skirmish.energy_pool[skirmish.PLAYER_TEAM].capacity
	if capacity_after_plant <= capacity_after_unit_generator:
		print("  [FAIL] A power_plant BUILDING should raise team base power capacity, went from ", capacity_after_unit_generator, " to ", capacity_after_plant)
		unit.queue_free()
		plant.queue_free()
		skirmish.queue_free()
		return false

	# HUD label should read as base power, not a bare/ambiguous "Energy".
	# RTS_CORE_ROADMAP.md E1: moved from resource_label into its own real
	# power bar's status label.
	skirmish._update_resource_ui()
	if not "Base Power" in skirmish.power_status_label.text:
		print("  [FAIL] The HUD readout should clearly label this as base/team power, got '", skirmish.power_status_label.text, "'")
		unit.queue_free()
		plant.queue_free()
		skirmish.queue_free()
		return false

	unit.queue_free()
	plant.queue_free()
	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] A mobile unit's own generator only powers that unit (never the team pool); only base infrastructure (HQ/power_plant/defense generators) feeds team base power; the HUD label reads as base power, not a universal resource.")
	return true

func test_every_weight_tweak_also_costs_real_resources() -> bool:
	print("Running Test Suite: Systemic Tweak-Cost Audit - Every Weight/Range/DPS Tweak Also Costs Real Resources (FABLE_REVIEW 1.5)...")
	# Before this fix, get_cost()'s whitelist covered only 5 of the ~22
	# tweaks that already cost real weight (and, via the weight-driven
	# traverse formula, real traverse speed too) - so most of the roster's
	# "max every slider" sliders were free power in resource terms. Spot-
	# checks a representative sample that was previously uncosted, across
	# several different module categories (weapon/support), confirming
	# cost now moves in the same direction weight already does.
	var samples = [
		{"type_id": "pd_laser", "tweak": "cooling_jacket", "max": 2.0},
		{"type_id": "flamethrower", "tweak": "pressure_valve", "max": 2.0},
		{"type_id": "resource_harvester", "tweak": "extractor_size", "max": 2.0},
		{"type_id": "sensor_suite", "tweak": "mast_height", "max": 2.0},
		{"type_id": "drone_carrier", "tweak": "hangar_size", "max": 5.0},
		{"type_id": "gauss_railgun", "tweak": "rod_thickness", "max": 2.0}, # was on the weight list but not cost
	]
	for s in samples:
		var catalog_data = ModuleCatalog.get_module_data(s.type_id)
		var baseline = ModuleData.new()
		baseline.type_id = s.type_id
		baseline.cost_metal = catalog_data.metal
		baseline.cost_crystal = catalog_data.crystal
		baseline.base_weight = catalog_data.weight
		var tweaked = ModuleData.new()
		tweaked.type_id = s.type_id
		tweaked.cost_metal = catalog_data.metal
		tweaked.cost_crystal = catalog_data.crystal
		tweaked.base_weight = catalog_data.weight
		tweaked.tweaks = {s.tweak: s.max}

		var base_cost = baseline.get_cost()
		var tweaked_cost = tweaked.get_cost()
		var base_weight = baseline.get_weight()
		var tweaked_weight = tweaked.get_weight()

		if tweaked_weight <= base_weight:
			print("  [FAIL] Test assumption broken: '", s.tweak, "' on ", s.type_id, " should already raise weight at its max value, got ", base_weight, " -> ", tweaked_weight)
			return false
		if tweaked_cost.x <= base_cost.x and tweaked_cost.y <= base_cost.y:
			print("  [FAIL] '", s.tweak, "' on ", s.type_id, " raises weight (", base_weight, " -> ", tweaked_weight, ") but its max value doesn't raise cost at all (", base_cost, " -> ", tweaked_cost, ")")
			return false

	# barrel_count/tube_count previously only scaled metal, not crystal -
	# confirm both now move together (consistent with grid_size/
	# welder_count, which already scaled both).
	var rotary_catalog = ModuleCatalog.get_module_data("rotary_cannon")
	if rotary_catalog.crystal > 0:
		var rotary_base = ModuleData.new()
		rotary_base.cost_metal = rotary_catalog.metal
		rotary_base.cost_crystal = rotary_catalog.crystal
		var rotary_tweaked = ModuleData.new()
		rotary_tweaked.cost_metal = rotary_catalog.metal
		rotary_tweaked.cost_crystal = rotary_catalog.crystal
		rotary_tweaked.tweaks = {"barrel_count": 8.0}
		if rotary_tweaked.get_cost().y <= rotary_base.get_cost().y:
			print("  [FAIL] barrel_count should now scale crystal cost too, not just metal")
			return false

	print("  [PASS] Every tweak that already costs real weight (and thus real traverse) now also costs real metal/crystal - the cost model no longer whitelists only 5 of ~22 such tweaks.")
	return true

func test_production_is_one_shared_authority_for_player_and_ai() -> bool:
	print("Running Test Suite: Production - One Shared Authority For Player And AI (RTS_CORE_ROADMAP.md A1)...")

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

	# A player-side entry that resolves to the "medium" tier AND actually
	# passes build legality (not every bundled roster entry does - e.g. a
	# harvester-only design has no weapon/support module and is legally
	# unbuildable), so we know exactly which shared queue to check and that
	# enqueue() won't reject it for an unrelated reason. Cheapest legal match,
	# not just the first - build_time is cost-derived (skirmish.gd's
	# build_time_for_cost(), clamped 3-40s) and the wait loop below needs the
	# spawn to land within its tick budget.
	var player_entry = null
	for e in skirmish.roster:
		if e.is_defense: continue
		if ModuleCatalog.get_hull_size_tier(e.blueprint.get("hull_type", "medium_hull")) != "medium": continue
		if not ModuleCatalog.validate_build_legality(e.blueprint).valid: continue
		if player_entry == null or (e.cost_metal + e.cost_crystal) < (player_entry.cost_metal + player_entry.cost_crystal):
			player_entry = e
	if not player_entry:
		print("  [SKIP] No legally-buildable medium-tier entry in the bundled player roster to test against.")
		skirmish.queue_free()
		return true

	skirmish.economy[skirmish.PLAYER_TEAM].metal = 100000
	skirmish.economy[skirmish.PLAYER_TEAM].crystal = 100000
	skirmish.economy[skirmish.ENEMY_TEAM].metal = 100000
	skirmish.economy[skirmish.ENEMY_TEAM].crystal = 100000
	skirmish.debug_instant_build = true

	var player_units_before = skirmish.get_team_units(skirmish.PLAYER_TEAM).size()
	var enemy_units_before = skirmish.get_team_units(skirmish.ENEMY_TEAM).size()

	# Player path: skirmish.gd's build-bar handler.
	skirmish._queue_player_unit(player_entry)
	if skirmish.production.queue_depth(skirmish.PLAYER_TEAM, "medium") != 1:
		print("  [FAIL] _queue_player_unit() should append to skirmish.production's shared medium-tier queue.")
		skirmish.queue_free()
		return false

	# AI path: enemy_ai.gd's own producer, going through the exact same
	# ProductionQueue object - not a second, similar-looking implementation.
	ai._try_produce()
	var enemy_queued = skirmish.production.queue_depth(skirmish.ENEMY_TEAM, "light") > 0 \
		or skirmish.production.queue_depth(skirmish.ENEMY_TEAM, "medium") > 0 \
		or skirmish.production.queue_depth(skirmish.ENEMY_TEAM, "heavy") > 0
	if not enemy_queued:
		print("  [FAIL] enemy_ai.gd's _try_produce() did not queue anything through skirmish.production.")
		skirmish.queue_free()
		return false
	# Both real units, produced through the one shared authority.
	# Budget generously above build_time_for_cost()'s 40s clamp at ~60
	# physics ticks/sec, not just the cheapest observed cost - a headless run
	# is not guaranteed to hold exactly 60fps.
	var ticks = 0
	var player_produced = false
	var enemy_produced = false
	while ticks < 3000 and not (player_produced and enemy_produced):
		await tree.process_frame
		ticks += 1
		if not player_produced and skirmish.get_team_units(skirmish.PLAYER_TEAM).size() > player_units_before:
			player_produced = true
		if not enemy_produced and skirmish.get_team_units(skirmish.ENEMY_TEAM).size() > enemy_units_before:
			enemy_produced = true

	skirmish.queue_free()
	await tree.process_frame

	if not player_produced:
		print("  [FAIL] Player-queued unit never spawned.")
		return false
	if not enemy_produced:
		print("  [FAIL] AI-queued unit never spawned.")
		return false

	print("  [PASS] Player build bar and enemy AI both queue through the exact same ProductionQueue object, and both produce real units.")
	return true

func test_debug_infinite_resources_is_a_real_runtime_toggle() -> bool:
	print("Running Test Suite: Debug Toggle - Infinite Resources Is A Real Runtime Toggle (RTS_CORE_ROADMAP.md A2)...")

	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	# Was a hardcoded const (INFINITE_PLAYER_RESOURCES_FOR_TESTING) that only
	# a source edit could flip. Now a runtime var - set it false here and
	# prove spend() genuinely runs out, not just that the flag changed.
	skirmish.debug_infinite_resources = false
	skirmish.economy[skirmish.PLAYER_TEAM].metal = 50
	skirmish.economy[skirmish.PLAYER_TEAM].crystal = 0

	if skirmish.spend(skirmish.PLAYER_TEAM, 999999, 0):
		print("  [FAIL] With debug_infinite_resources off, an unaffordable spend should be rejected.")
		skirmish.queue_free()
		return false
	if not skirmish.spend(skirmish.PLAYER_TEAM, 50, 0):
		print("  [FAIL] With debug_infinite_resources off, an affordable spend should still succeed.")
		skirmish.queue_free()
		return false
	if skirmish.economy[skirmish.PLAYER_TEAM].metal != 0:
		print("  [FAIL] With debug_infinite_resources off, spend() should not top the bank back up. Got ", skirmish.economy[skirmish.PLAYER_TEAM].metal)
		skirmish.queue_free()
		return false

	# Flip it back on and confirm the top-up path still works.
	skirmish.debug_infinite_resources = true
	if not skirmish.spend(skirmish.PLAYER_TEAM, 0, 0):
		print("  [FAIL] spend() of an affordable (zero) amount should succeed with the toggle back on.")
		skirmish.queue_free()
		return false
	if skirmish.economy[skirmish.PLAYER_TEAM].metal < skirmish.INFINITE_RESOURCE_FLOOR:
		print("  [FAIL] With debug_infinite_resources back on, spend() should top the bank back up to the floor. Got ", skirmish.economy[skirmish.PLAYER_TEAM].metal)
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame

	print("  [PASS] debug_infinite_resources is a genuine runtime toggle, not a compile-time const - off makes spend() a real economy check, on restores the sandbox top-up.")
	return true

func test_b2_n_player_slots_alliance_fog_repair_and_independent_resources() -> bool:
	print("Running Test Suite: N-Player Slots - 3-Slot Alliance (2v1): Fog, Repair, and Independent Resources (RTS_CORE_ROADMAP.md B2)...")
	await tree.process_frame # let any deferred queue_free()s from prior tests actually clear

	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	# Default boot: exactly 2 slots, matching PLAYER_TEAM/ENEMY_TEAM - "N
	# players representable, runtime still spawns 2" per the roadmap.
	if skirmish.slots.size() != 2:
		print("  [FAIL] Expected exactly 2 default slots, got ", skirmish.slots.size())
		skirmish.queue_free()
		return false
	if skirmish.slots[skirmish.LOCAL_SLOT].team != skirmish.PLAYER_TEAM:
		print("  [FAIL] slots[LOCAL_SLOT] should be the player's own team.")
		skirmish.queue_free()
		return false

	# Add a 3rd slot allied with the player - authored symmetric, same
	# convention the header comment on _alliance_for_team() documents.
	var ALLY_TEAM = 2
	skirmish.add_slot({"team": ALLY_TEAM, "faction": "industrialists", "is_local": false, "is_bot": false, "allies": [skirmish.PLAYER_TEAM], "hq": null})
	skirmish._get_slot(skirmish.PLAYER_TEAM)["allies"].append(ALLY_TEAM)

	if not skirmish.is_allied(skirmish.PLAYER_TEAM, ALLY_TEAM):
		print("  [FAIL] Player should be allied with the newly-added slot.")
		skirmish.queue_free()
		return false
	if skirmish.is_allied(skirmish.PLAYER_TEAM, skirmish.ENEMY_TEAM):
		print("  [FAIL] Player should NOT be allied with the enemy just because a 3rd slot exists.")
		skirmish.queue_free()
		return false

	# --- Resources independent ---
	if not skirmish.economy.has(ALLY_TEAM):
		print("  [FAIL] add_slot() should have given the new slot its own economy entry.")
		skirmish.queue_free()
		return false
	skirmish.economy[ALLY_TEAM].metal = 777
	if skirmish.economy[skirmish.PLAYER_TEAM].metal == 777 or skirmish.economy[skirmish.ENEMY_TEAM].metal == 777:
		print("  [FAIL] The ally's economy should be independent of the player's/enemy's.")
		skirmish.queue_free()
		return false
	if not skirmish.spend(ALLY_TEAM, 700, 0):
		print("  [FAIL] Ally should be able to spend its own independent metal.")
		skirmish.queue_free()
		return false
	if skirmish.economy[ALLY_TEAM].metal != 77:
		print("  [FAIL] Ally's spend() should only affect the ally's own economy, got ", skirmish.economy[ALLY_TEAM].metal)
		skirmish.queue_free()
		return false

	# --- Fog reveals ally vision ---
	# Far from the player's own base (lake_crossing's HQ sits around
	# z=+/-102 with a 240 half-extent map) so only the ally's own vision
	# can possibly see the enemy here - proves fog is genuinely alliance-
	# aware, not just "player's own team sees."
	var ally_pos = Vector3(200, 0, -200)
	var enemy_pos = Vector3(205, 0, -200) # well within any hull's base_vision (~20+)
	var ally_bp = skirmish.roster[0].blueprint
	var enemy_bp = skirmish.enemy_roster[0].blueprint
	var ally_unit = skirmish.spawn_unit(ally_bp, ALLY_TEAM, ally_pos)
	var enemy_unit = skirmish.spawn_unit(enemy_bp, skirmish.ENEMY_TEAM, enemy_pos)
	await tree.process_frame

	skirmish._recalc_fog_of_war()
	if enemy_unit.fog_hidden:
		print("  [FAIL] An enemy unit within the ALLY's vision range should be revealed, even though the player's own units are nowhere near it.")
		skirmish.queue_free()
		return false

	# --- Allied repair works ---
	# The ally's own unit (not the player's, not the enemy's) gets healed
	# by a player-team repair_array - proves repair_array's targets_allies
	# filter is genuinely alliance-aware, not same-team-only.
	var ModuleDataScript = preload("res://scripts/module_data.gd")
	var healer = CharacterBody3D.new()
	healer.set_script(preload("res://scripts/battle_unit.gd"))
	root.add_child(healer)
	healer.team = skirmish.PLAYER_TEAM
	healer.set_meta("team", skirmish.PLAYER_TEAM)
	healer.add_to_group("damageable")
	healer.global_position = ally_pos + Vector3(0, 0, 3)

	var weapon = Node3D.new()
	weapon.set_script(preload("res://scripts/auto_weapon.gd"))
	healer.add_child(weapon)
	var w_data = ModuleDataScript.new()
	w_data.type_id = "repair_array"
	w_data.base_weight = 70.0
	w_data.base_heal_rate = 30.0
	weapon.set_meta("module_data", w_data)
	weapon._ready()

	ally_unit.max_hp = 200.0
	ally_unit.hp = 100.0
	ally_unit.global_position = healer.global_position + Vector3(0, 0, -3) # within the weapon's default forward cone

	# skirmish._damageable_grid only rebuilds on a FOG_TICK_INTERVAL (0.3s)
	# Timer (PERFORMANCE_PLAN.md P1c) - ally_unit was spawned well after the
	# one-time initial populate in _setup_navigation(), and a single
	# process_frame above is nowhere near 0.3 real seconds, so without this
	# the grid auto_weapon.gd's _damageable_candidates() queries can still be
	# missing ally_unit here, making this test genuinely timing-dependent
	# (this was a real, found-and-fixed flake, not hypothetical - see
	# UNIFIED_ROADMAP.md 3.5). Force a rebuild the same way the Timer would,
	# deterministically, rather than waiting on real time to pass.
	skirmish._rebuild_damageable_grid()
	weapon._find_nearest_target()
	if weapon.target != ally_unit:
		print("  [FAIL] repair_array on the player's team should target the damaged ALLY (different team, same alliance), got ", weapon.target)
		skirmish.queue_free(); healer.queue_free()
		return false

	var hp_before = ally_unit.hp
	weapon._fire_repair_array_beam()
	if ally_unit.hp <= hp_before:
		print("  [FAIL] repair_array's beam should have healed the allied unit, hp went from ", hp_before, " to ", ally_unit.hp)
		skirmish.queue_free(); healer.queue_free()
		return false

	skirmish.queue_free()
	healer.queue_free()
	await tree.process_frame

	print("  [PASS] A manually-added 3rd slot is a real ally: independent economy, fog reveals what only the ally can see, and a player-team repair_array heals the ally's different-team unit.")
	return true

# RTS_CORE_ROADMAP.md 1.3, item 1: "the enemy AI has never placed a
# building" - killing its heavy manufactory used to permanently remove heavy
# units from the match, since enemy_ai.gd's whole loop was produce/ensure-
# harvester/launch-wave and nothing ever rebuilt. Proves the real end-to-end
# path: destroy it, let the AI's own structures queue (enemy_ai.gd's
# _rebuild_lost_manufactories(), ticked every STRUCTURE_CHECK_INTERVAL) drip-
# feed a real replacement through production.enqueue_structure(), then let
# skirmish.gd's _place_ai_structure() site and spawn it for real - not a
# mocked call, the actual production tick + placement-legality search.
func test_1_3_ai_rebuilds_a_destroyed_manufactory() -> bool:
	print("Running Test Suite: 1.3 - Enemy AI Rebuilds A Destroyed Manufactory (UNIFIED_ROADMAP.md 1.3)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	var heavy = skirmish.get_team_factory(skirmish.ENEMY_TEAM, "heavy")
	if not is_instance_valid(heavy):
		print("  [FAIL] Test setup: enemy should start with a live heavy manufactory")
		skirmish.queue_free()
		return false
	heavy.take_damage(999999.0, "explosive")
	await tree.process_frame
	if skirmish.has_factory_of_tier(skirmish.ENEMY_TEAM, "heavy"):
		print("  [FAIL] Test setup: destroying the heavy manufactory should leave the enemy without one")
		skirmish.queue_free()
		return false

	# Give the AI resources to actually afford the rebuild (D1's drip-fed
	# cost still needs something to draw from) and drive its own
	# _physics_process() directly rather than waiting real wall-clock time -
	# same pattern the rest of the suite uses for timer-gated AI behavior.
	skirmish.add_resources(skirmish.ENEMY_TEAM, 5000, 5000)
	var ai = skirmish.get_node("EnemyAI")
	var new_heavy: Node = null
	for i in range(3000):
		ai._physics_process(1.0 / 60.0)
		skirmish.production.tick(1.0 / 60.0)
		skirmish._physics_process(1.0 / 60.0)
		# Checked via get_team_buildings() directly, NOT has_factory_of_tier() -
		# a freshly-placed building's start_construction_animation() tween
		# only advances on real engine frames (Tween.finished), which manually
		# driving _physics_process() in a tight loop never produces, so
		# build_incomplete would never clear and has_factory_of_tier() (which
		# correctly excludes incomplete buildings, same as D4's own gate)
		# would never see it - the point here is proving the AI placed a real
		# replacement at all, not proving the cosmetic tween finishes.
		for b in skirmish.get_team_buildings(skirmish.ENEMY_TEAM):
			if b.kind == "heavy_manufactory" and b != heavy:
				new_heavy = b
				break
		if new_heavy:
			break
	if not new_heavy:
		print("  [FAIL] The AI should have rebuilt its heavy manufactory within the simulated time budget")
		skirmish.queue_free()
		return false

	if new_heavy == heavy:
		print("  [FAIL] The rebuilt manufactory should be a genuinely NEW building, not the destroyed one")
		skirmish.queue_free()
		return false
	if new_heavy.team != skirmish.ENEMY_TEAM:
		print("  [FAIL] The rebuilt manufactory should belong to the ENEMY_TEAM")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] The AI's own structures queue rebuilds a destroyed manufactory through the real D4 production pipeline and a real legal placement.")
	return true

# RTS_CORE_ROADMAP.md 1.3, item 2: the AI never reacted to its own low-power
# state (E1's power states/build-slowdown/defense-gating were all player-
# only in practice, since nothing on the enemy side ever built a
# power_plant). Forces Low power the same way test_e1_power_state_derives...
# does (extra static buildings tip upkeep past capacity), then proves
# enemy_ai.gd's _build_power_plant_if_needed() queues and places a real one.
func test_1_3_ai_builds_a_power_plant_under_low_power() -> bool:
	print("Running Test Suite: 1.3 - Enemy AI Builds A Power Plant When Its Own Team Is Low Power (UNIFIED_ROADMAP.md 1.3)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	skirmish._recalc_energy_economy()
	if skirmish.is_low_power(skirmish.ENEMY_TEAM):
		print("  [FAIL] Test setup: a fresh match's enemy team should start at Normal power")
		skirmish.queue_free()
		return false

	# Same trick as E1's own threshold test - extra static buildings on the
	# ENEMY team push its upkeep past capacity without touching the player.
	var extras: Array = []
	for i in range(6):
		extras.append(skirmish._spawn_prefab("light_manufactory", skirmish.ENEMY_TEAM, skirmish.enemy_hq.global_position + Vector3(-30, 0, 6.0 * i), skirmish.enemy_faction))
	await tree.process_frame
	skirmish._recalc_energy_economy()
	if not skirmish.is_low_power(skirmish.ENEMY_TEAM):
		print("  [FAIL] Test setup: 6 extra static buildings should have tipped the enemy team into Low/Critical power")
		for b in extras: b.queue_free()
		skirmish.queue_free()
		return false

	skirmish.add_resources(skirmish.ENEMY_TEAM, 5000, 5000)
	var ai = skirmish.get_node("EnemyAI")
	var built = false
	var power_plant_count_before = 0
	for b in skirmish.get_team_buildings(skirmish.ENEMY_TEAM):
		if b.kind == "power_plant":
			power_plant_count_before += 1
	for i in range(3000):
		ai._physics_process(1.0 / 60.0)
		skirmish.production.tick(1.0 / 60.0)
		skirmish._physics_process(1.0 / 60.0)
		var count = 0
		for b in skirmish.get_team_buildings(skirmish.ENEMY_TEAM):
			if b.kind == "power_plant":
				count += 1
		if count > power_plant_count_before:
			built = true
			break
	if not built:
		print("  [FAIL] The AI should have built a power_plant to answer its own Low power state within the simulated time budget")
		for b in extras: b.queue_free()
		skirmish.queue_free()
		return false

	for b in extras: b.queue_free()
	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] The AI queues and places a real power_plant through the same E1 power-state check the HUD itself uses, once its own team is Low/Critical.")
	return true

# RTS_CORE_ROADMAP.md E2: sell refunds RA's own 50%, scaled by the building's
# current health fraction - selling a half-dead building should give back
# half of half, not the full 50%.
func test_e2_selling_a_building_refunds_health_scaled_50_percent() -> bool:
	print("Running Test Suite: E2 - Selling A Building Refunds 50% Of Its Build Cost, Scaled By Current HP (RTS_CORE_ROADMAP.md E2)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	var refinery = skirmish._spawn_prefab("refinery", skirmish.PLAYER_TEAM, skirmish.player_hq.global_position + Vector3(20, 0, 0), skirmish.player_faction)
	await tree.process_frame
	if refinery.build_cost_metal != 150 or refinery.build_cost_crystal != 0:
		print("  [FAIL] Test setup: refinery should carry its own build cost (150M/0C), got ", refinery.build_cost_metal, "M/", refinery.build_cost_crystal, "C")
		skirmish.queue_free()
		return false

	# Full health: 150 * 0.5 = 75 metal exactly.
	var metal_before = skirmish.economy[skirmish.PLAYER_TEAM].metal
	skirmish.sell_building(refinery)
	if skirmish.economy[skirmish.PLAYER_TEAM].metal != metal_before + 75:
		print("  [FAIL] Selling a full-health refinery should refund exactly 75 metal (50% of 150), got delta ", skirmish.economy[skirmish.PLAYER_TEAM].metal - metal_before)
		skirmish.queue_free()
		return false
	if not refinery.is_dead:
		print("  [FAIL] A sold building should be marked dead")
		skirmish.queue_free()
		return false

	# Half health: 150 * 0.5 * 0.5 = 37.5 -> rounds to 38.
	var refinery2 = skirmish._spawn_prefab("refinery", skirmish.PLAYER_TEAM, skirmish.player_hq.global_position + Vector3(20, 0, 20), skirmish.player_faction)
	await tree.process_frame
	refinery2.hp = refinery2.max_hp * 0.5
	var metal_before2 = skirmish.economy[skirmish.PLAYER_TEAM].metal
	skirmish.sell_building(refinery2)
	if skirmish.economy[skirmish.PLAYER_TEAM].metal != metal_before2 + 38:
		print("  [FAIL] Selling a half-health refinery should refund 38 metal (round(150*0.5*0.5)), got delta ", skirmish.economy[skirmish.PLAYER_TEAM].metal - metal_before2)
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Selling refunds RA's own 50%, correctly scaled by the building's current HP fraction.")
	return true

# RTS_CORE_ROADMAP.md E2: repair on a real interval/HP-per-step cadence,
# drawing real resources per step (not free), and stopping automatically at
# full health.
func test_e2_repair_heals_over_real_ticks_and_spends_real_resources() -> bool:
	print("Running Test Suite: E2 - Repair Heals Over Real Ticks And Spends Real Resources, Stopping At Full HP (RTS_CORE_ROADMAP.md E2)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	var refinery = skirmish._spawn_prefab("refinery", skirmish.PLAYER_TEAM, skirmish.player_hq.global_position + Vector3(20, 0, 0), skirmish.player_faction)
	await tree.process_frame
	refinery.hp = refinery.max_hp - 20.0 # damaged, not dead
	skirmish.add_resources(skirmish.PLAYER_TEAM, 1000, 1000)
	var metal_before = skirmish.economy[skirmish.PLAYER_TEAM].metal

	refinery.is_repairing = true
	var hp_before = refinery.hp
	for i in range(120): # 2 real seconds - comfortably past one REPAIR_INTERVAL (0.96s)
		skirmish._process_repairs(1.0 / 60.0)
	if refinery.hp <= hp_before:
		print("  [FAIL] Repair should have healed some HP after 2 simulated seconds, stayed at ", refinery.hp)
		skirmish.queue_free()
		return false
	if refinery.hp > refinery.max_hp:
		print("  [FAIL] Repair should never overheal past max_hp, got ", refinery.hp, "/", refinery.max_hp)
		skirmish.queue_free()
		return false
	if skirmish.economy[skirmish.PLAYER_TEAM].metal >= metal_before:
		print("  [FAIL] Repair should have drawn real metal, got ", skirmish.economy[skirmish.PLAYER_TEAM].metal, " (started at ", metal_before, ")")
		skirmish.queue_free()
		return false

	# Run long enough to fully heal - is_repairing should clear itself once
	# hp reaches max_hp, not stay stuck on forever.
	for i in range(600):
		skirmish._process_repairs(1.0 / 60.0)
		if refinery.hp >= refinery.max_hp:
			break
	if refinery.hp != refinery.max_hp:
		print("  [FAIL] Repair should reach exactly full HP given enough time, got ", refinery.hp, "/", refinery.max_hp)
		skirmish.queue_free()
		return false
	if refinery.is_repairing:
		print("  [FAIL] Repair should auto-stop (is_repairing = false) once full HP is reached")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Repair heals real HP over real ticks, spends real resources per step, and auto-stops at full health.")
	return true

# RTS_CORE_ROADMAP.md E3: OpenRA's CancelUnbuildableItems - a vehicle-tier
# job already mid-build shouldn't just keep drip-feeding cost toward a
# factory that's never coming back once that tier's last manufactory dies
# (production_queue.gd's tick() has nowhere to spawn it and would otherwise
# silently drop the finished job - see its own comment).
func test_e3_losing_last_manufactory_of_a_tier_refunds_its_queued_items() -> bool:
	print("Running Test Suite: E3 - Losing A Tier's Last Manufactory Refunds Everything Queued In It (RTS_CORE_ROADMAP.md E3)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	skirmish.debug_infinite_resources = false
	skirmish.add_resources(skirmish.PLAYER_TEAM, 1000, 1000)
	var combat_entry = null
	for entry in skirmish.roster:
		if not entry.is_defense and ModuleCatalog.get_hull_size_tier(entry.blueprint.get("hull_type", "medium_hull")) == "light":
			combat_entry = entry
			break
	if combat_entry == null:
		print("  [FAIL] Test setup: roster should have at least one light-tier combat unit")
		skirmish.queue_free()
		return false

	skirmish._queue_player_unit(combat_entry)
	var q = skirmish.production.get_queue(skirmish.PLAYER_TEAM, "light")
	if q.is_empty():
		print("  [FAIL] Test setup: queuing the unit should have created a real light-tier job")
		skirmish.queue_free()
		return false
	# Tick partway through so remaining_cost is genuinely less than total_cost -
	# proving the refund is the amount actually drawn, not the full price.
	for i in range(30):
		skirmish.production.tick(1.0 / 60.0)
	var drawn_metal = int(round(q[0].total_cost_metal - q[0].remaining_cost_metal))
	var drawn_crystal = int(round(q[0].total_cost_crystal - q[0].remaining_cost_crystal))
	if drawn_metal <= 0:
		print("  [FAIL] Test setup: some cost should have been drawn by now, got ", drawn_metal)
		skirmish.queue_free()
		return false

	var metal_before = skirmish.economy[skirmish.PLAYER_TEAM].metal
	var crystal_before = skirmish.economy[skirmish.PLAYER_TEAM].crystal
	var light_factory = skirmish.get_team_factory(skirmish.PLAYER_TEAM, "light")
	light_factory.take_damage(999999.0, "explosive")
	await tree.process_frame

	if not q.is_empty():
		print("  [FAIL] The queued light-tier job should have been cancelled once the last light manufactory died, queue still has ", q.size(), " item(s)")
		skirmish.queue_free()
		return false
	if skirmish.economy[skirmish.PLAYER_TEAM].metal != metal_before + drawn_metal or skirmish.economy[skirmish.PLAYER_TEAM].crystal != crystal_before + drawn_crystal:
		print("  [FAIL] Cancelling should refund exactly what was drawn (", drawn_metal, "M/", drawn_crystal, "C), got delta ", skirmish.economy[skirmish.PLAYER_TEAM].metal - metal_before, "M/", skirmish.economy[skirmish.PLAYER_TEAM].crystal - crystal_before, "C")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Losing a tier's last manufactory refunds every queued item in that tier's line, exactly what had actually been drawn.")
	return true

# RTS_CORE_ROADMAP.md E3: a SECOND live manufactory of the same tier should
# NOT trigger a cancel when the first one dies - only losing the LAST one
# should touch the queue.
func test_e3_losing_one_of_two_manufactories_of_a_tier_does_not_cancel_the_queue() -> bool:
	print("Running Test Suite: E3 - Losing One Of TWO Manufactories Of The Same Tier Does NOT Cancel The Queue (RTS_CORE_ROADMAP.md E3)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	skirmish.debug_infinite_resources = false
	skirmish.add_resources(skirmish.PLAYER_TEAM, 1000, 1000)
	var first_light = skirmish.get_team_factory(skirmish.PLAYER_TEAM, "light")
	var second_light = skirmish._spawn_prefab("light_manufactory", skirmish.PLAYER_TEAM, first_light.global_position + Vector3(0, 0, 14), skirmish.player_faction)
	await tree.process_frame

	var combat_entry = null
	for entry in skirmish.roster:
		if not entry.is_defense and ModuleCatalog.get_hull_size_tier(entry.blueprint.get("hull_type", "medium_hull")) == "light":
			combat_entry = entry
			break
	skirmish._queue_player_unit(combat_entry)
	var q = skirmish.production.get_queue(skirmish.PLAYER_TEAM, "light")
	if q.is_empty():
		print("  [FAIL] Test setup: queuing should have created a real light-tier job")
		skirmish.queue_free()
		return false

	first_light.take_damage(999999.0, "explosive")
	await tree.process_frame
	if q.is_empty():
		print("  [FAIL] Losing only ONE of two live light manufactories should NOT cancel the queue - it's still buildable from the survivor")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Losing one of two same-tier manufactories leaves the queue alone - only losing the last one cancels it.")
	return true



# A harvester must be able to REACH the radius at which it unloads.
#
# THE BUG THIS PINS. The delivery check was a flat 4.5 m measured origin-to-
# centre (battle_unit.gd's _process_harvest). A refinery is 5x5 - half-extent
# 2.5 - and the default ore_trucker is a 5.5 m medium hull that approaches
# nose-on, so its origin comes to rest about 2.75 m behind its nose: measured
# closest approach 5.31 m against a 4.50 m trigger. It parked against the wall
# and never delivered, resources never rose, and the truck sat there for the
# rest of the match.
#
# Asserted as GEOMETRY rather than against a fixed number, because re-tuning the
# constant would break again the first time somebody designs a longer harvester -
# which is the entire point of the Design Lab.
func test_harvester_delivery_radius_clears_hull_and_refinery() -> bool:
	print("Running Test Suite: Harvester delivery radius clears the building and the hull...")
	# battle_unit.gd extends CharacterBody3D, so it is attached to a body rather
	# than constructed - the same way every other test in this file builds one.
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var unit = CharacterBody3D.new()
	unit.set_script(BattleUnitScript)
	root.add_child(unit)

	# A stand-in refinery: the function measures the building off its own box
	# collider, so that is all it needs.
	var refinery := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 3, 5)
	col.shape = box
	refinery.add_child(col)
	root.add_child(refinery)

	# And a hull carrying the size meta reconstruct_vehicle() writes.
	var hull := Node3D.new()
	hull.set_meta("base_hull_size", Vector3(3.0, 1.8, 5.5))
	hull.set_meta("hull_scale", Vector3.ONE)
	unit.add_child(hull)
	unit.hull_node = hull

	var reach: float = unit._refinery_deliver_distance(refinery)
	# The floor: half the building plus half the hull is where the two solids
	# touch. Anything at or below that is unreachable by definition.
	var touching: float = 2.5 + 5.5 * 0.5
	print("  delivery radius %.2f m, solids touch at %.2f m" % [reach, touching])
	if reach <= touching:
		print("  [FAIL] The delivery radius (%.2f) is inside the point where the harvester and the refinery collide (%.2f) - it can never trigger." % [reach, touching])
		unit.queue_free(); refinery.queue_free()
		return false

	# It must also scale WITH the hull, or a longer harvester reintroduces the bug.
	hull.set_meta("base_hull_size", Vector3(3.0, 1.8, 11.0))
	var longer: float = unit._refinery_deliver_distance(refinery)
	if longer <= reach:
		print("  [FAIL] A hull twice as long did not widen the delivery radius (%.2f vs %.2f)" % [longer, reach])
		unit.queue_free(); refinery.queue_free()
		return false

	unit.queue_free()
	refinery.queue_free()
	await tree.process_frame
	print("  [PASS] Delivery radius is derived from the refinery footprint and the harvester's own hull, so it stays reachable for any design.")
	return true
