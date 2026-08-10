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
	# A GENERATOR NO LONGER RAISES max_energy, AND THAT IS THE POINT.
	#
	# This suite used to assert that mounting a fusion_generator pushed
	# max_energy above the hull's base. That stopped being true when generation
	# and storage were split into separate stats: the generator produces power
	# and stores none, the capacitor stores and produces none. The assertion is
	# inverted rather than deleted, because "a generator must NOT change the
	# buffer size" is now the property worth protecting - a generator that
	# quietly grew the pool again would be the old conflation coming back.
	var unit_with_gen = CharacterBody3D.new()
	unit_with_gen.set_script(BattleUnitScript)
	root.add_child(unit_with_gen)
	unit_with_gen.setup(bp_with_gen, 0, bp_manager)
	if not is_equal_approx(unit_with_gen.max_energy, base_only):
		print("  [FAIL] A fusion_generator makes POWER, not storage - max_energy should be unchanged at ", base_only, ", got ", unit_with_gen.max_energy)
		bp_manager.queue_free()
		return false
	if unit_with_gen.energy_regen_rate <= 0.0:
		print("  [FAIL] A mounted fusion_generator should give a positive net regen rate, got ", unit_with_gen.energy_regen_rate)
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

	# ...and a capacitor is the module that DOES raise it, with no generation.
	var bp_with_cap = bp_no_gen.duplicate(true)
	bp_with_cap["modules"] = [
		{"type_id": "capacitor_bank", "name": "Capacitor Bank", "position": {"x": 0.0, "y": 0.5, "z": 0.0}, "rotation": {"x": 0.0, "y": 0.0, "z": 0.0}, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "yaw_offset": 0.0, "tweaks": {}}
	]
	var unit_with_cap = CharacterBody3D.new()
	unit_with_cap.set_script(BattleUnitScript)
	root.add_child(unit_with_cap)
	unit_with_cap.setup(bp_with_cap, 0, bp_manager)
	if unit_with_cap.max_energy <= base_only:
		print("  [FAIL] A capacitor_bank is the module that raises storage - max_energy should exceed ", base_only, ", got ", unit_with_cap.max_energy)
		bp_manager.queue_free()
		return false
	unit_with_cap.queue_free()

	bp_manager.queue_free()
	print("  [PASS] Hulls carry a base energy pool; a generator adds generation without adding storage; a capacitor adds storage without adding generation; energy regenerates over time.")
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

func test_energy_damage_class_reclassification() -> bool:
	print("Running Test Suite: heavy_laser/plasma_lobber/pd_laser Reclassified To Energy Damage...")
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
		# Every energy weapon costs the shooter's own capacitor to fire (Chris:
		# "all the energy weapons should"), not only tesla_coil/arc_projector/
		# ion_cannon - damage_class and capacitor cost are two separate lists
		# (see ENERGY_DAMAGE_CLASS_TYPES's comment in auto_weapon.gd) that
		# happen to agree for every weapon in the game today.
		if weapon.energy_cost_per_shot <= 0.0:
			print("  [FAIL] ", type_id, " should cost the shooter's own Energy pool to fire, got cost=", weapon.energy_cost_per_shot)
			weapon.queue_free()
			return false
		weapon.queue_free()

	await tree.process_frame
	print("  [PASS] damage_resolver.gd has a real energy armor row; heavy_laser/plasma_lobber/pd_laser deal energy damage and cost the shooter's capacitor.")
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


# --- Power budget -----------------------------------------------------------
#
# Storage and generation used to be one number: the refill rate was derived as
# `capacity * 0.08`, so storage manufactured generation and neither of the two
# interesting shapes (big buffer that trickles, small buffer that refills fast)
# could be built. This suite guards the split itself - if those two stats ever
# start feeding each other again, everything downstream quietly collapses back
# into a single axis with two names.
func test_generation_and_storage_are_independent() -> bool:
	print("Running Test Suite: Power - Generation And Storage Are Separate Stats...")
	var PowerBudget = preload("res://scripts/power_budget.gd")

	var make_hull = func(specs: Array) -> Node3D:
		var hull = Node3D.new()
		hull.set_meta("type_id", "medium_hull")
		for spec in specs:
			var n = Node3D.new()
			var d = ModuleData.new()
			d.type_id = spec["type_id"]
			var cat: Dictionary = ModuleCatalog.get_module_data(spec["type_id"])
			d.category = cat.get("category", "module")
			d.base_energy_capacity = cat.get("energy_capacity", 0.0)
			d.base_power_output = cat.get("power_output", 0.0)
			d.tweaks = spec.get("tweaks", {})
			n.set_meta("module_data", d)
			hull.add_child(n)
		root.add_child(hull)
		return hull

	var bare = make_hull.call([])
	var base: Dictionary = PowerBudget.analyze(bare)
	# The hull must bring BOTH of its own, or every design in the roster is
	# broken out of the box until a generator is bolted on.
	if base["storage"] <= 0.0 or base["generation"] <= 0.0:
		print("  [FAIL] A bare hull must carry both storage and generation of its own; got storage=", base["storage"], " generation=", base["generation"])
		bare.free()
		return false
	bare.free()

	# A capacitor moves storage and ONLY storage.
	var capped = make_hull.call([{"type_id": "capacitor_bank"}])
	var cap: Dictionary = PowerBudget.analyze(capped)
	if cap["storage"] <= base["storage"]:
		print("  [FAIL] A capacitor_bank must raise storage; ", base["storage"], " -> ", cap["storage"])
		capped.free()
		return false
	if not is_equal_approx(cap["generation"], base["generation"]):
		print("  [FAIL] A capacitor_bank stores charge, it does not make any - generation should be unchanged at ", base["generation"], ", got ", cap["generation"])
		capped.free()
		return false
	capped.free()

	# A generator moves generation and ONLY generation.
	var genned = make_hull.call([{"type_id": "fusion_generator"}])
	var gen: Dictionary = PowerBudget.analyze(genned)
	if gen["generation"] <= base["generation"]:
		print("  [FAIL] A fusion_generator must raise generation; ", base["generation"], " -> ", gen["generation"])
		genned.free()
		return false
	if not is_equal_approx(gen["storage"], base["storage"]):
		print("  [FAIL] A fusion_generator makes power, it does not store it - storage should be unchanged at ", base["storage"], ", got ", gen["storage"])
		genned.free()
		return false
	genned.free()

	print("  [PASS] Hulls carry both stats; capacitors move storage alone and generators move generation alone.")
	return true


# Before the split, fusion_generator carried capacity AND regen while its two
# tweaks scaled only regen - and capacitor_bank was the mirror image. So on each
# module one pair of sliders tuned a stat the module also got from elsewhere,
# and the other pair was simply inert. This asserts all four are live, which is
# the concrete payoff of the split and exactly what a future rebalance could
# silently undo by handing either module back the other stat.
func test_all_four_power_module_tweaks_are_live() -> bool:
	print("Running Test Suite: Power - Generator And Capacitor Tweaks All Do Something...")
	var PowerBudget = preload("res://scripts/power_budget.gd")

	var measure = func(type_id: String, tweaks: Dictionary, key: String) -> float:
		var hull = Node3D.new()
		hull.set_meta("type_id", "medium_hull")
		var n = Node3D.new()
		var d = ModuleData.new()
		d.type_id = type_id
		var cat: Dictionary = ModuleCatalog.get_module_data(type_id)
		d.category = cat.get("category", "module")
		d.base_energy_capacity = cat.get("energy_capacity", 0.0)
		d.base_power_output = cat.get("power_output", 0.0)
		d.tweaks = tweaks
		n.set_meta("module_data", d)
		hull.add_child(n)
		root.add_child(hull)
		var v: float = float(PowerBudget.analyze(hull)[key])
		hull.free()
		return v

	# Generator tweaks -> generation.
	var gen_base: float = measure.call("fusion_generator", {}, "generation")
	for tweak in ["reactor_length", "cooling_radiator"]:
		var raised: float = measure.call("fusion_generator", {tweak: 2.0}, "generation")
		if raised <= gen_base:
			print("  [FAIL] fusion_generator's '", tweak, "' is a dead slider: generation stayed at ", gen_base, " (got ", raised, "). Both its tweaks must move generation now that generation is all it has.")
			return false

	# Capacitor tweaks -> storage.
	var store_base: float = measure.call("capacitor_bank", {}, "storage")
	for tweak in [["bank_capacity", 6.0], ["busbar_gauge", 2.0]]:
		var raised2: float = measure.call("capacitor_bank", {tweak[0]: tweak[1]}, "storage")
		if raised2 <= store_base:
			print("  [FAIL] capacitor_bank's '", tweak[0], "' is a dead slider: storage stayed at ", store_base, " (got ", raised2, ").")
			return false

	# ...and neither module's tweaks leak into the other's stat.
	if not is_equal_approx(measure.call("fusion_generator", {"reactor_length": 2.0}, "storage"),
			measure.call("fusion_generator", {}, "storage")):
		print("  [FAIL] reactor_length changed the generator's STORAGE. A generation tweak must not grow the buffer.")
		return false
	if not is_equal_approx(measure.call("capacitor_bank", {"bank_capacity": 6.0}, "generation"),
			measure.call("capacitor_bank", {}, "generation")):
		print("  [FAIL] bank_capacity changed the capacitor's GENERATION. A storage tweak must not raise the refill rate.")
		return false

	print("  [PASS] All four tweaks move their own module's stat, and neither module's tweaks leak into the other's.")
	return true


# Consumption is the genuinely new quantity here - before it, electronics were
# free and a generator was worth fitting only on an energy-weapon platform. This
# checks draw is summed, that net is the difference, that firing cost is tracked
# apart from always-on cost, and that the no-design path carries a full key set
# (which the Design Lab depends on: clear_hull() calls update_stats(null), and a
# partial dictionary there has broken that screen before).
func test_power_budget_sums_draw_and_reports_net() -> bool:
	print("Running Test Suite: Power - Draw Sums And The Budget Balances...")
	var PowerBudget = preload("res://scripts/power_budget.gd")

	var empty: Dictionary = PowerBudget.analyze(null)
	for key in ["has_hull", "storage", "generation", "draw", "weapon_draw", "total_draw",
			"net", "firing_net", "has_deficit", "firing_deficit_only", "endurance", "firing_endurance"]:
		if not empty.has(key):
			print("  [FAIL] The no-hull early return is missing '", key, "'. The Design Lab reads this dict unconditionally on clear_hull().")
			return false
	if empty["has_hull"] or empty["storage"] != 0.0 or empty["generation"] != 0.0:
		print("  [FAIL] With no design there is nothing to report; expected has_hull=false and zeroed figures, got ", empty)
		return false

	var make_hull = func(ids: Array) -> Node3D:
		var hull = Node3D.new()
		hull.set_meta("type_id", "medium_hull")
		for id in ids:
			var n = Node3D.new()
			var d = ModuleData.new()
			d.type_id = id
			var cat: Dictionary = ModuleCatalog.get_module_data(id)
			d.category = cat.get("category", "module")
			d.base_dps = cat.get("dps", 0.0)
			d.base_energy_capacity = cat.get("energy_capacity", 0.0)
			d.base_power_output = cat.get("power_output", 0.0)
			n.set_meta("module_data", d)
			hull.add_child(n)
		root.add_child(hull)
		return hull

	# Draw is a SUM, not a max and not a flat per-design figure.
	var one = make_hull.call(["sensor_suite"])
	var three = make_hull.call(["sensor_suite", "fire_control_radar", "jammer_mast"])
	var d1: Dictionary = PowerBudget.analyze(one)
	var d3: Dictionary = PowerBudget.analyze(three)
	var expected: float = ModuleCatalog.get_power_draw("sensor_suite") \
		+ ModuleCatalog.get_power_draw("fire_control_radar") \
		+ ModuleCatalog.get_power_draw("jammer_mast")
	if not is_equal_approx(d3["draw"], expected):
		print("  [FAIL] Draw must sum across every drawing module; expected ", expected, ", got ", d3["draw"])
		one.free(); three.free()
		return false
	if d1["draw"] <= 0.0:
		print("  [FAIL] A sensor_suite must cost something to run - electronics being free is what this table exists to end.")
		one.free(); three.free()
		return false

	if not is_equal_approx(d3["net"], d3["generation"] - d3["draw"]):
		print("  [FAIL] net should be generation - draw; got net=", d3["net"], " from generation=", d3["generation"], " draw=", d3["draw"])
		one.free(); three.free()
		return false
	# Three power-hungry electronics on a bare medium hull must actually
	# overdraw it, or the table is too timid to create a decision at all.
	if not d3["has_deficit"]:
		print("  [FAIL] Three electronics on a bare medium_hull should overdraw it; net was ", d3["net"])
		one.free(); three.free()
		return false
	if d3["endurance"] >= INF or d3["endurance"] <= 0.0:
		print("  [FAIL] A design in deficit must report a finite, positive endurance; got ", d3["endurance"])
		one.free(); three.free()
		return false
	one.free(); three.free()

	# An energy weapon is a FIRING cost, not an always-on one. Keeping them
	# apart is what stops a legitimate burst design reading as permanently
	# under-powered.
	var gun = make_hull.call(["ion_cannon"])
	var g: Dictionary = PowerBudget.analyze(gun)
	if g["has_deficit"]:
		print("  [FAIL] An energy weapon costs power only while firing; a design mounting one should not read as in deficit at rest.")
		gun.free()
		return false
	if g["weapon_draw"] <= 0.0:
		print("  [FAIL] An ion_cannon should report a nonzero sustained weapon draw, got ", g["weapon_draw"])
		gun.free()
		return false
	if not g["firing_deficit_only"]:
		print("  [FAIL] An ion_cannon on a bare hull should out-draw it WHILE FIRING (firing_net=", g["firing_net"], "), flagged separately from a resting deficit.")
		gun.free()
		return false
	gun.free()

	# Storage buys endurance, not solvency. This is the whole reason the two
	# modules are different answers rather than one being strictly better.
	var short_hull = make_hull.call(["sensor_suite", "fire_control_radar", "jammer_mast"])
	var buffered = make_hull.call(["sensor_suite", "fire_control_radar", "jammer_mast", "capacitor_bank"])
	var s: Dictionary = PowerBudget.analyze(short_hull)
	var b: Dictionary = PowerBudget.analyze(buffered)
	if not is_equal_approx(s["net"], b["net"]):
		print("  [FAIL] A capacitor must not change the net rate; ", s["net"], " -> ", b["net"])
		short_hull.free(); buffered.free()
		return false
	if b["endurance"] <= s["endurance"]:
		print("  [FAIL] A capacitor must extend how long a deficit is survivable; endurance ", s["endurance"], " -> ", b["endurance"])
		short_hull.free(); buffered.free()
		return false
	short_hull.free(); buffered.free()

	print("  [PASS] Draw sums across modules, net is generation minus always-on draw, firing cost is tracked separately, and storage buys endurance without buying solvency.")
	return true


# The consequence. A design that cannot feed itself sheds systems in a fixed
# order - shields, then electronics, then weapons - running from the loss that
# is most recoverable to the one that ends the fight. Asserted as ORDERING and
# as real runtime effect rather than against the threshold values, so retuning
# those does not break this.
func test_brownout_sheds_systems_in_priority_order() -> bool:
	print("Running Test Suite: Power - Brownout Sheds In Priority Order...")
	var PowerBudget = preload("res://scripts/power_budget.gd")

	if not (PowerBudget.SHIELDS_OFFLINE > PowerBudget.ELECTRONICS_BROWNOUT
			and PowerBudget.ELECTRONICS_BROWNOUT > PowerBudget.WEAPONS_OFFLINE):
		print("  [FAIL] Shed order must be shields, then electronics, then weapons; thresholds are ",
			PowerBudget.SHIELDS_OFFLINE, " / ", PowerBudget.ELECTRONICS_BROWNOUT, " / ", PowerBudget.WEAPONS_OFFLINE)
		return false

	# Walking the buffer down must never un-shed something.
	var state := {}
	var first_seen := {}
	var step := 1.0
	while step >= 0.0:
		state = PowerBudget.brownout_state(step, state)
		for key in ["shields_offline", "electronics_brownout", "weapons_offline"]:
			if state[key] and not first_seen.has(key):
				first_seen[key] = step
		step -= 0.01
	for key in ["shields_offline", "electronics_brownout", "weapons_offline"]:
		if not first_seen.has(key):
			print("  [FAIL] '", key, "' never shed even at an empty buffer.")
			return false
	if not (first_seen["shields_offline"] > first_seen["electronics_brownout"]
			and first_seen["electronics_brownout"] > first_seen["weapons_offline"]):
		print("  [FAIL] Systems shed out of order: shields at ", first_seen["shields_offline"],
			", electronics at ", first_seen["electronics_brownout"], ", weapons at ", first_seen["weapons_offline"])
		return false

	# Hysteresis. A design hovering on a boundary must not flicker its vision
	# radius every physics frame, which is what a bare threshold comparison does.
	var h := {}
	h = PowerBudget.brownout_state(PowerBudget.ELECTRONICS_BROWNOUT - 0.01, h)
	if not h["electronics_brownout"]:
		print("  [FAIL] Test setup wrong: below the threshold electronics should be shed.")
		return false
	h = PowerBudget.brownout_state(PowerBudget.ELECTRONICS_BROWNOUT + 0.01, h)
	if not h["electronics_brownout"]:
		print("  [FAIL] Electronics recovered the instant the buffer crossed back over the threshold - that is the flicker the hysteresis exists to prevent.")
		return false
	h = PowerBudget.brownout_state(PowerBudget.ELECTRONICS_BROWNOUT + PowerBudget.RECOVERY_HYSTERESIS + 0.01, h)
	if h["electronics_brownout"]:
		print("  [FAIL] Electronics never recovered once the buffer cleared the hysteresis margin - a brownout has to be temporary.")
		return false

	# Vision degrades but never to zero: a blind unit reads as a bug.
	var dim: float = PowerBudget.vision_multiplier({"electronics_brownout": true})
	if dim >= 1.0 or dim <= 0.0:
		print("  [FAIL] A brownout must reduce vision without blinding the unit; multiplier was ", dim)
		return false

	# And the real thing, end to end.
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var bp_manager = preload("res://scripts/blueprint_manager.gd").new()
	root.add_child(bp_manager)
	var mods := []
	for id in ["sensor_suite", "fire_control_radar", "jammer_mast"]:
		mods.append({"type_id": id, "name": id, "position": {"x": 0.0, "y": 0.6, "z": 0.0},
			"rotation": {"x": 0.0, "y": 0.0, "z": 0.0}, "scale": {"x": 1.0, "y": 1.0, "z": 1.0},
			"yaw_offset": 0.0, "tweaks": {}})
	var unit = CharacterBody3D.new()
	unit.set_script(BattleUnitScript)
	root.add_child(unit)
	unit.setup({
		"version": 2.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "tracked_treads", "settings": {"width": 1.0}},
		"modules": mods,
	}, 0, bp_manager)
	if unit.energy_regen_rate >= 0.0:
		print("  [FAIL] Test setup wrong: three electronics on a medium_hull should give a negative net rate, got ", unit.energy_regen_rate)
		bp_manager.queue_free()
		return false
	var full_vision: float = unit.vision_range
	var order := []
	for i in range(400):
		unit._tick_power(0.1)
		for key in ["shields_offline", "electronics_brownout", "weapons_offline"]:
			if unit._brownout[key] and not order.has(key):
				order.append(key)
	if order != ["shields_offline", "electronics_brownout", "weapons_offline"]:
		print("  [FAIL] A real unit shed in the order ", order, ", expected shields, electronics, weapons.")
		bp_manager.queue_free()
		return false
	if unit.vision_range >= full_vision:
		print("  [FAIL] The brownout should have cut this unit's sight range; still ", unit.vision_range, " against a healthy ", full_vision)
		bp_manager.queue_free()
		return false
	unit.queue_free()
	bp_manager.queue_free()

	print("  [PASS] Thresholds are ordered shields/electronics/weapons, shedding is monotonic with hysteresis on recovery, vision dims without blinding, and a real overdrawn unit drains and sheds in that order.")
	return true


# Playtest item #1: harvesters need a visible bar showing how full their bays
# are. Deliberately drives the bar functions directly against a hand-built
# harvester rather than spawning a full blueprint-reconstructed unit - the bar
# is pure presentation over HarvesterFSM.cargo()/capacity, and a real spawn
# would drag in a blueprint, a controller and a match director without testing
# anything more about THIS code.
func test_harvester_cargo_bar_tracks_fill_fraction() -> bool:
	print("Running Test Suite: Harvester Cargo Bar Tracks cargo()/capacity...")
	var UnitScript = preload("res://scripts/battle/units/unit.gd")
	var HarvesterFSMScript = preload("res://scripts/battle/economy/harvester_fsm.gd")

	var unit := CharacterBody3D.new()
	unit.set_script(UnitScript)
	var fsm = HarvesterFSMScript.new()
	fsm.capacity = 100
	unit.harvester = fsm
	unit.is_harvester = true
	unit._create_cargo_bar(Vector3(4, 2, 6))

	if unit._cargo_bar_root == null or unit._cargo_fill == null:
		print("  [FAIL] A harvester should have been given a cargo bar; got root=", unit._cargo_bar_root, " fill=", unit._cargo_fill)
		unit.free()
		return false

	# Empty reads as hidden, not as an empty plate over every idle truck.
	if unit._cargo_bar_root.visible:
		print("  [FAIL] An empty harvester's cargo bar should be hidden.")
		unit.free()
		return false

	for want in [0.25, 0.5, 1.0]:
		# cargo() sums cargo_by_type, which is where a real harvest lands.
		fsm.cargo_by_type = {"ore": int(fsm.capacity * want)}
		unit._update_cargo_bar()
		if not unit._cargo_bar_root.visible:
			print("  [FAIL] A carrying harvester's bar should be visible at fill ", want)
			unit.free()
			return false
		if absf(unit._cargo_fill.scale.x - want) > 0.001:
			print("  [FAIL] Fill scale should be %.3f at %d/%d cargo, got %.3f" % [want, fsm.cargo(), fsm.capacity, unit._cargo_fill.scale.x])
			unit.free()
			return false
		# Grows from the left edge: a bar that scaled about its own centre
		# would read as shrinking rather than filling.
		var want_x: float = -(unit._cargo_bar_width * 0.5) * (1.0 - want)
		if absf(unit._cargo_fill.position.x - want_x) > 0.001:
			print("  [FAIL] Fill should be left-anchored at x=%.3f for fill %.2f, got %.3f" % [want_x, want, unit._cargo_fill.position.x])
			unit.free()
			return false

	# A zero capacity must not divide by zero or show a full bar.
	fsm.capacity = 0
	unit._update_cargo_bar()
	if unit._cargo_bar_root.visible:
		print("  [FAIL] A zero-capacity harvester should show no fill rather than a full bar.")
		unit.free()
		return false

	# A combat unit must never carry the node at all.
	var combat := CharacterBody3D.new()
	combat.set_script(UnitScript)
	combat.is_harvester = false
	combat._create_cargo_bar(Vector3(4, 2, 6))
	if combat._cargo_bar_root != null:
		print("  [FAIL] A non-harvester should never be given a cargo bar.")
		combat.free()
		unit.free()
		return false
	combat.free()
	unit.free()

	print("  [PASS] Harvester cargo bar exists only on harvesters, hides when empty, is left-anchored, and its fill scale tracks cargo()/capacity exactly.")
	return true
