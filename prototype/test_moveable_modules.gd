extends SceneTree

# Headless regression test for moveable modules (click and drag) in the Design Lab.
# Run with: ./Godot_v4.3-stable_win64_console.exe --headless --script test_moveable_modules.gd

const ModulePlacerScript = preload("res://scripts/module_placer.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const ModuleData = preload("res://scripts/module_data.gd")

func _init():
	print("\n==============================================")
	print("    REGRESSION TEST: MOVEABLE MODULES DRAG")
	print("==============================================\n")
	
	_run_tests()

func _run_tests():
	var root_node = Node3D.new()
	var hull = StaticBody3D.new()
	hull.name = "Hull"
	root_node.add_child(hull)
	root.add_child(root_node)
	
	var placer = root_node
	placer.set_script(ModulePlacerScript)
	placer.hull = hull
	
	# Wait for node to enter tree
	await process_frame
	await process_frame
	
	# Place using the UI wrapper which sets up mirroring
	placer._place_weapon_from_ui("basic_cannon", Vector3(1.0, 0.5, 0.0), Vector3.UP)
	
	# Find primary and mirror
	var mod1 = null
	for child in hull.get_children():
		if child.has_meta("module_data"):
			if child.position.x > 0.0:
				mod1 = child
				break
				
	assert(mod1 != null, "Primary module not created")
	
	var mirror = mod1.get_meta("mirrored_counterpart")
	assert(mirror != null, "Mirrored counterpart not created")
	
	print("Initial position: Primary=", mod1.position, " Mirror=", mirror.position)
	assert(mod1.position.x == 1.0, "Primary start position incorrect")
	assert(mirror.position.x == -1.0, "Mirror start position incorrect")
	
	# Start dragging mod1
	placer.selected_module = mod1
	placer.drag_pending = false
	placer.is_dragging_module = true
	placer.drag_original_transform = mod1.transform
	placer.drag_has_mirror = true
	placer.drag_original_mirror_transform = mirror.transform
	
	# Move to a new position (e.g. x=1.5, z=-1.0)
	placer._update_module_placement(mod1, Vector3(1.5, 0.5, -1.0), Vector3.UP)
	
	print("Dragged position: Primary=", mod1.position, " Mirror=", mirror.position)
	assert(mod1.position.x == 1.5, "Primary dragged position incorrect")
	assert(mod1.position.z == -1.0, "Primary dragged position incorrect")
	assert(mirror.position.x == -1.5, "Mirror dragged position incorrect")
	assert(mirror.position.z == -1.0, "Mirror dragged position incorrect")
	
	# Simulate ESCAPE cancel
	var escape_event = InputEventKey.new()
	escape_event.pressed = true
	escape_event.keycode = KEY_ESCAPE
	placer._unhandled_input(escape_event)
	
	print("Cancelled position: Primary=", mod1.position, " Mirror=", mirror.position)
	assert(mod1.position.x == 1.0, "Cancel did not restore primary position")
	assert(mirror.position.x == -1.0, "Cancel did not restore mirror position")
	
	root_node.queue_free()
	
	print("\n[PASS] Moveable modules and mirrored dragging verified successfully!")
	quit(0)
