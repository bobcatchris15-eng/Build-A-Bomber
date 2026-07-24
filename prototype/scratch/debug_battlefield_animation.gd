extends SceneTree
# Debug: replicate battlefield.gd's _spawn_vehicle() exactly (CharacterBody3D
# + battle_unit.gd script + setup()), but with a hand-built blueprint that's
# guaranteed to include a helicopter_rotors module, then manually tick
# _physics_process() a few times and check whether "RotorBlades" actually
# rotates - to find out whether the Test Range animation bug is real or a
# stale-process artifact.
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/debug_battlefield_animation.gd --path .

func _init():
	var BlueprintManager = load("res://scripts/blueprint_manager.gd")

	var blueprint_data = {
		"version": 1.0,
		"hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "wheels", "settings": {}},
		"modules": [
			{
				"type_id": "helicopter_rotors",
				"position": {"x": 3.2, "y": 0.8, "z": 0.0},
				"rotation": {"x": 0.0, "y": 0.0, "z": 0.0},
				"tweaks": {"blade_count": 4, "blade_length": 1.0, "duct": false, "mount_side": 1.0, "mount_reach_x": 3.2, "mount_reach_y": 0.8}
			}
		]
	}

	var vehicle = CharacterBody3D.new()
	vehicle.name = "DebugVehicle"
	vehicle.set_script(load("res://scripts/battle_unit.gd"))
	root.add_child(vehicle)

	var bp_manager = BlueprintManager.new()
	root.add_child(bp_manager)

	vehicle.setup(blueprint_data, 0, bp_manager)
	for i in range(4): await process_frame

	var hull_node = vehicle.hull_node
	print("[DEBUG] hull_node valid: ", is_instance_valid(hull_node))
	if not is_instance_valid(hull_node):
		quit(1)
		return

	var rotor_module = null
	for child in hull_node.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "helicopter_rotors":
			rotor_module = child
			break
	print("[DEBUG] rotor_module found: ", rotor_module != null)
	if not rotor_module:
		print("[DEBUG] hull_node children: ")
		for child in hull_node.get_children():
			print("   - ", child.name, " meta=", child.get_meta("module_data").type_id if child.has_meta("module_data") else "NONE")
		quit(1)
		return

	var rotor_blades = rotor_module.get_node_or_null("RotorBlades")
	print("[DEBUG] RotorBlades node found via get_node_or_null: ", rotor_blades != null)
	var found_recursive = rotor_module.find_child("RotorBlades", true, false)
	print("[DEBUG] RotorBlades node found via find_child (recursive): ", found_recursive != null)
	if not rotor_blades and not found_recursive:
		print("[DEBUG] Full rotor_module subtree:")
		var stack = [[rotor_module, 0]]
		while stack.size() > 0:
			var entry = stack.pop_back()
			var node = entry[0]
			var depth = entry[1]
			print("   ", "  ".repeat(depth), node.name, " (", node.get_class(), ")")
			for c in node.get_children():
				stack.append([c, depth + 1])
		quit(1)
		return
	if not rotor_blades:
		rotor_blades = found_recursive

	var rot_before = rotor_blades.rotation.y
	print("[DEBUG] RotorBlades.rotation.y BEFORE: ", rot_before)

	# Manually invoke _physics_process several times, same as the physics
	# server would - process_frame alone doesn't guarantee physics ticks in
	# headless --script mode, so call it directly to be certain.
	for i in range(30):
		vehicle._physics_process(1.0 / 60.0)

	var rot_after = rotor_blades.rotation.y
	print("[DEBUG] RotorBlades.rotation.y AFTER 30 manual ticks: ", rot_after)
	print("[DEBUG] Delta: ", rot_after - rot_before)

	if abs(rot_after - rot_before) > 0.001:
		print("[PASS] RotorBlades rotation DID change - animation code works when called directly.")
	else:
		print("[FAIL] RotorBlades rotation did NOT change - real bug in the animation code path.")

	quit(0)
