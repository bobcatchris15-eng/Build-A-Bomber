extends SceneTree

const ModuleData = preload("res://scripts/module_data.gd")
# Headless regression test for the Blueprint Library (Phase 2, Milestone A).
# Run with: godot.exe --headless --script res://test_blueprint_library.gd
# Exercises save -> list -> duplicate -> load_into_designer -> delete, and
# instantiates the library browser panel to catch script errors in it too.

func _init():
	print("=== Blueprint Library test started ===")
	var scene = preload("res://scenes/MainLab.tscn").instantiate()
	scene.name = "MainLab"
	root.add_child(scene)

	for i in range(5):
		await process_frame

	var bm = scene.get_node("BlueprintManager")
	var hull = scene.get_node("Hull")
	assert(bm != null, "BlueprintManager missing")
	assert(hull != null, "Hull missing")

	# --- Save ---
	hull.set_meta("blueprint_name", "AutoTest Bomber")
	
	# Manually add a test module to verify tweaks serialization
	var new_mod = Node3D.new()
	var m_data = ModuleData.new()
	m_data.type_id = "basic_cannon"
	m_data.module_name = "Basic Cannon Test"
	m_data.tweaks = {"caliber": 1.5, "barrel_length": 1.2}
	new_mod.set_meta("module_data", m_data)
	hull.add_child(new_mod)
		
	bm.save_blueprint()
	for i in range(3):
		await process_frame

	# --- List ---
	var entries = bm.list_blueprints()
	print("Blueprints found: ", entries.size())
	var test_entry = null
	for e in entries:
		if e["name"] == "AutoTest Bomber":
			test_entry = e
	assert(test_entry != null, "Saved blueprint not found in list_blueprints()")
	print("Saved blueprint id: ", test_entry["id"], " name: ", test_entry["name"])

	# --- Duplicate ---
	var dup_id = bm.duplicate_blueprint(test_entry["id"])
	assert(dup_id != "", "duplicate_blueprint() failed")
	var entries_after_dup = bm.list_blueprints()
	print("Blueprints after duplicate: ", entries_after_dup.size())
	assert(entries_after_dup.size() == entries.size() + 1, "Duplicate did not add a new entry")

	# --- Load into designer (swaps the active hull) ---
	var old_hull_instance_id = hull.get_instance_id()
	var ok = bm.load_blueprint_into_designer(test_entry["id"])
	assert(ok, "load_blueprint_into_designer() returned false")
	for i in range(3):
		await process_frame
	var new_hull = scene.get("hull")
	assert(new_hull != null, "hull var on MainLab was not reassigned")
	assert(new_hull.get_instance_id() != old_hull_instance_id, "Hull was not replaced")
	assert(new_hull.get_meta("blueprint_name") == "AutoTest Bomber", "Reconstructed hull has wrong name meta")
	print("Reconstructed hull name meta: ", new_hull.get_meta("blueprint_name"))
	print("Reconstructed hull child count: ", new_hull.get_child_count())
	
	# Verify custom tweaks restoration
	var restored_mod = null
	for child in new_hull.get_children():
		if child.has_meta("module_data"):
			restored_mod = child
			break
	if restored_mod:
		var restored_data = restored_mod.get_meta("module_data")
		assert(restored_data.tweaks.get("caliber") == 1.5, "Custom caliber tweak was not restored")
		assert(restored_data.tweaks.get("barrel_length") == 1.2, "Custom barrel_length tweak was not restored")
		print("Reconstructed tweaks successfully verified: ", restored_data.tweaks)

	# --- Library panel instantiation (script-error smoke test) ---
	var PanelScript = preload("res://scripts/blueprint_library_panel.gd")
	var panel = PanelScript.new()
	scene.add_child(panel)
	for i in range(3):
		await process_frame
	print("Library panel row count (list_vbox children): ", panel.list_vbox.get_child_count())
	panel.queue_free()

	# --- Cleanup: don't leave test junk in the real library ---
	bm.delete_blueprint(test_entry["id"])
	bm.delete_blueprint(dup_id)
	var entries_final = bm.list_blueprints()
	print("Blueprints after cleanup: ", entries_final.size())
	assert(entries_final.size() == entries.size() - 1, "Cleanup did not fully remove test entries")

	print("=== Blueprint Library test PASSED ===")
	quit()
