extends "res://tests/suite_base.gd"
# sim and stats suites, split out of the former single-file
# run_tests.gd. Registration order lives in run_tests.gd's SUITE_ORDER,
# not here - the runner drives that manifest so execution order is
# identical to the pre-split single file.

func test_stats_calculations() -> bool:
	print("Running Test Suite 1: Stats Calculations...")
	
	# Instantiate MainLab scene to load UI and dependencies
	var lab_scene = preload("res://scenes/MainLab.tscn").instantiate()
	root.add_child(lab_scene)
	
	# Wait a frame for scene setup
	await tree.process_frame
	
	var stat_ui = lab_scene.get_node_or_null("UI_StatBlock")
	if not stat_ui:
		print("  [FAIL] UI_StatBlock not found in MainLab.")
		lab_scene.queue_free()
		return false
		
	# Create a mock hull with custom metadata
	var mock_hull = Node3D.new()
	mock_hull.name = "MockHull"
	mock_hull.set_meta("type_id", "medium_hull")
	mock_hull.set_meta("faction", "industrialists") # 20% weight reduction
	mock_hull.set_meta("armor_material", "hardened_steel") # 1.0 hp mult, 1.0 weight mult
	mock_hull.set_meta("armor_thickness", 1.5)
	
	# Create a mock module (weapon)
	var mock_weapon = Node3D.new()
	var w_data = ModuleData.new()
	w_data.type_id = "basic_cannon"
	w_data.module_name = "Main Cannon"
	w_data.category = "weapon"
	w_data.base_hp = 100.0
	w_data.base_weight = 80.0
	w_data.cost_metal = 30
	w_data.base_dps = 40.0
	w_data.scale_multiplier = Vector3(1, 1, 1) # base volume scale 1.0
	mock_weapon.set_meta("module_data", w_data)
	mock_hull.add_child(mock_weapon)
	
	# Calculate stats using stat_calculator.gd script attached to UI_StatBlock
	stat_ui.update_stats(mock_hull)
	
	# Expected Calculations (FABLE_REVIEW.md 2.6: the sidebar now shows the
	# COMBAT formulas via the shared ModuleCatalog.compute_hull_* functions,
	# not its old display-only module-sum-times-material math):
	# "Hull HP" = the unit's real combat max_hp (hull base * thickness *
	# material mult * volume) - the mock module's own HP is a separate
	# strip pool shown alongside, not part of this figure.
	var expected_hp = ModuleCatalog.compute_hull_max_hp("medium_hull", 1.5, "hardened_steel", Vector3.ONE)

	# "Total Weight" = hull combat weight (incl. the Industrialists 20%
	# armor-weight discount, which is now REAL in combat too) + module sum.
	var expected_weight = ModuleCatalog.compute_hull_weight("medium_hull", 1.5, "hardened_steel", Vector3.ONE, 0.8) + 80.0
	
	# Expected Thresholds (from DamageResolver.ARMOR_TABLE's hardened_steel
	# row - the sidebar reads this directly now, not a separate hardcoded
	# copy; "E" is a real Energy threshold as of this pass, not the
	# Explosive value mislabeled):
	# Kinetic (K): Base K (15.0) * thickness (1.5) = 22.5
	# Thermal (T): Base T (5.0) * thickness (1.5) = 7.5
	# Energy (E): Base Energy (8.0) * thickness (1.5) = 12.0
	var expected_k_thresh = 22.5
	var expected_t_thresh = 7.5
	var expected_e_thresh = 12.0
	
	# Retrieve calculated values from labels
	var hp_label_text = stat_ui.hp_label.text
	var weight_label_text = stat_ui.weight_label.text
	var threshold_label_text = stat_ui.armor_threshold_label.text
	
	var got_hp = float(hp_label_text.split(":")[-1])
	var got_weight = float(weight_label_text.split(":")[-1])
	
	# Parse thresholds: e.g. "Armor Thresholds: K: 22.5, T: 7.5, E: 15.0"
	var tokens = threshold_label_text.split(",")
	var got_k = float(tokens[0].split(":")[-1])
	var got_t = float(tokens[1].split(":")[-1])
	var got_e = float(tokens[2].split(":")[-1])
	
	var pass_hp = abs(got_hp - expected_hp) < 0.01
	var pass_weight = abs(got_weight - expected_weight) < 0.01
	var pass_thresholds = abs(got_k - expected_k_thresh) < 0.01 and abs(got_t - expected_t_thresh) < 0.01 and abs(got_e - expected_e_thresh) < 0.01
	
	if not pass_hp:
		print("  [FAIL] HP calculation wrong. Expected: ", expected_hp, " Got: ", got_hp)
	if not pass_weight:
		print("  [FAIL] Weight calculation wrong. Expected: ", expected_weight, " Got: ", got_weight)
	if not pass_thresholds:
		print("  [FAIL] Thresholds wrong. Expected K/T/E: ", expected_k_thresh, "/", expected_t_thresh, "/", expected_e_thresh, " Got: ", got_k, "/", got_t, "/", got_e)
		
	# Clean up
	mock_hull.queue_free()
	lab_scene.queue_free()
	
	if pass_hp and pass_weight and pass_thresholds:
		print("  [PASS] Stats Calculation matches all analytical models.")
		return true
	return false

func test_modular_assembly_types_have_no_shadowed_monolithic_mesh() -> bool:
	print("Running Test Suite: No MODULAR_ASSEMBLY_TYPES id has an unreachable monolithic mesh...")
	# build_visual() loads a whole-module authored mesh with
	#   _part(type_id) if not MODULAR_ASSEMBLY_TYPES.has(type_id) else null
	# so for any id in that table the monolithic assets/models/parts/<id>.glb
	# can NEVER be loaded. Seventeen such files existed and read like intended
	# fallbacks while being unreachable (tracked_treads.glb alone was 257KB).
	# They were deleted; this stops the table and the parts dir from drifting
	# back into that ambiguity, in either direction - adding an id to the table
	# without deleting its monolith, or re-authoring a monolith for an id that
	# is already modular.
	var VisualBuilderScript = preload("res://scripts/visual_builder.gd")
	var offenders: Array = []
	for type_id in VisualBuilderScript.MODULAR_ASSEMBLY_TYPES.keys():
		if ResourceLoader.exists("res://assets/models/parts/%s.glb" % type_id):
			offenders.append(type_id)

	if not offenders.is_empty():
		print("  [FAIL] %d modular type(s) have a shadowed monolithic .glb that build_visual() can never load: %s" % [offenders.size(), str(offenders)])
		print("         Either delete assets/models/parts/<id>.glb, or remove the id from MODULAR_ASSEMBLY_TYPES.")
		return false

	print("  [PASS] All %d modular assembly types are free of unreachable monolithic meshes." % VisualBuilderScript.MODULAR_ASSEMBLY_TYPES.size())
	return true


func test_design_to_battle_integration() -> bool:
	print("Running Test Suite: Design -> Serialize -> Battle-Spawn Integration...")
	# Thursday integration pass: design a unit using several of this week's
	# fixes together (legs at a non-default size, gauss_railgun's rail_length
	# gizmo tweak, sensor_suite's mast_height tweak), then push it through the
	# EXACT same reconstruct_vehicle() path Skirmish/Battlefield use to spawn
	# real battle units, and confirm nothing was lost or silently reset.
	#
	# Deliberately does NOT call save_blueprint() / touch user://blueprints -
	# that's Chris's real save directory with ~24 real designs in it, and
	# this test doesn't need the disk round-trip to prove the pipeline works;
	# serialize_hull() + reconstruct_vehicle() is the same code save/load uses.
	var placer = Node3D.new()
	placer.name = "MainLab"
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	var bm = Node.new()
	bm.name = "BlueprintManager"
	bm.set_script(preload("res://scripts/blueprint_manager.gd"))
	placer.add_child(bm)
	await tree.process_frame

	placer._place_hull_from_ui("heavy_hull")
	await tree.process_frame
	placer._place_weapon_from_ui("gauss_railgun", Vector3(0, 0.75, -1.0), Vector3.UP)
	await tree.process_frame
	placer._place_weapon_from_ui("sensor_suite", Vector3(1.5, 0.75, 1.5), Vector3.UP)
	await tree.process_frame
	placer._place_weapon_from_ui("legs", Vector3.ZERO, Vector3.DOWN)
	await tree.process_frame

	# Apply this week's fixed tweaks directly (mirrors what the gizmo-drag /
	# slider UI would write into module_data.tweaks / locomotion settings).
	for child in placer.hull.get_children():
		if child.has_meta("module_data"):
			var data = child.get_meta("module_data")
			if data.type_id == "gauss_railgun":
				data.tweaks["rail_length"] = 1.8
			elif data.type_id == "sensor_suite":
				data.tweaks["mast_height"] = 1.6
	placer.update_locomotion("legs", {"size": 1.7, "count": 4})
	await tree.process_frame

	var snapshot = bm.serialize_hull(placer.hull)
	if snapshot.is_empty():
		print("  [FAIL] serialize_hull produced an empty snapshot")
		placer.queue_free()
		return false

	# Confirm the tweaks actually made it into the snapshot before we even
	# get to reconstruction, so a failure below is unambiguous about which
	# stage broke.
	var found_rail_length = false
	var found_mast_height = false
	for mod in snapshot.get("modules", []):
		if mod.get("type_id", "") == "gauss_railgun" and abs(mod.get("tweaks", {}).get("rail_length", 0.0) - 1.8) < 0.01:
			found_rail_length = true
		if mod.get("type_id", "") == "sensor_suite" and abs(mod.get("tweaks", {}).get("mast_height", 0.0) - 1.6) < 0.01:
			found_mast_height = true
	if not found_rail_length or not found_mast_height:
		print("  [FAIL] Snapshot lost tweaks before reconstruction (rail_length=", found_rail_length, " mast_height=", found_mast_height, ")")
		placer.queue_free()
		return false

	# Now spawn it the way Skirmish/Battlefield actually do: is_designer=false,
	# into a plain parent, not the MainLab hull path.
	var battle_parent = Node3D.new()
	root.add_child(battle_parent)
	var battle_hull = bm.reconstruct_vehicle(snapshot, battle_parent, false)
	await tree.process_frame

	if not battle_hull:
		print("  [FAIL] reconstruct_vehicle returned null for battle spawn")
		placer.queue_free()
		battle_parent.queue_free()
		return false

	var legs_found = false
	var legs_scale_ok = false
	var railgun_tweak_ok = false
	var sensor_tweak_ok = false
	for child in battle_hull.get_children():
		if not child.has_meta("module_data"): continue
		var data = child.get_meta("module_data")
		if data.type_id == "legs":
			legs_found = true
			# Batch E hull-relative scaling fix: the outer node's scale.y
			# carries ONLY the hull's own height factor relative to the
			# reference hull (module_placer.gd's update_locomotion()) - leg_length
			# itself is baked directly into the thigh/shin/foot/mount sub-part
			# scales inside _build_legs() (and into module_data.get_weight()/
			# get_cost() via the tweaks dict), so the outer node is deliberately
			# left unscaled by leg_length to avoid double-applying it (see
			# module_placer.gd comments).
			#
			# Derived from the catalog rather than hardcoded: this used to
			# assert 1.7 * 1.5 against a comment claiming heavy_hull.size.y
			# was 1.5. The hull data has since been re-authored (it is 2.5
			# now), so the literal silently went stale and the suite could
			# only have passed by accident. It was invisible because Suite 7
			# failed first and the `and` chain short-circuited every suite
			# after it.
			# The node scale is now FIXED at 1.0, not the hull-height factor
			# this used to assert. Scaling a leg by the hull's height meant a
			# taller body got taller legs, which raised the body further -
			# enormous spider legs on anything above a scout (Chris,
			# 2026-08-02). Ride height belongs to the running gear, so leg
			# proportions are keyed to their own mount now; see the DROP
			# comment in visual_builder.gd's _build_legs(). What this suite
			# actually exists to prove is that the TWEAK survives the
			# design -> serialize -> battle-spawn round trip, which it still
			# does - so that is what it checks, plus that the scale is the
			# fixed 1.0 and not some silently reintroduced hull factor.
			var leg_length_ok = abs(data.tweaks.get("leg_length", 0.0) - 1.7) < 0.01
			var hull_factor_ok = abs(child.scale.y - 1.0) < 0.05
			if leg_length_ok and hull_factor_ok:
				legs_scale_ok = true
		elif data.type_id == "gauss_railgun":
			if abs(data.tweaks.get("rail_length", 0.0) - 1.8) < 0.01:
				railgun_tweak_ok = true
		elif data.type_id == "sensor_suite":
			if abs(data.tweaks.get("mast_height", 0.0) - 1.6) < 0.01:
				sensor_tweak_ok = true

	placer.queue_free()
	battle_parent.queue_free()

	if not legs_found or not legs_scale_ok:
		print("  [FAIL] Battle-spawned legs lost their size tweak (found=", legs_found, " scale_ok=", legs_scale_ok, ")")
		return false
	if not railgun_tweak_ok:
		print("  [FAIL] Battle-spawned gauss_railgun lost its rail_length tweak")
		return false
	if not sensor_tweak_ok:
		print("  [FAIL] Battle-spawned sensor_suite lost its mast_height tweak")
		return false

	print("  [PASS] A unit designed with this week's fixed mechanics survives the full design -> serialize -> battle-spawn pipeline intact.")
	return true

func test_trait_system_composability() -> bool:
	print("Running Test Suite: Unit-Class Trait System (composable tags, no hard-blocking)...")
	# Traits union from whatever hull+locomotion combo is actually present -
	# no validation anywhere. Chris's explicit constraint: a player can put
	# treads on a naval hull if they want; this test only checks that
	# traits compose correctly, not that any combination is rejected
	# (nothing rejects combinations, by design).
	var wheels_traits = ModuleCatalog.get_traits("medium_hull", "wheels")
	if "ground_contact" not in wheels_traits or "high_speed" not in wheels_traits:
		print("  [FAIL] medium_hull + wheels should carry ground_contact and high_speed traits, got ", wheels_traits)
		return false

	var heli_traits = ModuleCatalog.get_traits("light_hull", "helicopter_rotors")
	if "airborne" not in heli_traits or "rotary_wing" not in heli_traits or "hovering" not in heli_traits:
		print("  [FAIL] light_hull + helicopter_rotors should carry airborne/rotary_wing/hovering traits, got ", heli_traits)
		return false

	# A foundation hull should carry "static" automatically, derived from
	# the existing is_foundation() mechanism rather than needing its own
	# separate flag.
	var foundation_traits = ModuleCatalog.get_traits("pillbox_foundation", "")
	if "static" not in foundation_traits:
		print("  [FAIL] pillbox_foundation should carry the 'static' trait (derived from is_foundation), got ", foundation_traits)
		return false

	# No hard-blocking: nothing prevents combining traits/locomotion that
	# might seem to make no sense (e.g. legs on a foundation - foundations
	# already block locomotion PLACEMENT at the design-lab level for a
	# different, pre-existing reason, but get_traits() itself must never
	# validate or throw - it just describes whatever's asked of it).
	var weird_traits = ModuleCatalog.get_traits("pillbox_foundation", "hover_engine")
	if "static" not in weird_traits or "hovering" not in weird_traits:
		print("  [FAIL] get_traits() should compose even an unusual combination without rejecting it, got ", weird_traits)
		return false

	# All 7 hull types default to turreted_capable=true (nothing overrides
	# it yet) - confirms the default doesn't silently break existing mounting.
	for hull_id in ["light_hull", "medium_hull", "heavy_hull", "assault_hull", "pillbox_foundation", "tower_foundation"]:
		if not ModuleCatalog.is_turreted_capable(hull_id):
			print("  [FAIL] ", hull_id, " should default to turreted_capable=true")
			return false

	print("  [PASS] Traits compose from whatever hull+locomotion is present, derive 'static' from is_foundation, and never block a combination.")
	return true

func test_frame_built_whole_vehicle_aim() -> bool:
	print("Running Test Suite: Frame-Built Weapons - Zero Traverse + Whole-Vehicle-Aim AI...")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	# gauss_railgun is always frame_built per get_mount_style() - verify the
	# traverse angle collapses to zero once facet/hull_type are supplied
	# (omitting them keeps the old weapon-type-only angle, unaffected).
	var angle = ModuleCatalog.get_traverse_limit_angle("gauss_railgun", "front", "medium_hull")
	if angle > 0.001:
		print("  [FAIL] gauss_railgun should have zero traverse when mount-aware, got ", angle)
		return false
	var turret_angle = ModuleCatalog.get_traverse_limit_angle("basic_cannon", "top", "medium_hull")
	if turret_angle < PI - 0.01:
		print("  [FAIL] basic_cannon should keep its full 360-degree traverse on a turreted-capable hull, got ", turret_angle)
		return false

	# auto_weapon.gd should read this mount context and never rotate its own
	# local transform, regardless of where the target is.
	var hull = Node3D.new()
	hull.name = "Hull"
	hull.set_meta("type_id", "medium_hull")
	root.add_child(hull)
	var weapon = Node3D.new()
	weapon.set_script(load("res://scripts/auto_weapon.gd"))
	hull.add_child(weapon)
	weapon.set_meta("facet", "front")
	var w_data = ModuleData.new()
	w_data.type_id = "gauss_railgun"
	w_data.base_weight = 300.0
	w_data.base_dps = 40.0
	weapon.set_meta("module_data", w_data)
	weapon._ready()
	if weapon.traverse_limit_angle > 0.001:
		print("  [FAIL] auto_weapon.gd should derive a zero traverse_limit_angle for a frame_built mount")
		hull.queue_free()
		return false

	var los_target = Node3D.new()
	los_target.add_to_group("damageable")
	root.add_child(los_target)
	los_target.global_position = weapon.global_position + Vector3(5, 0, 0) # off to the side, not straight ahead
	var resting_before = weapon.resting_transform.basis
	weapon.target = los_target
	for i in range(20):
		weapon._physics_process(0.1)
	if not weapon.transform.basis.is_equal_approx(resting_before):
		print("  [FAIL] A frame_built weapon's local transform should never rotate away from resting, regardless of target position")
		hull.queue_free()
		los_target.queue_free()
		return false
	hull.queue_free()
	los_target.queue_free()

	# Whole-vehicle-aim: a unit whose active weapon is frame_built should
	# keep turning its whole hull to face the target while in range, not
	# just stop and leave the weapon (which can't aim itself) pointed
	# wherever the hull happened to be facing on arrival.
	var unit = CharacterBody3D.new()
	unit.set_script(BattleUnitScript)
	root.add_child(unit)
	unit.rotate_speed = 4.0
	unit.attack_range = 20.0
	unit.has_frame_built_weapon = true
	unit.global_transform = Transform3D.IDENTITY # facing -Z
	var side_target = Node3D.new()
	root.add_child(side_target)
	side_target.global_position = Vector3(10, 0, 0) # +X, 90 degrees off the current -Z facing, within range
	unit.order_attack(side_target)
	var initial_forward = -unit.global_transform.basis.z
	var initial_angle = initial_forward.angle_to((side_target.global_position - unit.global_position).normalized())
	for i in range(40):
		unit._physics_process(0.05)
	var final_forward = -unit.global_transform.basis.z
	var final_angle = final_forward.angle_to((side_target.global_position - unit.global_position).normalized())
	if final_angle >= initial_angle:
		print("  [FAIL] A frame_built unit should keep turning to face its target while in range, not hold its arrival heading (initial angle ", initial_angle, ", final ", final_angle, ")")
		unit.queue_free()
		side_target.queue_free()
		return false
	var horizontal_speed = Vector2(unit.velocity.x, unit.velocity.z).length()
	if horizontal_speed > 0.01:
		print("  [FAIL] A frame_built unit turning in place while in range should not be translating, got horizontal speed ", horizontal_speed)
		unit.queue_free()
		side_target.queue_free()
		return false

	unit.queue_free()
	side_target.queue_free()
	print("  [PASS] frame_built weapons never independently traverse; the whole vehicle turns in place to aim them.")
	return true

func test_headless_combat_simulation() -> bool:
	print("Running Test Suite 4: Headless Combat Simulation Tick Loop...")

	# Field a known, POINT-DEFENCE-FREE design instead of whatever happens to
	# be sitting in user://blueprint.json.
	#
	# Battlefield._spawn_vehicle() loads the player's real last-active design,
	# and this suite drops a missile directly overhead and asserts the player
	# takes damage from it. That only held while weapons could not aim
	# straight up: Basis.looking_at(dir, Vector3.UP) is singular for a target
	# directly above, so a CIWS/pd_laser/flak_cannon simply failed to track
	# anything overhead. auto_weapon.gd's _looking_at_safe() fixed that (part
	# of giving pintle mounts a genuine full-sphere envelope), at which point
	# the user's current PD-heavy design started shooting the missile down at
	# tick 2 - a correct interception, reported as "failed to apply damage".
	#
	# Same machine-state fix the Test Range suite already uses: write a known
	# fixture, restore whatever was there afterwards.
	var bp_path = "user://blueprint.json"
	var had_prior_bp = FileAccess.file_exists(bp_path)
	var prior_bp_content = ""
	if had_prior_bp:
		var rf = FileAccess.open(bp_path, FileAccess.READ)
		prior_bp_content = rf.get_as_text()
		rf.close()
	var fixture_bp = {
		"version": 1.0,
		"hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"faction": "industrialists",
		"locomotion": {"type_id": "wheels", "settings": {"count": 4}},
		"modules": [
			{"type_id": "wheels", "position": {"x": 0, "y": 0, "z": 0}, "normal": {"x": 0, "y": 1, "z": 0}},
			{"type_id": "basic_cannon", "position": {"x": 0, "y": 1.0, "z": -1.5}, "normal": {"x": 0, "y": 1, "z": 0}}
		]
	}
	var wf = FileAccess.open(bp_path, FileAccess.WRITE)
	wf.store_string(JSON.stringify(fixture_bp))
	wf.close()

	# We simulate a dynamic combat scenario headlessly
	var battlefield_scene = preload("res://scenes/Battlefield.tscn").instantiate()
	root.add_child(battlefield_scene)
	current_scene = battlefield_scene
	await tree.process_frame

	if had_prior_bp:
		var rwf = FileAccess.open(bp_path, FileAccess.WRITE)
		rwf.store_string(prior_bp_content)
		rwf.close()
	else:
		DirAccess.remove_absolute(bp_path)

	var player = battlefield_scene.get_node_or_null("PlayerVehicle")
	if not player:
		print("  [FAIL] Player vehicle not spawned in Battlefield.")
		battlefield_scene.queue_free()
		return false
		
	# Get starting player HP
	var initial_hp = player.hp
	var initial_modules_hp = 0.0
	for m in player.get_active_modules():
		initial_modules_hp += m.get_meta("current_hp") if m.has_meta("current_hp") else m.get_meta("module_data").get_hp()
	
	# Spawn a missile directly above the player and target it
	var missile = Node3D.new()
	missile.set_script(IncomingMissileScript)
	battlefield_scene.add_child(missile)
	missile.global_position = player.global_position + Vector3(0.5, 5.0, 0.5)
	missile.target_node = player
	missile.damage_amount = 80.0 # High enough to beat most armor thresholds
	
	# Process multiple ticks manually to simulate physics movement
	var hit_detected = false
	var ticks = 0
	while ticks < 100:
		await tree.process_frame
		ticks += 1
		if not is_instance_valid(missile) or missile.is_queued_for_deletion():
			hit_detected = true
			break
			
	# Check HP reduction
	var hp_after_battle = player.hp
	var end_modules_hp = 0.0
	for m in player.get_active_modules():
		if is_instance_valid(m):
			end_modules_hp += m.get_meta("current_hp") if m.has_meta("current_hp") else m.get_meta("module_data").get_hp()
			
	var total_initial = initial_hp + initial_modules_hp
	var total_end = hp_after_battle + end_modules_hp
	
	# Clean up. queue_free() is deferred - without waiting a frame, this
	# scene's target dummies (now real "damageable" team-1 members, needed
	# for Test Range parity) can still be alive and in-group when the very
	# next test (test_team_targeting) runs immediately after, contaminating
	# its own team-based targeting scan with leftover hostiles.
	battlefield_scene.queue_free()
	await tree.process_frame

	if hit_detected and total_end < total_initial:
		print("  [PASS] Headless combat simulation ticks successfully. Player total HP reduced from ", total_initial, " to ", total_end)
		return true
	else:
		print("  [FAIL] Combat tick simulation failed to hit or apply damage. Hit: ", hit_detected, " Start HP: ", total_initial, " End HP: ", total_end)
		return false

func test_evasion_model_speed_defends_against_ballistic_not_hitscan() -> bool:
	print("Running Test Suite: Evasion Model - Speed Has Real Defensive Value (FABLE_REVIEW 1.4)...")
	seed(1234) # deterministic roll sequence for the statistical assertions below

	var fast_target = CharacterBody3D.new()
	fast_target.velocity = Vector3(15.0, 0.0, 0.0) # well above the 0.5 "stationary" floor

	var stationary_target = CharacterBody3D.new()
	stationary_target.velocity = Vector3.ZERO

	var ballistic_weapon = Node3D.new()
	ballistic_weapon.set_script(load("res://scripts/auto_weapon.gd"))
	ballistic_weapon.type_id = "rotary_cannon" # ballistic class

	var hitscan_weapon = Node3D.new()
	hitscan_weapon.set_script(load("res://scripts/auto_weapon.gd"))
	hitscan_weapon.type_id = "heavy_laser" # hitscan class

	var guided_weapon = Node3D.new()
	guided_weapon.set_script(load("res://scripts/auto_weapon.gd"))
	guided_weapon.type_id = "guided_missile" # guided class

	# None of the 5 nodes above are ever added to the tree (this test only
	# needs their scripts' pure functions, not a live scene) - Node is not
	# RefCounted, so an un-parented, un-freed Node is a genuine engine-level
	# leak, not just a GDScript reference dropped. Free them all through one
	# path so every return below (pass or fail) cleans up.
	var _to_free = [fast_target, stationary_target, ballistic_weapon, hitscan_weapon, guided_weapon]
	var ok = true
	var fail_msg = ""

	# A fast mover should sometimes dodge a ballistic weapon - not a
	# guarantee (that would make speed strictly dominant, same trap as the
	# armor material dropdown in 1.2), but a real, non-trivial chance.
	var misses = 0
	var trials = 400
	for i in range(trials):
		if not ballistic_weapon._roll_hit(fast_target):
			misses += 1
	if ok and (misses < int(trials * 0.15) or misses > int(trials * 0.85)):
		ok = false
		fail_msg = "A fast target should have a real (but not near-0%% or near-100%%) miss chance against a ballistic weapon, got %d/%d misses" % [misses, trials]

	# Hitscan and guided weapons never miss from speed - their counters are
	# elsewhere (aim/traverse, PD interception), not target speed.
	for i in range(50):
		if ok and not hitscan_weapon._roll_hit(fast_target):
			ok = false
			fail_msg = "Hitscan weapons should never miss due to target speed"
		if ok and not guided_weapon._roll_hit(fast_target):
			ok = false
			fail_msg = "Guided weapons should never miss due to target speed"

	# A stationary target can't dodge anything - "fast but standing still"
	# shouldn't accidentally read as evasive.
	for i in range(50):
		if ok and not ballistic_weapon._roll_hit(stationary_target):
			ok = false
			fail_msg = "A stationary target should never miss - it isn't moving to dodge anything"

	for n in _to_free:
		n.free()

	if not ok:
		print("  [FAIL] ", fail_msg)
		return false
	print("  [PASS] Ballistic fire can be dodged by a fast-moving target (", misses, "/", trials, " misses); hitscan/guided never miss from speed; stationary targets never dodge.")
	return true

func test_support_modules_get_combat_script_in_real_spawn() -> bool:
	print("Running Test Suite: repair_array/drone_carrier Actually Get Scripted Through The Real Spawn Pipeline...")
	# Real bug found while verifying the repair/drone fixes: every
	# _setup_weapons()-equivalent only attached auto_weapon.gd when
	# category=="weapon", but repair_array/drone_carrier are catalogued as
	# category="module" - so in actual gameplay (setup()/reconstruct_vehicle(),
	# not a synthetic test that manually attaches the script) neither module
	# ever got its firing/targeting logic at all. This test goes through the
	# REAL pipeline specifically to make sure that gap stays closed.
	await tree.process_frame
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var bp_manager = preload("res://scripts/blueprint_manager.gd").new()
	root.add_child(bp_manager)

	var bp = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "tracked_treads", "settings": {"width": 1.0}},
		"modules": [
			{"type_id": "repair_array", "name": "Repair Welder Array", "position": {"x": 0.0, "y": 0.5, "z": 0.0}, "rotation": {"x": 0.0, "y": 0.0, "z": 0.0}, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "yaw_offset": 0.0, "tweaks": {}},
			{"type_id": "drone_carrier", "name": "Drone Carrier Bay", "position": {"x": 2.0, "y": 0.5, "z": 0.0}, "rotation": {"x": 0.0, "y": 0.0, "z": 0.0}, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "yaw_offset": 0.0, "tweaks": {}}
		]
	}
	var unit = CharacterBody3D.new()
	unit.set_script(BattleUnitScript)
	root.add_child(unit)
	unit.setup(bp, 0, bp_manager)

	var repair_scripted = false
	var drone_scripted = false
	for child in unit.hull_node.get_children():
		if not child.has_meta("module_data"): continue
		var data = child.get_meta("module_data")
		if data.type_id == "repair_array" and "targets_allies" in child:
			repair_scripted = true
		if data.type_id == "drone_carrier" and "fire_range" in child:
			drone_scripted = true

	unit.queue_free()
	bp_manager.queue_free()

	if not repair_scripted:
		print("  [FAIL] repair_array should get auto_weapon.gd attached through the real setup() pipeline, not just in synthetic tests")
		return false
	if not drone_scripted:
		print("  [FAIL] drone_carrier should get auto_weapon.gd attached through the real setup() pipeline, not just in synthetic tests")
		return false

	print("  [PASS] repair_array and drone_carrier both receive auto_weapon.gd through the real spawn pipeline (battle_unit.gd/battlefield.gd/building.gd all use ModuleCatalog.needs_combat_script()).")
	return true

func test_facet_aware_kiting() -> bool:
	print("Running Test Suite: Facet-Aware Kiting - Repositions To Present Its Strongest Facet...")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var unit = CharacterBody3D.new()
	unit.set_script(BattleUnitScript)
	root.add_child(unit)
	unit.move_speed = 6.0
	unit.rotate_speed = 4.0
	unit.attack_range = 20.0
	unit.has_frame_built_weapon = false # turreted - kiting is only for these
	unit.global_transform = Transform3D.IDENTITY # facing -Z ("front")
	unit.global_position = Vector3.ZERO

	# Real hull_node with a reinforced RIGHT facet - front/left/back stay at
	# baseline (weaker). classify_facet's "right" normal is (1,0,0), not the
	# 180-degree-opposite of "front" - deliberately NOT reinforcing "back",
	# since a strongest-facet-is-back scenario degenerates to the same
	# heading a plain retreat would already produce and wouldn't actually
	# exercise the decoupled rotate-while-strafing behavior this test needs
	# to distinguish from the older plain-retreat kiting.
	var hull = Node3D.new()
	hull.name = "Hull"
	hull.set_meta("armor_material", "hardened_steel")
	hull.set_meta("armor_thickness", 1.0)
	unit.add_child(hull)
	unit.hull_node = hull

	var right_plate = Node3D.new()
	right_plate.set_meta("facet", "right")
	var plate_data = ModuleData.new()
	plate_data.type_id = "armor_plating"
	plate_data.category = "armor"
	plate_data.base_hp = 500.0
	right_plate.set_meta("module_data", plate_data)
	hull.add_child(right_plate)

	# Attacker directly in front (matches "front" facet's own normal,
	# (0,0,-1)) - "front" has no reinforcement, so it's tied-weakest and
	# selected deterministically (FACET_NORMALS iterates front first).
	var attacker = Node3D.new()
	root.add_child(attacker)
	attacker.global_position = Vector3(0, 0, -3)
	unit.attack_range = 20.0 # well outside 0.45x standoff (9.0), so distance(3) triggers kiting
	unit.order_attack(attacker)

	var extremes = unit._my_facet_extremes()
	if extremes.strongest != "right" or extremes.weakest != "front":
		print("  [FAIL] Setup sanity check failed - expected strongest=right/weakest=front, got ", extremes)
		unit.queue_free(); attacker.queue_free()
		return false

	var initial_dist = unit.global_position.distance_to(attacker.global_position)
	for i in range(50):
		unit._physics_process(0.05)
		# No floor collider in this synthetic test, so is_on_floor() is
		# always false and gravity would free-fall the unit indefinitely,
		# contaminating the facet math with a huge Y offset that never
		# happens in a real level (which always has a floor). Keep it
		# grounded, same as move_and_slide() would with a real floor.
		unit.global_position.y = 0.0
		unit.velocity.y = 0.0
	var final_dist = unit.global_position.distance_to(attacker.global_position)

	if final_dist <= initial_dist + 0.001:
		print("  [FAIL] Facet-aware kiting should still increase distance from the attacker, went from ", initial_dist, " to ", final_dist)
		unit.queue_free(); attacker.queue_free()
		return false

	# The real behavioral difference from plain kiting: the facet now
	# facing the attacker should be the STRONGEST one, not still the
	# weakest one it started with.
	var final_local_dir = unit.global_transform.basis.inverse() * (attacker.global_position - unit.global_position)
	var final_facing_facet = ModuleCatalog.classify_facet(final_local_dir)
	if final_facing_facet != "right":
		print("  [FAIL] After repositioning, the unit's STRONGEST facet (right) should face the attacker, got '", final_facing_facet, "' facing instead")
		unit.queue_free(); attacker.queue_free()
		return false

	unit.queue_free()
	attacker.queue_free()
	print("  [PASS] A unit whose weakest facet initially faces the attacker repositions (rotate + strafe, not just retreat) to present its strongest facet instead, while still increasing distance.")
	return true

# Every locomotor carries its own top speed now, replacing the universal 18.0
# ceiling that used to be hardcoded into battle_unit.gd's speed clamp. Two
# things have to hold for that to mean anything: the ceiling must actually BIND
# (a design with surplus thrust cannot exceed it), and the roster must not all
# share one value - which is the failure mode the old clamp WAS.
func test_locomotor_base_top_speed_is_a_real_per_type_ceiling() -> bool:
	print("Running Test Suite: Locomotor Base Top Speed - Per-Type Ceiling...")
	var Drivetrain = preload("res://scripts/drivetrain.gd")

	# A featherweight hull with a huge thrust surplus: power_top_speed here is
	# far above every chassis rating, so whatever comes out IS the ceiling.
	var make_hull = func(locomotion_id: String, node_count: int) -> Node3D:
		var hull = Node3D.new()
		hull.set_meta("type_id", "light_hull")
		hull.set_meta("locomotion_type", locomotion_id)
		hull.set_meta("locomotion_settings", {})
		for _i in range(node_count):
			var child = Node3D.new()
			var d = ModuleData.new()
			d.type_id = locomotion_id
			d.category = "locomotion"
			d.base_weight = 1.0
			child.set_meta("module_data", d)
			hull.add_child(child)
		root.add_child(hull)
		return hull

	var seen: Dictionary = {}
	for loco_id in ["wheels", "tracked_treads", "legs", "fixed_wing_engine",
			"buoyant_envelope", "rocker_bogie", "hover_engine"]:
		var hull = make_hull.call(loco_id, 1)
		var dt = Drivetrain.analyze(hull)
		var rated = ModuleCatalog.get_base_top_speed(loco_id)
		# Surplus thrust must NOT push the design past its chassis rating.
		if dt["power_top_speed"] <= rated:
			print("  [FAIL] Test setup is wrong for ", loco_id, ": needs surplus thrust so the ceiling is what binds. power=", dt["power_top_speed"], " rated=", rated)
			hull.free()
			return false
		if abs(dt["top_speed"] - rated) > 0.001:
			print("  [FAIL] ", loco_id, " has far more thrust than it can use, so top_speed should equal its base_top_speed (", rated, "), got ", dt["top_speed"])
			hull.free()
			return false
		if not dt["capacity_limited"]:
			print("  [FAIL] ", loco_id, " is chassis-limited here and should report capacity_limited = true")
			hull.free()
			return false
		seen[loco_id] = rated
		hull.free()

	# The whole point of the change: these are not all the same number. The old
	# universal ceiling meant any light enough design on ANY locomotion
	# converged on 18.0.
	var distinct: Array = []
	for k in seen:
		if not distinct.has(seen[k]):
			distinct.append(seen[k])
	if distinct.size() < 6:
		print("  [FAIL] Base top speeds should be genuinely differentiated per locomotor; got only ", distinct.size(), " distinct values across ", seen.size(), " types: ", seen)
		return false

	# Direction checks on the archetypes, so a future retune cannot quietly
	# invert the roster's identity: a jet outruns wheels, wheels outrun legs,
	# and an airship is the slowest thing in the game.
	if not (ModuleCatalog.get_base_top_speed("fixed_wing_engine") > ModuleCatalog.get_base_top_speed("wheels")):
		print("  [FAIL] fixed_wing_engine should be faster than wheels.")
		return false
	if not (ModuleCatalog.get_base_top_speed("wheels") > ModuleCatalog.get_base_top_speed("tracked_treads")):
		print("  [FAIL] wheels should be faster than tracked_treads.")
		return false
	if not (ModuleCatalog.get_base_top_speed("tracked_treads") > ModuleCatalog.get_base_top_speed("legs")):
		print("  [FAIL] tracked_treads should be faster than legs.")
		return false
	if not (ModuleCatalog.get_base_top_speed("buoyant_envelope") < ModuleCatalog.get_base_top_speed("legs")):
		print("  [FAIL] buoyant_envelope should be the slowest of the archetypes.")
		return false

	# Every locomotion type in the catalog must declare one, or it silently
	# inherits the old universal ceiling and reads as the fastest thing in the
	# roster - the exact bug this suite exists to prevent recurring.
	var missing: Array = []
	for type_id in ModuleCatalog.get_catalog():
		var entry = ModuleCatalog.get_module_data(type_id)
		if entry.get("category", "") == "locomotion" and not entry.has("base_top_speed"):
			missing.append(type_id)
	if not missing.is_empty():
		print("  [FAIL] These locomotion types declare no base_top_speed and would inherit the generic default: ", missing)
		return false

	print("  [PASS] Each locomotor's base_top_speed is a real ceiling that surplus thrust cannot exceed, the roster's values are genuinely differentiated (not one shared number), the archetype ordering holds, and every locomotion type declares one.")
	return true

# The overload penalty has to be steep enough to feel (Chris: going over
# capacity "drops the top speed the finished unit can achieve rapidly") while
# still resolving across the range a player actually lands in. Pinning both
# ends matters: too shallow and the warning is noise, too steep and everything
# past ~1.5x capacity collapses onto the speed floor and the readout stops
# telling the player which way is out.
func test_overload_penalty_is_steep_and_monotonic() -> bool:
	print("Running Test Suite: Overload Penalty Curve...")
	var Drivetrain = preload("res://scripts/drivetrain.gd")

	var mult = func(ratio: float) -> float:
		return maxf(Drivetrain.OVERLOAD_FLOOR, pow(1.0 / ratio, Drivetrain.OVERLOAD_EXPONENT))

	# No penalty at or under capacity - a true no-op, not a small one.
	if not is_equal_approx(mult.call(1.0), 1.0):
		print("  [FAIL] At exactly capacity the multiplier should be 1.0, got ", mult.call(1.0))
		return false

	# "Rapidly": 10% over must cost at least 10% of top speed. The previous
	# linear-0.6 curve cost 6% here, which is what made it unfelt.
	var at_110 = mult.call(1.1)
	if at_110 > 0.90:
		print("  [FAIL] 10% overweight should cost at least 10% of top speed to register as a real tradeoff, got multiplier ", at_110)
		return false
	# ...but not so steep that a marginal design is already ruined.
	if at_110 < 0.70:
		print("  [FAIL] 10% overweight should not cost more than 30% of top speed - being marginally over is a tradeoff, not a write-off. Got multiplier ", at_110)
		return false

	# Strictly monotonic through the band a player can actually read, so the
	# Design Lab bar always moves the same direction as the mistake.
	var prev = 1.0
	for pct in [105, 110, 120, 130, 140, 150, 160]:
		var m = mult.call(float(pct) / 100.0)
		if m >= prev:
			print("  [FAIL] Penalty must increase monotonically with load; at ", pct, "% got ", m, " which is not worse than the previous ", prev)
			return false
		if m <= Drivetrain.OVERLOAD_FLOOR:
			print("  [FAIL] The curve bottoms out at ", pct, "% of capacity - too early. Everything past that point is indistinguishable, which is what made the 2.5 exponent unusable.")
			return false
		prev = m

	# Never zero: a unit frozen in place reads as a bug rather than a balance
	# outcome, however overloaded it is.
	if mult.call(50.0) < Drivetrain.OVERLOAD_FLOOR - 0.001:
		print("  [FAIL] The multiplier must never fall below OVERLOAD_FLOOR, got ", mult.call(50.0), " at 50x capacity")
		return false

	print("  [PASS] Overload costs >=10% of top speed at 10% over, increases monotonically without bottoming out inside the readable band, and never freezes a unit outright.")
	return true

# The mirror of the suite above. Running significantly under capacity is
# supposed to BUY something, and the two properties that make it a design
# decision rather than a free lunch are: nothing happens until you are properly
# light (or the "bonus" is universal and therefore invisible), and the payout
# flattens (or stripping a design to nothing is always the right answer).
func test_underload_bonus_has_a_deadzone_and_diminishing_returns() -> bool:
	print("Running Test Suite: Underload Speed Bonus Curve...")
	var Drivetrain = preload("res://scripts/drivetrain.gd")

	var mult = func(ratio: float) -> float:
		if ratio >= Drivetrain.UNDERLOAD_THRESHOLD:
			return 1.0
		var slack: float = clampf((Drivetrain.UNDERLOAD_THRESHOLD - ratio) / Drivetrain.UNDERLOAD_THRESHOLD, 0.0, 1.0)
		return 1.0 + (Drivetrain.UNDERLOAD_CEILING - 1.0) * pow(slack, Drivetrain.UNDERLOAD_EXPONENT)

	# The deadzone. A design that is merely legal is not "light", and paying it
	# a bonus would mean every non-overloaded design in the game runs above its
	# rated speed - which makes the rating a lie and the bonus unnoticeable.
	for ratio in [1.0, 0.95, 0.85, Drivetrain.UNDERLOAD_THRESHOLD]:
		if not is_equal_approx(mult.call(ratio), 1.0):
			print("  [FAIL] At load ", ratio, " (at or above the ", Drivetrain.UNDERLOAD_THRESHOLD, " threshold) there should be no bonus, got ", mult.call(ratio))
			return false

	# It must actually pay inside the band, or the deadzone swallowed it.
	var at_half = mult.call(0.5)
	if at_half <= 1.02:
		print("  [FAIL] At half capacity the bonus should be worth reading; got ", at_half)
		return false

	# Strictly monotonic - lighter is always at least as fast, never worse.
	var prev = 1.0
	for pct in [70, 60, 50, 40, 30, 20, 10, 0]:
		var m = mult.call(float(pct) / 100.0)
		if m < prev:
			print("  [FAIL] Bonus must not decrease as the design gets lighter; at ", pct, "% load got ", m, " against ", prev, " at the heavier step")
			return false
		prev = m

	# Capped, and capped where the constant says. An uncapped bonus multiplies a
	# speed that is ALREADY helped by low mass through thrust/weight.
	if mult.call(0.0) > Drivetrain.UNDERLOAD_CEILING + 0.0001:
		print("  [FAIL] An empty design must not exceed UNDERLOAD_CEILING (", Drivetrain.UNDERLOAD_CEILING, "), got ", mult.call(0.0))
		return false

	# Concave: the first slice of slack is worth more than the last. This is the
	# property that stops "shed everything" being the universal answer, and it is
	# the deliberate asymmetry against OVERLOAD_EXPONENT, which is convex.
	var first_half_gain = mult.call(0.375) - mult.call(Drivetrain.UNDERLOAD_THRESHOLD)
	var second_half_gain = mult.call(0.0) - mult.call(0.375)
	if second_half_gain >= first_half_gain:
		print("  [FAIL] Returns should diminish: the first half of the slack band gained ", first_half_gain, " but the second gained ", second_half_gain, ". A linear or convex payout makes stripping a design strictly dominant.")
		return false
	if Drivetrain.UNDERLOAD_EXPONENT >= 1.0:
		print("  [FAIL] UNDERLOAD_EXPONENT must be below 1.0 for the payout to be concave; got ", Drivetrain.UNDERLOAD_EXPONENT)
		return false

	print("  [PASS] Underload pays nothing until ", Drivetrain.UNDERLOAD_THRESHOLD, " load, then rises monotonically with diminishing returns to a hard ceiling of x", Drivetrain.UNDERLOAD_CEILING, ".")
	return true


# The curve above is arithmetic. This one checks it is actually WIRED: that a
# real analysis reports the keys, that they only fire on the correct side of the
# threshold, and - the part most likely to regress - that the bonus survives the
# chassis cap. Most of the roster is chassis-limited, so folding the bonus in
# underneath min(power, chassis) would silently delete it for exactly the
# designs it exists to reward.
func test_underload_bonus_is_wired_through_a_real_analysis() -> bool:
	print("Running Test Suite: Underload Bonus - Wired Into Drivetrain.analyze...")
	var Drivetrain = preload("res://scripts/drivetrain.gd")

	# Every key must exist on the no-locomotion early return too, or a consumer
	# reading dt["underload_multiplier"] crashes on an empty hull - which is the
	# state the Design Lab starts in.
	var bare: Dictionary = Drivetrain.analyze(null)
	for key in ["underload_multiplier", "is_underloaded", "speed_gained_from_underload"]:
		if not bare.has(key):
			print("  [FAIL] The no-locomotion early return is missing '", key, "'. clear_hull() -> update_stats(null) reads this dictionary.")
			return false
	if bare["is_underloaded"]:
		print("  [FAIL] A design with no locomotion has no capacity to be under; is_underloaded should be false.")
		return false

	# A featherweight hull on wheels: masses of surplus capacity, so this is
	# deep inside the bonus band.
	var make_hull = func(loco_weight: float, cargo: Array) -> Node3D:
		var hull = Node3D.new()
		hull.set_meta("type_id", "light_hull")
		hull.set_meta("locomotion_type", "wheels")
		hull.set_meta("locomotion_settings", {})
		var child = Node3D.new()
		var d = ModuleData.new()
		d.type_id = "wheels"
		d.category = "locomotion"
		d.base_weight = loco_weight
		child.set_meta("module_data", d)
		hull.add_child(child)
		for w in cargo:
			var c = Node3D.new()
			var cd = ModuleData.new()
			cd.type_id = "heavy_cannon"
			cd.base_weight = w
			c.set_meta("module_data", cd)
			hull.add_child(c)
		root.add_child(hull)
		return hull

	var light = make_hull.call(1.0, [])
	var dt_light: Dictionary = Drivetrain.analyze(light)
	if not dt_light["is_underloaded"]:
		print("  [FAIL] A bare light hull on wheels sits at load ", dt_light["load_ratio"], " and should be flagged underloaded.")
		light.free()
		return false
	if dt_light["move_speed"] <= dt_light["top_speed"]:
		print("  [FAIL] The bonus did not survive the chassis cap: move_speed ", dt_light["move_speed"], " should exceed top_speed ", dt_light["top_speed"], ". Applying it under min(power, chassis) deletes it for every chassis-limited design.")
		light.free()
		return false
	if dt_light["speed_gained_from_underload"] <= 0.0:
		print("  [FAIL] speed_gained_from_underload should be positive for an underloaded design, got ", dt_light["speed_gained_from_underload"])
		light.free()
		return false
	var light_speed: float = dt_light["move_speed"]
	light.free()

	# The same running gear, loaded up past the threshold. Its combat speed must
	# be lower - that is the whole decision the bonus creates.
	var loaded = make_hull.call(1.0, [900.0])
	var dt_loaded: Dictionary = Drivetrain.analyze(loaded)
	if dt_loaded["load_ratio"] < Drivetrain.UNDERLOAD_THRESHOLD:
		print("  [FAIL] Test setup is wrong: the loaded hull is at ", dt_loaded["load_ratio"], " and needs to be past the ", Drivetrain.UNDERLOAD_THRESHOLD, " threshold to be a contrast.")
		loaded.free()
		return false
	if dt_loaded["is_underloaded"]:
		print("  [FAIL] A design at load ", dt_loaded["load_ratio"], " is past the threshold and must not be flagged underloaded.")
		loaded.free()
		return false
	if is_equal_approx(dt_loaded["underload_multiplier"], 1.0) == false:
		print("  [FAIL] Past the threshold the multiplier must be exactly 1.0, got ", dt_loaded["underload_multiplier"])
		loaded.free()
		return false
	if dt_loaded["move_speed"] >= light_speed:
		print("  [FAIL] The loaded design (", dt_loaded["move_speed"], ") should be slower than the light one (", light_speed, ") on identical running gear.")
		loaded.free()
		return false
	loaded.free()

	print("  [PASS] Underload is reported by analyze(), fires only below the threshold, and lifts move_speed above the chassis cap where the bonus would otherwise be invisible.")
	return true


func test_napalm_mortar_tube_points_upward() -> bool:
	print("Running Test Suite: Napalm Mortar - Tube Elevates Instead Of Firing Into The Deck...")
	var VisualBuilder = preload("res://scripts/visual_builder.gd")
	var ok = true

	var holder = Node3D.new()
	root.add_child(holder)
	var cd = ModuleCatalog.get_module_data("napalm_mortar")
	VisualBuilder.build_visual("napalm_mortar", holder, cd.size, cd.color, {})

	var pivot = holder.get_node_or_null("ElevationPivot")
	if pivot == null:
		print("  [FAIL] No ElevationPivot on the napalm mortar")
		ok = false
	else:
		# The elevation was authored as deg_to_rad(-55.0) while artillery and
		# the mortar array both use a POSITIVE angle. Parts are built with the
		# bore along -Z and a positive X rotation pitches -Z up, so the
		# negative sign pitched the whole assembly nose-down through the deck
		# and put the flared muzzle underneath the breech - which is what read
		# as the barrel being fitted upside down.
		if pivot.rotation.x <= 0.0:
			print("  [FAIL] ElevationPivot pitches DOWN (%.1f deg) - the tube fires into the deck" % rad_to_deg(pivot.rotation.x))
			ok = false

		# Assert the actual geometry, not just the sign: the muzzle end of the
		# tube has to end up above the trunnion it swings on.
		var muzzle_world = pivot.to_global(Vector3(0, 0, -0.55))
		var breech_world = pivot.to_global(Vector3(0, 0, 0.05))
		if muzzle_world.y <= breech_world.y:
			print("  [FAIL] Muzzle (y=%.2f) sits at or below the breech (y=%.2f)" % [muzzle_world.y, breech_world.y])
			ok = false

	holder.free()
	if not ok:
		return false
	print("  [PASS] The napalm mortar's tube elevates, with the muzzle above the breech.")
	return true

func test_idle_units_auto_engage_sighted_enemies() -> bool:
	print("Running Test Suite: Idle/Moving Units Auto-Engage Enemies In Sight...")
	# Previously a unit only ever got an ATTACK order from an explicit
	# external command (player right-click, or the enemy AI's wave-launch
	# always targeting the player HQ specifically) - there was no logic for
	# a unit to notice a nearby hostile on its own. An idle unit, or one
	# marching toward an unrelated MOVE order, would walk right past an
	# enemy, only getting whatever passive fire its own weapons' narrow
	# traverse arcs happened to land, never actually maneuvering to fight.
	var bp_manager = preload("res://scripts/blueprint_manager.gd").new()
	root.add_child(bp_manager)
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var bp = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "wheels", "settings": {"count": 4}},
		"modules": [
			{"type_id": "wheels", "position": {"x": 0, "y": 0, "z": 0}, "normal": {"x": 0, "y": 1, "z": 0}},
			{"type_id": "basic_cannon", "position": {"x": 0.0, "y": 1.4, "z": 0.0}, "rotation": {"x": 0.0, "y": 0.0, "z": 0.0}, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "yaw_offset": 0.0, "tweaks": {}}
		]
	}

	var idle_unit = CharacterBody3D.new()
	idle_unit.set_script(BattleUnitScript)
	root.add_child(idle_unit)
	idle_unit.setup(bp, 0, bp_manager)
	idle_unit.global_position = Vector3(0, 1, 0)

	var moving_unit = CharacterBody3D.new()
	moving_unit.set_script(BattleUnitScript)
	root.add_child(moving_unit)
	moving_unit.setup(bp, 0, bp_manager)
	moving_unit.global_position = Vector3(30, 1, 30)
	moving_unit.order_move(Vector3(30, 1, 0)) # heading somewhere unrelated

	var enemy = CharacterBody3D.new()
	enemy.set_script(BattleUnitScript)
	root.add_child(enemy)
	enemy.setup(bp, 1, bp_manager)
	# Within the idle unit's vision_range, well outside the moving unit's.
	enemy.global_position = Vector3(0, 1, min(idle_unit.vision_range * 0.5, 10.0))

	if idle_unit.vision_range <= 0.0:
		print("  [FAIL] Test assumption broken: medium_hull should have a real vision_range.")
		idle_unit.queue_free(); moving_unit.queue_free(); enemy.queue_free(); bp_manager.queue_free()
		return false

	# Advance past both the idle-before-engaging grace period
	# (IDLE_BEFORE_AUTO_ENGAGE, 1.5s - a move order is now inviolable, only
	# an idle unit starts hunting on its own, and only after sitting idle
	# that long) and the throttled scan interval on top of it (0.5s).
	for i in range(200):
		idle_unit._physics_process(0.05)
		moving_unit._physics_process(0.05)
		await tree.process_frame

	var idle_engaged = idle_unit.order == idle_unit.OrderType.ATTACK and idle_unit.attack_target == enemy
	var moving_still_moving = moving_unit.order == moving_unit.OrderType.MOVE

	idle_unit.queue_free()
	moving_unit.queue_free()
	enemy.queue_free()
	bp_manager.queue_free()

	if not idle_engaged:
		print("  [FAIL] An idle unit with an enemy within vision_range should have auto-engaged it, got order=", idle_unit.order, " attack_target=", idle_unit.attack_target)
		return false
	if not moving_still_moving:
		print("  [FAIL] A unit with no enemy anywhere near its position should keep its existing MOVE order (auto-engage shouldn't fire on nothing), got order=", moving_unit.order)
		return false

	print("  [PASS] An idle unit with a hostile within vision_range automatically switches to attacking it, without disturbing a unit that has nothing nearby to engage.")
	return true

func test_audio_system() -> bool:
	print("Running Test Suite: Audio System, Sound Effects & Ambient Music Assets...")
	var sfx_list = [
		"sfx_click.wav", "sfx_hover.wav", "sfx_error.wav", "sfx_select.wav", "sfx_place.wav",
		"sfx_cannon.wav", "sfx_machine_gun.wav", "sfx_laser.wav", "sfx_missile.wav",
		"sfx_explosion.wav", "sfx_hit.wav", "sfx_harvest.wav", "sfx_construct.wav",
		"sfx_victory.wav", "sfx_defeat.wav"
	]
	for sfx in sfx_list:
		var path = "res://assets/audio/sfx/" + sfx
		if not ResourceLoader.exists(path):
			print("  [FAIL] Missing SFX audio file: ", path)
			return false
	if not ResourceLoader.exists("res://assets/audio/music/music_main_theme.wav"):
		print("  [FAIL] Missing ambient music track: res://assets/audio/music/music_main_theme.wav")
		return false
	if not ResourceLoader.exists("res://scripts/audio_manager.gd"):
		print("  [FAIL] Missing res://scripts/audio_manager.gd")
		return false

	print("  [PASS] Audio System: All 15 procedural SFX files, ambient music track loop, and AudioManager autoload validated clean.")
	return true

# Guards against the class of bug DECISIONS_NEEDED.md already logged once
# (a parts_menu.gd parse error would have broken the Design Lab while the
# rest of this suite printed ALL TESTS PASSED) and that actually shipped
# for real in hull_builder.gd - a scene's attached script can have a parse
# error that no other test here happens to exercise. Uses GDScript.reload()
# directly (the same entry point Godot's own "at: GDScript::reload" error
# messages cite) rather than instantiating each scene, so a broken script
# is caught as a real Error return code instead of a swallowed engine log line.
func test_every_scene_script_parses_cleanly() -> bool:
	print("Running Test Suite: Every Scene-Attached Script Parses Cleanly...")
	var dir = DirAccess.open("res://scenes")
	if not dir:
		print("  [FAIL] Could not open res://scenes")
		return false

	var script_paths: Dictionary = {}
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if fname.ends_with(".tscn"):
			var text = FileAccess.get_file_as_string("res://scenes/" + fname)
			for line in text.split("\n"):
				if line.begins_with("[ext_resource") and line.find("type=\"Script\"") != -1:
					var path_start = line.find("path=\"")
					if path_start != -1:
						var start = path_start + 6
						var end = line.find("\"", start)
						if end != -1:
							script_paths[line.substr(start, end - start)] = true
		fname = dir.get_next()
	dir.list_dir_end()

	if script_paths.is_empty():
		print("  [FAIL] No scene-attached scripts discovered - the scan itself is broken.")
		return false

	var all_ok = true
	for path in script_paths.keys():
		if not FileAccess.file_exists(path):
			print("  [FAIL] %s is referenced by a scene but does not exist on disk." % path)
			all_ok = false
			continue
		var gd = GDScript.new()
		gd.source_code = FileAccess.get_file_as_string(path)
		var err = gd.reload()
		if err != OK:
			print("  [FAIL] %s failed to parse (Error code %d) - see the SCRIPT ERROR line above for the exact line/reason." % [path, err])
			all_ok = false

	if all_ok:
		print("  [PASS] All %d scene-attached scripts (across every .tscn under res://scenes) parse cleanly." % script_paths.size())
	return all_ok

