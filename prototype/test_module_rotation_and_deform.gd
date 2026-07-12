extends SceneTree

# Headless unit test for module rotation, customization popup positioning, and visual mesh deforms.
# Run with: ./Godot_v4.3-stable_win64_console.exe --headless --script test_module_rotation_and_deform.gd

const ModulePlacerScript = preload("res://scripts/module_placer.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const ModuleData = preload("res://scripts/module_data.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")

func _init():
	print("\n==============================================")
	print("  TEST: ROTATION, POPUP, AND MESH DEFORMS")
	print("==============================================\n")
	
	_run_tests()

func _run_tests():
	var root_node = Node3D.new()
	var hull = StaticBody3D.new()
	hull.name = "Hull"
	root_node.add_child(hull)
	root.add_child(root_node)
	
	# Instantiate Placer script
	var placer = root_node
	placer.set_script(ModulePlacerScript)
	placer.hull = hull
	
	# Instantiate actual UI scene
	var stat_ui = load("res://scenes/UI_StatBlock.tscn").instantiate()
	root_node.add_child(stat_ui)
	
	# Wait for frame so UI is ready
	await process_frame
	await process_frame
	
	# 1. Place a module
	placer._place_weapon_from_ui("basic_cannon", Vector3(1.0, 0.5, 0.0), Vector3.UP)
	var mod = null
	for child in hull.get_children():
		if child.has_meta("module_data") and child.position.x > 0.0:
			mod = child
			break
			
	assert(mod != null, "Cannon module was not created")
	var mirror = mod.get_meta("mirrored_counterpart")
	assert(mirror != null, "Mirror counterpart was not created")
	
	# 2. Select the module and verify customization popup
	placer._select_module(mod)
	stat_ui.on_module_selected(mod)
	
	assert(stat_ui.popup_panel.visible == true, "Customization popup should be visible for selected module")
	assert(stat_ui.popup_name_label.text.contains("CANON") or stat_ui.popup_name_label.text.contains("CANNON"), "Popup name label incorrect")
	print("Initial Popup details verified: ", stat_ui.popup_name_label.text, " - Stats: ", stat_ui.popup_stats_label.text)
	
	# 3. Verify rotation logic
	print("Initial rotation: Primary yaw_offset=", mod.get_meta("yaw_offset", 0.0))
	assert(mod.get_meta("yaw_offset", 0.0) == 0.0, "Initial yaw offset should be zero")
	
	# Rotate!
	placer.rotate_selected_module()
	var rotated_yaw = mod.get_meta("yaw_offset", 0.0)
	print("Rotated once: Primary yaw_offset=", rotated_yaw, " Mirror yaw_offset=", mirror.get_meta("yaw_offset", 0.0))
	assert(abs(rotated_yaw - PI/2.0) < 0.01, "Rotation should be 90 degrees (PI/2)")
	assert(abs(mirror.get_meta("yaw_offset", 0.0) - (-PI/2.0)) < 0.01, "Mirror rotation should be -90 degrees (-PI/2)")
	
	# 4. Verify mesh deformation based on tweaks
	var data = mod.get_meta("module_data")
	data.tweaks["caliber"] = 1.8
	data.tweaks["barrel_length"] = 1.5
	
	# Force rebuild
	VisualBuilder.rebuild_visual(mod)
	
	var children = mod.get_children().filter(func(c): return c is MeshInstance3D)
	assert(children.size() > 1, "Cannon meshes should exist")
	var barrel = children[1]
	print("Deformed barrel scale: ", barrel.scale)
	assert(abs(barrel.scale.x - 1.8) < 0.01, "Barrel caliber scale should match caliber tweak")
	assert(abs(barrel.scale.y - 1.5) < 0.01, "Barrel length scale should match barrel_length tweak")
	
	root_node.queue_free()
	print("\n[PASS] Rotation, Hovering Customization Popup, and Mesh Deformations verified successfully!")
	quit(0)
