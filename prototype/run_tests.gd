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
	success = success and await test_undo_redo()
	success = success and await test_foundation_design_lab_parity()
	success = success and await test_design_to_battle_integration()
	success = success and await test_firing_arc_visualization()
	success = success and await test_free_rotation_ring()
	success = success and await test_armor_module_facet_fitting()
	success = success and await test_armor_module_combat_bonus()
	success = success and await test_face_based_weapon_mounting()
	success = success and await test_centerline_placement_does_not_self_mirror()
	success = success and await test_hull_nose_taper()
	success = success and await test_directional_armor_facet_resolution()
	success = success and await test_per_module_armor_material()
	success = success and await test_sloped_armor_angle_of_incidence()
	success = success and await test_ai_flanking_targets_weakest_facet()
	success = success and await test_trait_system_composability()
	success = success and await test_headless_combat_simulation()
	success = success and await test_team_targeting()
	success = success and await test_blueprint_cost_and_rosters()
	success = success and await test_skirmish_economy_and_production()
	success = success and await test_win_condition()
	
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
	
	# Expected Thresholds:
	# Kinetic (K): Base K (15.0) * thickness (1.5) = 22.5
	# Thermal (T): Base T (5.0) * thickness (1.5) = 7.5
	# Explosive (E): Base E (10.0) * thickness (1.5) = 15.0
	var expected_k_thresh = 22.5
	var expected_t_thresh = 7.5
	var expected_e_thresh = 15.0
	
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
	# undo all run through the same hull-type-agnostic code paths as vehicles
	# EXCEPT locomotion, which is deliberately blocked for foundations - this
	# verifies that block works and everything else still has full parity.
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

	# Locomotion should be rejected on a foundation.
	placer._place_weapon_from_ui("wheels", Vector3.ZERO, Vector3.DOWN)
	await process_frame
	var loco_count = 0
	for child in placer.hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").category == "locomotion":
			loco_count += 1
	if loco_count != 0:
		print("  [FAIL] Foundation should reject locomotion, found ", loco_count, " locomotion parts")
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
	print("  [PASS] Foundation hulls get full placement/mirror/rotate/undo/serialize parity with vehicle hulls.")
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
			if abs(child.scale.y - 1.7) < 0.05:
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
