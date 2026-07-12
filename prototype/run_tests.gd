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
	success = success and await test_locomotion_tweak_parity()
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

func test_locomotion_tweak_parity() -> bool:
	print("Running Test Suite: Locomotion Tweak Parity (DESIGN_VISION.md audit)...")
	# Regression test for a real bug found during the Sunday audit: the "legs" and
	# "anti_grav" locomotion UI sliders updated settings but update_locomotion()
	# never read the "size" key, so dragging the slider had zero effect on the
	# resulting unit. "hover_engine" had no tweak UI at all. All three are fixed
	# to respond to a continuous "size" setting like wheels/treads/rotors already did.
	var gizmo_probe = Node3D.new()
	gizmo_probe.set_script(preload("res://scripts/gizmo_3d.gd"))
	root.add_child(gizmo_probe)

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
			gizmo_probe.queue_free()
			return false

	gizmo_probe.queue_free()
	print("  [PASS] Locomotion size tweaks (legs/anti_grav/hover_engine) and gizmo axis mappings verified.")
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
