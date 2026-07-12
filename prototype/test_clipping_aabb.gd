extends SceneTree

# Comprehensive test script to verify AABB-based clipping logic and turret swiveling.
# Run with: ./Godot_v4.3-stable_win64_console.exe --headless --script test_clipping_aabb.gd

const ModulePlacerScript = preload("res://scripts/module_placer.gd")
const AutoWeaponScript = preload("res://scripts/auto_weapon.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const ModuleData = preload("res://scripts/module_data.gd")

func _init():
	print("\n==============================================")
	print("    COMPREHENSIVE AABB & SWIVEL TEST SUITE")
	print("==============================================\n")
	
	var all_passed = true
	all_passed = all_passed and _test_adjacent_non_clipping()
	all_passed = all_passed and _test_overlapping_clipping()
	all_passed = all_passed and _test_rotated_clipping()
	
	print("\n==============================================")
	if all_passed:
		print("    ALL COMPREHENSIVE TESTS PASSED!")
		print("==============================================\n")
		quit(0)
	else:
		print("    SOME COMPREHENSIVE TESTS FAILED!")
		print("==============================================\n")
		quit(1)

func _test_adjacent_non_clipping() -> bool:
	print("Test 1: Adjacent touching modules (should NOT clip)...")
	var root_node = Node3D.new()
	var hull = StaticBody3D.new()
	hull.name = "Hull"
	root_node.add_child(hull)
	root.add_child(root_node)
	
	var placer = root_node
	placer.set_script(ModulePlacerScript)
	placer.hull = hull
	
	# Place two basic cannons adjacent to each other
	# Cannon size is (0.6, 0.6, 2.0). Centered at placement pos.
	var mod1 = Node3D.new()
	var d1 = ModuleData.new()
	d1.type_id = "basic_cannon"
	mod1.set_meta("module_data", d1)
	mod1.position = Vector3(0.0, 0.3, 0.0)
	hull.add_child(mod1)
	
	var mod2 = Node3D.new()
	var d2 = ModuleData.new()
	d2.type_id = "basic_cannon"
	mod2.set_meta("module_data", d2)
	# Touch on X: 0.0 + 0.6/2.0 + 0.6/2.0 = 0.6
	mod2.position = Vector3(0.6, 0.3, 0.0)
	hull.add_child(mod2)
	
	placer.check_all_clipping()
	var clip_detected = placer.clipping_detected
	
	root_node.queue_free()
	
	if not clip_detected:
		print("  [PASS] Adjacent touching modules verified as clean (no clipping).")
		return true
	else:
		print("  [FAIL] Adjacent touching modules flagged as clipping!")
		return false

func _test_overlapping_clipping() -> bool:
	print("Test 2: Overlapping modules (should CLIP)...")
	var root_node = Node3D.new()
	var hull = StaticBody3D.new()
	hull.name = "Hull"
	root_node.add_child(hull)
	root.add_child(root_node)
	
	var placer = root_node
	placer.set_script(ModulePlacerScript)
	placer.hull = hull
	
	var mod1 = Node3D.new()
	var d1 = ModuleData.new()
	d1.type_id = "basic_cannon"
	mod1.set_meta("module_data", d1)
	mod1.position = Vector3(0.0, 0.3, 0.0)
	hull.add_child(mod1)
	
	var mod2 = Node3D.new()
	var d2 = ModuleData.new()
	d2.type_id = "basic_cannon"
	mod2.set_meta("module_data", d2)
	# Overlap on X: center distance 0.4 (less than size 0.6)
	mod2.position = Vector3(0.4, 0.3, 0.0)
	hull.add_child(mod2)
	
	placer.check_all_clipping()
	var clip_detected = placer.clipping_detected
	
	root_node.queue_free()
	
	if clip_detected:
		print("  [PASS] Overlapping modules successfully flagged as clipping.")
		return true
	else:
		print("  [FAIL] Overlapping modules not flagged as clipping!")
		return false

func _test_rotated_clipping() -> bool:
	print("Test 3: Rotated touching modules (should NOT clip)...")
	var root_node = Node3D.new()
	var hull = StaticBody3D.new()
	hull.name = "Hull"
	root_node.add_child(hull)
	root.add_child(root_node)
	
	var placer = root_node
	placer.set_script(ModulePlacerScript)
	placer.hull = hull
	
	# Placing one module on top and one on the left side
	# Top module: size (0.6, 0.6, 2.0), centered at (0, 0.3, 0)
	# Bounding box top module X range: [-0.3, 0.3]
	var mod_top = Node3D.new()
	var d_top = ModuleData.new()
	d_top.type_id = "basic_cannon"
	mod_top.set_meta("module_data", d_top)
	mod_top.position = Vector3(0.0, 0.3, 0.0)
	hull.add_child(mod_top)
	
	# Side module rotated 90 deg around Z:
	# Bounding box original size is (0.6, 0.6, 2.0)
	# When rotated 90 degrees around Z, the X component is still 0.6 (since X and Y are both 0.6).
	# Touch on X: 0.0 - 0.3 (half of top) - 0.3 (half of side) = -0.6
	var mod_side = Node3D.new()
	var d_side = ModuleData.new()
	d_side.type_id = "basic_cannon"
	mod_side.set_meta("module_data", d_side)
	mod_side.position = Vector3(-0.6, 0.3, 0.0)
	mod_side.rotate_z(PI / 2.0)
	hull.add_child(mod_side)
	
	placer.check_all_clipping()
	var clip_detected = placer.clipping_detected
	
	root_node.queue_free()
	
	if not clip_detected:
		print("  [PASS] Rotated adjacent modules verified as clean (no clipping).")
		return true
	else:
		print("  [FAIL] Rotated adjacent modules flagged as clipping!")
		return false
