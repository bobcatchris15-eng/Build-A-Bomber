extends SceneTree
# Headless automated testing suite for Build-A-Bomber.
# Run with: ./Godot_v4.3-stable_win64_console.exe --headless --script run_tests.gd
#
# Covers:
# 1. Stats Calculations (Faction multipliers, thickness, and materials)
# 2. Clipping & Collision bounds checking
# 3. Damage Model Thresholds & Reduction mitigation
# 4. Headless Battle Tick simulation

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const ModuleData = preload("res://scripts/module_data.gd")
const HullLoader = preload("res://scripts/hull_loader.gd")
const PlayerVehicleScript = preload("res://scripts/player_vehicle.gd")
const TargetDummyScript = preload("res://scripts/target_dummy.gd")
const IncomingMissileScript = preload("res://scripts/incoming_missile.gd")
const DamageResolverScript = preload("res://scripts/damage_resolver.gd")

func _init():
	print("\n==============================================")
	print("    BUILD-A-BOMBER HEADLESS TEST RUNNER")
	print("==============================================\n")
	
	var success = true
	
	# Run tests sequentially
	success = success and await test_stats_calculations()
	success = success and await test_clipping_detection()
	success = success and await test_damage_mitigation()
	success = success and await test_traverse_limit()
	success = success and await test_subsystem_stripping()
	success = success and await test_rotation_popup_and_deforms()
	success = success and await test_sensor_mast_tweak_and_proportions()
	success = success and await test_no_dead_tweaks()
	success = success and await test_designer_camera_pan()
	success = success and await test_locomotion_tweak_parity()
	success = success and await test_new_locomotion_types_spawn_and_differentiate()
	success = success and await test_ship_hull_locomotion_mount_gap_fix()
	success = success and await test_undo_redo()
	success = success and await test_foundation_design_lab_parity()
	success = success and await test_fortress_wall_foundation_spawns_correctly()
	success = success and await test_design_to_battle_integration()
	success = success and await test_firing_arc_visualization()
	success = success and await test_free_rotation_ring()
	success = success and await test_armor_module_facet_fitting()
	success = success and await test_armor_module_combat_bonus()
	success = success and await test_face_based_weapon_mounting()
	success = success and await test_angled_pintle_mount()
	success = success and await test_centerline_placement_does_not_self_mirror()
	success = success and await test_hull_nose_taper()
	success = success and await test_directional_armor_facet_resolution()
	success = success and await test_per_module_armor_material()
	success = success and await test_sloped_armor_angle_of_incidence()
	success = success and await test_ai_flanking_targets_weakest_facet()
	success = success and await test_trait_system_composability()
	success = success and await test_fixed_wing_and_naval_movement()
	success = success and await test_frame_built_whole_vehicle_aim()
	success = success and await test_ranged_unit_kiting()
	success = success and await test_enemy_roster_new_movement_archetypes()
	success = success and await test_ui_no_overflow_or_offscreen()
	success = success and await test_ui_audit_has_real_teeth()
	success = success and await test_headless_combat_simulation()
	success = success and await test_team_targeting()
	success = success and await test_blueprint_cost_and_rosters()
	success = success and await test_skirmish_economy_and_production()
	success = success and await test_match_config_overrides_apply_to_skirmish()
	success = success and await test_faction_catalog_and_hull_material()
	success = success and await test_brushed_aluminum_ui_theme()
	success = success and await test_new_faction_mechanical_bonuses()
	success = success and await test_hull_greebles()
	success = success and await test_hull_decals()
	success = success and await test_size_tiered_manufactories()
	success = success and await test_win_condition()
	success = success and await test_energy_pool_and_generators()
	success = success and await test_repair_array_heals_allies_only()
	success = success and await test_drone_carrier_spawns_real_drones()
	success = success and await test_energy_weapons_cost_and_drain()
	success = success and await test_logistics_sharing_boosts_allies()
	success = success and await test_support_modules_get_combat_script_in_real_spawn()
	success = success and await test_build_legality_gate()
	success = success and await test_balance_report_covers_every_catalog_entry()
	success = success and await test_screenshot_diff_tolerance()
	success = success and await test_no_energy_deficit_at_match_start()
	success = success and await test_energy_damage_class_reclassification()
	success = success and await test_facet_aware_kiting()
	success = success and await test_vision_range_computation()
	success = success and await test_fog_of_war_hides_reveals_and_never_hides_own_team()
	success = success and await test_fog_hidden_excluded_from_targeting()
	success = success and await test_vision_blocked_by_real_obstacle_cover()
	success = success and await test_navmesh_routes_around_the_lake()
	success = success and await test_ground_and_naval_units_use_different_nav_maps()
	success = success and await test_hull_draught_routes_to_correct_water_nav_map()
	success = success and await test_unit_order_move_actually_navigates_around_the_lake()
	success = success and await test_terrain_builder_pure_functions()
	success = success and await test_terrain_builder_navmesh_ramp_connects()
	success = success and await test_bridges_carve_a_real_ground_crossing_through_water()
	success = success and await test_building_obstacle_spawns_taller_real_cover_than_rock_cluster()
	success = success and await test_amphibious_navmesh_crosses_water()
	success = success and await test_deep_water_navmesh_blocks_shallow_draught_hulls()
	success = success and await test_elevation_combat_and_vision_bonus()
	success = success and await test_build_placement_rejects_water_and_obstacles()
	success = success and await test_map_open_plains_smoke()
	success = success and await test_map_lake_crossing_smoke()
	success = success and await test_map_highland_chokepoint_smoke()
	success = success and await test_map_coastal_strand_smoke()
	success = success and await test_map_twin_bridges_smoke()
	success = success and await test_map_twin_summits_smoke()
	success = success and await test_map_close_quarters_smoke()
	success = success and await test_map_urban_sprawl_smoke()
	success = success and await test_weapon_traverse_and_range_differentiation()
	success = success and await test_weight_vs_locomotion_capacity_penalty()
	success = success and await test_mobility_addon_modules_boost_capacity_and_thrust()
	success = success and await test_terrain_types_differentiate_locomotion()
	success = success and await test_locomotion_tweaks_have_real_visual_and_stat_effects()
	success = success and await test_ornithopter_wing_spawns_flaps_and_flies()
	success = success and await test_rhomboid_treads_spawns_and_differentiates_from_tracked_treads()
	success = success and await test_omni_wheels_can_strafe_sideways_without_turning()
	success = success and await test_hull_modding_loader_scan_and_validation()
	success = success and await test_hull_modding_parts_menu_two_buckets()
	success = success and await test_hull_modding_hard_fail_on_unknown_hull()
	success = success and await test_hull_modding_mod_hull_placeable()
	success = success and await test_weapon_los_blocked_by_cover_and_skirmish_bug_fixes()

	print("\n==============================================")
	if success:
		print("    ALL AUTOMATED TESTS PASSED SUCCESSFULLY!")
		print("==============================================\n")
		quit(0)
	else:
		print("    TEST SUITE FAILED!")
		print("==============================================\n")
		quit(1)

func test_stats_calculations() -> bool:
	print("Running Test Suite 1: Stats Calculations...")
	
	# Instantiate MainLab scene to load UI and dependencies
	var lab_scene = preload("res://scenes/MainLab.tscn").instantiate()
	root.add_child(lab_scene)
	
	# Wait a frame for scene setup
	await process_frame
	
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
	
	# Expected Calculations:
	# Base Module HP = 100.0
	# HP: HP * hp_mult (1.0) * thickness (1.5) = 150.0
	var expected_hp = 150.0
	
	# Base Module Weight = 80.0
	# Weight: Weight * wt_mult (1.0) * thickness (1.5) * faction_armor_weight_reduction (0.8) = 96.0
	var expected_weight = 96.0
	
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

func test_clipping_detection() -> bool:
	print("Running Test Suite 2: Clipping & Collision Checking...")
	
	# Instantiate MainLab
	var lab_scene = preload("res://scenes/MainLab.tscn").instantiate()
	root.add_child(lab_scene)
	await process_frame
	
	var hull = lab_scene.get_node_or_null("Hull")
	if not hull:
		print("  [FAIL] Hull node not found in MainLab.")
		lab_scene.queue_free()
		return false
		
	# Clear default children of hull (if any)
	for child in hull.get_children():
		if child is StaticBody3D or child is MeshInstance3D: continue
		child.queue_free()
		
	# Add two module nodes close to each other (clipping)
	var mod1 = Node3D.new()
	var d1 = ModuleData.new()
	d1.type_id = "basic_cannon"
	mod1.set_meta("module_data", d1)
	mod1.position = Vector3(0.1, 0.5, 0.0) # Center
	hull.add_child(mod1)
	
	var mod2 = Node3D.new()
	var d2 = ModuleData.new()
	d2.type_id = "heavy_machine_gun"
	mod2.set_meta("module_data", d2)
	mod2.position = Vector3(-0.1, 0.5, 0.0) # Very close to mod1
	hull.add_child(mod2)
	
	# Trigger check
	lab_scene.check_all_clipping()
	var clip_close = lab_scene.clipping_detected
	
	# Move them far apart (no clipping)
	mod2.position = Vector3(8.0, 0.5, 0.0)
	lab_scene.check_all_clipping()
	var clip_far = lab_scene.clipping_detected
	
	# Clean up
	lab_scene.queue_free()
	
	if clip_close == true and clip_far == false:
		print("  [PASS] Clipping checks accurately flag proximity overlaps.")
		return true
	else:
		print("  [FAIL] Clipping detection logic failed. Overlap clip: ", clip_close, " (expected true), Far clip: ", clip_far, " (expected false)")
		return false

func test_damage_mitigation() -> bool:
	print("Running Test Suite 3: Damage Model Mitigation...")
	
	# Instantiate character body player vehicle
	var player = CharacterBody3D.new()
	player.set_script(PlayerVehicleScript)
	player._ready()
	root.add_child(player)
	
	# Add a mock Hull child node inside the player to hold armor metadata
	var mock_hull = Node3D.new()
	mock_hull.name = "Hull"
	mock_hull.set_meta("armor_material", "reactive_armor") # Explosive reduction: 0.4, Base threshold: 30
	mock_hull.set_meta("armor_thickness", 2.0) # Total threshold: 30 * 2 = 60
	player.add_child(mock_hull)
	
	player.max_hp = 400.0
	player.hp = 400.0
	player.is_dead = false
	
	# 1. Test Damage below threshold (Should be negated, HP remains 400)
	player.take_damage(50.0, "explosive")
	var hp_after_negated = player.hp
	
	# 2. Test Damage above threshold (Should apply reduction: 100 * 0.4 = 40 damage, HP becomes 360)
	player.take_damage(100.0, "explosive")
	var hp_after_applied = player.hp
	
	# Clean up
	player.queue_free()
	
	var pass_negated = abs(hp_after_negated - 400.0) < 0.01
	var pass_applied = abs(hp_after_applied - 360.0) < 0.01
	
	if not pass_negated:
		print("  [FAIL] Damage below threshold was not negated. HP: ", hp_after_negated)
	if not pass_applied:
		print("  [FAIL] Damage above threshold applied incorrectly. HP: ", hp_after_applied, " (expected 360.0)")
		
	if pass_negated and pass_applied:
		print("  [PASS] Threshold and reduction mathematical models verify correctly.")
		return true
	return false

func test_headless_combat_simulation() -> bool:
	print("Running Test Suite 4: Headless Combat Simulation Tick Loop...")
	
	# We simulate a dynamic combat scenario headlessly
	var battlefield_scene = preload("res://scenes/Battlefield.tscn").instantiate()
	root.add_child(battlefield_scene)
	current_scene = battlefield_scene
	await process_frame
	
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
		await process_frame
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
	
	# Clean up
	battlefield_scene.queue_free()
	
	if hit_detected and total_end < total_initial:
		print("  [PASS] Headless combat simulation ticks successfully. Player total HP reduced from ", total_initial, " to ", total_end)
		return true
	else:
		print("  [FAIL] Combat tick simulation failed to hit or apply damage. Hit: ", hit_detected, " Start HP: ", total_initial, " End HP: ", total_end)
		return false

func test_traverse_limit() -> bool:
	print("Running Test Suite 5: Firing Arc & Traverse Limits...")
	
	# Set up a mock weapon with auto_weapon script
	var mock_parent = Node3D.new()
	var weapon = Node3D.new()
	var w_script = load("res://scripts/auto_weapon.gd")
	weapon.set_script(w_script)
	mock_parent.add_child(weapon)
	root.add_child(mock_parent)
	
	# Configure metadata
	var w_data = ModuleData.new()
	w_data.type_id = "mortar_array" # Limit: 30 degrees (PI / 6 = 0.523 rad)
	w_data.base_weight = 90.0
	w_data.base_dps = 50.0
	weapon.set_meta("module_data", w_data)
	
	weapon._ready()
	
	# Mock resting forward
	var resting_forward = mock_parent.global_transform.basis * weapon.resting_transform.basis * Vector3.FORWARD
	
	# Target 1: 15 degrees angle (inside arc)
	var dir_inside = resting_forward.rotated(Vector3.UP, 0.26) # 15 deg
	var target_inside = preload("res://scenes/TargetDummy.tscn").instantiate()
	target_inside.name = "TargetInside"
	target_inside.add_to_group("targets")
	mock_parent.add_child(target_inside)
	target_inside.global_position = weapon.global_position + dir_inside * 5.0
	
	# Let tracking check
	weapon._find_nearest_target()
	var tracked_inside = weapon.target == target_inside
	
	# Clean target inside
	weapon.target = null
	target_inside.queue_free()
	
	# Target 2: 45 degrees angle (outside arc)
	var dir_outside = resting_forward.rotated(Vector3.UP, 0.78) # 45 deg
	var target_outside = preload("res://scenes/TargetDummy.tscn").instantiate()
	target_outside.name = "TargetOutside"
	target_outside.add_to_group("targets")
	mock_parent.add_child(target_outside)
	target_outside.global_position = weapon.global_position + dir_outside * 5.0
	
	# Let tracking check
	weapon._find_nearest_target()
	var tracked_outside = weapon.target == target_outside
	
	# Clean up
	mock_parent.queue_free()
	
	if tracked_inside == true and tracked_outside == false:
		print("  [PASS] Firing arc limit successfully filters out-of-range targets.")
		return true
	else:
		print("  [FAIL] Firing arc filtering failed. Tracked inside: ", tracked_inside, " (expected true), Tracked outside: ", tracked_outside, " (expected false)")
		return false

func test_subsystem_stripping() -> bool:
	print("Running Test Suite 6: Subsystem Damage & Stripping...")
	
	# Create player vehicle
	var player = CharacterBody3D.new()
	player.set_script(PlayerVehicleScript)
	player._ready()
	player.max_hp = 10000.0
	player.hp = 10000.0
	root.add_child(player)
	
	# Hull
	var mock_hull = Node3D.new()
	mock_hull.name = "Hull"
	mock_hull.set_meta("armor_material", "hardened_steel")
	mock_hull.set_meta("armor_thickness", 1.0)
	player.add_child(mock_hull)
	
	# Weapon module with health
	var mock_weapon = Node3D.new()
	var w_data = ModuleData.new()
	w_data.type_id = "basic_cannon"
	w_data.base_hp = 100.0
	mock_weapon.set_meta("module_data", w_data)
	mock_weapon.set_meta("current_hp", 100.0)
	mock_hull.add_child(mock_weapon)
	
	# Hit in a loop until we trigger the 35% subsystem chance
	var module_hp_decreased = false
	var ticks = 0
	while ticks < 20:
		player.take_damage(50.0, "kinetic")
		var hp = mock_weapon.get_meta("current_hp") if is_instance_valid(mock_weapon) else 0.0
		if hp < 100.0:
			module_hp_decreased = true
			break
		ticks += 1
		
	# Now let's apply enough damage to strip it completely
	ticks = 0
	while ticks < 20 and is_instance_valid(mock_weapon):
		player.take_damage(200.0, "kinetic")
		ticks += 1
		
	# Let queue_free resolve
	await process_frame
	var module_destroyed = not is_instance_valid(mock_weapon)
	
	# Clean up
	player.queue_free()
	
	if module_hp_decreased and module_destroyed:
		print("  [PASS] Subsystem hit and module stripping verify successfully.")
		return true
	else:
		print("  [FAIL] Subsystem stripping failed. HP decreased: ", module_hp_decreased, " Destroyed: ", module_destroyed)
		return false

func test_rotation_popup_and_deforms() -> bool:
	print("Running Test Suite 7: Rotation, Popups, and Mesh Deformations...")
	var hull = StaticBody3D.new()
	hull.name = "Hull"
	root.add_child(hull)
	
	# Instantiate Placer script
	var placer = Node3D.new()
	placer.set_script(preload("res://scripts/module_placer.gd"))
	placer.hull = hull
	root.add_child(placer)
	
	# Instantiate actual UI scene
	var stat_ui = load("res://scenes/UI_StatBlock.tscn").instantiate()
	root.add_child(stat_ui)
	
	# Wait for frames
	await process_frame
	await process_frame
	
	# Place module
	placer._place_weapon_from_ui("basic_cannon", Vector3(1.0, 0.5, 0.0), Vector3.UP)
	var mod = null
	for child in hull.get_children():
		if child.has_meta("module_data") and child.position.x > 0.0:
			mod = child
			break
			
	if not mod:
		print("  [FAIL] Failed to place cannon")
		stat_ui.queue_free()
		placer.queue_free()
		hull.queue_free()
		return false
		
	var mirror = mod.get_meta("mirrored_counterpart")
	if not mirror:
		print("  [FAIL] Failed to mirror cannon")
		stat_ui.queue_free()
		placer.queue_free()
		hull.queue_free()
		return false
		
	# Select and show popup
	placer._select_module(mod)
	stat_ui.on_module_selected(mod)
	
	if not stat_ui.popup_panel.visible:
		print("  [FAIL] stats popup panel not visible")
		stat_ui.queue_free()
		placer.queue_free()
		hull.queue_free()
		return false
		
	# Rotate!
	placer.rotate_selected_module()
	var rotated_yaw = mod.get_meta("yaw_offset", 0.0)
	if abs(rotated_yaw - PI/2.0) > 0.01 or abs(mirror.get_meta("yaw_offset", 0.0) - (-PI/2.0)) > 0.01:
		print("  [FAIL] Rotation offset incorrect. Primary: ", rotated_yaw, " Mirror: ", mirror.get_meta("yaw_offset", 0.0))
		stat_ui.queue_free()
		placer.queue_free()
		hull.queue_free()
		return false
		
	# Deformation
	var data = mod.get_meta("module_data")
	data.tweaks["caliber"] = 1.8
	data.tweaks["barrel_length"] = 1.5
	var VisualBuilder = preload("res://scripts/visual_builder.gd")
	VisualBuilder.rebuild_visual(mod)
	
	var children = mod.get_children().filter(func(c): return c is MeshInstance3D)
	if children.size() <= 1:
		print("  [FAIL] Cannon mesh children missing")
		stat_ui.queue_free()
		placer.queue_free()
		hull.queue_free()
		return false
		
	var barrel = children[1]
	if abs(barrel.scale.x - 1.8) > 0.01 or abs(barrel.scale.y - 1.5) > 0.01:
		print("  [FAIL] barrel scaling deformation incorrect: ", barrel.scale)
		stat_ui.queue_free()
		placer.queue_free()
		hull.queue_free()
		return false
		
	# Clean up
	stat_ui.queue_free()
	placer.queue_free()
	hull.queue_free()
	await process_frame

	print("  [PASS] Module rotation, hovering stats popup, and mesh deformations verified.")
	return true

func test_sensor_mast_tweak_and_proportions() -> bool:
	print("Running Test Suite: Sensor Mast Dish Proportions + Tweak Target (visual QA fix)...")
	# Regression test for two bugs found during the Tuesday visual QA pass:
	# 1) the radar dish was a fixed 0.7 radius regardless of hull/module size,
	#    towering over the sensor_suite's actual 0.5-wide footprint.
	# 2) the "mast_height" tweak scaled the DISH's thickness (children[1]),
	#    not the MAST's height (children[0]) - the slider's label was a lie.
	var VisualBuilderScript = preload("res://scripts/visual_builder.gd")
	var catalog_data = ModuleCatalog.get_module_data("sensor_suite")

	var node_default = Node3D.new()
	root.add_child(node_default)
	VisualBuilderScript.build_visual("sensor_suite", node_default, catalog_data.size, catalog_data.color, {})
	await process_frame

	var default_children = node_default.get_children().filter(func(c): return c is MeshInstance3D)
	if default_children.size() < 2:
		print("  [FAIL] sensor_suite should build a mast + dish, got ", default_children.size(), " mesh children")
		node_default.queue_free()
		return false

	var dish_default = default_children[1]
	var dish_radius = (dish_default.mesh as CylinderMesh).top_radius if dish_default.mesh is CylinderMesh else -1.0
	if dish_radius > catalog_data.size.x * 1.5:
		print("  [FAIL] Dish radius (", dish_radius, ") is still disproportionate to module footprint (", catalog_data.size.x, ")")
		node_default.queue_free()
		return false
	var default_mast_scale_y = default_children[0].scale.y
	node_default.queue_free()

	var node_tweaked = Node3D.new()
	root.add_child(node_tweaked)
	VisualBuilderScript.build_visual("sensor_suite", node_tweaked, catalog_data.size, catalog_data.color, {"mast_height": 2.0})
	await process_frame

	# Compare against the untweaked baseline rather than asserting an absolute
	# value: the authored-mesh path's baseline scale.y already equals base_size.y
	# (from _fit_scale), so mast_height=2.0 correctly produces scale.y=2x that
	# baseline, not literally 2.0.
	var tweaked_children = node_tweaked.get_children().filter(func(c): return c is MeshInstance3D)
	var mast_scale_y = tweaked_children[0].scale.y
	var ratio = mast_scale_y / default_mast_scale_y if default_mast_scale_y != 0.0 else 0.0
	if abs(ratio - 2.0) > 0.05:
		print("  [FAIL] mast_height=2.0 should scale the MAST (children[0]) to 2x its baseline, got ratio=", ratio, " (baseline=", default_mast_scale_y, ", tweaked=", mast_scale_y, ")")
		node_tweaked.queue_free()
		return false

	var dish_y = tweaked_children[1].position.y
	var expected_dish_y = catalog_data.size.y * 2.0
	if abs(dish_y - expected_dish_y) > 0.05:
		print("  [FAIL] Dish should ride the mast top at y=", expected_dish_y, ", got y=", dish_y)
		node_tweaked.queue_free()
		return false

	node_tweaked.queue_free()
	print("  [PASS] Sensor mast dish is proportionate and mast_height tweak now scales the mast, not the dish.")
	return true

func test_no_dead_tweaks() -> bool:
	print("Running Test Suite: No Dead Tweaks (every slider must change something)...")
	# Systematic version of the sensor_suite/gauss_railgun/cluster_dispenser
	# bugs found during Tuesday's audit: for every numeric tweak in
	# stat_calculator.gd's TWEAK_SPECS, pushing it to its max value must
	# change EITHER the visual mesh transforms OR at least one of
	# weight/dps/cost.x/cost.y. A tweak that changes neither is pure UI
	# theater - exactly the "Forged Battalion trap" DESIGN_VISION.md warns
	# about, just at the single-tweak level instead of whole-part level.
	var StatCalcScript = preload("res://scripts/stat_calculator.gd")
	var VisualBuilderScript = preload("res://scripts/visual_builder.gd")
	var TWEAK_SPECS = StatCalcScript.TWEAK_SPECS

	var dead_tweaks = []

	for type_id in TWEAK_SPECS.keys():
		var catalog_data = ModuleCatalog.get_module_data(type_id)
		for spec in TWEAK_SPECS[type_id]:
			if spec.get("type", "") == "bool":
				continue # bool tweaks (multi_barrel) are special-cased separately, skip here

			var probe_val = spec.max

			# --- Visual comparison ---
			var node_a = Node3D.new()
			root.add_child(node_a)
			VisualBuilderScript.build_visual(type_id, node_a, catalog_data.size, catalog_data.color, {})
			await process_frame
			var snap_a = _snapshot_mesh_transforms(node_a)
			node_a.queue_free()

			var node_b = Node3D.new()
			root.add_child(node_b)
			VisualBuilderScript.build_visual(type_id, node_b, catalog_data.size, catalog_data.color, {spec.name: probe_val})
			await process_frame
			var snap_b = _snapshot_mesh_transforms(node_b)
			node_b.queue_free()

			var visual_changed = snap_a != snap_b

			# --- Stat comparison ---
			var data_a = ModuleData.new()
			data_a.base_hp = catalog_data.hp
			data_a.base_weight = catalog_data.weight
			data_a.cost_metal = catalog_data.metal
			data_a.cost_crystal = catalog_data.crystal
			data_a.base_dps = catalog_data.dps

			var data_b = ModuleData.new()
			data_b.base_hp = catalog_data.hp
			data_b.base_weight = catalog_data.weight
			data_b.cost_metal = catalog_data.metal
			data_b.cost_crystal = catalog_data.crystal
			data_b.base_dps = catalog_data.dps
			data_b.tweaks = {spec.name: probe_val}

			var stat_changed = (
				abs(data_a.get_weight() - data_b.get_weight()) > 0.001 or
				abs(data_a.get_dps() - data_b.get_dps()) > 0.001 or
				data_a.get_cost() != data_b.get_cost()
			)

			if not visual_changed and not stat_changed:
				dead_tweaks.append("%s.%s" % [type_id, spec.name])

	if not dead_tweaks.is_empty():
		print("  [FAIL] Dead tweaks found (change neither visuals nor stats): ", dead_tweaks)
		return false

	print("  [PASS] Every numeric tweak across the catalog changes visuals and/or stats.")
	return true

func _snapshot_mesh_transforms(node: Node3D) -> Array:
	var result = []
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append([child.position, child.scale, child.rotation])
	return result

func test_designer_camera_pan() -> bool:
	print("Running Test Suite: Designer Camera Pan (was entirely missing - orbit+zoom only)...")
	var parent = Node3D.new()
	root.add_child(parent)
	var cam = Camera3D.new()
	cam.set_script(preload("res://scripts/designer_camera.gd"))
	parent.add_child(cam)
	await process_frame
	await process_frame

	var pivot = null
	for c in parent.get_children():
		if c != cam:
			pivot = c
			break
	if not pivot:
		print("  [FAIL] Camera did not create its orbit pivot")
		parent.queue_free()
		return false

	var before = pivot.position
	var delta = cam._compute_pan_delta(Vector2(50, 0))
	if delta.length() < 0.001:
		print("  [FAIL] Panning right produced zero movement")
		parent.queue_free()
		return false
	pivot.position += delta
	if (pivot.position - before).length() < 0.001:
		print("  [FAIL] Pivot position did not change after applying pan delta")
		parent.queue_free()
		return false

	# Panning should scale with zoom distance (tight zoom = fine control,
	# zoomed out = coarse control), not be a fixed screen-space speed.
	var close_delta = cam._compute_pan_delta(Vector2(50, 0)).length()
	cam._distance = 30.0
	var far_delta = cam._compute_pan_delta(Vector2(50, 0)).length()
	if far_delta <= close_delta:
		print("  [FAIL] Pan distance should scale up when zoomed out, got close=", close_delta, " far=", far_delta)
		parent.queue_free()
		return false

	parent.queue_free()
	print("  [PASS] Designer camera pan math verified (middle-drag, distance-scaled).")
	return true

func test_locomotion_tweak_parity() -> bool:
	print("Running Test Suite: Locomotion Tweak Parity (DESIGN_VISION.md audit)...")
	# Regression test for a real bug found during the Sunday audit: the "legs" and
	# "anti_grav" locomotion UI sliders updated settings but update_locomotion()
	# never read the "size" key, so dragging the slider had zero effect on the
	# resulting unit. "hover_engine" had no tweak UI at all. All three are fixed
	# to respond to a continuous "size" setting like wheels/treads/rotors already did.
	var gizmo_probe_parent = Node3D.new()
	root.add_child(gizmo_probe_parent)
	var gizmo_probe = Node3D.new()
	gizmo_probe.set_script(preload("res://scripts/gizmo_3d.gd"))
	gizmo_probe_parent.add_child(gizmo_probe)

	for type_id in ["legs", "anti_grav", "hover_engine"]:
		var hull = StaticBody3D.new()
		hull.name = "Hull"
		root.add_child(hull)
		var placer = Node3D.new()
		placer.set_script(preload("res://scripts/module_placer.gd"))
		placer.hull = hull
		root.add_child(placer)
		await process_frame

		placer.update_locomotion(type_id, {"size": 1.0, "count": 4})
		await process_frame
		var small_scale_mult = Vector3.ONE
		for child in hull.get_children():
			if child.has_meta("module_data") and child.get_meta("module_data").type_id == type_id:
				small_scale_mult = child.get_meta("module_data").scale_multiplier
				break

		placer.update_locomotion(type_id, {"size": 2.0, "count": 4})
		await process_frame
		var big_scale_mult = Vector3.ONE
		var found_big = false
		for child in hull.get_children():
			if child.has_meta("module_data") and child.get_meta("module_data").type_id == type_id:
				big_scale_mult = child.get_meta("module_data").scale_multiplier
				found_big = true
				break

		if not found_big:
			print("  [FAIL] %s: no locomotion part spawned" % type_id)
			placer.queue_free(); hull.queue_free()
			return false
		if (big_scale_mult - small_scale_mult).length() < 0.5:
			print("  [FAIL] %s: size=2.0 did not change scale_multiplier (still %s vs %s) - slider is dead" % [type_id, small_scale_mult, big_scale_mult])
			placer.queue_free(); hull.queue_free()
			return false

		placer.queue_free()
		hull.queue_free()
		await process_frame

	# Gizmo-drag axis mapping: these three weapons had TWEAK_SPECS (slider-tweakable)
	# but no 3D gizmo-handle mapping, so the tactile Spore-style drag didn't work on them.
	var axis_checks = {
		"mortar_array": "tube_count",
		"cluster_dispenser": "dispersion",
		"missile_pod": "grid_size"
	}
	for type_id in axis_checks:
		var expected = axis_checks[type_id]
		var got = gizmo_probe.get_tweak_for_axis(type_id, Vector3.RIGHT)
		if got != expected:
			print("  [FAIL] %s: expected gizmo x-axis to map to '%s', got '%s'" % [type_id, expected, got])
			gizmo_probe_parent.queue_free()
			return false

	gizmo_probe_parent.queue_free()
	print("  [PASS] Locomotion size tweaks (legs/anti_grav/hover_engine) and gizmo axis mappings verified.")
	return true

func test_new_locomotion_types_spawn_and_differentiate() -> bool:
	print("Running Test Suite: New Locomotion Types (buoyant_envelope/screw_drive) Spawn + Differentiate...")

	for type_id in ["buoyant_envelope", "screw_drive"]:
		var hull = StaticBody3D.new()
		hull.name = "Hull"
		root.add_child(hull)
		var placer = Node3D.new()
		placer.set_script(preload("res://scripts/module_placer.gd"))
		placer.hull = hull
		root.add_child(placer)
		await process_frame

		placer.update_locomotion(type_id, {})
		await process_frame
		var count = 0
		for child in hull.get_children():
			if child.has_meta("module_data") and child.get_meta("module_data").type_id == type_id:
				count += 1
		placer.queue_free(); hull.queue_free()
		if count < 2:
			print("  [FAIL] %s: update_locomotion() should spawn a real left/right pair, got %d" % [type_id, count])
			return false

	# buoyant_envelope: real buoyant-lift character (task/DECISIONS_NEEDED.md
	# judgment call) - low thrust (small cruise motors, buoyancy does the
	# lifting) but very high weight_capacity (buoyancy scales generously),
	# opposite of a thrust-driven flyer like fixed_wing_engine.
	if ModuleCatalog.get_thrust_coefficient("buoyant_envelope") >= ModuleCatalog.get_thrust_coefficient("fixed_wing_engine"):
		print("  [FAIL] buoyant_envelope should have a lower thrust_coefficient than fixed_wing_engine (buoyancy does the lifting, not the motors).")
		return false
	if ModuleCatalog.get_base_weight_capacity("buoyant_envelope") <= ModuleCatalog.get_base_weight_capacity("fixed_wing_engine"):
		print("  [FAIL] buoyant_envelope should have a higher base_weight_capacity than fixed_wing_engine (buoyancy scales generously with envelope size).")
		return false

	# screw_drive: genuinely amphibious trait composition, not hard-gated.
	var screw_traits = ModuleCatalog.get_traits("medium_hull", "screw_drive")
	if "ground_contact" not in screw_traits or "amphibious" not in screw_traits:
		print("  [FAIL] screw_drive should carry BOTH ground_contact and amphibious traits, got ", screw_traits)
		return false

	print("  [PASS] buoyant_envelope and screw_drive both spawn real matched pairs via update_locomotion(), and their catalog stats/traits reflect their real-world distinct character.")
	return true

func test_ship_hull_locomotion_mount_gap_fix() -> bool:
	print("Running Test Suite: Visual Bug Pass - Ship/Airship Hull Locomotion No Longer Floats Below The Mesh...")

	# Catalog-level: only the 4 hulls whose mesh doesn't fill its collision
	# box symmetrically (ship taper, airship ellipsoid) carry a nonzero
	# bias; every box-ish hull is untouched.
	for hull_id in ["naval_hull", "small_boat_hull", "heavy_cruiser_hull", "airship_hull"]:
		if ModuleCatalog.get_underside_y_bias(hull_id) <= 0.0:
			print("  [FAIL] %s should carry a nonzero underside_y_bias (visual bug pass fix)." % hull_id)
			return false
	if ModuleCatalog.get_underside_y_bias("medium_hull") != 0.0:
		print("  [FAIL] medium_hull (a plain box-ish hull) should NOT have a bias - the fix shouldn't touch hulls that were already fine.")
		return false

	# End-to-end: placing wheels on naval_hull via the real module_placer.gd
	# path should mount them measurably HIGHER than the naive box-bottom
	# calculation would put them - the actual regression this bug pass fixed.
	var hull = StaticBody3D.new()
	hull.name = "Hull"
	root.add_child(hull)
	hull.set_meta("type_id", "naval_hull")
	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = ModuleCatalog.get_module_data("naval_hull").size
	col_shape.shape = box
	hull.add_child(col_shape)

	var placer = Node3D.new()
	placer.set_script(preload("res://scripts/module_placer.gd"))
	placer.hull = hull
	root.add_child(placer)
	await process_frame

	placer.update_locomotion("wheels", {})
	await process_frame
	var wheel_y = 0.0
	var found_wheel = false
	for child in hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "wheels":
			wheel_y = child.position.y
			found_wheel = true
			break
	var naive_y = -box.size.y / 2.0 - 0.8
	if not found_wheel:
		print("  [FAIL] wheels should spawn on naval_hull.")
		placer.queue_free(); hull.queue_free()
		return false
	if wheel_y <= naive_y:
		print("  [FAIL] wheels on naval_hull should mount higher than the naive box-bottom calculation (", naive_y, "), got ", wheel_y, " - the underside_y_bias fix isn't being applied.")
		placer.queue_free(); hull.queue_free()
		return false

	# naval_propeller's stern position should no longer sit at the exact
	# hull_size.z/2.0 edge (past the keel's real taper) - the other half of
	# this bug pass's fix.
	placer.update_locomotion("naval_propeller", {})
	await process_frame
	var prop_z = 0.0
	var found_prop = false
	for child in hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "naval_propeller":
			prop_z = child.position.z
			found_prop = true
			break
	if not found_prop:
		print("  [FAIL] naval_propeller should spawn on naval_hull.")
		placer.queue_free(); hull.queue_free()
		return false
	if abs(prop_z - box.size.z / 2.0) < 0.01:
		print("  [FAIL] naval_propeller should no longer mount at the exact stern edge (hull_size.z/2.0=", box.size.z / 2.0, ") - got ", prop_z, ", which is the old buggy position past the keel's real taper.")
		placer.queue_free(); hull.queue_free()
		return false

	placer.queue_free()
	hull.queue_free()
	print("  [PASS] Wheels/naval_propeller on ship-shaped hulls now mount measurably closer to the real hull mesh instead of floating below/behind it.")
	return true

func test_terrain_types_differentiate_locomotion() -> bool:
	print("Running Test Suite: Terrain Variety - marsh/rocky/snow_mud/sand Genuinely Differentiate Locomotor Types...")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	# Fake controller: only get_surface_type_at() exists (no get_ground_nav_map),
	# so _setup_navigation() never creates a real nav_agent and _steer_towards()
	# falls back to plain direct-line steering - a real, deterministic distance
	# per fixed physics tick count, driven by the exact same _recalculate_
	# terrain_speed_multiplier() -> _steer_towards() code path a real match uses.
	var controller_script = preload("res://scripts/fake_surface_controller.gd")

	var measure = func(locomotion_type_id: String, surface_type: String) -> float:
		var controller = Node.new()
		controller.set_script(controller_script)
		controller.surface_type = surface_type
		root.add_child(controller)

		var unit = CharacterBody3D.new()
		unit.set_script(BattleUnitScript)
		controller.add_child(unit)
		unit.locomotion_type = locomotion_type_id
		unit.locomotion_settings = {}
		var fake_hull = Node3D.new()
		unit.add_child(fake_hull)
		unit.hull_node = fake_hull

		var loco_data = ModuleData.new()
		loco_data.type_id = locomotion_type_id
		loco_data.category = "locomotion"
		loco_data.base_weight = 80.0
		var loco_child = Node3D.new()
		loco_child.set_meta("module_data", loco_data)
		fake_hull.add_child(loco_child)
		unit._recalculate_move_speed()

		unit.global_position = Vector3.ZERO
		unit._setup_navigation()
		unit.order_move(Vector3(0, 0, -1000))
		# Matches test_unit_order_move_actually_navigates_around_the_lake's
		# established pattern: CharacterBody3D.move_and_slide() reads the
		# real engine physics delta internally regardless of what's passed
		# to _physics_process(), so an explicit move_and_slide() call after
		# each manual tick (with delta matching the real physics_fps) is
		# needed for a synthetic, non-scene-tree-driven loop to produce
		# real, comparable distances.
		for i in range(140):
			unit._physics_process(1.0 / 60.0)
			unit.move_and_slide()
		var dist = unit.global_position.length()
		controller.queue_free()
		return dist

	# marsh: screw_drive should outpace wheels by a wide margin (favored vs.
	# punished), not just a marginal difference.
	var marsh_wheels = measure.call("wheels", "marsh")
	var marsh_screw = measure.call("screw_drive", "marsh")
	if marsh_screw <= marsh_wheels * 1.5:
		print("  [FAIL] marsh: screw_drive should cross noticeably faster than wheels. wheels=", marsh_wheels, " screw_drive=", marsh_screw)
		return false

	# rocky: legs should outpace wheels.
	var rocky_wheels = measure.call("wheels", "rocky")
	var rocky_legs = measure.call("legs", "rocky")
	if rocky_legs <= rocky_wheels * 1.5:
		print("  [FAIL] rocky: legs should cross noticeably faster than wheels. wheels=", rocky_wheels, " legs=", rocky_legs)
		return false

	# snow_mud: tracked_treads should outpace wheels hard.
	var mud_wheels = measure.call("wheels", "snow_mud")
	var mud_treads = measure.call("tracked_treads", "snow_mud")
	if mud_treads <= mud_wheels * 2.0:
		print("  [FAIL] snow_mud: tracked_treads should cross far faster than wheels (wheels bog down hard). wheels=", mud_wheels, " treads=", mud_treads)
		return false

	# sand: tracked_treads should outpace wheels.
	var sand_wheels = measure.call("wheels", "sand")
	var sand_treads = measure.call("tracked_treads", "sand")
	if sand_treads <= sand_wheels * 1.5:
		print("  [FAIL] sand: tracked_treads should cross noticeably faster than wheels. wheels=", sand_wheels, " treads=", sand_treads)
		return false

	# Sanity: plain ground (no surface_type) should be unaffected by any of
	# this - same locomotion type covers the same distance on "" as it does
	# with a 1.0 multiplier explicitly, proving the default fallback works.
	var plain_wheels = measure.call("wheels", "")
	if abs(plain_wheels - marsh_wheels) < 0.01:
		print("  [FAIL] plain ground and marsh gave wheels the identical distance (", plain_wheels, ") - the multiplier isn't actually being applied.")
		return false

	print("  [PASS] marsh favors screw_drive over wheels, rocky favors legs over wheels, snow_mud and sand both favor tracked_treads over wheels - all measured via real physics-tick movement, not just catalog numbers.")
	return true

func test_undo_redo() -> bool:
	print("Running Test Suite: Undo/Redo (Design_Lab_UI_UX.md top-bar spec, previously entirely missing)...")
	var placer = Node3D.new()
	placer.name = "MainLab"
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	var bm = Node.new()
	bm.name = "BlueprintManager"
	bm.set_script(preload("res://scripts/blueprint_manager.gd"))
	placer.add_child(bm)
	await process_frame

	placer._place_hull_from_ui("medium_hull")
	await process_frame

	if placer.can_undo():
		print("  [FAIL] Undo history should be empty before any mutation")
		placer.queue_free()
		return false

	placer._place_weapon_from_ui("basic_cannon", Vector3(1.0, 0.5, 0.0), Vector3.UP)
	await process_frame

	var module_count = 0
	for child in placer.hull.get_children():
		if child.has_meta("module_data"):
			module_count += 1
	if module_count != 2: # primary + mirror
		print("  [FAIL] Expected 2 modules (primary + mirror) after placement, got ", module_count)
		placer.queue_free()
		return false

	if not placer.can_undo():
		print("  [FAIL] Undo history should be populated after placing a module")
		placer.queue_free()
		return false

	placer.undo()
	await process_frame

	module_count = 0
	for child in placer.hull.get_children():
		if child.has_meta("module_data"):
			module_count += 1
	if module_count != 0:
		print("  [FAIL] Undo should have reverted to the pre-placement empty hull, found ", module_count, " modules")
		placer.queue_free()
		return false

	if not placer.can_redo():
		print("  [FAIL] Redo history should be populated after an undo")
		placer.queue_free()
		return false

	placer.redo()
	await process_frame

	module_count = 0
	for child in placer.hull.get_children():
		if child.has_meta("module_data"):
			module_count += 1
	if module_count != 2:
		print("  [FAIL] Redo should have restored the cannon placement, found ", module_count, " modules")
		placer.queue_free()
		return false

	placer.queue_free()
	print("  [PASS] Undo/Redo restores prior hull state correctly (place -> undo -> redo verified).")
	return true

func test_foundation_design_lab_parity() -> bool:
	print("Running Test Suite: Foundation/Defense Design Lab Parity (Factions_and_Buildings.md)...")
	# Factions_and_Buildings.md: "You design [defenses] in the Armory exactly
	# like you design mobile units... Hardpoints & Tweaking: you snap weapons
	# onto the bunker's hardpoints and tweak them." Placement/tweak/mirror/
	# undo all run through the same hull-type-agnostic code paths as vehicles.
	# Locomotion on foundations used to be hard-blocked; per Chris's explicit
	# no-hard-blocking constraint (MOUNTING_AND_ARMOR_SPEC.md addendum) that
	# gate was removed - a mobile pillbox is now a legitimate (if odd) thing
	# a player can build. This test now asserts the OPPOSITE of what it used
	# to: locomotion placement on a foundation succeeds, not rejected.
	var placer = Node3D.new()
	placer.name = "MainLab"
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	var bm = Node.new()
	bm.name = "BlueprintManager"
	bm.set_script(preload("res://scripts/blueprint_manager.gd"))
	placer.add_child(bm)
	await process_frame

	placer._place_hull_from_ui("pillbox_foundation")
	await process_frame

	# Locomotion should now be ALLOWED on a foundation (no hard-blocking).
	placer._place_weapon_from_ui("wheels", Vector3.ZERO, Vector3.DOWN)
	await process_frame
	var loco_count = 0
	for child in placer.hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").category == "locomotion":
			loco_count += 1
	if loco_count == 0:
		print("  [FAIL] Foundation should now ACCEPT locomotion (no hard-blocking), found 0 locomotion parts")
		placer.queue_free()
		return false

	# Weapon placement + mirror should work identically to a vehicle hull.
	placer._place_weapon_from_ui("rotary_cannon", Vector3(0.75, 0.6, 0.0), Vector3.UP)
	await process_frame
	var weapon_count = 0
	for child in placer.hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").category == "weapon":
			weapon_count += 1
	if weapon_count != 2:
		print("  [FAIL] Expected mirrored weapon pair on foundation, got ", weapon_count)
		placer.queue_free()
		return false

	# Rotate + undo/redo should work identically to a vehicle hull.
	placer._select_module(placer.hull.get_children().filter(func(c): return c.has_meta("module_data"))[0])
	placer.rotate_selected_module()
	await process_frame
	if not placer.can_undo():
		print("  [FAIL] Foundation mutations should populate undo history same as vehicles")
		placer.queue_free()
		return false
	placer.undo()
	await process_frame

	# Serialization should correctly round-trip and be classifiable as a defense.
	var snapshot = bm.serialize_hull(placer.hull)
	if not ModuleCatalog.is_foundation(snapshot.get("hull_type", "")):
		print("  [FAIL] Serialized foundation blueprint should classify as is_foundation")
		placer.queue_free()
		return false
	if snapshot.get("modules", []).is_empty():
		print("  [FAIL] Serialized foundation blueprint lost its weapons")
		placer.queue_free()
		return false

	placer.queue_free()
	print("  [PASS] Foundation hulls get full placement/mirror/rotate/undo/serialize parity with vehicle hulls, including locomotion (no longer hard-blocked).")
	return true

func test_fortress_wall_foundation_spawns_correctly() -> bool:
	print("Running Test Suite: Fortress Wall Foundation - Real Spawn Pipeline (Factions_and_Buildings.md's third foundation type)...")
	var bp_manager = preload("res://scripts/blueprint_manager.gd").new()
	root.add_child(bp_manager)
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var bp = {
		"version": 1.0, "hull_type": "fortress_wall_foundation",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "", "settings": {}},
		"modules": [
			{"type_id": "rotary_cannon", "name": "Rotary Cannon", "position": {"x": 0.0, "y": 1.4, "z": 0.0}, "rotation": {"x": 0.0, "y": 0.0, "z": 0.0}, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "yaw_offset": 0.0, "tweaks": {}}
		]
	}
	var unit = CharacterBody3D.new()
	unit.set_script(BattleUnitScript)
	root.add_child(unit)
	unit.setup(bp, 0, bp_manager)

	if not is_instance_valid(unit.hull_node):
		print("  [FAIL] fortress_wall_foundation should reconstruct a real hull via the authored .glb mesh, got no hull_node")
		unit.queue_free()
		return false
	if unit.max_hp <= 0.0:
		print("  [FAIL] fortress_wall_foundation should carry real HP from the catalog, got ", unit.max_hp)
		unit.queue_free()
		return false
	if unit.vision_range <= 0.0:
		print("  [FAIL] fortress_wall_foundation should have a real base_vision, got ", unit.vision_range)
		unit.queue_free()
		return false
	if not ModuleCatalog.is_foundation("fortress_wall_foundation"):
		print("  [FAIL] fortress_wall_foundation should classify as a foundation (static, no locomotion required)")
		unit.queue_free()
		return false
	if not ModuleCatalog.validate_build_legality(bp).valid:
		print("  [FAIL] A fortress_wall_foundation with a weapon should be a legal build (static defense, no locomotion required)")
		unit.queue_free()
		return false

	unit.queue_free()
	print("  [PASS] fortress_wall_foundation reconstructs via the real spawn pipeline with a working mesh, real HP/vision, and passes the build-legality gate as a static defense.")
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
	await process_frame

	placer._place_hull_from_ui("heavy_hull")
	await process_frame
	placer._place_weapon_from_ui("gauss_railgun", Vector3(0, 0.75, -1.0), Vector3.UP)
	await process_frame
	placer._place_weapon_from_ui("sensor_suite", Vector3(1.5, 0.75, 1.5), Vector3.UP)
	await process_frame
	placer._place_weapon_from_ui("legs", Vector3.ZERO, Vector3.DOWN)
	await process_frame

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
	await process_frame

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
	await process_frame

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
			# Batch E hull-relative scaling fix: leg length is the "size"
			# tweak (1.7) times heavy_hull's own height factor relative to
			# medium_hull (heavy_hull.size.y=1.5 / REFERENCE_HULL_SIZE.y=1.0
			# = 1.5), not the raw tweak value alone - see module_placer.gd's
			# update_locomotion().
			var expected_leg_scale = 1.7 * 1.5
			if abs(child.scale.y - expected_leg_scale) < 0.05:
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

func test_firing_arc_visualization() -> bool:
	print("Running Test Suite: Firing Arc Visualization (was a fixed decorative cone, now a real live-obstruction check)...")
	# Design_Lab_UI_UX.md's "Radar Sweep": select a weapon and see a wedge
	# spanning its actual traverse_limit_angle, colored red where something
	# blocks line of sight and blue where it's clear. Set up a hull with a
	# 360-degree-traverse cannon (basic_cannon) and a tall blocking module
	# placed directly in front of it, so we can assert both a red (blocked)
	# and a blue (clear) segment exist in the same build.
	var placer = Node3D.new()
	placer.name = "MainLab"
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	await process_frame

	placer._place_hull_from_ui("heavy_hull")
	await process_frame

	# The cannon that will be selected and inspected for its firing arc.
	placer._place_weapon_from_ui("basic_cannon", Vector3(0, 0.75, 0), Vector3.UP)
	await process_frame
	var cannon = null
	for child in placer.hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "basic_cannon":
			cannon = child
			break
	if not cannon:
		print("  [FAIL] Cannon was not placed")
		placer.queue_free()
		return false

	# A tall sensor mast placed directly in the cannon's forward (-Z) line,
	# close enough to guarantee a blocked ray in that direction.
	placer._place_weapon_from_ui("sensor_suite", Vector3(0, 0.75, -1.2), Vector3.UP)
	await process_frame

	placer._select_module(cannon)
	await process_frame

	var arc = cannon.get_node_or_null("ArcCone")
	if not arc:
		print("  [FAIL] Selecting a weapon should build an ArcCone firing-arc container")
		placer.queue_free()
		return false

	var red_count = 0
	var blue_count = 0
	for seg in arc.get_children():
		if not seg is MeshInstance3D: continue
		var mat = seg.material_override as StandardMaterial3D
		if not mat: continue
		if mat.albedo_color.r > 0.8 and mat.albedo_color.g < 0.3:
			red_count += 1
		elif mat.albedo_color.b > 0.8:
			blue_count += 1

	if red_count == 0:
		print("  [FAIL] Expected at least one blocked (red) segment toward the mast placed directly in front, got 0")
		placer.queue_free()
		return false
	if blue_count == 0:
		print("  [FAIL] Expected at least one clear (blue) segment (basic_cannon has 360-degree traverse), got 0")
		placer.queue_free()
		return false

	# basic_cannon has a full 360-degree traverse_limit_angle - confirm the
	# arc actually spans the full circle rather than some other angle.
	var expected_segments = 32
	if arc.get_child_count() != expected_segments:
		print("  [FAIL] Full-circle traverse should build ", expected_segments, " segments, got ", arc.get_child_count())
		placer.queue_free()
		return false

	placer.queue_free()
	print("  [PASS] Firing arc correctly shows red toward a real obstruction and blue toward clear space (", red_count, " blocked / ", blue_count, " clear of ", expected_segments, " segments).")
	return true

func test_free_rotation_ring() -> bool:
	print("Running Test Suite: Free-Form Rotation Ring (MOUNTING_AND_ARMOR_SPEC.md #3, replaces 90-degree-only snap)...")
	var placer = Node3D.new()
	placer.name = "MainLab"
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	await process_frame

	placer._place_hull_from_ui("medium_hull")
	await process_frame
	placer._place_weapon_from_ui("basic_cannon", Vector3(1.0, 0.5, 0.0), Vector3.UP)
	await process_frame

	var cannon = null
	for child in placer.hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "basic_cannon" and child.position.x > 0.0:
			cannon = child
			break
	var mirror = cannon.get_meta("mirrored_counterpart")

	placer._select_module(cannon)
	await process_frame

	var gizmo = cannon.get_node_or_null("Gizmo3D")
	if not gizmo:
		print("  [FAIL] Selecting a weapon should attach a Gizmo3D")
		placer.queue_free()
		return false
	var ring = gizmo.get_node_or_null("HandleRotate")
	if not ring:
		print("  [FAIL] Weapon gizmo should include a HandleRotate ring")
		placer.queue_free()
		return false

	# Non-90-degree angle is the whole point: proves this isn't secretly
	# still snapping to fixed increments.
	var arbitrary_angle = 0.37
	var start_yaw = cannon.rotation.y
	gizmo._on_rotated(arbitrary_angle)
	await process_frame

	if abs((cannon.rotation.y - start_yaw) - arbitrary_angle) > 0.001:
		print("  [FAIL] Ring rotation should apply the exact delta (", arbitrary_angle, "), got ", cannon.rotation.y - start_yaw)
		placer.queue_free()
		return false
	if abs(cannon.get_meta("yaw_offset", -99.0) - arbitrary_angle) > 0.001:
		print("  [FAIL] yaw_offset meta should track the free-form angle, got ", cannon.get_meta("yaw_offset", -99.0))
		placer.queue_free()
		return false

	# Mirror should rotate the opposite direction by the same magnitude.
	if not mirror or abs(mirror.rotation.y - (-arbitrary_angle)) > 0.001:
		print("  [FAIL] Mirrored counterpart should rotate by -delta, got ", mirror.rotation.y if mirror else "null")
		placer.queue_free()
		return false

	placer.queue_free()
	print("  [PASS] Rotation ring applies a free-form (non-snapped) angle delta and mirrors it correctly.")
	return true

func test_armor_module_facet_fitting() -> bool:
	print("Running Test Suite: Armor-as-Module Facet Fitting + Mirroring (MOUNTING_AND_ARMOR_SPEC.md #2)...")
	var placer = Node3D.new()
	placer.name = "MainLab"
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	await process_frame

	placer._place_hull_from_ui("medium_hull") # size 4 x 1 x 6
	await process_frame

	# Top facet: should auto-fit to hull_size.x x hull_size.z, center on the
	# facet (x=0, z=0), and NOT mirror (top is already on the symmetry plane).
	placer._place_weapon_from_ui("armor_plating", Vector3(0.7, 0.5, -0.3), Vector3.UP)
	await process_frame

	var top_plate = null
	for child in placer.hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "armor_plating":
			top_plate = child
			break
	if not top_plate:
		print("  [FAIL] Top-facet armor plate was not placed")
		placer.queue_free()
		return false

	var catalog_data = ModuleCatalog.get_module_data("armor_plating")
	var fitted_x = top_plate.scale.x * catalog_data.size.x
	var fitted_z = top_plate.scale.z * catalog_data.size.z
	if abs(fitted_x - 4.0) > 0.1 or abs(fitted_z - 6.0) > 0.1:
		print("  [FAIL] Top plate should auto-fit to 4.0 x 6.0 (hull footprint), got ", fitted_x, " x ", fitted_z)
		placer.queue_free()
		return false
	var local_pos = placer.hull.to_local(top_plate.global_position)
	if abs(local_pos.x) > 0.05 or abs(local_pos.z) > 0.05:
		print("  [FAIL] Top plate should be centered on its facet regardless of click position, got local pos ", local_pos)
		placer.queue_free()
		return false
	if top_plate.has_meta("mirrored_counterpart"):
		print("  [FAIL] Top-facet armor (on the symmetry plane) should NOT be mirrored")
		placer.queue_free()
		return false

	# Right-side facet: SHOULD mirror to the left side.
	placer._place_weapon_from_ui("armor_plating", Vector3(2.0, 0.5, 1.0), Vector3.RIGHT)
	await process_frame

	var right_plate = null
	for child in placer.hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "armor_plating":
			var lp = placer.hull.to_local(child.global_position)
			if lp.x > 0.1:
				right_plate = child
				break
	if not right_plate:
		print("  [FAIL] Right-facet armor plate was not placed")
		placer.queue_free()
		return false
	if not right_plate.has_meta("mirrored_counterpart"):
		print("  [FAIL] Side-facet armor should be mirrored to the opposite side")
		placer.queue_free()
		return false
	var mirror_plate = right_plate.get_meta("mirrored_counterpart")
	var mirror_local = placer.hull.to_local(mirror_plate.global_position)
	if mirror_local.x > -0.1:
		print("  [FAIL] Mirrored armor plate should be on the opposite (left) side, got local x=", mirror_local.x)
		placer.queue_free()
		return false

	placer.queue_free()
	print("  [PASS] Armor modules auto-fit and center on their facet; only side facets mirror.")
	return true

func test_armor_module_combat_bonus() -> bool:
	print("Running Test Suite: Armor Module Combat Bonus (aggregate, see DECISIONS_NEEDED.md)...")
	# Same pattern as test_damage_mitigation(). Two setups compared:
	# A) no modules at all - deterministic (subsystem stripping can't trigger
	#    on an empty module list), baseline threshold 15.0 (hardened_steel,
	#    kinetic) is punched through by an 18.0 hit -> HP drops.
	# B) one armor module present - EITHER it resolves through the raised
	#    threshold (18.0 < 15.0+50.0, fully negated) OR the 35% subsystem-
	#    stripping roll picks the armor module itself as the target instead
	#    (which also leaves player.hp untouched, since stripping damages the
	#    module's own HP pool, not the vehicle HP). Both branches leave HP
	#    at 1000.0, so this comparison is deterministic either way - no flakiness.
	var baseline = CharacterBody3D.new()
	baseline.set_script(PlayerVehicleScript)
	baseline._ready()
	root.add_child(baseline)
	var baseline_hull = Node3D.new()
	baseline_hull.name = "Hull"
	baseline_hull.set_meta("armor_material", "hardened_steel")
	baseline_hull.set_meta("armor_thickness", 1.0)
	baseline.add_child(baseline_hull)
	baseline.max_hp = 1000.0
	baseline.hp = 1000.0
	baseline.is_dead = false
	baseline.take_damage(18.0, "kinetic")
	var hp_without_armor_module = baseline.hp
	baseline.queue_free()

	if abs(hp_without_armor_module - 1000.0) < 0.01:
		print("  [FAIL] Baseline (no armor module) should NOT fully negate 18.0 kinetic damage against threshold 15.0, HP stayed ", hp_without_armor_module)
		return false

	var player = CharacterBody3D.new()
	player.set_script(PlayerVehicleScript)
	player._ready()
	root.add_child(player)
	var mock_hull = Node3D.new()
	mock_hull.name = "Hull"
	mock_hull.set_meta("armor_material", "hardened_steel")
	mock_hull.set_meta("armor_thickness", 1.0)
	player.add_child(mock_hull)
	var armor_module = Node3D.new()
	var armor_data = ModuleData.new()
	armor_data.type_id = "armor_plating"
	armor_data.category = "armor"
	armor_data.base_hp = 500.0
	armor_module.set_meta("module_data", armor_data)
	mock_hull.add_child(armor_module)
	player.max_hp = 1000.0
	player.hp = 1000.0
	player.is_dead = false
	player.take_damage(18.0, "kinetic")
	var hp_with_armor_module = player.hp
	player.queue_free()

	if abs(hp_with_armor_module - 1000.0) > 0.01:
		print("  [FAIL] With an armor module present, 18.0 kinetic damage should be fully negated (raised threshold) or absorbed by the module itself (stripping), HP: ", hp_with_armor_module)
		return false

	print("  [PASS] Placed armor modules raise the effective damage threshold in combat (without: HP ", hp_without_armor_module, ", with: HP ", hp_with_armor_module, ").")
	return true

func test_face_based_weapon_mounting() -> bool:
	print("Running Test Suite: Face-Based Weapon Mounting (MOUNTING_AND_ARMOR_SPEC.md #3)...")
	var placer = Node3D.new()
	placer.name = "MainLab"
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	await process_frame

	placer._place_hull_from_ui("heavy_hull")
	await process_frame

	# basic_cannon: "turret" mount style, no extra hardware, existing
	# enclosed-turret visual explicitly left unchanged.
	placer._place_weapon_from_ui("basic_cannon", Vector3(0, 0.75, -1.0), Vector3.UP)
	await process_frame
	var cannon = null
	for c in placer.hull.get_children():
		if c.has_meta("module_data") and c.get_meta("module_data").type_id == "basic_cannon":
			cannon = c
			break
	if not cannon or cannon.get_meta("mount_style", "") != "turret" or cannon.get_node_or_null("MountHardware"):
		print("  [FAIL] basic_cannon should be mount_style 'turret' with no MountHardware, got '", cannon.get_meta("mount_style", "") if cannon else "null", "'")
		placer.queue_free()
		return false

	# gauss_railgun: "frame_built", no hardware, but embedded deeper into
	# the hull (whole vehicle aims, not the weapon).
	placer._place_weapon_from_ui("gauss_railgun", Vector3(0, 0.75, 1.0), Vector3.UP)
	await process_frame
	var railgun = null
	for c in placer.hull.get_children():
		if c.has_meta("module_data") and c.get_meta("module_data").type_id == "gauss_railgun":
			railgun = c
			break
	if not railgun or railgun.get_meta("mount_style", "") != "frame_built" or railgun.get_node_or_null("MountHardware"):
		print("  [FAIL] gauss_railgun should be mount_style 'frame_built' with no MountHardware")
		placer.queue_free()
		return false

	# heavy_machine_gun on the TOP facet: "pintle_top" with visible hardware.
	placer._place_weapon_from_ui("heavy_machine_gun", Vector3(1.5, 0.75, -1.5), Vector3.UP)
	await process_frame
	var top_mg = null
	for c in placer.hull.get_children():
		if c.has_meta("module_data") and c.get_meta("module_data").type_id == "heavy_machine_gun":
			top_mg = c
			break
	if not top_mg or top_mg.get_meta("mount_style", "") != "pintle_top" or not top_mg.get_node_or_null("MountHardware"):
		print("  [FAIL] Top-facet heavy_machine_gun should be 'pintle_top' with MountHardware present")
		placer.queue_free()
		return false

	# heavy_machine_gun on a SIDE facet: "sponson", embedded inward, with a collar.
	var pre_embed_pos = placer.hull.global_position + Vector3(3.0, 0.5, 0.0)
	placer._place_weapon_from_ui("heavy_machine_gun", pre_embed_pos, Vector3.RIGHT)
	await process_frame
	var side_mg = null
	for c in placer.hull.get_children():
		if c.has_meta("module_data") and c.get_meta("module_data").type_id == "heavy_machine_gun" and c != top_mg:
			var lp = placer.hull.to_local(c.global_position)
			if lp.x > 0.1:
				side_mg = c
				break
	if not side_mg or side_mg.get_meta("mount_style", "") != "sponson" or not side_mg.get_node_or_null("MountHardware"):
		print("  [FAIL] Side-facet heavy_machine_gun should be 'sponson' with MountHardware (collar) present")
		placer.queue_free()
		return false
	var side_local = placer.hull.to_local(side_mg.global_position)
	if side_local.x >= 3.0:
		print("  [FAIL] Sponson-mounted weapon should be embedded inward from the clicked surface point, local x=", side_local.x, " (clicked at ~3.0)")
		placer.queue_free()
		return false

	# Mount hardware must survive a tweak-driven rebuild_visual() call, not
	# just the initial placement (this was a real risk: build_visual() clears
	# MeshInstance3D children on every rebuild).
	var VisualBuilderScript = preload("res://scripts/visual_builder.gd")
	var mg_data = top_mg.get_meta("module_data")
	mg_data.tweaks["drum_size"] = 1.8
	VisualBuilderScript.rebuild_visual(top_mg)
	await process_frame
	if not top_mg.get_node_or_null("MountHardware"):
		print("  [FAIL] MountHardware should survive rebuild_visual() (tweak-drag), but was lost")
		placer.queue_free()
		return false

	placer.queue_free()
	print("  [PASS] Face-based mounting: turret/frame_built exceptions correct, pintle_top/sponson hardware present, sponson embeds inward, hardware survives tweak rebuilds.")
	return true

func test_angled_pintle_mount() -> bool:
	print("Running Test Suite: Angled Pintle Mount (MOUNTING_AND_ARMOR_SPEC.md #3 correction - sloped surfaces like a glacis plate)...")
	var ModuleCatalogScript = preload("res://scripts/module_catalog.gd")
	var VisualBuilderScript = preload("res://scripts/visual_builder.gd")

	# Pure function checks first: the continuous threshold itself.
	if ModuleCatalogScript.get_mount_style_for_normal("rotary_cannon", Vector3(0, 0.7, -0.7).normalized(), "interceptor_hull") != "pintle_top":
		print("  [FAIL] A 45-degree sloped-upward normal should still resolve to pintle_top")
		return false
	if ModuleCatalogScript.get_mount_style_for_normal("rotary_cannon", Vector3(0, 0.05, -0.999).normalized(), "interceptor_hull") != "sponson":
		print("  [FAIL] A near-vertical normal (small up component) should still resolve to sponson")
		return false
	if ModuleCatalogScript.get_mount_style_for_normal("rotary_cannon", Vector3.RIGHT, "interceptor_hull") != "sponson":
		print("  [FAIL] A pure side normal should still resolve to sponson (regression check)")
		return false

	# The actual correction: eligibility is PER WEAPON TYPE, not one
	# uniform angle for every weapon. At a shared, moderately-steep slope
	# (dot~0.4, between the light-autogun and ballistic-arc thresholds), a
	# compact machine gun should still pintle-mount while a mortar (whose
	# arc trajectory math wants a much more level base) should not.
	var moderate_slope = Vector3(0, 0.4, -0.92).normalized()
	if ModuleCatalogScript.get_mount_style_for_normal("heavy_machine_gun", moderate_slope, "interceptor_hull") != "pintle_top":
		print("  [FAIL] heavy_machine_gun (low pintle_min_up_alignment) should still pintle-mount at a moderate slope")
		return false
	if ModuleCatalogScript.get_mount_style_for_normal("mortar_array", moderate_slope, "interceptor_hull") != "sponson":
		print("  [FAIL] mortar_array (high pintle_min_up_alignment - needs a level base for its arc) should sponson-mount at the SAME moderate slope a machine gun tolerates")
		return false
	if ModuleCatalogScript.get_pintle_min_up_alignment("heavy_machine_gun") >= ModuleCatalogScript.get_pintle_min_up_alignment("mortar_array"):
		print("  [FAIL] heavy_machine_gun should have a lower (more permissive) pintle threshold than mortar_array")
		return false

	# Real placement: a weapon on a sloped (not exactly flat) upward
	# surface should get pintle_top, stay level itself, and its
	# MountHardware should contain a BasePlate tilted to match the slope.
	var placer = Node3D.new()
	placer.name = "MainLab"
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	var bm = Node.new()
	bm.name = "BlueprintManager"
	bm.set_script(preload("res://scripts/blueprint_manager.gd"))
	placer.add_child(bm)
	await process_frame

	placer._place_hull_from_ui("interceptor_hull")
	await process_frame

	var glacis_normal = Vector3(0, 0.7, -0.7).normalized()
	placer._place_weapon_from_ui("rotary_cannon", Vector3(0, 0.6, -1.0), glacis_normal)
	await process_frame

	var gun = null
	for c in placer.hull.get_children():
		if c.has_meta("module_data") and c.get_meta("module_data").type_id == "rotary_cannon":
			gun = c
			break
	if not gun or gun.get_meta("mount_style", "") != "pintle_top":
		print("  [FAIL] Weapon placed on a 45-degree sloped surface should be mount_style 'pintle_top', got '", gun.get_meta("mount_style", "") if gun else "null", "'")
		placer.queue_free()
		return false

	# "Stays level" = the weapon's own basis.y is still world-up, not
	# tilted to match the placement normal - that's the whole point of the
	# correction (the TILT lives in the base plate, not the weapon).
	if gun.global_transform.basis.y.dot(Vector3.UP) < 0.999:
		print("  [FAIL] A pintle-mounted weapon on a sloped surface should stay level (basis.y ~= UP), got basis.y=", gun.global_transform.basis.y)
		placer.queue_free()
		return false

	var hardware = gun.get_node_or_null("MountHardware")
	var plate = hardware.get_node_or_null("BasePlate") if hardware else null
	if not plate:
		print("  [FAIL] pintle_top MountHardware should contain a BasePlate")
		placer.queue_free()
		return false
	if plate.transform.basis.y.dot(Vector3.UP) > 0.99:
		print("  [FAIL] BasePlate on a 45-degree sloped surface should be visibly tilted (not flat), basis.y=", plate.transform.basis.y)
		placer.queue_free()
		return false
	# The plate should sit slightly INTO the hull (embedded backward along
	# the surface normal), not flush/floating at exactly the origin.
	if plate.position.dot(glacis_normal) >= 0.0:
		print("  [FAIL] BasePlate should be embedded backward along the surface normal, not floating at/past the surface, position=", plate.position)
		placer.queue_free()
		return false

	# Post itself must stay exactly local-vertical regardless of the
	# plate's tilt - unaffected by any of the above.
	var post = hardware.get_node_or_null("MeshInstance3D") if hardware else null
	if not post:
		for child in hardware.get_children():
			if child is MeshInstance3D:
				post = child
				break
	if post and abs(post.rotation.x) + abs(post.rotation.z) > 0.001:
		print("  [FAIL] The post itself should remain unrotated (local-vertical) regardless of the base plate's tilt")
		placer.queue_free()
		return false

	# Save -> reconstruct round-trip: the tilt must survive a reload, not
	# just the live in-session placement - mount_normal meta specifically
	# exists for this; without it, reconstruct_vehicle() would fall back
	# to the default (flat) normal and silently flatten the plate.
	var blueprint = bm.serialize_hull(placer.hull)
	var reconstructed_root = Node3D.new()
	root.add_child(reconstructed_root)
	var new_hull = bm.reconstruct_vehicle(blueprint, reconstructed_root)
	await process_frame

	var reloaded_gun = null
	for c in new_hull.get_children():
		if c.has_meta("module_data") and c.get_meta("module_data").type_id == "rotary_cannon":
			reloaded_gun = c
			break
	var reloaded_hardware = reloaded_gun.get_node_or_null("MountHardware") if reloaded_gun else null
	var reloaded_plate = reloaded_hardware.get_node_or_null("BasePlate") if reloaded_hardware else null
	if not reloaded_plate or reloaded_plate.transform.basis.y.dot(Vector3.UP) > 0.99:
		print("  [FAIL] BasePlate tilt should survive a save/reconstruct round-trip via mount_normal meta, got ", (reloaded_plate.transform.basis.y if reloaded_plate else "no plate"))
		placer.queue_free()
		reconstructed_root.queue_free()
		return false

	placer.queue_free()
	reconstructed_root.queue_free()
	print("  [PASS] Angled pintle mount: sloped surfaces resolve to pintle_top (not sponson), the weapon stays level, the base plate tilts to match the real surface while embedding slightly into the hull, and the tilt survives a save/reload round-trip.")
	return true

func test_centerline_placement_does_not_self_mirror() -> bool:
	print("Running Test Suite: Centerline Placement Doesn't Mirror Onto Itself (found while visually verifying face-based mounting)...")
	# A module placed dead-center (local x ~= 0) - e.g. a frame_built railgun
	# mounted on the front/back centerline, a very natural placement for
	# that weapon type - would previously mirror onto its own position,
	# producing a fully-overlapping duplicate that read as a clipping-red
	# bug. Not mount-style-specific: any module placed on the centerline
	# hit this.
	var placer = Node3D.new()
	placer.name = "MainLab"
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	await process_frame

	placer._place_hull_from_ui("heavy_hull")
	await process_frame
	placer._place_weapon_from_ui("gauss_railgun", Vector3(0, 0.75, 2.0), Vector3.UP)
	await process_frame

	var railguns = []
	for c in placer.hull.get_children():
		if c.has_meta("module_data") and c.get_meta("module_data").type_id == "gauss_railgun":
			railguns.append(c)

	if railguns.size() != 1:
		print("  [FAIL] Centerline placement should produce exactly 1 module, not mirror onto itself, got ", railguns.size())
		placer.queue_free()
		return false
	if railguns[0].has_meta("mirrored_counterpart"):
		print("  [FAIL] Centerline-placed module should not have a mirrored_counterpart at all")
		placer.queue_free()
		return false

	placer.check_all_clipping()
	if placer.clipping_detected:
		print("  [FAIL] Centerline placement should not trigger a false-positive clipping flag")
		placer.queue_free()
		return false

	placer.queue_free()
	print("  [PASS] Centerline-placed modules no longer mirror onto their own position.")
	return true

func test_hull_nose_taper() -> bool:
	print("Running Test Suite: Interceptor Hull Nose Taper (MOUNTING_AND_ARMOR_SPEC.md #4 proof-of-concept)...")
	var MeshAssetLoaderScript = preload("res://scripts/mesh_asset_loader.gd")
	var HullDeformScript = preload("res://scripts/hull_deform.gd")

	var cached_before = MeshAssetLoaderScript.get_hull_mesh("interceptor_hull")
	if not cached_before:
		print("  [FAIL] interceptor_hull has no authored mesh - can't test deform")
		return false
	var cached_vertex_count_before = _count_mesh_vertices(cached_before)

	var placer = Node3D.new()
	placer.name = "MainLab"
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	var bm = Node.new()
	bm.name = "BlueprintManager"
	bm.set_script(preload("res://scripts/blueprint_manager.gd"))
	placer.add_child(bm)
	await process_frame

	placer._place_hull_from_ui("interceptor_hull")
	await process_frame

	var mesh_inst = placer.hull.get_node_or_null("MeshInstance3D") as MeshInstance3D
	var default_mesh = mesh_inst.mesh

	placer.hull.set_meta("nose_taper", 0.4)
	placer.update_hull_appearance()
	await process_frame

	if mesh_inst.mesh == default_mesh:
		print("  [FAIL] Applying a nose_taper should produce a different mesh resource than the default")
		placer.queue_free()
		return false

	# The shared cached asset must never be mutated by the deform - only a
	# fresh copy should change.
	var cached_after = MeshAssetLoaderScript.get_hull_mesh("interceptor_hull")
	var cached_vertex_count_after = _count_mesh_vertices(cached_after)
	if cached_vertex_count_after != cached_vertex_count_before:
		print("  [FAIL] MeshAssetLoader's cached interceptor_hull mesh was mutated by the deform (vertex count changed)")
		placer.queue_free()
		return false

	# Round-trip through save->battle-spawn: the taper must survive, not
	# silently reset to the default nose shape (this was a real gap found
	# while implementing - reconstruct_vehicle() never used authored hull
	# meshes at all before this fix, always falling back to a plain box).
	var snapshot = bm.serialize_hull(placer.hull)
	if abs(snapshot.get("nose_taper", 1.0) - 0.4) > 0.001:
		print("  [FAIL] nose_taper should be captured in the serialized snapshot")
		placer.queue_free()
		return false

	var battle_parent = Node3D.new()
	root.add_child(battle_parent)
	var battle_hull = bm.reconstruct_vehicle(snapshot, battle_parent, false)
	await process_frame
	var battle_mesh_inst = battle_hull.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not battle_mesh_inst or not battle_mesh_inst.mesh or battle_mesh_inst.mesh is BoxMesh:
		print("  [FAIL] Battle-spawned interceptor_hull should use the authored (tapered) mesh, not a plain box")
		placer.queue_free()
		battle_parent.queue_free()
		return false

	placer.queue_free()
	battle_parent.queue_free()
	print("  [PASS] Nose taper deforms a fresh mesh copy (cache untouched) and survives the battle-spawn round-trip.")
	return true

func _count_mesh_vertices(mesh: Mesh) -> int:
	var total = 0
	for surf in range(mesh.get_surface_count()):
		var arrays = mesh.surface_get_arrays(surf)
		total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return total

func test_directional_armor_facet_resolution() -> bool:
	print("Running Test Suite: Directional Armor Facet Resolution (Armor phase 2)...")
	# An armor module on the FRONT facet only should protect against a hit
	# arriving from the front, but NOT against an identical hit from the
	# back - this is the actual point of directional armor: flanking should
	# matter. Uses DamageResolver directly (defender + hit_origin), the same
	# path battle_unit.gd/player_vehicle.gd/building.gd now all call through.
	var defender = Node3D.new()
	root.add_child(defender)
	defender.global_position = Vector3.ZERO

	var hull = Node3D.new()
	hull.name = "Hull"
	hull.set_meta("armor_material", "hardened_steel") # kinetic threshold 15.0
	hull.set_meta("armor_thickness", 1.0)
	defender.add_child(hull)

	var front_armor = Node3D.new()
	front_armor.set_meta("facet", "front")
	var front_data = ModuleData.new()
	front_data.type_id = "armor_plating"
	front_data.category = "armor"
	front_data.base_hp = 500.0 # contributes +50.0 threshold (500 * 0.1) when it applies
	front_armor.set_meta("module_data", front_data)
	hull.add_child(front_armor)

	var active_modules = [front_armor]

	# Hit from the front (-Z, matching the barrel-forward convention): the
	# attacker sits in -Z, so the vector FROM the defender TO the attacker
	# points toward -Z, which classify_facet() reads as "front".
	var hit_from_front = defender.global_position + Vector3(0, 0, -5.0)
	var resolved_front = DamageResolverScript.resolve(hull, active_modules, "kinetic", defender, hit_from_front)
	if abs(resolved_front.x - 65.0) > 0.5: # 15.0 baseline + 50.0 from the front plate
		print("  [FAIL] Hit from the front should get the front plate's bonus (expected threshold ~65.0), got ", resolved_front.x)
		defender.queue_free()
		return false

	# Hit from the back (+Z): the front-only plate should NOT apply.
	var hit_from_back = defender.global_position + Vector3(0, 0, 5.0)
	var resolved_back = DamageResolverScript.resolve(hull, active_modules, "kinetic", defender, hit_from_back)
	if abs(resolved_back.x - 15.0) > 0.5: # baseline only, no plate bonus
		print("  [FAIL] Hit from the back should NOT get the front plate's bonus (expected threshold ~15.0), got ", resolved_back.x)
		defender.queue_free()
		return false

	# No hit_origin at all (AoE/unknown direction) should fall back to the
	# old aggregate-everything behavior, not silently drop the bonus.
	var resolved_unknown = DamageResolverScript.resolve(hull, active_modules, "kinetic")
	if abs(resolved_unknown.x - 65.0) > 0.5:
		print("  [FAIL] Omitting hit_origin should fall back to aggregate (expected ~65.0), got ", resolved_unknown.x)
		defender.queue_free()
		return false

	defender.queue_free()
	print("  [PASS] Armor only protects the facet it's actually mounted on; unknown-direction damage still falls back to aggregate.")
	return true

func test_per_module_armor_material() -> bool:
	print("Running Test Suite: Per-Module Armor Material (Armor phase 3)...")
	# A plate's OWN material choice should override the hull's baseline
	# material for a hit that actually lands on that plate - e.g. a hull
	# with hardened_steel armor but an energy_shielding plate bolted onto
	# the front should resolve a front hit using energy_shielding's profile
	# (threshold 20.0), not hardened_steel's (threshold 15.0).
	var defender = Node3D.new()
	root.add_child(defender)
	defender.global_position = Vector3.ZERO

	var hull = Node3D.new()
	hull.name = "Hull"
	hull.set_meta("armor_material", "hardened_steel") # kinetic threshold 15.0
	hull.set_meta("armor_thickness", 1.0)
	defender.add_child(hull)

	var front_plate = Node3D.new()
	front_plate.set_meta("facet", "front")
	var plate_data = ModuleData.new()
	plate_data.type_id = "armor_plating"
	plate_data.category = "armor"
	plate_data.base_hp = 100.0 # small, so the +10.0 HP bonus doesn't dominate the material swap
	plate_data.tweaks = {"material": "energy_shielding"} # kinetic threshold 20.0
	front_plate.set_meta("module_data", plate_data)
	hull.add_child(front_plate)

	var active_modules = [front_plate]
	var hit_from_front = defender.global_position + Vector3(0, 0, -5.0)
	var resolved = DamageResolverScript.resolve(hull, active_modules, "kinetic", defender, hit_from_front)

	# Expected: energy_shielding's 20.0 base threshold (not hardened_steel's
	# 15.0), plus the plate's own +10.0 HP-derived bonus = 30.0.
	if abs(resolved.x - 30.0) > 0.5:
		print("  [FAIL] Front hit should resolve via the plate's OWN energy_shielding material (expected threshold ~30.0), got ", resolved.x)
		defender.queue_free()
		return false

	# A hit from the back (uncovered facet) should still use the hull's own
	# hardened_steel baseline, unaffected by the front plate's material.
	var hit_from_back = defender.global_position + Vector3(0, 0, 5.0)
	var resolved_back = DamageResolverScript.resolve(hull, active_modules, "kinetic", defender, hit_from_back)
	if abs(resolved_back.x - 15.0) > 0.5:
		print("  [FAIL] Back hit should still use the hull's hardened_steel baseline (expected ~15.0), got ", resolved_back.x)
		defender.queue_free()
		return false

	defender.queue_free()
	print("  [PASS] A plate's own material choice overrides the hull baseline for hits landing on that specific plate.")
	return true

func test_sloped_armor_angle_of_incidence() -> bool:
	print("Running Test Suite: Sloped Armor - Angle of Incidence via Raycast (Armor phase 4)...")
	# A real physics collider this time (StaticBody3D + BoxShape3D on the
	# Hull collision layer), so compute_slope_multiplier() has real
	# geometry to raycast against. Two shots at the same front face: one
	# dead-on (perpendicular), one from an oblique angle - the oblique shot
	# should resolve to a HIGHER effective threshold (more survivable),
	# matching real sloped-armor ballistics.
	var defender = StaticBody3D.new()
	defender.collision_layer = 1 # Hull layer, matches the convention used everywhere else
	defender.collision_mask = 0
	root.add_child(defender)
	defender.global_position = Vector3.ZERO

	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	col.shape = box
	defender.add_child(col)

	var hull = Node3D.new()
	hull.name = "Hull"
	hull.set_meta("armor_material", "hardened_steel")
	hull.set_meta("armor_thickness", 1.0)
	defender.add_child(hull)

	await process_frame # let the physics server register the new collider

	var perpendicular_origin = Vector3(0, 0.1, -5.0)
	var oblique_origin = Vector3(3.5, 0.1, -5.0)

	var resolved_perp = DamageResolverScript.resolve(hull, [], "kinetic", defender, perpendicular_origin)
	var resolved_oblique = DamageResolverScript.resolve(hull, [], "kinetic", defender, oblique_origin)

	if abs(resolved_perp.x - 15.0) > 1.0:
		print("  [FAIL] A perpendicular hit should be close to the unmodified baseline threshold (~15.0), got ", resolved_perp.x)
		defender.queue_free()
		return false

	if resolved_oblique.x <= resolved_perp.x + 1.0:
		print("  [FAIL] An oblique hit on the same face should resolve to a HIGHER effective threshold than a perpendicular hit (more survivable) - perp: ", resolved_perp.x, ", oblique: ", resolved_oblique.x)
		defender.queue_free()
		return false

	defender.queue_free()
	print("  [PASS] Oblique hits are more survivable than perpendicular ones on the same face (perp threshold: %.1f, oblique: %.1f)." % [resolved_perp.x, resolved_oblique.x])
	return true

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
	var weird_traits = ModuleCatalog.get_traits("pillbox_foundation", "anti_grav")
	if "static" not in weird_traits or "hovering" not in weird_traits:
		print("  [FAIL] get_traits() should compose even an unusual combination without rejecting it, got ", weird_traits)
		return false

	# All 7 hull types default to turreted_capable=true (nothing overrides
	# it yet) - confirms the default doesn't silently break existing mounting.
	for hull_id in ["light_hull", "medium_hull", "heavy_hull", "interceptor_hull", "assault_hull", "pillbox_foundation", "tower_foundation"]:
		if not ModuleCatalog.is_turreted_capable(hull_id):
			print("  [FAIL] ", hull_id, " should default to turreted_capable=true")
			return false

	print("  [PASS] Traits compose from whatever hull+locomotion is present, derive 'static' from is_foundation, and never block a combination.")
	return true

func test_fixed_wing_and_naval_movement() -> bool:
	print("Running Test Suite: Fixed-Wing + Naval Movement Models (Traits B3)...")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	# --- Fixed-wing: never stops, banks into turns ---
	var plane = CharacterBody3D.new()
	plane.set_script(BattleUnitScript)
	root.add_child(plane)
	plane.move_speed = 8.0
	plane.rotate_speed = 3.0
	plane.is_fixed_wing = true
	plane.global_position = Vector3.ZERO
	await process_frame

	# A destination essentially at the plane's own position (already
	# "arrived") - a ground unit would zero its velocity here; a fixed-wing
	# unit must keep flying at minimum airspeed regardless.
	plane._steer_fixed_wing(plane.global_position + Vector3(0, 0, -0.01), 0.1)
	var horizontal_speed = Vector2(plane.velocity.x, plane.velocity.z).length()
	if horizontal_speed < plane.move_speed - 0.5:
		print("  [FAIL] Fixed-wing should never drop below minimum airspeed even when 'arrived', got speed ", horizontal_speed, " (min ", plane.move_speed, ")")
		plane.queue_free()
		return false

	# A sharp turn should produce a non-trivial bank (roll) angle, not a
	# flat yaw-only turn like ground/hover steering.
	plane.global_transform = Transform3D.IDENTITY # facing -Z (default forward)
	plane._steer_fixed_wing(Vector3(10, 0, 0), 0.1) # hard turn toward +X
	var roll = plane.global_transform.basis.get_euler().z
	if abs(roll) < 0.05:
		print("  [FAIL] A sharp turn should produce a visible bank/roll angle, got ", roll)
		plane.queue_free()
		return false
	plane.queue_free()

	# --- Naval: surface-locked, unaffected by gravity ---
	var ship = CharacterBody3D.new()
	ship.set_script(BattleUnitScript)
	root.add_child(ship)
	ship.is_naval = true
	ship.global_position = Vector3(0, 5.0, 0) # start well above the waterline
	for i in range(30):
		ship._physics_process(0.1)
	if abs(ship.global_position.y - 0.3) > 1.0:
		print("  [FAIL] A naval unit should settle near the fixed waterline (y~0.3) regardless of gravity, got y=", ship.global_position.y)
		ship.queue_free()
		return false
	ship.queue_free()

	print("  [PASS] Fixed-wing units never stop and bank into turns; naval units stay surface-locked, unaffected by gravity.")
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

func test_ranged_unit_kiting() -> bool:
	print("Running Test Suite: Ranged Unit Kiting - Backs Off Once An Enemy Closes Past Standoff...")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var unit = CharacterBody3D.new()
	unit.set_script(BattleUnitScript)
	root.add_child(unit)
	unit.move_speed = 6.0
	unit.rotate_speed = 4.0
	unit.attack_range = 20.0
	unit.has_frame_built_weapon = false # turreted - independent aim, free to kite
	unit.global_position = Vector3.ZERO
	var target = Node3D.new()
	root.add_child(target)
	target.global_position = Vector3(0, 0, -3) # well inside 0.45*20=9, the kiting threshold
	unit.order_attack(target)

	var initial_dist = unit.global_position.distance_to(target.global_position)
	for i in range(20):
		unit._physics_process(0.1)
	var final_dist = unit.global_position.distance_to(target.global_position)
	if final_dist <= initial_dist + 0.5:
		print("  [FAIL] A turreted ranged unit should back away once an enemy closes past its standoff distance, dist went from ", initial_dist, " to ", final_dist)
		unit.queue_free()
		target.queue_free()
		return false
	unit.queue_free()
	target.queue_free()

	# A frame_built unit must NOT kite - it needs to hold position and turn
	# to keep its fixed weapon on target instead of backing away from it.
	var fb_unit = CharacterBody3D.new()
	fb_unit.set_script(BattleUnitScript)
	root.add_child(fb_unit)
	fb_unit.move_speed = 6.0
	fb_unit.attack_range = 20.0
	fb_unit.has_frame_built_weapon = true
	fb_unit.global_position = Vector3.ZERO
	var target2 = Node3D.new()
	root.add_child(target2)
	target2.global_position = Vector3(0, 0, -3)
	fb_unit.order_attack(target2)
	for i in range(20):
		fb_unit._physics_process(0.1)
	var fb_horizontal_speed = Vector2(fb_unit.velocity.x, fb_unit.velocity.z).length()
	if fb_horizontal_speed > 0.01:
		print("  [FAIL] A frame_built unit should hold position (turn in place) instead of kiting/retreating, got horizontal speed ", fb_horizontal_speed)
		fb_unit.queue_free()
		target2.queue_free()
		return false
	fb_unit.queue_free()
	target2.queue_free()

	print("  [PASS] Turreted ranged units back off once an enemy closes past standoff distance; frame_built units hold and turn instead.")
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

func test_ui_no_overflow_or_offscreen() -> bool:
	print("Running Test Suite: UI Overflow + Off-Screen Audit (headless, no windowed rendering needed)...")
	# Validated technique (see PROGRESS.md): compare each fixed-size panel's
	# actual size against its content's natural combined minimum size -
	# NOT a control's own size vs its own minimum, which is meaningless in
	# this codebase's auto-sizing VBoxContainer-heavy layout.
	var UIAuditScript = preload("res://scripts/ui_audit.gd")

	# Force the real project resolution - headless mode's default viewport
	# is a tiny 64x64 unless explicitly set, which would make every anchor-
	# based layout calculation meaningless. Confirmed empirically that this
	# needs to be re-asserted after a frame (the first assignment doesn't
	# reliably stick before the scene's own _ready() runs).
	root.size = Vector2i(1280, 720)
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	root.size = Vector2i(1280, 720)
	await process_frame
	root.size = Vector2i(1280, 720)
	await process_frame

	var overflow = UIAuditScript.find_overflowing_panels(scene)
	if not overflow.is_empty():
		for o in overflow:
			print("  [FAIL] UI overflow: ", o.path, " fixed_size=", o.fixed_size, " content_min=", o.content_min_size, " culprit=", o.culprit)
		scene.queue_free()
		return false

	var viewport_rect = Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var offscreen = UIAuditScript.find_offscreen_controls(scene, viewport_rect)
	if not offscreen.is_empty():
		for o in offscreen:
			print("  [FAIL] Off-screen control: ", o.path, " rect=", o.rect, " (viewport=", viewport_rect, ")")
		scene.queue_free()
		return false

	scene.queue_free()
	print("  [PASS] No UI panels have content wider/taller than their fixed size, and nothing is positioned off-screen (MainLab.tscn).")
	return true

func test_ui_audit_has_real_teeth() -> bool:
	print("Running Test Suite: UI Audit Tool Sanity Check (does it actually catch bugs?)...")
	# Guards against a future refactor silently making the checker a no-op -
	# the MainLab.tscn regression test above only proves today's UI is
	# clean, not that the tool would notice if it stopped being clean.
	var UIAuditScript = preload("res://scripts/ui_audit.gd")

	# --- Overflow: a fixed-size panel with a child that needs more room ---
	# Must use ScrollContainer, not PanelContainer/VBoxContainer: Godot
	# enforces an internal floor where a Container's own .size can never be
	# set smaller than its own computed minimum size, UNLESS that container
	# type is specifically designed to allow oversized content (that's the
	# entire point of ScrollContainer - clip/scroll rather than grow).
	# Confirmed empirically: a PanelContainer's forced .size silently
	# snapped back to its content's exact minimum on every attempt. This is
	# also *why* the real bug this tool caught used a ScrollContainer.
	var panel = ScrollContainer.new()
	panel.size = Vector2(100, 40)
	root.add_child(panel)
	var wide_label = Label.new()
	wide_label.text = "This label is deliberately far too wide for a 100px panel"
	panel.add_child(wide_label)
	await process_frame
	await process_frame
	panel.size = Vector2(100, 40)

	var overflow = UIAuditScript.find_overflowing_panels(panel)
	if overflow.is_empty():
		print("  [FAIL] UI audit tool failed to catch a deliberately injected overflow - it has no teeth")
		panel.queue_free()
		return false

	# A panel that's actually big enough should NOT be flagged.
	panel.size = Vector2(600, 40)
	await process_frame
	var no_overflow = UIAuditScript.find_overflowing_panels(panel)
	if not no_overflow.is_empty():
		print("  [FAIL] UI audit tool false-positived on a panel that's actually large enough for its content: ", no_overflow)
		panel.queue_free()
		return false
	panel.queue_free()

	# --- Off-screen: a control positioned entirely outside the viewport ---
	var offscreen_control = ColorRect.new()
	offscreen_control.position = Vector2(5000, 5000)
	offscreen_control.size = Vector2(50, 50)
	root.add_child(offscreen_control)
	await process_frame

	var viewport_rect = Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var offscreen_results = UIAuditScript.find_offscreen_controls(offscreen_control, viewport_rect)
	if offscreen_results.is_empty():
		print("  [FAIL] UI audit tool failed to catch a control positioned at (5000,5000), off-screen")
		offscreen_control.queue_free()
		return false
	offscreen_control.queue_free()

	print("  [PASS] UI audit tool correctly catches injected overflow/off-screen bugs and doesn't false-positive on legitimately-sized panels.")
	return true

# --- Skirmish mode test suites ---

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
	await process_frame
	await process_frame

	# Economy math
	var start_metal = skirmish.economy[0].metal
	if not skirmish.spend(0, 100, 0):
		print("  [FAIL] Could not spend affordable amount.")
		skirmish.queue_free()
		return false
	if skirmish.economy[0].metal != start_metal - 100:
		print("  [FAIL] Spend did not deduct correctly.")
		skirmish.queue_free()
		return false
	if skirmish.spend(0, 999999, 0):
		print("  [FAIL] Overspend was allowed.")
		skirmish.queue_free()
		return false
	skirmish.add_resources(0, 100, 0)

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
		await process_frame
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
	await process_frame

	if harvester_ok:
		print("  [PASS] Economy, rosters, base spawn, and factory production all verified.")
		return true
	print("  [FAIL] Starting harvester missing.")
	return false

func test_match_config_overrides_apply_to_skirmish() -> bool:
	print("Running Test Suite: Pre-Match Settings - MatchConfig Overrides (Faction/Blueprint-Import/AI-Difficulty/Starting-Resources) Flow Into A Real Match...")
	var match_config = root.get_node_or_null("MatchConfig")
	if not match_config:
		print("  [SKIP] MatchConfig autoload not present in this run context - nothing to verify.")
		return true

	# Save every field this test touches so no other test (which assumes
	# MatchConfig's defaults) is affected by a leftover override - restored
	# unconditionally at the end, on both the pass and fail paths.
	var saved = {
		"player_faction": match_config.player_faction,
		"enemy_faction": match_config.enemy_faction,
		"selected_blueprint_paths": match_config.selected_blueprint_paths.duplicate(),
		"ai_difficulty": match_config.ai_difficulty,
		"starting_metal": match_config.starting_metal,
		"starting_crystal": match_config.starting_crystal,
	}

	# A deterministic test blueprint (independent of whatever the real
	# %APPDATA% user:// blueprint folder happens to contain) so the
	# blueprint-import override can be proven regardless of environment.
	var test_bp_path = "user://blueprints/_test_matchconfig_override.json"
	var source_bp = bp_manager_test_load("res://data/loadout/rattler_scout.json")
	source_bp["name"] = "MatchConfigOverrideProbe"
	var f = FileAccess.open(test_bp_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(source_bp))
	f.close()

	match_config.player_faction = "technocrats"
	match_config.enemy_faction = "expansionists"
	match_config.ai_difficulty = "hard"
	match_config.starting_metal = 900
	match_config.starting_crystal = 400
	match_config.selected_blueprint_paths = [test_bp_path]

	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await process_frame
	await process_frame

	var ok = true
	if skirmish.player_faction != "technocrats":
		print("  [FAIL] MatchConfig.player_faction should override the roster-derived default, got ", skirmish.player_faction)
		ok = false
	if skirmish.enemy_faction != "expansionists":
		print("  [FAIL] MatchConfig.enemy_faction should override the roster-derived default, got ", skirmish.enemy_faction)
		ok = false
	if skirmish.economy[skirmish.PLAYER_TEAM].metal != 900 or skirmish.economy[skirmish.ENEMY_TEAM].metal != 900:
		print("  [FAIL] MatchConfig.starting_metal should set both teams' starting metal, got ", skirmish.economy)
		ok = false
	if skirmish.economy[skirmish.PLAYER_TEAM].crystal != 400 or skirmish.economy[skirmish.ENEMY_TEAM].crystal != 400:
		print("  [FAIL] MatchConfig.starting_crystal should set both teams' starting crystal, got ", skirmish.economy)
		ok = false
	if skirmish.ai_difficulty != "hard":
		print("  [FAIL] MatchConfig.ai_difficulty should flow into skirmish.ai_difficulty, got ", skirmish.ai_difficulty)
		ok = false
	var found_imported_blueprint = false
	for e in skirmish.roster:
		if e.name == "MatchConfigOverrideProbe":
			found_imported_blueprint = true
	if not found_imported_blueprint:
		print("  [FAIL] selected_blueprint_paths should import exactly the chosen saved design into the roster")
		ok = false
	var ai = skirmish.get_node_or_null("EnemyAI")
	if not ai or ai.wave_interval >= ai.WAVE_INTERVAL or ai.produce_interval >= ai.PRODUCE_INTERVAL:
		print("  [FAIL] 'hard' AI difficulty should scale enemy_ai.gd's timers below their normal defaults, got produce=", ai.produce_interval if ai else "?", " wave=", ai.wave_interval if ai else "?")
		ok = false

	skirmish.queue_free()
	await process_frame
	DirAccess.remove_absolute(test_bp_path)

	match_config.player_faction = saved.player_faction
	match_config.enemy_faction = saved.enemy_faction
	match_config.selected_blueprint_paths = saved.selected_blueprint_paths
	match_config.ai_difficulty = saved.ai_difficulty
	match_config.starting_metal = saved.starting_metal
	match_config.starting_crystal = saved.starting_crystal

	if ok:
		print("  [PASS] Player/enemy faction, blueprint-library import, starting resources, and AI difficulty overrides from MatchConfig all flow into a real Skirmish instance.")
	return ok

func bp_manager_test_load(path: String) -> Dictionary:
	var f = FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	return data

func test_faction_catalog_and_hull_material() -> bool:
	print("Running Test Suite: Faction Visual Identity - FactionCatalog (10 Factions, VISUAL_ART_DIRECTION.md model) + Shared Hull Shader Material...")
	var FactionCatalog = preload("res://scripts/faction_catalog.gd")
	var HullMaterialBuilder = preload("res://scripts/hull_material_builder.gd")

	var ids = FactionCatalog.get_ids()
	if ids.size() != 10:
		print("  [FAIL] Expected exactly 10 factions, got ", ids.size(), ": ", ids)
		return false
	var required_keys = ["name", "passive_summary", "base_color", "accent_color", "detail_color", "wear_color", "wear_amount", "anisotropy", "grime_amount", "edge_highlight_strength"]
	for fid in ids:
		var f = FactionCatalog.get_faction(fid)
		for key in required_keys:
			if not f.has(key):
				print("  [FAIL] Faction '", fid, "' is missing required visual field '", key, "': ", f.keys())
				return false

	# Same armor material, two different factions - should differ in paint
	# color but share the identical metallic/roughness "what is this armor
	# made of" character (faction=ownership/paint, armor_material=PBR
	# substance, deliberately independent axes).
	var mat_a = HullMaterialBuilder.build_hull_material("hardened_steel", "industrialists")
	var mat_b = HullMaterialBuilder.build_hull_material("hardened_steel", "technocrats")
	if mat_a.get_shader_parameter("base_color") == mat_b.get_shader_parameter("base_color"):
		print("  [FAIL] Two different factions with the same armor material should get different paint colors")
		return false
	if mat_a.get_shader_parameter("metallic") != mat_b.get_shader_parameter("metallic") or mat_a.get_shader_parameter("roughness") != mat_b.get_shader_parameter("roughness"):
		print("  [FAIL] Two different factions with the SAME armor material should share identical metallic/roughness (armor character is faction-independent)")
		return false
	if mat_a.shader != mat_b.shader:
		print("  [FAIL] Every faction should share the exact same shader resource (same mesh models, texture-only differentiation - no per-faction shader variants)")
		return false

	# Same faction, two different armor materials - paint color should stay
	# identical (ownership doesn't change), metallic/roughness should differ.
	var mat_c = HullMaterialBuilder.build_hull_material("ablative_ceramic", "industrialists")
	if mat_a.get_shader_parameter("base_color") != mat_c.get_shader_parameter("base_color"):
		print("  [FAIL] The same faction with a different armor material should keep the same paint color")
		return false
	if mat_a.get_shader_parameter("roughness") == mat_c.get_shader_parameter("roughness"):
		print("  [FAIL] hardened_steel vs. ablative_ceramic should have different roughness")
		return false

	# energy_shielding should carry shield_mode=1.0 and reduced alpha,
	# regardless of faction.
	var shield_mat = HullMaterialBuilder.build_hull_material("energy_shielding", "glacier_syndicate")
	if shield_mat.get_shader_parameter("shield_mode") < 0.5:
		print("  [FAIL] energy_shielding should set shield_mode >= 0.5")
		return false
	if shield_mat.get_shader_parameter("alpha_base") >= 1.0:
		print("  [FAIL] energy_shielding should be translucent (alpha_base < 1.0)")
		return false

	# Bayou Irregulars' camo is the one faction that blends accent into
	# broad mottled patches rather than thin panel-seam trim - proves the
	# mottle_amount parameter actually differs per faction, not a constant.
	if FactionCatalog.get_visual("bayou_irregulars").mottle_amount <= FactionCatalog.get_visual("industrialists").mottle_amount:
		print("  [FAIL] Bayou Irregulars should have a distinctly higher mottle_amount than a non-camo faction")
		return false

	# Real spawn-pipeline check: reconstruct_vehicle() should apply this
	# shared ShaderMaterial to the actual hull mesh, not just have the
	# builder function work in isolation.
	var BlueprintManager = preload("res://scripts/blueprint_manager.gd")
	var bp_manager = BlueprintManager.new()
	root.add_child(bp_manager)
	var blueprint_data = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "reactive_armor", "faction": "crimson_concordat",
		"modules": [],
	}
	var parent = Node3D.new()
	root.add_child(parent)
	var hull = bp_manager.reconstruct_vehicle(blueprint_data, parent, false)
	var mesh_inst = hull.get_node_or_null("MeshInstance3D") if hull else null
	# Hull materials are per-surface overrides now (HullMaterialBuilder.
	# apply_hull_materials() - real material slots, not a single whole-mesh
	# material_override, which is always null for a hull - see that
	# function's own comment). Surface count depends on which surface
	# index is checked here: surface 0 (structural) darkens base_color and
	# the last surface (armor) LIGHTENS it (2026-07-18, widening the
	# armor/structural value contrast) - neither carries the faction's raw,
	# unmodified color anymore, so comparing against FactionCatalog.
	# get_visual_color() directly (as this test originally did) breaks
	# every time that tuning changes. Cross-check against build_hull_
	# material()'s OWN output for the same inputs instead - proves the real
	# spawn pipeline applies the same transform the builder function does,
	# without hardcoding a lighten/darken amount that's expected to keep
	# moving during tuning passes.
	var check_surf = mesh_inst.mesh.get_surface_count() - 1 if mesh_inst and mesh_inst.mesh else 0
	var surface_mat = mesh_inst.get_surface_override_material(check_surf) if mesh_inst else null
	if not mesh_inst or not (surface_mat is ShaderMaterial):
		print("  [FAIL] A real reconstructed hull should have a ShaderMaterial (not StandardMaterial3D) as its armor surface override material")
		parent.queue_free()
		bp_manager.queue_free()
		return false
	var expected_armor_mat = HullMaterialBuilder.build_hull_material("reactive_armor", "crimson_concordat")
	if surface_mat.get_shader_parameter("base_color") != expected_armor_mat.get_shader_parameter("base_color"):
		print("  [FAIL] The real spawned hull's material should carry the blueprint's own faction color (crimson_concordat)")
		parent.queue_free()
		bp_manager.queue_free()
		return false
	parent.queue_free()
	bp_manager.queue_free()

	print("  [PASS] All 10 factions have complete VISUAL_ART_DIRECTION.md-model visual identities, share one shader across every faction/armor-material combination, and a real reconstructed hull carries the correct faction-colored material.")
	return true

func test_brushed_aluminum_ui_theme() -> bool:
	print("Running Test Suite: Faction Visual Identity - Brushed-Aluminum UI Theme...")
	var UITheme = preload("res://scripts/ui_theme.gd")
	var FactionCatalog = preload("res://scripts/faction_catalog.gd")

	var panel = Panel.new()
	root.add_child(panel)
	UITheme.apply_brushed_panel(panel, "industrialists")
	var mat_a = panel.material as ShaderMaterial
	if not mat_a:
		print("  [FAIL] apply_brushed_panel should assign a ShaderMaterial to the node's .material")
		panel.queue_free()
		return false
	if mat_a.get_shader_parameter("faction_tint") != FactionCatalog.get_visual_color("industrialists"):
		print("  [FAIL] Panel's faction_tint should match industrialists' catalog color")
		panel.queue_free()
		return false

	# Re-theming the SAME panel to a different faction should reuse the
	# existing ShaderMaterial (not allocate a new one each call) and update
	# its tint - this is what match_setup.gd's live dropdown re-theme relies on.
	UITheme.apply_brushed_panel(panel, "cybernetics")
	var mat_b = panel.material as ShaderMaterial
	if mat_b != mat_a:
		print("  [FAIL] Re-theming the same panel should reuse its existing ShaderMaterial instance, not replace it")
		panel.queue_free()
		return false
	if mat_b.get_shader_parameter("faction_tint") != FactionCatalog.get_visual_color("cybernetics"):
		print("  [FAIL] After re-theming, faction_tint should now match cybernetics' catalog color, got ", mat_b.get_shader_parameter("faction_tint"))
		panel.queue_free()
		return false

	# Real screen check: MatchSetup.tscn's background should carry the
	# brushed shader from the moment it loads (not just when a helper is
	# called in isolation).
	var setup_scene = preload("res://scenes/MatchSetup.tscn").instantiate()
	root.add_child(setup_scene)
	current_scene = setup_scene
	await process_frame
	await process_frame
	if not (setup_scene.bg_rect.material is ShaderMaterial):
		print("  [FAIL] MatchSetup.tscn's background should have the brushed-aluminum ShaderMaterial applied on load")
		panel.queue_free()
		setup_scene.queue_free()
		return false
	# Switching the faction dropdown should re-theme the background live.
	var before_tint = setup_scene.bg_rect.material.get_shader_parameter("faction_tint")
	var concordat_idx = setup_scene.FACTIONS.find("crimson_concordat")
	setup_scene.player_faction_btn.selected = concordat_idx
	setup_scene.player_faction_btn.item_selected.emit(concordat_idx)
	await process_frame
	var after_tint = setup_scene.bg_rect.material.get_shader_parameter("faction_tint")
	if before_tint == after_tint or after_tint != FactionCatalog.get_visual_color("crimson_concordat"):
		print("  [FAIL] Picking 'Crimson Concordat' in the faction dropdown should live-retint MatchSetup's background to its color, got before=", before_tint, " after=", after_tint)
		panel.queue_free()
		setup_scene.queue_free()
		return false

	panel.queue_free()
	setup_scene.queue_free()
	await process_frame
	print("  [PASS] Brushed-aluminum panels apply faction-correct shader params, reuse their ShaderMaterial on re-theme, and MatchSetup's background live-retints when the faction dropdown changes.")
	return true

func test_new_faction_mechanical_bonuses() -> bool:
	print("Running Test Suite: Faction Visual Identity - 7 New Faction Mechanical Bonuses (Real Spawn Pipeline)...")
	var FactionCatalog = preload("res://scripts/faction_catalog.gd")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var ModuleDataScript = preload("res://scripts/module_data.gd")

	var base_bp = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "armor_thickness": 1.0,
		"locomotion": {"type_id": "tracked_treads", "settings": {"width": 1.0}},
		"modules": [
			{"type_id": "tracked_treads", "name": "Treads", "position": {"x": 0, "y": 0, "z": 0}, "rotation": {"x": 0, "y": 0, "z": 0}, "scale": {"x": 1, "y": 1, "z": 1}, "tweaks": {}},
		],
	}

	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await process_frame
	await process_frame

	var ok = true

	# Salvage Union: -10% metal cost, baked into the roster once at load time.
	if FactionCatalog.get_passive("salvage_union", "metal_cost_mult", 1.0) != 0.9:
		print("  [FAIL] Salvage Union should have a metal_cost_mult of 0.9")
		ok = false
	var discount_roster = [{"cost_metal": 100, "cost_crystal": 50}]
	skirmish._apply_faction_cost_discount(discount_roster, "salvage_union")
	if discount_roster[0].cost_metal != 90:
		print("  [FAIL] _apply_faction_cost_discount should reduce a 100-metal entry to 90 for salvage_union, got ", discount_roster[0].cost_metal)
		ok = false

	# Ledger Combine: -15% factory build time - real skirmish.build_time_for_cost() call.
	var base_build_time = skirmish.build_time_for_cost(Vector2i(200, 100))
	var ledger_build_time = base_build_time * FactionCatalog.get_passive("ledger_combine", "build_time_mult", 1.0)
	if not (ledger_build_time < base_build_time) or not is_equal_approx(ledger_build_time, base_build_time * 0.85):
		print("  [FAIL] Ledger Combine should build at exactly 85% of the base build time, got base=", base_build_time, " ledger=", ledger_build_time)
		ok = false

	# Crimson Concordat: weapon DPS rises as its OWN vehicle nears death -
	# spawn a real unit with a basic_cannon, check dps at full HP (no bonus)
	# vs. dps at near-zero HP (should approach base_dps * 1.5).
	var concordat_bp = base_bp.duplicate(true)
	concordat_bp["faction"] = "crimson_concordat"
	concordat_bp["modules"].append({"type_id": "basic_cannon", "name": "Cannon", "position": {"x": 0, "y": 0.75, "z": 0}, "rotation": {"x": 0, "y": 0, "z": 0}, "scale": {"x": 1, "y": 1, "z": 1}, "tweaks": {}})
	var concordat_unit = CharacterBody3D.new()
	concordat_unit.set_script(BattleUnitScript)
	skirmish.add_child(concordat_unit)
	concordat_unit.setup(concordat_bp, skirmish.PLAYER_TEAM, skirmish.bp_manager)
	var concordat_weapon = null
	for child in concordat_unit.hull_node.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "basic_cannon":
			concordat_weapon = child
	if not concordat_weapon:
		print("  [FAIL] Crimson Concordat test unit should have spawned a real basic_cannon weapon")
		ok = false
	else:
		concordat_unit.hp = concordat_unit.max_hp
		concordat_weapon._recalculate_low_hp_dps_bonus()
		var full_hp_dps = concordat_weapon.dps
		concordat_unit.hp = 0.0
		concordat_weapon._recalculate_low_hp_dps_bonus()
		var near_death_dps = concordat_weapon.dps
		if not (near_death_dps > full_hp_dps) or not is_equal_approx(near_death_dps, concordat_weapon.base_dps * 1.5):
			print("  [FAIL] Crimson Concordat's dps should rise to ~1.5x base_dps near death (got ", near_death_dps, " vs base ", concordat_weapon.base_dps, ") and be un-boosted at full HP (got ", full_hp_dps, ")")
			ok = false

	# Glacier Syndicate: negates half of any active terrain speed penalty -
	# direct _recalculate_terrain_speed_multiplier() check via the same fake
	# surface-controller double the terrain-differentiation test already uses.
	var controller_script = preload("res://scripts/fake_surface_controller.gd")
	var controller = Node.new()
	controller.set_script(controller_script)
	controller.surface_type = "sand" # wheels are hit hard on sand (0.3x, a real penalty)
	root.add_child(controller)
	var glacier_unit = CharacterBody3D.new()
	glacier_unit.set_script(BattleUnitScript)
	controller.add_child(glacier_unit)
	glacier_unit.locomotion_type = "wheels"
	glacier_unit.locomotion_settings = {}
	var glacier_hull = Node3D.new()
	glacier_hull.set_meta("faction", "glacier_syndicate")
	glacier_unit.add_child(glacier_hull)
	glacier_unit.hull_node = glacier_hull
	glacier_unit.global_position = Vector3.ZERO
	glacier_unit._recalculate_terrain_speed_multiplier()
	var glacier_mult = glacier_unit.terrain_speed_multiplier
	glacier_hull.set_meta("faction", "industrialists")
	glacier_unit._recalculate_terrain_speed_multiplier()
	var baseline_mult = glacier_unit.terrain_speed_multiplier
	if not (glacier_mult > baseline_mult) or not is_equal_approx(glacier_mult, 1.0 - (1.0 - baseline_mult) * 0.5):
		print("  [FAIL] Glacier Syndicate should negate exactly half of the sand-terrain penalty, got glacier=", glacier_mult, " baseline=", baseline_mult)
		ok = false
	controller.queue_free()

	# Dune Runners: +15% harvester extraction per tick.
	var dune_bp = base_bp.duplicate(true)
	dune_bp["faction"] = "dune_runners"
	dune_bp["modules"].append({"type_id": "resource_harvester", "name": "Harvester", "position": {"x": 0, "y": 0, "z": 1}, "rotation": {"x": 0, "y": 0, "z": 0}, "scale": {"x": 1, "y": 1, "z": 1}, "tweaks": {}})
	var dune_unit = CharacterBody3D.new()
	dune_unit.set_script(BattleUnitScript)
	skirmish.add_child(dune_unit)
	dune_unit.setup(dune_bp, skirmish.PLAYER_TEAM, skirmish.bp_manager)
	if not dune_unit.is_harvester:
		print("  [FAIL] Dune Runners test unit should have been detected as a harvester")
		ok = false

	# Bayou Irregulars: shrinks the effective vision distance at which
	# THEY (as the target) can be spotted - via _get_construct_faction() +
	# the real detection_range_mult multiply in _recalc_fog_of_war().
	var bayou_enemy = CharacterBody3D.new()
	bayou_enemy.set_script(BattleUnitScript)
	skirmish.add_child(bayou_enemy)
	bayou_enemy.team = skirmish.ENEMY_TEAM
	bayou_enemy.set_meta("team", skirmish.ENEMY_TEAM)
	bayou_enemy.add_to_group("units")
	bayou_enemy.add_to_group("damageable")
	bayou_enemy.vision_range = 5.0
	bayou_enemy.global_position = Vector3(400, 0, 0)
	var bayou_hull = Node3D.new()
	bayou_hull.set_meta("faction", "bayou_irregulars")
	bayou_enemy.add_child(bayou_hull)
	bayou_enemy.hull_node = bayou_hull

	var bayou_viewer = CharacterBody3D.new()
	bayou_viewer.set_script(BattleUnitScript)
	skirmish.add_child(bayou_viewer)
	bayou_viewer.team = skirmish.PLAYER_TEAM
	bayou_viewer.set_meta("team", skirmish.PLAYER_TEAM)
	bayou_viewer.add_to_group("units")
	bayou_viewer.add_to_group("damageable")
	bayou_viewer.vision_range = 25.0
	# Positioned so 25 * 0.7 (Bayou's detection_range_mult) = 17.5 < 20 <= 25 -
	# a non-camouflaged unit at this exact distance WOULD be seen, proving
	# the multiplier is what hides a Bayou unit, not raw distance alone.
	bayou_viewer.global_position = Vector3(380, 0, 0)
	skirmish._recalc_fog_of_war()
	if not bayou_enemy.fog_hidden:
		print("  [FAIL] Sanity check failed: a Bayou Irregulars unit just outside its reduced detection range should still be fog_hidden")
		ok = false
	bayou_hull.set_meta("faction", "industrialists")
	skirmish._recalc_fog_of_war()
	if bayou_enemy.fog_hidden:
		print("  [FAIL] The identical unit under a non-camouflage faction, at the same distance, should be visible (proves the mult is faction-specific, not a fixed range change)")
		ok = false

	# Aerodrome Cartel: +15% move_speed, but ONLY for airborne units.
	var cartel_air_bp = {
		"version": 1.0, "hull_type": "flying_wing_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "armor_thickness": 1.0, "faction": "aerodrome_cartel",
		"locomotion": {"type_id": "fixed_wing_engine", "settings": {}},
		"modules": [
			{"type_id": "fixed_wing_engine", "name": "Engine", "position": {"x": 0, "y": 0, "z": -2}, "rotation": {"x": 0, "y": 0, "z": 0}, "scale": {"x": 1, "y": 1, "z": 1}, "tweaks": {}},
		],
	}
	var baseline_air_bp = cartel_air_bp.duplicate(true)
	baseline_air_bp["faction"] = "industrialists"
	var cartel_air_unit = CharacterBody3D.new()
	cartel_air_unit.set_script(BattleUnitScript)
	skirmish.add_child(cartel_air_unit)
	cartel_air_unit.setup(cartel_air_bp, skirmish.PLAYER_TEAM, skirmish.bp_manager)
	var baseline_air_unit = CharacterBody3D.new()
	baseline_air_unit.set_script(BattleUnitScript)
	skirmish.add_child(baseline_air_unit)
	baseline_air_unit.setup(baseline_air_bp, skirmish.PLAYER_TEAM, skirmish.bp_manager)
	if not cartel_air_unit.is_flying or not baseline_air_unit.is_flying:
		print("  [FAIL] Both test units should be real airborne units (fixed_wing_engine on flying_wing_hull)")
		ok = false
	elif not is_equal_approx(cartel_air_unit.move_speed, baseline_air_unit.move_speed * 1.15):
		print("  [FAIL] Aerodrome Cartel airborne units should move exactly 15% faster than an identical industrialists airborne unit, got cartel=", cartel_air_unit.move_speed, " baseline=", baseline_air_unit.move_speed)
		ok = false
	# A GROUND Aerodrome Cartel unit should see zero speed change.
	var cartel_ground_bp = base_bp.duplicate(true)
	cartel_ground_bp["faction"] = "aerodrome_cartel"
	var baseline_ground_bp = base_bp.duplicate(true)
	baseline_ground_bp["faction"] = "industrialists"
	var cartel_ground_unit = CharacterBody3D.new()
	cartel_ground_unit.set_script(BattleUnitScript)
	skirmish.add_child(cartel_ground_unit)
	cartel_ground_unit.setup(cartel_ground_bp, skirmish.PLAYER_TEAM, skirmish.bp_manager)
	var baseline_ground_unit = CharacterBody3D.new()
	baseline_ground_unit.set_script(BattleUnitScript)
	skirmish.add_child(baseline_ground_unit)
	baseline_ground_unit.setup(baseline_ground_bp, skirmish.PLAYER_TEAM, skirmish.bp_manager)
	if not is_equal_approx(cartel_ground_unit.move_speed, baseline_ground_unit.move_speed):
		print("  [FAIL] Aerodrome Cartel's speed bonus should NOT apply to a ground unit, got cartel=", cartel_ground_unit.move_speed, " baseline=", baseline_ground_unit.move_speed)
		ok = false

	skirmish.queue_free()
	await process_frame

	if ok:
		print("  [PASS] Salvage Union's cost discount, Ledger Combine's build-time reduction, Crimson Concordat's low-HP dps ramp, Glacier Syndicate's terrain-penalty reduction, Dune Runners' harvester detection, Bayou Irregulars' detection-range reduction, and Aerodrome Cartel's airborne-only speed bonus all verified through real spawned instances / real system calls, not just catalog numbers.")
	return ok

func test_hull_decals() -> bool:
	print("Running Test Suite: Faction Visual Identity - Shared Decal/Stencil Atlas (Hazard Stripes + Serial Stencils + Mascot Icons, All 10 Factions)...")
	var HullDecals = preload("res://scripts/hull_decals.gd")
	var FactionCatalog = preload("res://scripts/faction_catalog.gd")
	var BlueprintManager = preload("res://scripts/blueprint_manager.gd")
	var hull_size = Vector3(4.0, 1.0, 6.0)

	var ok = true

	# Unlike hull_greebles.gd, decals are UNIVERSAL - every one of the 10
	# factions should get exactly 4 (2 hazard stripes + 1 serial + 1 mascot),
	# never a no-op.
	var ids = FactionCatalog.get_ids()
	if ids.size() != 10:
		print("  [FAIL] Expected 10 factions, got ", ids.size())
		return false
	for fac in ids:
		var hull = Node3D.new()
		root.add_child(hull)
		HullDecals.apply_decals(hull, fac, hull_size)
		var container = hull.get_node_or_null("HullDecals")
		if not container or container.get_child_count() != 5:
			print("  [FAIL] '", fac, "' should have exactly 5 decals (2 hazard + serial + badge + mascot), got ", container.get_child_count() if container else "no container")
			ok = false
		hull.queue_free()
	await process_frame

	# decal_tint should track detail_color exactly (the accessor's whole
	# point is to never silently drift from what the hull shader's own
	# decal_tint uniform already carries).
	for fac in ["industrialists", "crimson_concordat", "ledger_combine"]:
		if FactionCatalog.get_visual_decal_tint(fac) != FactionCatalog.get_faction(fac).get("detail_color"):
			print("  [FAIL] get_visual_decal_tint('", fac, "') should exactly match its detail_color")
			ok = false

	# Two different factions' mascot icons should be genuinely different
	# shapes (different cached textures), not the same crest recolored -
	# proves the per-faction simplification actually varies, not just tint.
	var hull_a = Node3D.new()
	root.add_child(hull_a)
	HullDecals.apply_decals(hull_a, "industrialists", hull_size)
	var hull_b = Node3D.new()
	root.add_child(hull_b)
	HullDecals.apply_decals(hull_b, "glacier_syndicate", hull_size)
	var mascot_a = hull_a.get_node("HullDecals").get_children()[4].material_override.albedo_texture
	var mascot_b = hull_b.get_node("HullDecals").get_children()[4].material_override.albedo_texture
	if mascot_a == mascot_b:
		print("  [FAIL] Industrialists and Glacier Syndicate should have genuinely different mascot icon shapes (gear vs. snowflake-star), not the same texture")
		ok = false
	# But their hazard-stripe texture (a shared, non-mascot element) SHOULD
	# be the literal same cached texture resource - proves the "one shared
	# atlas, re-tinted" model is real, not a fresh texture per faction.
	var hazard_a = hull_a.get_node("HullDecals").get_children()[0].material_override.albedo_texture
	var hazard_b = hull_b.get_node("HullDecals").get_children()[0].material_override.albedo_texture
	if hazard_a != hazard_b:
		print("  [FAIL] Every faction should share the identical cached hazard-stripe texture (only tint differs)")
		ok = false
	hull_a.queue_free()
	hull_b.queue_free()
	await process_frame

	# Re-applying (a faction change in the Design Lab) must replace, not accumulate.
	var reuse_hull = Node3D.new()
	root.add_child(reuse_hull)
	HullDecals.apply_decals(reuse_hull, "industrialists", hull_size)
	HullDecals.apply_decals(reuse_hull, "technocrats", hull_size)
	var reused_container = reuse_hull.get_node_or_null("HullDecals")
	if not reused_container or reused_container.get_child_count() != 5:
		print("  [FAIL] Re-applying decals for a different faction should REPLACE, not accumulate, got ", reused_container.get_child_count() if reused_container else "no container")
		ok = false
	reuse_hull.queue_free()
	await process_frame

	# Real spawn-pipeline check.
	var bp_manager = BlueprintManager.new()
	root.add_child(bp_manager)
	var blueprint_data = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "faction": "dune_runners",
		"modules": [],
	}
	var parent = Node3D.new()
	root.add_child(parent)
	var hull = bp_manager.reconstruct_vehicle(blueprint_data, parent, false)
	var real_container = hull.get_node_or_null("HullDecals") if hull else null
	if not real_container or real_container.get_child_count() != 5:
		print("  [FAIL] A real reconstructed hull should carry exactly 5 decals regardless of faction")
		ok = false
	parent.queue_free()
	bp_manager.queue_free()
	await process_frame

	if ok:
		print("  [PASS] All 10 factions get the universal 4-decal set (hazard stripes share one cached texture, mascot icons genuinely differ in shape), re-theming replaces rather than accumulates, and a real reconstructed hull carries its decals.")
	return ok

func test_hull_greebles() -> bool:
	print("Running Test Suite: Faction Visual Identity - Alpha-Cutout Greeble Cards (5 Treated Factions, 5 Untreated)...")
	var HullGreebles = preload("res://scripts/hull_greebles.gd")
	var BlueprintManager = preload("res://scripts/blueprint_manager.gd")
	var hull_size = Vector3(4.0, 1.0, 6.0)

	var ok = true

	# Every untreated faction should produce a real, empty container -
	# proves the exclusivity is genuine (a deliberate no-op branch), not
	# just "nobody bothered to add these 5 yet."
	var untreated = ["industrialists", "technocrats", "expansionists", "glacier_syndicate", "ledger_combine"]
	for fac in untreated:
		var hull = Node3D.new()
		root.add_child(hull)
		HullGreebles.apply_greebles(hull, fac, hull_size)
		var container = hull.get_node_or_null("HullGreebles")
		if not container or container.get_child_count() != 0:
			print("  [FAIL] Untreated faction '", fac, "' should get an empty HullGreebles container, got ", container.get_child_count() if container else "no container")
			ok = false
		hull.queue_free()

	# Every treated faction should produce a non-empty container with a
	# real, specific child count (not just "more than zero").
	var treated_counts = {
		"salvage_union": 3, "bayou_irregulars": 2, "crimson_concordat": 2,
		"aerodrome_cartel": 2, "dune_runners": 2,
	}
	for fac in treated_counts:
		var hull = Node3D.new()
		root.add_child(hull)
		HullGreebles.apply_greebles(hull, fac, hull_size)
		var container = hull.get_node_or_null("HullGreebles")
		if not container or container.get_child_count() != treated_counts[fac]:
			print("  [FAIL] '", fac, "' should produce exactly ", treated_counts[fac], " greeble children, got ", container.get_child_count() if container else "no container")
			ok = false
		hull.queue_free()
	await process_frame

	# Re-applying (a faction change in the Design Lab) must replace, not
	# accumulate - the classic "update function called twice" duplication bug.
	var reuse_hull = Node3D.new()
	root.add_child(reuse_hull)
	HullGreebles.apply_greebles(reuse_hull, "salvage_union", hull_size)
	HullGreebles.apply_greebles(reuse_hull, "bayou_irregulars", hull_size)
	var reused_container = reuse_hull.get_node_or_null("HullGreebles")
	if not reused_container or reused_container.get_child_count() != treated_counts["bayou_irregulars"]:
		print("  [FAIL] Re-applying greebles for a different faction should REPLACE the old ones, not accumulate - got ", reused_container.get_child_count() if reused_container else "no container", " expected ", treated_counts["bayou_irregulars"])
		ok = false
	reuse_hull.queue_free()
	await process_frame

	# Dune Runners' barrels are real 3D geometry (CylinderMesh + 2 band
	# children each), not flat alpha-cutout cards like the other 4.
	var barrel_hull = Node3D.new()
	root.add_child(barrel_hull)
	HullGreebles.apply_greebles(barrel_hull, "dune_runners", hull_size)
	var barrel_container = barrel_hull.get_node_or_null("HullGreebles")
	var found_real_barrel = false
	for child in barrel_container.get_children():
		if child is MeshInstance3D and child.mesh is CylinderMesh and child.get_child_count() == 2:
			found_real_barrel = true
	if not found_real_barrel:
		print("  [FAIL] Dune Runners should have real CylinderMesh barrel geometry (with 2 band children each), not flat cutout cards")
		ok = false
	barrel_hull.queue_free()
	await process_frame

	# Real spawn-pipeline check: reconstruct_vehicle() should apply greebles
	# to the actual hull, sized off the real footprint - not just have the
	# builder function work in isolation.
	var bp_manager = BlueprintManager.new()
	root.add_child(bp_manager)
	var blueprint_data = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "faction": "crimson_concordat",
		"modules": [],
	}
	var parent = Node3D.new()
	root.add_child(parent)
	var hull = bp_manager.reconstruct_vehicle(blueprint_data, parent, false)
	var real_container = hull.get_node_or_null("HullGreebles") if hull else null
	if not real_container or real_container.get_child_count() != 2:
		print("  [FAIL] A real reconstructed Crimson Concordat hull should carry exactly 2 pennant greebles")
		ok = false
	parent.queue_free()
	bp_manager.queue_free()
	await process_frame

	if ok:
		print("  [PASS] All 5 untreated factions stay clean, all 5 treated factions produce the right greeble count/geometry type, re-theming replaces rather than accumulates, and a real reconstructed hull carries its faction's greebles.")
	return ok

func test_size_tiered_manufactories() -> bool:
	print("Running Test Suite: Base-Building - Size-Tiered Manufactories (Light/Medium/Heavy By Hull Weight, Not Domain)...")
	var ModuleCatalog = preload("res://scripts/module_catalog.gd")

	# The exact per-hull tier mapping logged in DECISIONS_NEEDED.md - spot-
	# check a few, including the cross-domain claim (a boat and a ground
	# hull in the same tier).
	var expectations = {
		"interceptor_hull": "light", "small_boat_hull": "light", "flying_wing_hull": "light",
		"medium_hull": "medium", "naval_hull": "medium", "airship_hull": "medium",
		"heavy_hull": "heavy", "heavy_cruiser_hull": "heavy", "sponson_hull": "heavy", "assault_hull": "heavy",
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
	await process_frame
	await process_frame

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
	await process_frame

	if ok:
		print("  [PASS] Hull size tiers map correctly across domains (a boat and a ground hull share a tier by weight), every match starts with all 3 manufactories built for both teams, and queuing genuinely routes to the matching tier - not just any available factory.")
	return ok

func test_win_condition() -> bool:
	print("Running Test Suite 11: Win/Lose Condition...")

	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await process_frame
	await process_frame

	# Destroy the enemy HQ outright
	skirmish.enemy_hq.take_damage(999999.0, "explosive")
	await process_frame

	var won = skirmish.game_over
	skirmish.queue_free()
	await process_frame

	if won:
		print("  [PASS] Destroying the enemy HQ triggers game over (victory).")
		return true
	print("  [FAIL] Game over not triggered by HQ destruction.")
	return false

func test_energy_pool_and_generators() -> bool:
	print("Running Test Suite: Energy Resource - Base Pool + Generator Modules...")
	await process_frame # let any deferred queue_free()s from prior tests actually clear
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
	await process_frame # let any deferred queue_free()s from prior tests actually clear
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

func test_drone_carrier_spawns_real_drones() -> bool:
	print("Running Test Suite: Drone Carrier Bay - Real Autonomous Drones (not tweened fakery)...")
	await process_frame # let any deferred queue_free()s from prior tests actually clear
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var carrier_unit = CharacterBody3D.new()
	carrier_unit.set_script(BattleUnitScript)
	root.add_child(carrier_unit)
	carrier_unit.team = 0
	carrier_unit.set_meta("team", 0)
	carrier_unit.add_to_group("damageable")

	var weapon = Node3D.new()
	weapon.set_script(load("res://scripts/auto_weapon.gd"))
	carrier_unit.add_child(weapon)
	var w_data = ModuleData.new()
	w_data.type_id = "drone_carrier"
	w_data.base_weight = 350.0
	w_data.base_dps = 85.0
	w_data.tweaks = {"hangar_size": 3.0}
	weapon.set_meta("module_data", w_data)
	weapon._ready()

	var enemy = CharacterBody3D.new()
	enemy.set_script(BattleUnitScript)
	root.add_child(enemy)
	enemy.team = 1
	enemy.set_meta("team", 1)
	enemy.add_to_group("damageable")
	enemy.max_hp = 300.0
	enemy.hp = 300.0
	enemy.global_position = Vector3(10, 0, 0)

	var scene_stub = Node3D.new()
	root.add_child(scene_stub)
	current_scene = scene_stub # _fire_drone_swarm() spawns via get_tree().current_scene.add_child()
	weapon.target = enemy
	weapon._fire_drone_swarm()

	var drones = []
	for n in get_nodes_in_group("missiles"):
		if is_instance_valid(n) and "carrier" in n and n.carrier == carrier_unit:
			drones.append(n)
	if drones.size() != 3:
		print("  [FAIL] hangar_size=3.0 should spawn exactly 3 real drone_unit.gd nodes, got ", drones.size())
		carrier_unit.queue_free(); enemy.queue_free()
		return false
	for d in drones:
		if d.team != 0:
			print("  [FAIL] Spawned drone should carry the carrier's team, got ", d.team)
			carrier_unit.queue_free(); enemy.queue_free()
			return false
		if d.target != enemy:
			print("  [FAIL] Spawned drone's target should be the enemy, got ", d.target)
			carrier_unit.queue_free(); enemy.queue_free()
			return false

	# A real drone has independent physics-driven flight, not a canned
	# tween - verify it actually moves under its own _physics_process.
	var sample_drone = drones[0]
	var start_pos = sample_drone.global_position
	for i in range(10):
		sample_drone._physics_process(0.1)
	if sample_drone.global_position.distance_to(start_pos) < 0.5:
		print("  [FAIL] A drone should be flying (independent _physics_process movement) toward its target, but barely moved")
		carrier_unit.queue_free(); enemy.queue_free()
		return false

	for d in drones:
		if is_instance_valid(d): d.queue_free()
	carrier_unit.queue_free()
	enemy.queue_free()
	print("  [PASS] drone_carrier spawns real, independently-flying drone_unit.gd entities (count driven by Hangar Size), not tweened decorative meshes.")
	return true

func test_energy_weapons_cost_and_drain() -> bool:
	print("Running Test Suite: Energy Weapons - Cost To Fire + Target Energy Drain...")
	await process_frame # let any deferred queue_free()s from prior tests actually clear
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

func test_logistics_sharing_boosts_allies() -> bool:
	print("Running Test Suite: Logistics Tank - Energy-Sharing Aura (not just self-sufficiency)...")
	await process_frame # let any deferred queue_free()s from prior tests actually clear
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var supporter = CharacterBody3D.new()
	supporter.set_script(BattleUnitScript)
	root.add_child(supporter)
	supporter.team = 0
	supporter.global_position = Vector3.ZERO
	supporter.has_logistics_tank = true
	supporter.logistics_tank_strength = 1.0

	var ally = CharacterBody3D.new()
	ally.set_script(BattleUnitScript)
	root.add_child(ally)
	ally.team = 0
	ally.global_position = Vector3(5, 0, 0) # within LOGISTICS_SHARE_RADIUS
	ally.max_energy = 100.0
	ally.current_energy = 10.0
	ally.energy_regen_rate = 0.0 # isolate the aura's contribution from passive regen

	var stranger = CharacterBody3D.new()
	stranger.set_script(BattleUnitScript)
	root.add_child(stranger)
	stranger.team = 1 # enemy - must NOT receive the share
	stranger.global_position = Vector3(-5, 0, 0)
	stranger.max_energy = 100.0
	stranger.current_energy = 10.0
	stranger.energy_regen_rate = 0.0

	for i in range(20):
		supporter._physics_process(0.1)

	if ally.current_energy <= 10.0:
		print("  [FAIL] An ally within range of a logistics_tank-equipped unit should have its energy boosted, stayed at ", ally.current_energy)
		supporter.queue_free(); ally.queue_free(); stranger.queue_free()
		return false
	if stranger.current_energy != 10.0:
		print("  [FAIL] The logistics sharing aura should never boost an enemy, got ", stranger.current_energy)
		supporter.queue_free(); ally.queue_free(); stranger.queue_free()
		return false

	supporter.queue_free()
	ally.queue_free()
	stranger.queue_free()
	print("  [PASS] logistics_tank shares surplus energy with nearby allies only, boosting them beyond their own passive regen.")
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
	await process_frame
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

func test_build_legality_gate() -> bool:
	print("Running Test Suite: Build-Legality Gate (hull + weapon-or-support + locomotion-or-static)...")

	var no_hull = {"hull_type": "", "modules": []}
	if ModuleCatalog.validate_build_legality(no_hull).valid:
		print("  [FAIL] A blueprint with no hull should be invalid")
		return false

	var brick = {"hull_type": "medium_hull", "modules": []}
	if ModuleCatalog.validate_build_legality(brick).valid:
		print("  [FAIL] A hull with no weapon/support and no locomotion should be invalid (accidental brick)")
		return false

	var weapon_no_loco = {"hull_type": "medium_hull", "modules": [{"type_id": "basic_cannon"}]}
	var weapon_no_loco_result = ModuleCatalog.validate_build_legality(weapon_no_loco)
	if weapon_no_loco_result.valid:
		print("  [FAIL] A weapon alone doesn't excuse missing locomotion on a non-foundation hull")
		return false
	if "locomotion" not in weapon_no_loco_result.reason.to_lower():
		print("  [FAIL] The rejection reason should mention locomotion, got: ", weapon_no_loco_result.reason)
		return false

	var full_mobile = {"hull_type": "medium_hull", "modules": [{"type_id": "basic_cannon"}, {"type_id": "tracked_treads"}]}
	if not ModuleCatalog.validate_build_legality(full_mobile).valid:
		print("  [FAIL] Hull + weapon + locomotion should be a valid mobile design")
		return false

	# Support-only (no weapon) on a foundation - a static sensor tower or
	# generator outpost - is a legitimate intentional build, not a brick.
	var static_support = {"hull_type": "pillbox_foundation", "modules": [{"type_id": "sensor_suite"}]}
	if not ModuleCatalog.validate_build_legality(static_support).valid:
		print("  [FAIL] A foundation with a support module (no weapon) should be a valid intentional static build")
		return false

	# Support-only on a MOBILE hull with no locomotion is still a brick -
	# support doesn't excuse missing locomotion any more than a weapon does.
	var mobile_support_no_loco = {"hull_type": "medium_hull", "modules": [{"type_id": "sensor_suite"}]}
	if ModuleCatalog.validate_build_legality(mobile_support_no_loco).valid:
		print("  [FAIL] A non-foundation hull with only a support module and no locomotion should still be invalid")
		return false

	# drone_carrier alone (no "weapon"-category module) counts as a real
	# combat purpose, not an accidental brick.
	var drone_only = {"hull_type": "light_hull", "modules": [{"type_id": "drone_carrier"}, {"type_id": "wheels"}]}
	if not ModuleCatalog.validate_build_legality(drone_only).valid:
		print("  [FAIL] A drone_carrier-only combat design should be valid")
		return false

	# --- Integration: the match-queue gate actually rejects, and never spends resources ---
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await process_frame
	await process_frame

	var metal_before = skirmish.economy[skirmish.PLAYER_TEAM].metal
	var illegal_entry = {
		"blueprint": {"hull_type": "medium_hull", "modules": []},
		"name": "Accidental Brick",
		"cost_metal": 50,
		"cost_crystal": 0,
	}
	skirmish._queue_player_unit(illegal_entry)
	if skirmish.economy[skirmish.PLAYER_TEAM].metal != metal_before:
		print("  [FAIL] Queuing an illegal design should never spend resources")
		skirmish.queue_free()
		return false
	var factory = skirmish.get_team_factory(skirmish.PLAYER_TEAM)
	if factory and not factory.production_queue.is_empty():
		print("  [FAIL] An illegal design should never enter the production queue")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await process_frame
	print("  [PASS] validate_build_legality() correctly gates hull/weapon-or-support/locomotion-or-static, and the match-queue path rejects illegal designs without spending resources.")
	return true

func test_balance_report_covers_every_catalog_entry() -> bool:
	print("Running Test Suite: Balance Report Tool - Scores Every Catalog Entry Without Erroring...")
	# Not a balance-correctness check (balance is subjective, tuned by
	# playtest feel) - a regression guard that tools/balance_report.gd's
	# scoring function stays callable and well-behaved (finite, non-
	# negative) as the catalog grows, so it doesn't silently rot into an
	# unusable tool nobody notices is broken.
	var BalanceReportScript = load("res://tools/balance_report.gd")
	var catalog = ModuleCatalog.get_catalog()
	var checked = 0
	for type_id in catalog.keys():
		var data = catalog[type_id]
		var score = BalanceReportScript.compute_score(data)
		if not (score.has("value") and score.has("cost") and score.has("ratio")):
			print("  [FAIL] compute_score() should return value/cost/ratio for ", type_id)
			return false
		if is_nan(score.value) or is_nan(score.cost) or is_nan(score.ratio):
			print("  [FAIL] compute_score() produced NaN for ", type_id, ": ", score)
			return false
		if score.value < 0.0 or score.cost < 0.0:
			print("  [FAIL] compute_score() produced a negative value/cost for ", type_id, ": ", score)
			return false
		checked += 1

	if checked != catalog.size():
		print("  [FAIL] Expected to score all ", catalog.size(), " catalog entries, only checked ", checked)
		return false

	print("  [PASS] Balance report scores all ", checked, " catalog entries with finite, non-negative value/cost/ratio.")
	return true

func test_screenshot_diff_tolerance() -> bool:
	print("Running Test Suite: Screenshot-Diff Comparison Logic (headless, synthetic images)...")
	# The actual screenshot CAPTURE needs windowed rendering (headless
	# Godot's dummy renderer doesn't rasterize - confirmed earlier this
	# week), so that lives in visual_regression/run_visual_regression.gd.
	# This tests the comparison algorithm itself against synthetic Image
	# objects, which works fine headlessly.
	var ScreenshotDiffScript = preload("res://scripts/screenshot_diff.gd")

	var size = Vector2i(64, 64)
	var base = Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	base.fill(Color(0.4, 0.5, 0.6))

	# Identical images must match.
	var identical = base.duplicate()
	var r1 = ScreenshotDiffScript.compare_images(base, identical)
	if not r1.match:
		print("  [FAIL] Identical images should match, got ", r1)
		return false

	# Small scattered noise (simulating anti-aliasing/font-hinting jitter)
	# within tolerance must still match.
	var noisy = base.duplicate()
	for i in range(20): # ~0.5% of 4096 pixels
		noisy.set_pixel(i % size.x, i / size.x, Color(0.42, 0.52, 0.61))
	var r2 = ScreenshotDiffScript.compare_images(base, noisy)
	if not r2.match:
		print("  [FAIL] A small amount of scattered near-identical noise should still match within tolerance, got ", r2)
		return false

	# A large solid differing region (simulating a missing panel/wrong
	# color/moved element) must NOT match.
	var broken = base.duplicate()
	broken.fill_rect(Rect2i(0, 0, 40, 40), Color(1.0, 0.0, 0.0))
	var r3 = ScreenshotDiffScript.compare_images(base, broken)
	if r3.match:
		print("  [FAIL] A large solid differing region should be flagged as a mismatch, got ", r3)
		return false

	# Different sizes must never match, with a clear reason.
	var wrong_size = Image.create(32, 32, false, Image.FORMAT_RGB8)
	var r4 = ScreenshotDiffScript.compare_images(base, wrong_size)
	if r4.match or r4.reason == "":
		print("  [FAIL] Different-sized images should never match and should explain why, got ", r4)
		return false

	print("  [PASS] Screenshot-diff tolerance correctly absorbs small rendering noise while catching large regressions and size mismatches.")
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
	await process_frame
	await process_frame

	if skirmish.is_energy_deficit(skirmish.PLAYER_TEAM):
		print("  [FAIL] A freshly-started match should not begin in Energy deficit, got capacity=", skirmish.energy_pool[skirmish.PLAYER_TEAM].capacity)
		skirmish.queue_free()
		return false
	if skirmish.is_energy_deficit(skirmish.ENEMY_TEAM):
		print("  [FAIL] The enemy team should also not begin in Energy deficit")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await process_frame
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

	await process_frame
	print("  [PASS] damage_resolver.gd has a real energy armor row; heavy_laser/plasma_lobber/pd_laser deal energy damage but stay capacitor-free.")
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

	if final_dist <= initial_dist + 0.5:
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
	await process_frame

	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await process_frame
	await process_frame

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
	await process_frame
	print("  [PASS] Fog-of-war hides unscouted enemies, reveals them once a player construct's vision reaches them, and never hides the player's own units.")
	return true

func test_fog_hidden_excluded_from_targeting() -> bool:
	print("Running Test Suite: Fog-of-War - Hidden Enemies Can't Be Auto-Targeted...")
	await process_frame
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

func test_vision_blocked_by_real_obstacle_cover() -> bool:
	print("Running Test Suite: Fog-of-War - Buildings/Obstacles Are Real Cover, Not Just Movement Blockers (Map Variety Batch)...")
	await process_frame

	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await process_frame
	await process_frame

	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var enemy = CharacterBody3D.new()
	enemy.set_script(BattleUnitScript)
	skirmish.add_child(enemy)
	enemy.team = skirmish.ENEMY_TEAM
	enemy.set_meta("team", skirmish.ENEMY_TEAM)
	enemy.add_to_group("units")
	enemy.add_to_group("damageable")
	enemy.vision_range = 5.0
	enemy.global_position = Vector3(300, 0, 0) # far from the default map's lake/bases/obstacles

	var viewer = CharacterBody3D.new()
	viewer.set_script(BattleUnitScript)
	skirmish.add_child(viewer)
	viewer.team = skirmish.PLAYER_TEAM
	viewer.set_meta("team", skirmish.PLAYER_TEAM)
	viewer.add_to_group("units")
	viewer.add_to_group("damageable")
	viewer.vision_range = 30.0
	viewer.global_position = Vector3(280, 0, 0)

	skirmish._recalc_fog_of_war()
	if enemy.fog_hidden or not enemy.visible:
		print("  [FAIL] Sanity check failed: with clear line of sight and no obstacle, the enemy should already be visible")
		skirmish.queue_free()
		return false

	# Real cover, built the exact same way TerrainBuilder's rock/building
	# obstacles are (a StaticBody3D on collision layer 1), placed squarely
	# between viewer and enemy - proves _has_line_of_sight() genuinely
	# raycasts against that layer rather than the fog check being pure
	# distance math with an obstacle just coincidentally nearby.
	var cover = StaticBody3D.new()
	cover.collision_layer = 1
	cover.collision_mask = 0
	var shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(6.0, 6.0, 6.0)
	shape.shape = box_shape
	cover.add_child(shape)
	skirmish.add_child(cover)
	cover.global_position = Vector3(290, 3.0, 0)
	await process_frame # let the physics server register the new collider before raycasting against it

	skirmish._recalc_fog_of_war()
	if not enemy.fog_hidden or enemy.visible:
		print("  [FAIL] A real obstacle directly between viewer and enemy should block vision (fog_hidden should flip true) even though the enemy is still within vision_range")
		skirmish.queue_free()
		return false

	cover.queue_free()
	await process_frame
	skirmish._recalc_fog_of_war()
	if enemy.fog_hidden or not enemy.visible:
		print("  [FAIL] Removing the obstacle should restore line of sight and reveal the enemy again")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await process_frame
	print("  [PASS] Obstacles on the terrain collision layer genuinely block vision (a real LOS raycast, not just distance), and stop blocking once removed.")
	return true

func test_navmesh_routes_around_the_lake() -> bool:
	print("Running Test Suite: Real Pathfinding - Navmesh Routes Around The Lake...")
	await process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await process_frame
	await process_frame

	if not skirmish.ground_nav_map.is_valid() or not skirmish.water_nav_map.is_valid():
		print("  [FAIL] Skirmish should bake valid ground/water navigation maps at _ready()")
		skirmish.queue_free()
		return false

	# Query straight across the lake (LAKE_CENTER=(18,0,0), half-extents
	# 7x7 -> bounds x:[11,25] z:[-7,7]) - a real ground path must detour
	# around it, not cut straight through.
	var start = Vector3(0, 0, 0)
	var end = Vector3(35, 0, 0)
	var path = NavigationServer3D.map_get_path(skirmish.ground_nav_map, start, end, true)
	if path.size() < 2:
		print("  [FAIL] Expected a real multi-point path across the map, got ", path.size(), " points")
		skirmish.queue_free()
		return false
	var crosses_lake = false
	for p in path:
		if p.x > 11.0 and p.x < 25.0 and p.z > -7.0 and p.z < 7.0:
			crosses_lake = true
	if crosses_lake:
		print("  [FAIL] Ground navmesh path should detour around the lake, not cross through its bounds")
		skirmish.queue_free()
		return false

	# The water navmesh, conversely, should ONLY have geometry inside the
	# lake bounds - a path query from land to land on the water map
	# should be empty/degenerate (there's simply no connected water there).
	var water_path = NavigationServer3D.map_get_path(skirmish.water_nav_map, Vector3(18, 0, 0), Vector3(18, 0, 3), true)
	if water_path.size() < 2:
		print("  [FAIL] A short path fully inside the lake should resolve on the water navmesh, got ", water_path.size(), " points")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await process_frame
	print("  [PASS] Ground navmesh correctly detours around the lake; water navmesh correctly covers the lake interior.")
	return true

func test_ground_and_naval_units_use_different_nav_maps() -> bool:
	print("Running Test Suite: Real Pathfinding - Ground/Naval Units Get The Correct Nav Map, Flying Units Skip It...")
	await process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await process_frame
	await process_frame

	var bp_manager = skirmish.bp_manager
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var ground_bp = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "tracked_treads", "settings": {"width": 1.0}},
		"modules": []
	}
	var ground_unit = CharacterBody3D.new()
	ground_unit.set_script(BattleUnitScript)
	skirmish.add_child(ground_unit)
	ground_unit.setup(ground_bp, 0, bp_manager)
	if not is_instance_valid(ground_unit.nav_agent):
		print("  [FAIL] A ground unit spawned in a real Skirmish match should get a nav_agent")
		skirmish.queue_free()
		return false
	if ground_unit.nav_agent.get_navigation_map() != skirmish.ground_nav_map:
		print("  [FAIL] A ground unit's nav_agent should be assigned to the ground nav map")
		skirmish.queue_free()
		return false

	var naval_bp = {
		"version": 1.0, "hull_type": "heavy_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "naval_propeller", "settings": {"size": 1.0, "count": 2}},
		"modules": []
	}
	var naval_unit = CharacterBody3D.new()
	naval_unit.set_script(BattleUnitScript)
	skirmish.add_child(naval_unit)
	naval_unit.setup(naval_bp, 0, bp_manager)
	if not is_instance_valid(naval_unit.nav_agent):
		print("  [FAIL] A naval unit spawned in a real Skirmish match should get a nav_agent")
		skirmish.queue_free()
		return false
	if naval_unit.nav_agent.get_navigation_map() != skirmish.water_nav_map:
		print("  [FAIL] A naval unit's nav_agent should be assigned to the water nav map, not the ground one")
		skirmish.queue_free()
		return false

	var flying_bp = {
		"version": 1.0, "hull_type": "light_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "helicopter_rotors", "settings": {}},
		"modules": []
	}
	var flying_unit = CharacterBody3D.new()
	flying_unit.set_script(BattleUnitScript)
	skirmish.add_child(flying_unit)
	flying_unit.setup(flying_bp, 0, bp_manager)
	if is_instance_valid(flying_unit.nav_agent):
		print("  [FAIL] A flying unit should skip navigation entirely (open air, nothing to route around)")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await process_frame
	print("  [PASS] Ground units path on the ground map, naval units path on the water map, flying units skip navigation entirely.")
	return true

func test_hull_draught_routes_to_correct_water_nav_map() -> bool:
	print("Running Test Suite: Hull Draught - Deep vs. Shallow Naval Hulls Route To The Correct Nav Map...")
	await process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await process_frame
	await process_frame

	var bp_manager = skirmish.bp_manager
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var shallow_bp = {
		"version": 1.0, "hull_type": "small_boat_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "naval_propeller", "settings": {"size": 1.0, "count": 2}},
		"modules": []
	}
	var shallow_unit = CharacterBody3D.new()
	shallow_unit.set_script(BattleUnitScript)
	skirmish.add_child(shallow_unit)
	shallow_unit.setup(shallow_bp, 0, bp_manager)
	if shallow_unit.nav_agent.get_navigation_map() != skirmish.water_nav_map:
		print("  [FAIL] small_boat_hull (shallow draught) should route to the plain water map, which still includes shallow water.")
		skirmish.queue_free()
		return false

	var deep_bp = {
		"version": 1.0, "hull_type": "heavy_cruiser_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "naval_propeller", "settings": {"size": 1.0, "count": 2}},
		"modules": []
	}
	var deep_unit = CharacterBody3D.new()
	deep_unit.set_script(BattleUnitScript)
	skirmish.add_child(deep_unit)
	deep_unit.setup(deep_bp, 0, bp_manager)
	if deep_unit.nav_agent.get_navigation_map() != skirmish.deep_water_nav_map:
		print("  [FAIL] heavy_cruiser_hull (deep draught) should route to deep_water_nav_map, not the plain water map that still includes shallow water.")
		skirmish.queue_free()
		return false
	if deep_unit.hull_draught <= ModuleCatalog.SHALLOW_WATER_DRAUGHT_THRESHOLD:
		print("  [FAIL] heavy_cruiser_hull's own draught stat should exceed the shallow-water threshold. draught=", deep_unit.hull_draught, " threshold=", ModuleCatalog.SHALLOW_WATER_DRAUGHT_THRESHOLD)
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await process_frame
	print("  [PASS] small_boat_hull (shallow draught) routes to the shallow-capable water map; heavy_cruiser_hull (deep draught) routes to the deep-only map that excludes shallow water entirely.")
	return true

# End-to-end check that a unit given a real order_move() actually translates
# and actually detours around the lake, not just that the underlying navmesh
# query and nav_agent assignment are individually correct in isolation. This
# test exists because an earlier debug session found that a battle_unit's
# move_speed depends on the hull having an actual locomotion MODULE child
# (category "locomotion", added to "modules") - the top-level "locomotion"
# field alone (type_id/settings) is not enough on its own, it's only used to
# pick movement traits/count_contrib. Real saved blueprints always carry both
# (serialize_hull() emits every hull child with module_data, which includes
# the locomotion part placed via update_locomotion()) - this test's blueprint
# mirrors that real shape rather than the top-level-field-only shorthand used
# by nav_agent-assignment-only tests above.
func test_unit_order_move_actually_navigates_around_the_lake() -> bool:
	print("Running Test Suite: Real Pathfinding - order_move() Actually Moves A Unit Around The Lake...")
	await process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await process_frame
	await process_frame

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
	unit.global_position = Vector3(0, 0.5, 0)
	unit.setup(bp, 0, skirmish.bp_manager)

	if unit.move_speed <= 0.0:
		print("  [FAIL] Unit with a real locomotion module should have nonzero move_speed, got ", unit.move_speed)
		skirmish.queue_free()
		return false

	var start_pos = unit.global_position
	unit.order_move(Vector3(35, 0.5, 0))

	var crossed_lake = false
	for i in range(140):
		unit._physics_process(1.0 / 60.0)
		unit.move_and_slide()
		if unit.global_position.x > 11.0 and unit.global_position.x < 25.0 and unit.global_position.z > -7.0 and unit.global_position.z < 7.0:
			crossed_lake = true

	var moved_dist = start_pos.distance_to(unit.global_position)
	if moved_dist < 5.0:
		print("  [FAIL] Unit given order_move() across the map barely moved (", moved_dist, " units) - pathfinding/steering integration is not producing real movement")
		skirmish.queue_free()
		return false
	if crossed_lake:
		print("  [FAIL] Unit's real movement path cut through the lake bounds instead of detouring around it")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await process_frame
	print("  [PASS] A real order_move() across the map produces real movement (", moved_dist, " units) that detours around the lake.")
	return true

func test_terrain_builder_pure_functions() -> bool:
	print("Running Test Suite: Multi-Map Terrain - terrain_height_at()/is_position_blocked() (pure functions)...")
	var TerrainBuilder = preload("res://scripts/terrain_builder.gd")
	var map_def = {
		"map_half_extents": 80.0,
		"water_areas": [{"center": Vector3(18, 0, 0), "half_extents": Vector2(7, 7)}],
		"obstacles": [{"center": Vector3(-20, 0, 20), "half_extents": Vector2(5, 5)}],
		"elevation_zones": [
			{"center": Vector3(0, 0, -20), "half_extents": Vector2(10, 10), "height": 6.0, "ramp_side": "south", "ramp_width": 6.0},
		],
	}

	if TerrainBuilder.terrain_height_at(map_def, Vector3(0, 0, -20)) != 6.0:
		print("  [FAIL] Plateau center should report height 6.0")
		return false
	if TerrainBuilder.terrain_height_at(map_def, Vector3(40, 0, 40)) != 0.0:
		print("  [FAIL] Flat ground far from any zone should report height 0.0")
		return false
	var ramp_h = TerrainBuilder.terrain_height_at(map_def, Vector3(0, 0, -35))
	if ramp_h <= 0.5 or ramp_h >= 5.5:
		print("  [FAIL] Ramp midpoint should report an intermediate height between 0 and 6, got ", ramp_h)
		return false
	if not TerrainBuilder.is_position_blocked(map_def, Vector3(18, 0, 0)):
		print("  [FAIL] A position inside a water_area should be blocked")
		return false
	if not TerrainBuilder.is_position_blocked(map_def, Vector3(-20, 0, 20)):
		print("  [FAIL] A position inside an obstacle should be blocked")
		return false
	if TerrainBuilder.is_position_blocked(map_def, Vector3(0, 0, -20)):
		print("  [FAIL] A plateau's flat top should NOT be blocked - it's legitimate buildable high ground")
		return false
	if TerrainBuilder.is_position_blocked(map_def, Vector3(40, 0, 40)):
		print("  [FAIL] Ordinary flat ground should not be blocked")
		return false

	print("  [PASS] terrain_height_at()/is_position_blocked() correctly classify water, obstacles, ramps, plateau tops, and flat ground.")
	return true

func test_terrain_builder_navmesh_ramp_connects() -> bool:
	print("Running Test Suite: Multi-Map Terrain - Navmesh Ramp Actually Bridges Ground To Plateau...")
	# Regression test for a real bug: Recast silently drops a baked
	# triangle whose winding doesn't match the rest of the terrain's
	# convention (found via an isolated probe - not a slope/parameter
	# issue, a plain winding mismatch specific to "south"/"west" ramps
	# where the ramp's outer edge has a SMALLER coordinate than its inner
	# edge). Exercises all 4 ramp directions so this can't silently regress
	# for just one of them again.
	var TerrainBuilder = preload("res://scripts/terrain_builder.gd")
	var directions = [
		{"side": "south", "center": Vector3(0, 0, -20), "start": Vector3(0, 0, -50), "end": Vector3(0, 6, -20)},
		{"side": "north", "center": Vector3(0, 0, 20), "start": Vector3(0, 0, 50), "end": Vector3(0, 6, 20)},
		{"side": "east", "center": Vector3(-20, 0, 0), "start": Vector3(10, 0, 0), "end": Vector3(-20, 6, 0)},
		{"side": "west", "center": Vector3(20, 0, 0), "start": Vector3(-10, 0, 0), "end": Vector3(20, 6, 0)},
	]
	for d in directions:
		var map_def = {
			"map_half_extents": 80.0, "water_areas": [], "obstacles": [],
			"elevation_zones": [{"center": d.center, "half_extents": Vector2(10, 10), "height": 6.0, "ramp_side": d.side, "ramp_width": 6.0}],
		}
		var nav = TerrainBuilder.build_navmeshes(map_def)
		await process_frame
		await process_frame
		var path = NavigationServer3D.map_get_path(nav.ground_map, d.start, d.end, true)
		var max_y = 0.0
		for p in path:
			max_y = max(max_y, p.y)
		NavigationServer3D.free_rid(nav.ground_region)
		if nav.water_region.is_valid():
			NavigationServer3D.free_rid(nav.water_region)
		NavigationServer3D.free_rid(nav.amphibious_region)
		if nav.deep_water_region.is_valid():
			NavigationServer3D.free_rid(nav.deep_water_region)
		NavigationServer3D.free_rid(nav.ground_map)
		NavigationServer3D.free_rid(nav.water_map)
		NavigationServer3D.free_rid(nav.amphibious_map)
		NavigationServer3D.free_rid(nav.deep_water_map)
		if path.size() < 2 or max_y < 5.0:
			print("  [FAIL] ramp_side='", d.side, "' should produce a real path reaching the plateau (max Y >= 5.0), got ", path.size(), " points, max_y=", max_y)
			return false

	print("  [PASS] All 4 ramp directions (north/south/east/west) produce a real connected path from ground level up to the plateau.")
	return true

func test_bridges_carve_a_real_ground_crossing_through_water() -> bool:
	print("Running Test Suite: Bridges - Ground Units Cross Via The Bridge, Blocked Without One (Map Variety Batch)...")
	var TerrainBuilder = preload("res://scripts/terrain_builder.gd")
	var half = 40.0
	# Water spans the map's ENTIRE x-range (edge to edge) - with no bridge
	# there is literally zero room to go around, so any successful crossing
	# can only be explained by the bridge carve-out, not a lucky detour.
	var water = [{"center": Vector3(0, 0, 0), "half_extents": Vector2(half, 6)}]
	var map_no_bridge = {"map_half_extents": half, "water_areas": water, "obstacles": [], "elevation_zones": []}
	var map_with_bridge = {
		"map_half_extents": half, "water_areas": water, "obstacles": [], "elevation_zones": [],
		"bridges": [{"center": Vector3(0, 0, 0), "half_extents": Vector2(4, 6)}],
	}
	var start = Vector3(0, 0, -30)
	var end = Vector3(0, 0, 30)

	var nav_no_bridge = TerrainBuilder.build_navmeshes(map_no_bridge)
	await process_frame
	await process_frame
	var path_no_bridge = NavigationServer3D.map_get_path(nav_no_bridge.ground_map, start, end, true)
	var reached_no_bridge = path_no_bridge.size() >= 2 and path_no_bridge[path_no_bridge.size() - 1].distance_to(end) <= 3.0
	for k in ["ground_region", "water_region", "amphibious_region", "deep_water_region"]:
		if nav_no_bridge[k].is_valid(): NavigationServer3D.free_rid(nav_no_bridge[k])
	for k in ["ground_map", "water_map", "amphibious_map", "deep_water_map"]:
		NavigationServer3D.free_rid(nav_no_bridge[k])

	var nav_with_bridge = TerrainBuilder.build_navmeshes(map_with_bridge)
	await process_frame
	await process_frame
	var path_with_bridge = NavigationServer3D.map_get_path(nav_with_bridge.ground_map, start, end, true)
	var reached_with_bridge = path_with_bridge.size() >= 2 and path_with_bridge[path_with_bridge.size() - 1].distance_to(end) <= 3.0
	var crosses_via_bridge_strip = true
	for p in path_with_bridge:
		if p.z > -6.0 and p.z < 6.0 and abs(p.x) > 5.0: # outside the bridge's x=[-4,4] footprint (+1 slack)
			crosses_via_bridge_strip = false
	for k in ["ground_region", "water_region", "amphibious_region", "deep_water_region"]:
		if nav_with_bridge[k].is_valid(): NavigationServer3D.free_rid(nav_with_bridge[k])
	for k in ["ground_map", "water_map", "amphibious_map", "deep_water_map"]:
		NavigationServer3D.free_rid(nav_with_bridge[k])

	if reached_no_bridge:
		print("  [FAIL] Without a bridge, a full-width water band should completely block ground crossing")
		return false
	if not reached_with_bridge:
		print("  [FAIL] With a bridge carved through the water, ground crossing should succeed")
		return false
	if not crosses_via_bridge_strip:
		print("  [FAIL] The crossing path should stay within the bridge's own x-footprint while passing through the water band, not some other route")
		return false
	if TerrainBuilder.terrain_height_at(map_with_bridge, Vector3(0, 0, 0)) <= 0.0:
		print("  [FAIL] terrain_height_at() should report a real positive deck height on the bridge, not ground level 0.0")
		return false

	print("  [PASS] A bridge carves a genuine, narrow ground crossing through an otherwise fully-blocking water band, and reports a real deck height.")
	return true

func test_building_obstacle_spawns_taller_real_cover_than_rock_cluster() -> bool:
	print("Running Test Suite: Urban Obstacles - 'building' Type Spawns Real, Taller Cover Distinct From Rock Clusters (Map Variety Batch)...")
	var TerrainBuilder = preload("res://scripts/terrain_builder.gd")
	var parent = Node3D.new()
	root.add_child(parent)
	var map_def = {
		"map_half_extents": 80.0,
		"obstacles": [
			{"center": Vector3(0, 0, 0), "half_extents": Vector2(4, 4), "type": "rock"},
			{"center": Vector3(30, 0, 0), "half_extents": Vector2(4, 4), "type": "building", "building_height": 7.0},
		],
	}
	TerrainBuilder.spawn_visuals(map_def, parent)
	await process_frame

	var rock_body = null
	var building_body = null
	for child in parent.get_children():
		if child is StaticBody3D:
			if child.global_position.x < 15:
				rock_body = child
			else:
				building_body = child
	if not rock_body or not building_body:
		print("  [FAIL] Expected one real StaticBody3D collider per obstacle, got rock=", rock_body, " building=", building_body)
		parent.queue_free()
		return false
	# Code-generated nodes get anonymous engine names (e.g. "@CollisionShape3D@N")
	# unless force_readable_name is passed to add_child(), so find the
	# CollisionShape3D child by type rather than by name.
	var rock_shape: BoxShape3D = null
	for child in rock_body.get_children():
		if child is CollisionShape3D: rock_shape = child.shape
	var building_shape: BoxShape3D = null
	for child in building_body.get_children():
		if child is CollisionShape3D: building_shape = child.shape
	if not is_equal_approx(rock_shape.size.y, 3.0):
		print("  [FAIL] rock obstacle collider height should stay 3.0 (unchanged behavior), got ", rock_shape.size.y)
		parent.queue_free()
		return false
	if building_shape.size.y < 6.9 or building_shape.size.y > 7.1:
		print("  [FAIL] building obstacle collider height should honor building_height=7.0, got ", building_shape.size.y)
		parent.queue_free()
		return false

	parent.queue_free()
	await process_frame
	print("  [PASS] 'building' obstacles spawn a real, taller StaticBody3D collider honoring building_height, distinct from 'rock' obstacles' fixed height.")
	return true

func test_deep_water_navmesh_blocks_shallow_draught_hulls() -> bool:
	print("Running Test Suite: Hull Draught - Shallow Water Genuinely Blocks Deep-Draught Naval Hulls...")
	# A shallow_water_areas strip spans the FULL width of the lake, splitting
	# it into north/south halves - a deep-draught hull has no way around it
	# (this IS the entire body of water), so deep_water_map should have NO
	# connection between the two halves at all, while water_map (which
	# still includes shallow water as walkable) connects them fine.
	var map_def = {
		"map_half_extents": 80.0,
		"water_areas": [{"center": Vector3(0, 0, 0), "half_extents": Vector2(15, 40)}],
		"shallow_water_areas": [{"center": Vector3(0, 0, 0), "half_extents": Vector2(15, 3)}],
		"obstacles": [], "elevation_zones": [],
	}
	var nav = TerrainBuilder.build_navmeshes(map_def)
	await process_frame
	await process_frame

	var north = Vector3(0, 0, 20)
	var south = Vector3(0, 0, -20)
	var shallow_capable_path = NavigationServer3D.map_get_path(nav.water_map, north, south, true)
	var deep_draught_path = NavigationServer3D.map_get_path(nav.deep_water_map, north, south, true)

	NavigationServer3D.free_rid(nav.ground_region)
	if nav.water_region.is_valid():
		NavigationServer3D.free_rid(nav.water_region)
	NavigationServer3D.free_rid(nav.amphibious_region)
	if nav.deep_water_region.is_valid():
		NavigationServer3D.free_rid(nav.deep_water_region)
	NavigationServer3D.free_rid(nav.ground_map)
	NavigationServer3D.free_rid(nav.water_map)
	NavigationServer3D.free_rid(nav.amphibious_map)
	NavigationServer3D.free_rid(nav.deep_water_map)

	var shallow_dist = 0.0
	for i in range(1, shallow_capable_path.size()):
		shallow_dist += shallow_capable_path[i - 1].distance_to(shallow_capable_path[i])
	var direct_dist = north.distance_to(south)
	if shallow_capable_path.size() < 2 or shallow_dist > direct_dist * 1.2:
		print("  [FAIL] A shallow-draught-capable path (water_map) should connect the two halves almost directly. size=", shallow_capable_path.size(), " dist=", shallow_dist, " direct=", direct_dist)
		return false

	# NavigationServer3D.map_get_path() on a disconnected map returns
	# either an empty/degenerate path or one that doesn't actually reach
	# the goal - either way, it must NOT be a real corridor answer close to
	# the direct distance.
	var deep_dist = 0.0
	for i in range(1, deep_draught_path.size()):
		deep_dist += deep_draught_path[i - 1].distance_to(deep_draught_path[i])
	var deep_reaches_goal = deep_draught_path.size() > 0 and deep_draught_path[deep_draught_path.size() - 1].distance_to(south) < 2.0
	if deep_reaches_goal and deep_dist < direct_dist * 1.2:
		print("  [FAIL] A deep-draught hull (deep_water_map) should NOT be able to cross the shallow strip splitting the lake - it's the only water there, no way around. got a path of dist=", deep_dist)
		return false

	print("  [PASS] A deep-draught hull's navmesh has no route across the shallow-water strip splitting the lake (genuinely blocked, not just slowed), while a shallow-draught-capable path crosses it directly.")
	return true

func test_amphibious_navmesh_crosses_water() -> bool:
	print("Running Test Suite: Amphibious Navmesh - screw_drive Crosses Water In One Continuous Path...")
	var map_def = {
		"map_half_extents": 80.0,
		"water_areas": [{"center": Vector3(0, 0, 0), "half_extents": Vector2(15, 40)}],
		"obstacles": [], "elevation_zones": [],
	}
	var nav = TerrainBuilder.build_navmeshes(map_def)
	await process_frame
	await process_frame

	var start = Vector3(-30, 0, 0)
	var goal = Vector3(30, 0, 0)
	var ground_path = NavigationServer3D.map_get_path(nav.ground_map, start, goal, true)
	var amphibious_path = NavigationServer3D.map_get_path(nav.amphibious_map, start, goal, true)

	NavigationServer3D.free_rid(nav.ground_region)
	if nav.water_region.is_valid():
		NavigationServer3D.free_rid(nav.water_region)
	NavigationServer3D.free_rid(nav.amphibious_region)
	if nav.deep_water_region.is_valid():
		NavigationServer3D.free_rid(nav.deep_water_region)
	NavigationServer3D.free_rid(nav.ground_map)
	NavigationServer3D.free_rid(nav.water_map)
	NavigationServer3D.free_rid(nav.amphibious_map)
	NavigationServer3D.free_rid(nav.deep_water_map)

	# On ground_map (the water area is a hole), a straight line through the
	# 30-unit-wide lake isn't available - any real path has to detour a long
	# way around, or navigation may not even find a full route depending on
	# map bounds. On amphibious_map (water is walkable), the direct route
	# straight across is available - proof this is a genuinely different,
	# wider-terrain map, not a copy of ground_map.
	var ground_dist = 0.0
	for i in range(1, ground_path.size()):
		ground_dist += ground_path[i - 1].distance_to(ground_path[i])
	var amphibious_dist = 0.0
	for i in range(1, amphibious_path.size()):
		amphibious_dist += amphibious_path[i - 1].distance_to(amphibious_path[i])
	var direct_dist = start.distance_to(goal)

	if amphibious_path.size() < 2 or amphibious_dist > direct_dist * 1.1:
		print("  [FAIL] Amphibious path should go essentially straight across the water (direct=", direct_dist, "), got ", amphibious_dist, " over ", amphibious_path.size(), " points.")
		return false
	if ground_path.size() >= 2 and ground_dist < amphibious_dist * 1.5:
		print("  [FAIL] Ground-only path should detour meaningfully around the water instead of cutting through it like the amphibious path did. ground_dist=", ground_dist, " amphibious_dist=", amphibious_dist)
		return false

	print("  [PASS] Amphibious navmesh lets a screw_drive unit cross water directly (", amphibious_dist, " units), while the ground-only map can't take the same shortcut.")
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

	# Vision: a real Skirmish match, one player unit standing on an
	# elevation zone's plateau should see further than an identical unit
	# on flat ground - verified by overriding current_map with a synthetic
	# map that has one elevation zone, then comparing effective vision via
	# _recalc_fog_of_war()'s own real reveal/hide behavior.
	await process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await process_frame
	await process_frame
	skirmish.current_map = {
		"map_half_extents": 80.0, "water_areas": [], "obstacles": [],
		"elevation_zones": [{"center": Vector3(0, 0, 0), "half_extents": Vector2(10, 10), "height": 10.0, "ramp_side": "south", "ramp_width": 6.0}],
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
	scout_ground.global_position = Vector3(-40, 0, -40)
	scout_ground.setup(bp, skirmish.PLAYER_TEAM, skirmish.bp_manager)

	var scout_hill = CharacterBody3D.new()
	scout_hill.set_script(BattleUnitScript)
	skirmish.add_child(scout_hill)
	scout_hill.global_position = Vector3(0, 10, 0)
	scout_hill.setup(bp, skirmish.PLAYER_TEAM, skirmish.bp_manager)

	var enemy_unit = CharacterBody3D.new()
	enemy_unit.set_script(BattleUnitScript)
	skirmish.add_child(enemy_unit)
	# Distance chosen to sit just outside a flat unit's base vision_range
	# but inside the elevated unit's boosted range (vision_range ~20,
	# elevation bonus at height 10 = 1 + 10*0.02 = 1.2x -> ~24).
	var enemy_dist = scout_ground.vision_range * 1.08
	enemy_unit.global_position = Vector3(0, 0, -enemy_dist)
	enemy_unit.setup(bp, skirmish.ENEMY_TEAM, skirmish.bp_manager)

	skirmish._recalc_fog_of_war()
	await process_frame

	if enemy_unit.fog_hidden:
		print("  [FAIL] Setup sanity check failed - enemy should be within the hill-standing scout's boosted vision range for this test to mean anything, but it's hidden")
		skirmish.queue_free()
		return false

	# Move the hill scout down to flat ground at the same XZ distance from
	# the enemy and re-check - should now be hidden (loses the bonus).
	scout_hill.global_position = Vector3(-40, 0, -40)
	skirmish._recalc_fog_of_war()
	await process_frame
	if not enemy_unit.fog_hidden:
		print("  [FAIL] Without the elevation bonus (scout moved to flat ground, same base vision_range), the enemy at this distance should no longer be visible")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await process_frame
	print("  [PASS] Elevated ground gives a real, measurable combat threshold reduction and vision range boost, not just a cosmetic hill.")
	return true

func test_build_placement_rejects_water_and_obstacles() -> bool:
	print("Running Test Suite: Multi-Map Terrain - Build Placement Rejects Water/Obstacles (previously nothing stopped this)...")
	await process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await process_frame
	await process_frame

	skirmish.placing = {"kind": "refinery", "cost_metal": 150, "cost_crystal": 0}
	var metal_before = skirmish.economy[skirmish.PLAYER_TEAM].metal
	# lake_crossing's real lake is at (18,0,0) with half-extents (7,7) - well
	# within the player's 28m build radius of their own base.
	skirmish._try_place_building(Vector3(18, 0, 0))
	var buildings_after = skirmish.get_team_buildings(skirmish.PLAYER_TEAM).size()

	if skirmish.economy[skirmish.PLAYER_TEAM].metal != metal_before:
		print("  [FAIL] Placing a building inside the lake should be rejected before spending any resources")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await process_frame
	print("  [PASS] Attempting to place a building inside water is rejected without spending resources.")
	return true

# Reusable per-map smoke test (per Chris's one-at-a-time verification
# instruction: each map gets a real scripted playthrough, not just eyeball
# screenshots) - real Skirmish spawn on the given map_id, checks:
# start points are legal/unblocked, every resource node is actually
# reachable from its own team's harvester spawn (no unreachable resources
# from a bad hand-authored position), the two HQs are mutually reachable
# on the ground navmesh (the AI can actually reach the player and vice
# versa), and the economy/build-queue loop still produces a real unit.
func _smoke_test_map(map_id: String) -> bool:
	var MapCatalogScript = preload("res://scripts/map_catalog.gd")
	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
	var map_def = MapCatalogScript.get_map(map_id)

	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	skirmish.map_id = map_id
	root.add_child(skirmish)
	current_scene = skirmish
	await process_frame
	await process_frame
	await process_frame

	if skirmish.map_id != map_id or skirmish.current_map.get("name", "") != map_def.name:
		print("  [FAIL] Skirmish did not load the requested map '", map_id, "'")
		skirmish.queue_free()
		return false
	if not is_instance_valid(skirmish.player_hq) or not is_instance_valid(skirmish.enemy_hq):
		print("  [FAIL] Player/enemy HQ failed to spawn on map '", map_id, "'")
		skirmish.queue_free()
		return false

	# Start points must be real, unblocked, buildable ground.
	for start_name in ["player_start", "enemy_start"]:
		var start = map_def[start_name]
		for key in ["hq", "factory", "refinery"]:
			if TerrainBuilderScript.is_position_blocked(map_def, start[key]):
				print("  [FAIL] ", start_name, ".", key, " (", start[key], ") sits on blocked terrain (water/obstacle/ramp)")
				skirmish.queue_free()
				return false

	# Every resource node must be reachable from ITS side's harvester spawn.
	var player_start_pos = map_def.player_start.harvester
	var enemy_start_pos = map_def.enemy_start.harvester
	for node_data in map_def.get("resource_nodes", []):
		var from_pos = player_start_pos if node_data.position.distance_to(player_start_pos) < node_data.position.distance_to(enemy_start_pos) else enemy_start_pos
		var path = NavigationServer3D.map_get_path(skirmish.ground_nav_map, from_pos, node_data.position, true)
		if path.size() < 2 or path[path.size() - 1].distance_to(node_data.position) > 3.0:
			print("  [FAIL] Resource node at ", node_data.position, " is not reachable by ground navmesh from the nearest base")
			skirmish.queue_free()
			return false

	# The two HQs must be mutually reachable (AI can path to the player,
	# player can path to the AI) - not stranded on disconnected navmesh
	# islands by a badly-placed water/obstacle/elevation zone.
	var hq_path = NavigationServer3D.map_get_path(skirmish.ground_nav_map, map_def.player_start.hq, map_def.enemy_start.hq, true)
	if hq_path.size() < 2 or hq_path[hq_path.size() - 1].distance_to(map_def.enemy_start.hq) > 5.0:
		print("  [FAIL] Player and enemy HQs are not mutually reachable on the ground navmesh")
		skirmish.queue_free()
		return false

	# Economy/build loop still works: queue a unit, tick past its build
	# time, confirm the factory actually produced it.
	var factory = skirmish.get_team_factory(skirmish.PLAYER_TEAM)
	if not factory:
		print("  [FAIL] No player factory found on map '", map_id, "'")
		skirmish.queue_free()
		return false
	var harv_bp = skirmish._find_harvester_blueprint(skirmish.roster)
	if harv_bp.is_empty():
		print("  [FAIL] No harvester blueprint found in the roster for map '", map_id, "'")
		skirmish.queue_free()
		return false
	var units_before = skirmish.get_team_units(skirmish.PLAYER_TEAM).size()
	factory.queue_unit(harv_bp, 0.05)
	# Building.gd's production queue ticks in its own _physics_process(),
	# which the engine calls automatically each real physics frame -
	# awaiting enough frames here (well past the 0.05s build_time at any
	# real frame rate) lets it complete without manually driving it.
	for i in range(30):
		await process_frame
	var units_after = skirmish.get_team_units(skirmish.PLAYER_TEAM).size()
	if units_after <= units_before:
		print("  [FAIL] Factory did not produce a queued unit on map '", map_id, "' (before=", units_before, " after=", units_after, ")")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await process_frame
	return true

func test_map_open_plains_smoke() -> bool:
	print("Running Test Suite: Map Smoke Test - Open Plains (start points legal, resources reachable, HQs mutually reachable, economy loop works)...")
	var ok = await _smoke_test_map("open_plains")
	if ok:
		print("  [PASS] Open Plains: legal start points, all resources reachable, HQs mutually reachable, factory production works.")
	return ok

func test_map_lake_crossing_smoke() -> bool:
	print("Running Test Suite: Map Smoke Test - Lake Crossing (same generic smoke test, run against the refactored default map)...")
	var ok = await _smoke_test_map("lake_crossing")
	if ok:
		print("  [PASS] Lake Crossing: legal start points, all resources reachable, HQs mutually reachable, factory production works.")
	return ok

func test_map_highland_chokepoint_smoke() -> bool:
	print("Running Test Suite: Map Smoke Test - Highland Chokepoint (start points legal, resources reachable, HQs mutually reachable through the flanking lanes, economy loop works)...")
	var ok = await _smoke_test_map("highland_chokepoint")
	if ok:
		print("  [PASS] Highland Chokepoint: legal start points, all resources reachable, HQs mutually reachable, factory production works.")
	return ok

func test_map_coastal_strand_smoke() -> bool:
	print("Running Test Suite: Map Smoke Test - Coastal Strand (start points legal, resources reachable, HQs mutually reachable around inland obstacles, economy loop works)...")
	var ok = await _smoke_test_map("coastal_strand")
	if ok:
		print("  [PASS] Coastal Strand: legal start points, all resources reachable, HQs mutually reachable, factory production works.")
	return ok

func test_map_twin_bridges_smoke() -> bool:
	print("Running Test Suite: Map Smoke Test - Twin Bridges (start points legal, resources reachable, HQs mutually reachable via a real bridge crossing, economy loop works)...")
	var ok = await _smoke_test_map("twin_bridges")
	if ok:
		print("  [PASS] Twin Bridges: legal start points, all resources reachable, HQs mutually reachable across the river via a bridge, factory production works.")
	return ok

func test_map_twin_summits_smoke() -> bool:
	print("Running Test Suite: Map Smoke Test - Twin Summits (start points legal, resources reachable, both hills reachable, HQs mutually reachable, economy loop works)...")
	var ok = await _smoke_test_map("twin_summits")
	if ok:
		print("  [PASS] Twin Summits: legal start points, all resources reachable, HQs mutually reachable, factory production works.")
	return ok

func test_map_close_quarters_smoke() -> bool:
	print("Running Test Suite: Map Smoke Test - Close Quarters (start points legal, resources reachable through the 3 lanes, HQs mutually reachable, economy loop works)...")
	var ok = await _smoke_test_map("close_quarters")
	if ok:
		print("  [PASS] Close Quarters: legal start points, all resources reachable, HQs mutually reachable, factory production works.")
	return ok

func test_map_urban_sprawl_smoke() -> bool:
	print("Running Test Suite: Map Smoke Test - Urban Sprawl (start points legal, resources reachable through the street grid, HQs mutually reachable, economy loop works)...")
	var ok = await _smoke_test_map("urban_sprawl")
	if ok:
		print("  [PASS] Urban Sprawl: legal start points, all resources reachable, HQs mutually reachable, factory production works.")
	return ok

func test_weapon_traverse_and_range_differentiation() -> bool:
	print("Running Test Suite: Per-Weapon-Type Traverse Rate & Range Tweak Differentiation...")

	var w_script = load("res://scripts/auto_weapon.gd")

	var make_weapon = func(type_id: String, weight: float, tweaks: Dictionary) -> Node3D:
		var parent = Node3D.new()
		var weapon = Node3D.new()
		weapon.set_script(w_script)
		parent.add_child(weapon)
		root.add_child(parent)
		var data = ModuleData.new()
		data.type_id = type_id
		data.base_weight = weight
		data.base_dps = 50.0
		data.tweaks = tweaks
		weapon.set_meta("module_data", data)
		weapon._ready()
		return weapon

	# 1. Two weapons at the SAME weight but different archetypes should get
	# genuinely different traverse speeds - direct proof the per-type
	# traverse_agility multiplier is doing real work, not just weight (both
	# ~90kg here: ciws is a fast point-defense tracker, mortar_array is a
	# slow indirect-fire weapon that previously traversed identically).
	var ciws = make_weapon.call("ciws", 90.0, {})
	var mortar = make_weapon.call("mortar_array", 90.0, {})
	if ciws.traverse_speed <= mortar.traverse_speed:
		print("  [FAIL] ciws (fast point-defense tracker) should traverse meaningfully faster than mortar_array (slow indirect-fire) at the same weight. ciws=", ciws.traverse_speed, " mortar=", mortar.traverse_speed)
		return false
	ciws.get_parent().queue_free()
	mortar.get_parent().queue_free()

	# 2. gauss_railgun's only tweak (rail_length) previously had zero effect
	# on its own fire_range - confirm a bigger rail now actually extends it.
	var railgun_base = make_weapon.call("gauss_railgun", 180.0, {})
	var railgun_long_rail = make_weapon.call("gauss_railgun", 180.0, {"rail_length": 1.8})
	if railgun_long_rail.fire_range <= railgun_base.fire_range:
		print("  [FAIL] gauss_railgun's rail_length tweak should extend fire_range. base=", railgun_base.fire_range, " long_rail=", railgun_long_rail.fire_range)
		return false
	railgun_base.get_parent().queue_free()
	railgun_long_rail.get_parent().queue_free()

	# 3. A weapon's own size tweak (not just barrel_length/elevation) should
	# now cost EXTRA traverse_speed beyond what the weight increase alone
	# would explain - heavy_machine_gun's drum_size previously only touched
	# weight (an indirect effect), with zero direct traverse penalty.
	var mg_big_drum_data = ModuleData.new()
	mg_big_drum_data.type_id = "heavy_machine_gun"
	mg_big_drum_data.base_weight = 40.0
	mg_big_drum_data.tweaks = {"drum_size": 2.0}
	var weight_only_traverse = clamp(200.0 / mg_big_drum_data.get_weight(), 0.4, 8.0) * ModuleCatalog.get_traverse_agility("heavy_machine_gun")
	var mg_big_drum = make_weapon.call("heavy_machine_gun", 40.0, {"drum_size": 2.0})
	if mg_big_drum.traverse_speed >= weight_only_traverse - 0.001:
		print("  [FAIL] heavy_machine_gun's drum_size tweak should cost EXTRA traverse_speed beyond its weight effect alone. weight-only=", weight_only_traverse, " actual=", mg_big_drum.traverse_speed)
		return false
	mg_big_drum.get_parent().queue_free()

	print("  [PASS] Weapon traverse rate is genuinely differentiated per type (not just weight), and tweaks that weren't previously wired to traverse/range now move them.")
	return true

func test_weight_vs_locomotion_capacity_penalty() -> bool:
	print("Running Test Suite: Weight vs. Locomotion Capacity - Overload Slows The Unit...")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	# Builds a minimal unit with a fake hull_node carrying a locomotion
	# child (+ an optional heavy weapon child to push total weight up) and
	# calls _recalculate_move_speed() directly - same "mock the exact
	# fields the function reads" approach as test_traverse_limit's mock
	# weapon, so the test controls weight/scale precisely instead of
	# depending on the real blueprint pipeline's own scale decisions.
	var make_unit = func(locomotion_id: String, loco_weight: float, extra_module_weight: float) -> Node:
		var unit = CharacterBody3D.new()
		unit.set_script(BattleUnitScript)
		root.add_child(unit)
		unit.locomotion_type = locomotion_id
		unit.locomotion_settings = {}
		var fake_hull = Node3D.new()
		unit.add_child(fake_hull)
		unit.hull_node = fake_hull

		var loco_child = Node3D.new()
		var loco_data = ModuleData.new()
		loco_data.type_id = locomotion_id
		loco_data.category = "locomotion"
		loco_data.base_weight = loco_weight
		loco_child.set_meta("module_data", loco_data)
		fake_hull.add_child(loco_child)

		if extra_module_weight > 0.0:
			var extra_child = Node3D.new()
			var extra_data = ModuleData.new()
			extra_data.type_id = "heavy_howitzer"
			extra_data.category = "weapon"
			extra_data.base_weight = extra_module_weight
			extra_child.set_meta("module_data", extra_data)
			fake_hull.add_child(extra_child)

		unit._recalculate_move_speed()
		return unit

	# wheels' own capacity is 350 (ModuleCatalog.get_base_weight_capacity) -
	# a 400kg weapon on top of a 50kg wheel chassis (450 total) pushes it
	# over. tracked_treads' capacity is 700 - the SAME 400kg weapon on a
	# 120kg tread chassis (520 total) stays comfortably under. This is the
	# core ask made concrete: heavier/tougher locomotion tolerates more
	# excess weight before the penalty kicks in.
	var overloaded_wheels = make_unit.call("wheels", 50.0, 400.0)
	var loaded_treads = make_unit.call("tracked_treads", 120.0, 400.0)

	# Prove the wheels case is ACTUALLY penalized, not just naturally slower
	# from carrying more weight (which the pre-existing thrust/weight ratio
	# already accounts for) - compute what the unpenalized formula alone
	# would predict (motor_thrust=100+150 for one locomotion module,
	# weight=450) and confirm the real value is meaningfully below it.
	var wheels_motor_thrust = 100.0 + 150.0
	var wheels_unpenalized = clamp((wheels_motor_thrust / 450.0) * 5.0, 2.0, 15.0)
	if overloaded_wheels.move_speed >= wheels_unpenalized - 0.01:
		print("  [FAIL] An overloaded wheeled unit (450kg vs. 350 capacity) should be penalized below the unpenalized thrust/weight prediction. unpenalized=", wheels_unpenalized, " actual=", overloaded_wheels.move_speed)
		overloaded_wheels.queue_free()
		loaded_treads.queue_free()
		return false

	# Prove the treads case gets NO penalty (matches the plain formula
	# exactly, since it's under its own higher capacity).
	var treads_motor_thrust = 100.0 + 150.0
	var treads_unpenalized = clamp((treads_motor_thrust / 520.0) * 5.0, 2.0, 15.0)
	if abs(loaded_treads.move_speed - treads_unpenalized) > 0.01:
		print("  [FAIL] A tracked_treads unit under its own capacity (520kg vs. 700) should be unpenalized. expected=", treads_unpenalized, " actual=", loaded_treads.move_speed)
		overloaded_wheels.queue_free()
		loaded_treads.queue_free()
		return false

	# A lightly-loaded unit well under capacity should also see zero
	# penalty (multiplier is a true no-op below the threshold, not just a
	# small one).
	var light_wheels = make_unit.call("wheels", 50.0, 0.0)
	var light_unpenalized = clamp((wheels_motor_thrust / 50.0) * 5.0, 2.0, 15.0)
	if abs(light_wheels.move_speed - light_unpenalized) > 0.01:
		print("  [FAIL] A lightly-loaded wheeled unit (50kg vs. 350 capacity) should have zero overload penalty. expected=", light_unpenalized, " actual=", light_wheels.move_speed)
		overloaded_wheels.queue_free()
		loaded_treads.queue_free()
		light_wheels.queue_free()
		return false

	overloaded_wheels.queue_free()
	loaded_treads.queue_free()
	light_wheels.queue_free()
	print("  [PASS] Weight beyond a locomotor's own capacity measurably slows the unit; heavier locomotion types (tracked_treads) tolerate more excess weight before the penalty kicks in than lighter ones (wheels); units under capacity are unaffected.")
	return true

func test_mobility_addon_modules_boost_capacity_and_thrust() -> bool:
	print("Running Test Suite: Mobility Add-On Modules (wing/thruster) Boost Capacity/Thrust...")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var make_unit = func(extra_type_id: String) -> Node:
		var unit = CharacterBody3D.new()
		unit.set_script(BattleUnitScript)
		root.add_child(unit)
		unit.locomotion_type = "wheels"
		unit.locomotion_settings = {}
		var fake_hull = Node3D.new()
		unit.add_child(fake_hull)
		unit.hull_node = fake_hull

		var loco_child = Node3D.new()
		var loco_data = ModuleData.new()
		loco_data.type_id = "wheels"
		loco_data.category = "locomotion"
		loco_data.base_weight = 50.0
		loco_child.set_meta("module_data", loco_data)
		fake_hull.add_child(loco_child)

		# Heavy shared ballast (present in every case, including baseline) so
		# total_weight is high enough that move_speed sits comfortably below
		# the clamp(2.0, 15.0) ceiling - otherwise an already-maxed baseline
		# would hide a real thrust_bonus increase behind the clamp.
		var ballast_child = Node3D.new()
		var ballast_data = ModuleData.new()
		ballast_data.type_id = "armor_plating"
		ballast_data.category = "armor"
		ballast_data.base_weight = 400.0
		ballast_child.set_meta("module_data", ballast_data)
		fake_hull.add_child(ballast_child)

		if extra_type_id != "":
			var extra_child = Node3D.new()
			var extra_data = ModuleData.new()
			extra_data.type_id = extra_type_id
			extra_data.category = "module"
			extra_data.base_weight = 10.0
			extra_child.set_meta("module_data", extra_data)
			fake_hull.add_child(extra_child)

		unit._recalculate_move_speed()
		return unit

	# The shared 400kg ballast pushes total_weight (450kg) past wheels' own
	# 350 capacity for every case - baseline is genuinely overloaded, not
	# just slow from raw weight, so a wing lifting it back under capacity
	# (or a thruster/propeller adding raw thrust) shows up as a real,
	# unclamped move_speed increase rather than being masked by the
	# clamp(2.0, 15.0) ceiling a lighter baseline would hit.
	var baseline = make_unit.call("")
	var winged = make_unit.call("wing")
	if winged.move_speed <= baseline.move_speed:
		print("  [FAIL] wing's weight_capacity_bonus should raise move_speed above the overloaded baseline (by lifting total capacity closer to/above total weight). baseline=", baseline.move_speed, " with_wing=", winged.move_speed)
		baseline.queue_free(); winged.queue_free()
		return false

	var thrusted = make_unit.call("thruster")
	var propped = make_unit.call("propeller_prop")
	if thrusted.move_speed <= baseline.move_speed:
		print("  [FAIL] thruster's thrust_bonus should raise move_speed above the plain wheels-only baseline. baseline=", baseline.move_speed, " with_thruster=", thrusted.move_speed)
		baseline.queue_free(); winged.queue_free(); thrusted.queue_free(); propped.queue_free()
		return false
	if propped.move_speed <= baseline.move_speed:
		print("  [FAIL] propeller_prop's thrust_bonus should raise move_speed above the plain wheels-only baseline. baseline=", baseline.move_speed, " with_propeller=", propped.move_speed)
		baseline.queue_free(); winged.queue_free(); thrusted.queue_free(); propped.queue_free()
		return false

	baseline.queue_free(); winged.queue_free(); thrusted.queue_free(); propped.queue_free()
	print("  [PASS] Mobility add-on modules (wing/thruster/propeller_prop) each contribute a real, measurable capacity/thrust bonus beyond the base locomotion alone.")
	return true

func test_locomotion_tweaks_have_real_visual_and_stat_effects() -> bool:
	print("Running Test Suite: Locomotion Tweaks (axle-count/leg-count/tread-width) Have Real Visual + Stat Effects...")
	var ModulePlacerScript = preload("res://scripts/module_placer.gd")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var controller_script = preload("res://scripts/fake_surface_controller.gd")

	# --- Visual: count/width tweaks actually change spawned geometry, not
	# just the underlying stats - through the real module_placer.gd path. ---
	var hull = StaticBody3D.new()
	hull.name = "Hull"
	var mesh_inst = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(4.0, 1.0, 6.0)
	mesh_inst.mesh = box
	mesh_inst.name = "MeshInstance3D"
	hull.add_child(mesh_inst)
	var col = CollisionShape3D.new()
	var col_box = BoxShape3D.new()
	col_box.size = Vector3(4.0, 1.0, 6.0)
	col.shape = col_box
	col.name = "CollisionShape3D"
	hull.add_child(col)
	hull.set_meta("base_hull_size", Vector3(4.0, 1.0, 6.0))
	hull.set_meta("hull_scale", Vector3(1, 1, 1))
	hull.set_meta("type_id", "medium_hull")
	root.add_child(hull)
	await process_frame

	var placer = Node3D.new()
	placer.set_script(ModulePlacerScript)
	placer.hull = hull
	root.add_child(placer)
	await process_frame

	var count_children = func(type_id: String) -> int:
		var n = 0
		for child in hull.get_children():
			if child.has_meta("module_data") and child.get_meta("module_data").type_id == type_id:
				n += 1
		return n

	placer.update_locomotion("wheels", {"size": 1.0, "count": 2})
	await process_frame
	var wheels_low_count = count_children.call("wheels")
	placer.update_locomotion("wheels", {"size": 1.0, "count": 8})
	await process_frame
	var wheels_high_count = count_children.call("wheels")
	if wheels_high_count <= wheels_low_count:
		print("  [FAIL] wheels axle-count tweak didn't change the number of spawned wheel instances (low=", wheels_low_count, " high=", wheels_high_count, ")")
		placer.queue_free(); hull.queue_free()
		return false

	placer.update_locomotion("legs", {"size": 1.0, "count": 2})
	await process_frame
	var legs_low_count = count_children.call("legs")
	placer.update_locomotion("legs", {"size": 1.0, "count": 8})
	await process_frame
	var legs_high_count = count_children.call("legs")
	if legs_high_count <= legs_low_count:
		print("  [FAIL] legs leg-count tweak didn't change the number of spawned leg instances (low=", legs_low_count, " high=", legs_high_count, ")")
		placer.queue_free(); hull.queue_free()
		return false

	placer.update_locomotion("tracked_treads", {"width": 0.5})
	await process_frame
	var tread_narrow_scale = 0.0
	for child in hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "tracked_treads":
			tread_narrow_scale = child.scale.x
			break
	placer.update_locomotion("tracked_treads", {"width": 2.5})
	await process_frame
	var tread_wide_scale = 0.0
	for child in hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "tracked_treads":
			tread_wide_scale = child.scale.x
			break
	if tread_wide_scale <= tread_narrow_scale:
		print("  [FAIL] tracked_treads width tweak didn't visually widen the tread (narrow_scale=", tread_narrow_scale, " wide_scale=", tread_wide_scale, ")")
		placer.queue_free(); hull.queue_free()
		return false

	placer.queue_free()
	hull.queue_free()
	await process_frame

	# --- Stat: tweaks produce a real, correctly-directioned move_speed
	# effect, using the mobility-addon test's ballast pattern to isolate
	# thrust-only vs. capacity/overload-only effects. ---
	var make_unit = func(loco_type: String, settings: Dictionary, ballast_weight: float) -> Node:
		var unit = CharacterBody3D.new()
		unit.set_script(BattleUnitScript)
		root.add_child(unit)
		unit.locomotion_type = loco_type
		unit.locomotion_settings = settings
		var fake_hull = Node3D.new()
		unit.add_child(fake_hull)
		unit.hull_node = fake_hull

		var loco_child = Node3D.new()
		var loco_data = ModuleData.new()
		loco_data.type_id = loco_type
		loco_data.category = "locomotion"
		loco_data.base_weight = 50.0
		loco_child.set_meta("module_data", loco_data)
		fake_hull.add_child(loco_child)

		var ballast_child = Node3D.new()
		var ballast_data = ModuleData.new()
		ballast_data.type_id = "armor_plating"
		ballast_data.category = "armor"
		ballast_data.base_weight = ballast_weight
		ballast_child.set_meta("module_data", ballast_data)
		fake_hull.add_child(ballast_child)

		unit._recalculate_move_speed()
		return unit

	# Wheels regression check: axle count should still raise BOTH thrust and
	# capacity together (no tradeoff) exactly like before this batch's
	# thrust/capacity split refactor - same heavy-ballast overload pattern
	# as test_mobility_addon_modules_boost_capacity_and_thrust so the
	# capacity increase shows up as a real, unclamped speed gain.
	var wheels_2 = make_unit.call("wheels", {"count": 2}, 400.0)
	var wheels_8 = make_unit.call("wheels", {"count": 8}, 400.0)
	if wheels_8.move_speed <= wheels_2.move_speed:
		print("  [FAIL] more wheel axles should raise move_speed (more thrust AND more capacity, less overload). count=2:", wheels_2.move_speed, " count=8:", wheels_8.move_speed)
		return false

	# Legs, light load (no overload either way): fewer legs should be
	# FASTER (higher thrust_contrib - agility tradeoff), proving the
	# leg-count tweak now moves thrust, not just capacity.
	var legs_2_light = make_unit.call("legs", {"count": 2}, 50.0)
	var legs_8_light = make_unit.call("legs", {"count": 8}, 50.0)
	if legs_2_light.move_speed <= legs_8_light.move_speed:
		print("  [FAIL] fewer legs should be faster under light load (higher thrust_contrib). count=2:", legs_2_light.move_speed, " count=8:", legs_8_light.move_speed)
		return false

	# Legs, heavy load (overload isolation): MORE legs should win here
	# despite lower thrust_contrib, because more legs means more weight
	# capacity and the 2-leg case is badly overloaded at this weight.
	# Proves the capacity side of the tradeoff is real too, not just thrust.
	var legs_2_heavy = make_unit.call("legs", {"count": 2}, 600.0)
	var legs_8_heavy = make_unit.call("legs", {"count": 8}, 600.0)
	if legs_8_heavy.move_speed <= legs_2_heavy.move_speed:
		print("  [FAIL] more legs should win under heavy load (more capacity outweighs lower thrust_contrib). count=2:", legs_2_heavy.move_speed, " count=8:", legs_8_heavy.move_speed)
		return false

	# Treads, light load: narrower should be FASTER (higher thrust_contrib).
	var treads_narrow_light = make_unit.call("tracked_treads", {"width": 0.5}, 50.0)
	var treads_wide_light = make_unit.call("tracked_treads", {"width": 2.5}, 50.0)
	if treads_narrow_light.move_speed <= treads_wide_light.move_speed:
		print("  [FAIL] narrower treads should be faster under light load. narrow=", treads_narrow_light.move_speed, " wide=", treads_wide_light.move_speed)
		return false

	# Treads, heavy load: WIDER should win here (more capacity, less/no
	# overload penalty outweighs its lower thrust_contrib).
	var treads_narrow_heavy = make_unit.call("tracked_treads", {"width": 0.5}, 600.0)
	var treads_wide_heavy = make_unit.call("tracked_treads", {"width": 2.5}, 600.0)
	if treads_wide_heavy.move_speed <= treads_narrow_heavy.move_speed:
		print("  [FAIL] wider treads should win under heavy load (more capacity). narrow=", treads_narrow_heavy.move_speed, " wide=", treads_wide_heavy.move_speed)
		return false

	for u in [wheels_2, wheels_8, legs_2_light, legs_8_light, legs_2_heavy, legs_8_heavy, treads_narrow_light, treads_wide_light, treads_narrow_heavy, treads_wide_heavy]:
		u.queue_free()

	# --- Terrain multiplier: tread width should modulate the marsh
	# penalty (wider = less severe), not just the flat catalog number. ---
	var measure_terrain = func(width: float) -> float:
		var controller = Node.new()
		controller.set_script(controller_script)
		controller.surface_type = "marsh"
		root.add_child(controller)
		var unit = CharacterBody3D.new()
		unit.set_script(BattleUnitScript)
		controller.add_child(unit)
		unit.locomotion_type = "tracked_treads"
		unit.locomotion_settings = {"width": width}
		unit.global_position = Vector3.ZERO
		unit._recalculate_terrain_speed_multiplier()
		var result = unit.terrain_speed_multiplier
		controller.queue_free()
		return result

	var marsh_narrow = measure_terrain.call(0.5)
	var marsh_wide = measure_terrain.call(2.5)
	if marsh_wide <= marsh_narrow:
		print("  [FAIL] wider treads should suffer less of a marsh speed penalty than narrower ones. narrow_multiplier=", marsh_narrow, " wide_multiplier=", marsh_wide)
		return false

	print("  [PASS] Wheels axle-count, legs leg-count, and tracked_treads width tweaks all produce real spawned-geometry changes and real, correctly-directioned move_speed/terrain effects - not just sliders.")
	return true

func test_ornithopter_wing_spawns_flaps_and_flies() -> bool:
	print("Running Test Suite: Ornithopter Wing - Real Placement, Flap Animation, and Hover-Capable Flight...")
	var ModulePlacerScript = preload("res://scripts/module_placer.gd")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	# Traits: airborne (flies) but NOT fixed_wing - simple hover-arrival
	# flight like helicopter_rotors/hover_engine/anti_grav, not the
	# banking/minimum-airspeed paradigm. The mechanical similarity to
	# existing flight locomotion Chris explicitly asked for; the visual/
	# flavor (flapping motion, distinct silhouette) is the real differentiator.
	var loco_traits = ModuleCatalog.get_traits("medium_hull", "ornithopter_wing")
	if not ("airborne" in loco_traits):
		print("  [FAIL] ornithopter_wing should carry the airborne trait")
		return false
	if "fixed_wing" in loco_traits:
		print("  [FAIL] ornithopter_wing should NOT carry fixed_wing (simple hover flight, not banking/airspeed)")
		return false

	# Real placement via module_placer.gd: 2 wing instances (left/right),
	# each with a WingPivot node (the flap-animation target).
	var hull = StaticBody3D.new()
	hull.name = "Hull"
	var col = CollisionShape3D.new()
	var col_box = BoxShape3D.new()
	col_box.size = Vector3(4.0, 1.0, 6.0)
	col.shape = col_box
	col.name = "CollisionShape3D"
	hull.add_child(col)
	hull.set_meta("base_hull_size", Vector3(4.0, 1.0, 6.0))
	hull.set_meta("hull_scale", Vector3(1, 1, 1))
	hull.set_meta("type_id", "medium_hull")
	root.add_child(hull)
	await process_frame

	var placer = Node3D.new()
	placer.set_script(ModulePlacerScript)
	placer.hull = hull
	root.add_child(placer)
	await process_frame

	placer.update_locomotion("ornithopter_wing", {"size": 1.0, "count": 2})
	await process_frame

	var wing_instances = []
	for child in hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "ornithopter_wing":
			wing_instances.append(child)
	if wing_instances.size() != 2:
		print("  [FAIL] expected 2 ornithopter_wing instances (left/right), found ", wing_instances.size())
		placer.queue_free(); hull.queue_free()
		return false
	for w in wing_instances:
		if not w.has_node("WingPivot"):
			print("  [FAIL] ornithopter_wing instance missing WingPivot (flap-animation target)")
			placer.queue_free(); hull.queue_free()
			return false

	placer.queue_free()
	await process_frame

	# Flap animation: real oscillation over time, driven by battle_unit.gd's
	# per-physics-tick update, not a static authored pose.
	var unit = CharacterBody3D.new()
	unit.set_script(BattleUnitScript)
	root.add_child(unit)
	unit.locomotion_type = "ornithopter_wing"
	unit.locomotion_settings = {}
	unit.is_flying = true
	hull.get_parent().remove_child(hull)
	unit.add_child(hull)
	unit.hull_node = hull
	unit.global_position = Vector3.ZERO
	await process_frame

	var pivot = wing_instances[0].get_node("WingPivot")
	unit._physics_process(1.0 / 60.0)
	var rot_a = pivot.rotation.x
	await process_frame
	await process_frame
	await process_frame
	unit._physics_process(1.0 / 60.0)
	var rot_b = pivot.rotation.x
	unit.queue_free()
	if is_equal_approx(rot_a, rot_b):
		print("  [FAIL] ornithopter wing flap animation isn't changing over time (rot_a=", rot_a, " rot_b=", rot_b, ")")
		return false

	print("  [PASS] ornithopter_wing spawns 2 real wing instances with a flap-animation pivot, carries the airborne-not-fixed_wing trait combo for simple hover-capable flight, and its flap motion genuinely oscillates over time.")
	return true

func test_rhomboid_treads_spawns_and_differentiates_from_tracked_treads() -> bool:
	print("Running Test Suite: Rhomboid (MkIV) Treads - Real Placement, Tougher-But-Slower Tradeoff, and Terrain Differentiation...")
	var ModulePlacerScript = preload("res://scripts/module_placer.gd")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var controller_script = preload("res://scripts/fake_surface_controller.gd")

	# Real placement via module_placer.gd: 2 loop instances (left/right),
	# same mount pattern as tracked_treads.
	var hull = StaticBody3D.new()
	hull.name = "Hull"
	var col = CollisionShape3D.new()
	var col_box = BoxShape3D.new()
	col_box.size = Vector3(4.0, 1.0, 6.0)
	col.shape = col_box
	col.name = "CollisionShape3D"
	hull.add_child(col)
	hull.set_meta("base_hull_size", Vector3(4.0, 1.0, 6.0))
	hull.set_meta("hull_scale", Vector3(1, 1, 1))
	hull.set_meta("type_id", "medium_hull")
	root.add_child(hull)
	await process_frame

	var placer = Node3D.new()
	placer.set_script(ModulePlacerScript)
	placer.hull = hull
	root.add_child(placer)
	await process_frame

	placer.update_locomotion("rhomboid_treads", {"width": 1.0})
	await process_frame

	var loop_instances = []
	for child in hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "rhomboid_treads":
			loop_instances.append(child)
	if loop_instances.size() != 2:
		print("  [FAIL] expected 2 rhomboid_treads instances (left/right), found ", loop_instances.size())
		placer.queue_free(); hull.queue_free()
		return false
	placer.queue_free(); hull.queue_free()
	await process_frame

	# Stat tradeoff at default settings: tougher (more weight capacity) but
	# slower (lower thrust_coefficient) than tracked_treads - a real,
	# distinct silhouette AND a real, distinct stat profile, not a
	# reskinned tracked_treads.
	var make_unit = func(loco_type: String, ballast_weight: float) -> Node:
		var unit = CharacterBody3D.new()
		unit.set_script(BattleUnitScript)
		root.add_child(unit)
		unit.locomotion_type = loco_type
		unit.locomotion_settings = {"width": 1.0}
		var fake_hull = Node3D.new()
		unit.add_child(fake_hull)
		unit.hull_node = fake_hull
		var loco_child = Node3D.new()
		var loco_data = ModuleData.new()
		loco_data.type_id = loco_type
		loco_data.category = "locomotion"
		loco_data.base_weight = 50.0
		loco_child.set_meta("module_data", loco_data)
		fake_hull.add_child(loco_child)
		var ballast_child = Node3D.new()
		var ballast_data = ModuleData.new()
		ballast_data.type_id = "armor_plating"
		ballast_data.category = "armor"
		ballast_data.base_weight = ballast_weight
		ballast_child.set_meta("module_data", ballast_data)
		fake_hull.add_child(ballast_child)
		unit._recalculate_move_speed()
		return unit

	# Light load (no overload for either): rhomboid_treads should be
	# SLOWER than tracked_treads (lower thrust_coefficient - the real
	# Mark IV's ~4mph top speed).
	var tracked_light = make_unit.call("tracked_treads", 50.0)
	var rhomboid_light = make_unit.call("rhomboid_treads", 50.0)
	if rhomboid_light.move_speed >= tracked_light.move_speed:
		print("  [FAIL] rhomboid_treads should be slower than tracked_treads under light load. tracked=", tracked_light.move_speed, " rhomboid=", rhomboid_light.move_speed)
		return false

	# Heavy load (capacity matters): rhomboid_treads' higher base_weight_capacity
	# (900 vs 700) should let it shrug off a load that overloads tracked_treads
	# harder - closing the gap even though it's still the slower type at heart.
	var overload_weight = 750.0
	var tracked_heavy = make_unit.call("tracked_treads", overload_weight)
	var rhomboid_heavy = make_unit.call("rhomboid_treads", overload_weight)
	var tracked_ratio = tracked_heavy.move_speed / tracked_light.move_speed
	var rhomboid_ratio = rhomboid_heavy.move_speed / rhomboid_light.move_speed
	if rhomboid_ratio <= tracked_ratio:
		print("  [FAIL] rhomboid_treads' higher capacity should mean it retains proportionally more speed under a heavy load than tracked_treads. tracked_ratio=", tracked_ratio, " rhomboid_ratio=", rhomboid_ratio)
		return false

	tracked_light.queue_free(); rhomboid_light.queue_free(); tracked_heavy.queue_free(); rhomboid_heavy.queue_free()

	# Terrain: rhomboid_treads should beat tracked_treads on marsh (the
	# whole reason the real Mark IV existed) but lose to it on rocky
	# terrain (long, heavy, low-clearance loop is less nimble on rock).
	var measure_terrain = func(loco_type: String, surface: String) -> float:
		var controller = Node.new()
		controller.set_script(controller_script)
		controller.surface_type = surface
		root.add_child(controller)
		var unit = CharacterBody3D.new()
		unit.set_script(BattleUnitScript)
		controller.add_child(unit)
		unit.locomotion_type = loco_type
		unit.locomotion_settings = {"width": 1.0}
		unit.global_position = Vector3.ZERO
		unit._recalculate_terrain_speed_multiplier()
		var result = unit.terrain_speed_multiplier
		controller.queue_free()
		return result

	var tracked_marsh = measure_terrain.call("tracked_treads", "marsh")
	var rhomboid_marsh = measure_terrain.call("rhomboid_treads", "marsh")
	if rhomboid_marsh <= tracked_marsh:
		print("  [FAIL] rhomboid_treads should handle marsh better than tracked_treads. tracked=", tracked_marsh, " rhomboid=", rhomboid_marsh)
		return false

	var tracked_rocky = measure_terrain.call("tracked_treads", "rocky")
	var rhomboid_rocky = measure_terrain.call("rhomboid_treads", "rocky")
	if rhomboid_rocky >= tracked_rocky:
		print("  [FAIL] rhomboid_treads should handle rocky terrain worse than tracked_treads. tracked=", tracked_rocky, " rhomboid=", rhomboid_rocky)
		return false

	print("  [PASS] rhomboid_treads spawns 2 real full-loop instances distinct from tracked_treads, is genuinely slower but tougher (retains more speed under heavy load), and is genuinely better on marsh / worse on rocky terrain.")
	return true

func test_omni_wheels_can_strafe_sideways_without_turning() -> bool:
	print("Running Test Suite: Omni Wheels - Real Lateral Strafing (Not Just Cosmetic)...")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var controller_script = preload("res://scripts/fake_surface_controller.gd")

	# Trait check first: omni_wheels should carry the "omni" trait that
	# actually drives battle_unit.gd's is_omni derivation.
	var loco_traits = ModuleCatalog.get_traits("medium_hull", "omni_wheels")
	if not ("omni" in loco_traits):
		print("  [FAIL] omni_wheels should carry the omni trait")
		return false

	var make_unit = func(loco_type: String) -> Node:
		var controller = Node.new()
		controller.set_script(controller_script)
		controller.surface_type = ""
		root.add_child(controller)

		var unit = CharacterBody3D.new()
		unit.set_script(BattleUnitScript)
		controller.add_child(unit)
		unit.locomotion_type = loco_type
		unit.locomotion_settings = {}
		unit.is_omni = (loco_type == "omni_wheels")
		var fake_hull = Node3D.new()
		unit.add_child(fake_hull)
		unit.hull_node = fake_hull
		var loco_data = ModuleData.new()
		loco_data.type_id = loco_type
		loco_data.category = "locomotion"
		loco_data.base_weight = 80.0
		var loco_child = Node3D.new()
		loco_child.set_meta("module_data", loco_data)
		fake_hull.add_child(loco_child)
		unit._recalculate_move_speed()
		unit.global_position = Vector3.ZERO
		unit.global_rotation = Vector3.ZERO
		return unit

	var omni_unit = make_unit.call("omni_wheels")
	var wheels_unit = make_unit.call("wheels")

	# Sideways destination: directly along +X, perpendicular to both units'
	# initial forward (-Z, the default CharacterBody3D orientation) - a
	# normal wheeled unit has to turn ~90 degrees before it can make real
	# progress toward this; an omni unit structurally shouldn't need to.
	var sideways_target = Vector3(1000, 0, 0)
	omni_unit.order_move(sideways_target)
	wheels_unit.order_move(sideways_target)

	var initial_rot_y = omni_unit.rotation.y
	for i in range(60):
		omni_unit._physics_process(1.0 / 60.0)
		omni_unit.move_and_slide()
		wheels_unit._physics_process(1.0 / 60.0)
		wheels_unit.move_and_slide()

	var omni_rot_change = abs(wrapf(omni_unit.rotation.y - initial_rot_y, -PI, PI))
	var wheels_rot_change = abs(wrapf(wheels_unit.rotation.y - initial_rot_y, -PI, PI))

	var omni_controller = omni_unit.get_parent()
	var wheels_controller = wheels_unit.get_parent()

	if omni_rot_change > 0.05:
		print("  [FAIL] omni_wheels unit rotated while strafing sideways (rot_change=", omni_rot_change, ") - should hold a fixed facing")
		omni_controller.queue_free(); wheels_controller.queue_free()
		return false

	if wheels_rot_change < 0.3:
		print("  [FAIL] plain wheels unit should have turned substantially to face the sideways destination (rot_change=", wheels_rot_change, ") - the contrast case isn't behaving as expected")
		omni_controller.queue_free(); wheels_controller.queue_free()
		return false

	if omni_unit.global_position.x < 5.0:
		print("  [FAIL] omni_wheels unit should have made real lateral progress toward the sideways destination (x=", omni_unit.global_position.x, ")")
		omni_controller.queue_free(); wheels_controller.queue_free()
		return false

	# The actual comparative claim: having spent zero ticks turning, the
	# omni unit should out-pace the plain wheeled unit toward a purely
	# sideways target over the same tick count, since the wheeled unit
	# burns part of those ticks rotating before it can move efficiently
	# toward it.
	if omni_unit.global_position.x <= wheels_unit.global_position.x:
		print("  [FAIL] omni_wheels should out-pace plain wheels toward a purely-sideways target (it doesn't need to turn first). omni_x=", omni_unit.global_position.x, " wheels_x=", wheels_unit.global_position.x)
		omni_controller.queue_free(); wheels_controller.queue_free()
		return false

	omni_controller.queue_free()
	wheels_controller.queue_free()
	print("  [PASS] omni_wheels unit genuinely strafes sideways while holding a fixed facing (near-zero rotation change), out-pacing a plain wheeled unit toward the same sideways destination since it doesn't have to turn first.")
	return true

# --- Hull Modding (HULL_MODDING_PLAN.md) ---

func test_hull_modding_loader_scan_and_validation() -> bool:
	print("Running Test Suite: Hull Modding - HullLoader Scan, Validation, Mod-Overrides-Builtin Precedence...")
	var mods_dir = "user://mods/hulls"
	DirAccess.make_dir_recursive_absolute(mods_dir)

	var written_files = []
	var write_file = func(fname: String, content: String):
		var f = FileAccess.open(mods_dir + "/" + fname, FileAccess.WRITE)
		f.store_string(content)
		f.close()
		written_files.append(mods_dir + "/" + fname)

	# Malformed sidecars - must be skipped (with a warning), never fatal to
	# the whole scan (HULL_MODDING_PLAN.md §3, validation points 1-3).
	write_file.call("bad_missing_field.json", JSON.stringify({"name": "Bad", "hp": 1.0}))
	write_file.call("bad_missing_field.glb", "")
	write_file.call("bad_wrong_type.json", JSON.stringify({"name": "Bad2", "hp": "nope", "weight": 1.0, "metal": 1, "crystal": 1, "size": [1, 1, 1], "color": [1, 1, 1]}))
	write_file.call("bad_wrong_type.glb", "")

	var good_id = "run_tests_smoke_mod_hull"
	write_file.call(good_id + ".json", JSON.stringify({"name": "Run Tests Smoke Mod Hull", "hp": 111.0, "weight": 22.0, "metal": 5, "crystal": 1, "size": [1, 1, 1], "color": [1, 0, 0]}))
	write_file.call(good_id + ".glb", "")

	HullLoader.reset_cache_for_tests()
	var hulls = HullLoader.get_hulls()

	var ok = true
	if not hulls.has(good_id):
		print("  [FAIL] valid mod sidecar was not picked up")
		ok = false
	if hulls.has("bad_missing_field"):
		print("  [FAIL] sidecar missing a required field should have been skipped, not defaulted")
		ok = false
	if hulls.has("bad_wrong_type"):
		print("  [FAIL] sidecar with a wrong-typed field should have been skipped")
		ok = false
	if not HullLoader.is_modded(good_id):
		print("  [FAIL] valid mod hull should be flagged as sourced from user://mods/hulls")
		ok = false
	if not hulls.has("medium_hull") or hulls["medium_hull"]["hp"] != 400.0:
		print("  [FAIL] medium_hull should still be present and unaffected by unrelated mod files")
		ok = false

	# Mod-overrides-built-in precedence: a mod file using a built-in's own
	# id (e.g. a rebalance/reskin mod) wins, since it's a deliberate,
	# nameable override, not an accidental collision (HULL_MODDING_PLAN.md
	# §5's open question - see DECISIONS_NEEDED.md for the reasoning).
	write_file.call("medium_hull.json", JSON.stringify({"name": "Modded Medium Hull", "hp": 999.0, "weight": 250.0, "metal": 100, "crystal": 20, "size": [4, 1, 6], "color": [1, 1, 1]}))
	write_file.call("medium_hull.glb", "")
	HullLoader.reset_cache_for_tests()
	hulls = HullLoader.get_hulls()
	if hulls.get("medium_hull", {}).get("hp", -1.0) != 999.0:
		print("  [FAIL] a mod hull should override a built-in hull of the same id")
		ok = false
	if not HullLoader.is_modded("medium_hull"):
		print("  [FAIL] the overridden medium_hull should be flagged as modded while the override is active")
		ok = false

	for path in written_files:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if FileAccess.file_exists(mods_dir + "/medium_hull.json"):
		DirAccess.remove_absolute(mods_dir + "/medium_hull.json")
	if FileAccess.file_exists(mods_dir + "/medium_hull.glb"):
		DirAccess.remove_absolute(mods_dir + "/medium_hull.glb")
	HullLoader.reset_cache_for_tests()

	# Real protection against this test silently leaking state into every
	# test that runs after it: confirm a rescan after cleanup goes straight
	# back to the true on-disk state.
	var fresh = HullLoader.get_hulls()
	if fresh.get("medium_hull", {}).get("hp", -1.0) != 400.0:
		print("  [FAIL] medium_hull did not revert to its real built-in value after test cleanup")
		ok = false
	if fresh.has(good_id):
		print("  [FAIL] test mod hull should be gone after cleanup")
		ok = false

	if not ok:
		return false
	print("  [PASS] HullLoader scans both directories, skips malformed sidecars without failing the whole scan, and a mod hull correctly overrides a built-in of the same id (logged as a warning).")
	return true

func test_hull_modding_parts_menu_two_buckets() -> bool:
	print("Running Test Suite: Hull Modding - Parts Catalog Collapses To 2 Buckets (Vehicle / Static Building)...")
	var menu = preload("res://scenes/UI_PartsMenu.tscn").instantiate()
	root.add_child(menu)
	await process_frame

	var tab_hulls = menu.get_node("PanelContainer/VBoxContainer/TabContainer/Hulls/VBoxContainer")
	var drawer_categories = []
	for child in tab_hulls.get_children():
		if child.has_meta("drawer_category"):
			drawer_categories.append(child.get_meta("drawer_category"))
	drawer_categories.sort()

	var ok = true
	if drawer_categories != ["Static Building", "Vehicle"]:
		print("  [FAIL] Expected exactly the drawers [Static Building, Vehicle], got ", drawer_categories)
		ok = false

	# Every hull button must land in the bucket matching its OWN
	# is_foundation flag, not a hardcoded per-type_id table - this is what
	# lets a modded hull sort correctly with zero code changes.
	for child in tab_hulls.get_children():
		if not child.has_meta("drawer_category"):
			continue
		var category = child.get_meta("drawer_category")
		var content = child.get_meta("content_container")
		for btn in content.get_children():
			var data = ModuleCatalog.get_module_data(btn.module_type_id)
			var expect_static = data.get("is_foundation", false)
			var actual_static = category == "Static Building"
			if expect_static != actual_static:
				print("  [FAIL] %s (is_foundation=%s) landed in drawer '%s'" % [btn.module_type_id, expect_static, category])
				ok = false

	menu.queue_free()
	if not ok:
		return false
	print("  [PASS] Every hull sorts into Vehicle/Static Building purely off its own is_foundation flag - no hardcoded per-type_id domain table.")
	return true

func test_hull_modding_hard_fail_on_unknown_hull() -> bool:
	print("Running Test Suite: Hull Modding - Blueprint Load Hard-Fails On A Missing Hull (not a silent fallback)...")
	var bm = Node.new()
	bm.name = "BlueprintManager"
	bm.set_script(preload("res://scripts/blueprint_manager.gd"))
	root.add_child(bm)
	await process_frame

	var fake_blueprint = {
		"version": 1.0,
		"hull_type": "totally_not_a_real_hull_xyz",
		"name": "Broken Design",
		"modules": [],
	}

	# reconstruct_vehicle() itself must refuse - this is the second line of
	# defense that protects every non-Design-Lab caller (skirmish spawns,
	# battlefield, defense buildings), not just the explicit Load button.
	var parent = Node3D.new()
	root.add_child(parent)
	var result = bm.reconstruct_vehicle(fake_blueprint, parent)
	if result != null:
		print("  [FAIL] reconstruct_vehicle() should refuse (return null) for an unknown hull_type instead of building a hull off substitute data")
		bm.queue_free()
		parent.queue_free()
		return false
	parent.queue_free()

	# The Design Lab's own Load button must refuse BEFORE ever calling
	# reconstruct_vehicle(), and report which specific hull is missing.
	DirAccess.make_dir_recursive_absolute("user://blueprints")
	var bad_id = "test_hard_fail_missing_hull_bp"
	var bp_to_save = fake_blueprint.duplicate()
	bp_to_save["id"] = bad_id
	var file = FileAccess.open("user://blueprints/%s.json" % bad_id, FileAccess.WRITE)
	file.store_string(JSON.stringify(bp_to_save, "\t"))
	file.close()

	var ok = bm.load_blueprint_into_designer(bad_id)
	DirAccess.remove_absolute("user://blueprints/%s.json" % bad_id)
	bm.queue_free()

	if ok:
		print("  [FAIL] load_blueprint_into_designer() should return false for an unknown hull_type")
		return false
	if not "totally_not_a_real_hull_xyz" in bm.last_load_error:
		print("  [FAIL] last_load_error should name the specific missing hull, got: ", bm.last_load_error)
		return false

	print("  [PASS] Both reconstruct_vehicle() and load_blueprint_into_designer() refuse to load a blueprint referencing a missing hull, with a specific user-facing reason naming it.")
	return true

func test_hull_modding_mod_hull_placeable() -> bool:
	print("Running Test Suite: Hull Modding - Real user://mods/hulls Hull Loads And Is Placeable In The Design Lab...")
	if not ModuleCatalog.hull_exists("prospectors_folly_hull"):
		print("  [FAIL] prospectors_folly_hull not found in the catalog - is the committed test mod hull (.glb+.json) present under user://mods/hulls?")
		return false

	var placer = Node3D.new()
	placer.name = "MainLab"
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	var bm = Node.new()
	bm.name = "BlueprintManager"
	bm.set_script(preload("res://scripts/blueprint_manager.gd"))
	placer.add_child(bm)
	await process_frame

	placer._place_hull_from_ui("prospectors_folly_hull")
	await process_frame

	var ok = true
	if not placer.hull:
		print("  [FAIL] Hull was not placed")
		ok = false
	elif not HullLoader.is_modded("prospectors_folly_hull"):
		print("  [FAIL] expected prospectors_folly_hull to be sourced from user://mods/hulls, not res://")
		ok = false
	else:
		var mesh_inst = placer.hull.get_node_or_null("MeshInstance3D")
		if not mesh_inst or not mesh_inst.mesh:
			print("  [FAIL] Mod hull mesh was not assigned (runtime glTF import failed?)")
			ok = false
		elif mesh_inst.mesh.get_surface_count() == 0:
			print("  [FAIL] Mod hull mesh has no surfaces")
			ok = false

	placer.queue_free()
	if not ok:
		return false
	print("  [PASS] A real user://mods/hulls hull (mesh + JSON sidecar, zero code changes) scans, merges into the catalog, and places successfully in the Design Lab via a runtime glTF import.")
	return true

func test_weapon_los_blocked_by_cover_and_skirmish_bug_fixes() -> bool:
	print("Running Test Suite: FABLE review fixes - weapon LOS cover, factory load-balancing, building overlap, defense faction...")

	# --- Part 1: weapon fire LOS is genuinely blocked by world geometry ---
	# (FABLE_REVIEW.md 3.1: the old check only blocked on own-vehicle hits, so
	# units fired straight through rocks/buildings.)
	var weapon_rig = Node3D.new()
	root.add_child(weapon_rig)
	var weapon = Node3D.new()
	weapon.set_script(load("res://scripts/auto_weapon.gd"))
	var w_data = ModuleData.new()
	w_data.type_id = "basic_cannon"
	weapon.set_meta("module_data", w_data)
	weapon_rig.add_child(weapon)
	# The LOS check is called directly below; per-tick targeting would crash
	# against this synthetic rig (no vehicle root), so switch it off.
	weapon.set_physics_process(false)
	weapon.global_position = Vector3(0, 1.0, 0)

	var los_target = StaticBody3D.new()
	los_target.collision_layer = 8
	los_target.collision_mask = 0
	var t_col = CollisionShape3D.new()
	var t_box = BoxShape3D.new()
	t_box.size = Vector3(2, 2, 2)
	t_col.shape = t_box
	los_target.add_child(t_col)
	root.add_child(los_target)
	los_target.global_position = Vector3(0, 1.0, -14.0)
	weapon.target = los_target
	# Aim the weapon at the target so the muzzle-forward ray offset points the right way
	weapon.look_at(los_target.global_position, Vector3.UP)

	await process_frame

	var clear_result = weapon._is_line_of_sight_blocked()

	# Insert a wall (world-geometry layer 1) squarely between them
	var wall = StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var w_col = CollisionShape3D.new()
	var w_box = BoxShape3D.new()
	w_box.size = Vector3(6, 6, 1)
	w_col.shape = w_box
	wall.add_child(w_col)
	root.add_child(wall)
	wall.global_position = Vector3(0, 1.0, -7.0)

	await process_frame

	var blocked_result = weapon._is_line_of_sight_blocked()

	weapon_rig.queue_free()
	los_target.queue_free()
	wall.queue_free()

	if clear_result != false:
		print("  [FAIL] LOS reported blocked with a clear line to the target (the target's own collider must not block the shot at itself).")
		return false
	if blocked_result != true:
		print("  [FAIL] LOS reported clear with a wall between weapon and target - cover does not block weapon fire.")
		return false

	# --- Part 2: Skirmish-level fixes need a real match instance ---
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await process_frame
	await process_frame

	# Factory load-balancing (FABLE_REVIEW.md 2.4): a busy manufactory must
	# lose to an idle one of the same tier.
	var first_light = skirmish.get_team_factory(0, "light")
	if not first_light:
		print("  [FAIL] No starting light manufactory found.")
		skirmish.queue_free()
		return false
	var second_light = skirmish._spawn_prefab("light_manufactory", 0, first_light.global_position + Vector3(0, 0, 14), skirmish.player_faction)
	await process_frame
	first_light.queue_unit({}, 60.0)
	var chosen = skirmish.get_team_factory(0, "light")
	if chosen != second_light:
		print("  [FAIL] get_team_factory() did not pick the idle manufactory over the busy one - extra factories are still decorative.")
		skirmish.queue_free()
		return false
	first_light.production_queue.clear()

	# Building overlap rejection (FABLE_REVIEW.md 3.3): placing a refinery on
	# top of an existing building must be invalid; a clear nearby spot valid.
	skirmish.placing = {"kind": "refinery", "cost_metal": 150, "cost_crystal": 0}
	var stacked = skirmish._placement_validity(first_light.global_position)
	var hq_pos = skirmish.player_hq.global_position
	var clear_spot = hq_pos + Vector3(0, 0, -16)
	var clear = skirmish._placement_validity(clear_spot)
	skirmish.placing = {}
	if stacked.valid:
		print("  [FAIL] Placement on top of an existing building was accepted - buildings can still be stacked.")
		skirmish.queue_free()
		return false
	if not clear.valid:
		print("  [FAIL] A clear spot near the base was rejected (%s) - overlap check is too aggressive." % clear.reason)
		skirmish.queue_free()
		return false

	# Defense buildings carry their real faction (FABLE_REVIEW.md 3.7)
	var defense_bp = {
		"hull_type": "pillbox_foundation",
		"faction": "bayou_irregulars",
		"armor_material": "hardened_steel",
		"armor_thickness": 1.0,
		"locomotion": {"type_id": "", "settings": {}},
		"modules": [{"type_id": "heavy_machine_gun", "position": {"x": 0, "y": 1.2, "z": 0}, "rotation": {"x": 0, "y": 0, "z": 0}, "scale": {"x": 1, "y": 1, "z": 1}, "tweaks": {}}]
	}
	var defense = skirmish.spawn_defense(defense_bp, 0, hq_pos + Vector3(16, 0, 0))
	await process_frame
	if defense.faction != "bayou_irregulars":
		print("  [FAIL] Defense building faction field is '%s', expected the blueprint's own 'bayou_irregulars'." % defense.faction)
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await process_frame
	print("  [PASS] Weapon fire is blocked by real cover, idle factories receive queue jobs, buildings can't stack, and defenses carry their faction.")
	return true
