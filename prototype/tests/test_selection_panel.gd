extends "res://tests/suite_base.gd"

# Tactile Interface Programme Phase 9 Tests (Selection Panel, D8, D15)

const SelectionPanelScript = preload("res://scripts/battle/hud/selection_panel.gd")
const SelectionServiceScript = preload("res://scripts/battle/orders/selection_service.gd")


func test_selection_panel_aggregates_rows_by_design() -> bool:
	print("Running Test Suite: Selection Panel - Aggregates Rows By Design (Phase 9, D8)...")
	var panel = SelectionPanelScript.new()
	root.add_child(panel)

	var units: Array = []
	# 12 of Design A
	for i in range(12):
		var u := Node3D.new()
		u.set_meta("blueprint_id", "tank_heavy_a")
		u.set_meta("blueprint_name", "Heavy Tank A")
		units.append(u)
		root.add_child(u)

	# 4 of Design B
	for i in range(4):
		var u := Node3D.new()
		u.set_meta("blueprint_id", "scout_buggy_b")
		u.set_meta("blueprint_name", "Scout Buggy B")
		units.append(u)
		root.add_child(u)

	panel.update_selection(units)

	if panel._groups.size() != 2:
		print("  [FAIL] Expected 2 aggregated groups, got %d" % panel._groups.size())
		panel.queue_free()
		for u in units: u.queue_free()
		return false

	var count_a: int = panel._groups["tank_heavy_a"]["units"].size()
	var count_b: int = panel._groups["scout_buggy_b"]["units"].size()
	if count_a != 12 or count_b != 4:
		print("  [FAIL] Group counts mismatched: A=%d (exp 12), B=%d (exp 4)" % [count_a, count_b])
		panel.queue_free()
		for u in units: u.queue_free()
		return false

	panel.queue_free()
	for u in units: u.queue_free()
	print("  [PASS] Exactly 2 rows produced with accurate aggregated counts (12 and 4).")
	return true


func test_selection_panel_ctrl_shift_deselect_group() -> bool:
	print("Running Test Suite: Selection Panel - Ctrl+Shift Deselects Design Group (Phase 9)...")
	var service = SelectionServiceScript.new()
	var panel = SelectionPanelScript.new()
	root.add_child(panel)
	panel.bind_selection_service(service)

	var units_a: Array = []
	for i in range(12):
		var u := Node3D.new()
		u.set_meta("blueprint_id", "tank_a")
		units_a.append(u)
		root.add_child(u)

	var units_b: Array = []
	for i in range(4):
		var u := Node3D.new()
		u.set_meta("blueprint_id", "buggy_b")
		units_b.append(u)
		root.add_child(u)

	var all_units := units_a + units_b
	service.selected = all_units.duplicate()
	panel.update_selection(all_units)

	# Simulate Ctrl+Shift+Click on design A
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.ctrl_pressed = true
	event.shift_pressed = true

	panel._on_row_gui_input(event, "tank_a")

	if service.selected.size() != 4:
		print("  [FAIL] Expected 4 remaining units after group deselect, got %d" % service.selected.size())
		panel.queue_free()
		for u in all_units: u.queue_free()
		return false

	for u in service.selected:
		if u.get_meta("blueprint_id") != "buggy_b":
			print("  [FAIL] Non-buggy unit remaining in selection")
			panel.queue_free()
			for u2 in all_units: u2.queue_free()
			return false

	panel.queue_free()
	for u in all_units: u.queue_free()
	print("  [PASS] Ctrl+Shift+Click deselects whole design group cleanly.")
	return true


func test_selection_panel_priority_order() -> bool:
	print("Running Test Suite: Selection Panel - Sub-Group Priority (Phase 9, D8)...")
	var panel = SelectionPanelScript.new()
	root.add_child(panel)

	var u_harvester := Node3D.new()
	u_harvester.set_meta("blueprint_id", "harv")
	u_harvester.set_meta("is_harvester", true)
	root.add_child(u_harvester)

	var u_combat := Node3D.new()
	u_combat.set_meta("blueprint_id", "combat")
	u_combat.set_meta("is_combat", true)
	root.add_child(u_combat)

	var u_ability := Node3D.new()
	u_ability.set_meta("blueprint_id", "siege_artillery")
	u_ability.set_meta("has_active_abilities", true)
	root.add_child(u_ability)

	# Selection has all three
	panel.update_selection([u_harvester, u_combat, u_ability])

	if panel._primary_design_id != "siege_artillery":
		print("  [FAIL] Primary design was '%s', expected 'siege_artillery' (active abilities rank first)" % panel._primary_design_id)
		panel.queue_free()
		u_harvester.queue_free()
		u_combat.queue_free()
		u_ability.queue_free()
		return false

	# Remove ability unit, combat should become primary
	panel.update_selection([u_harvester, u_combat])
	if panel._primary_design_id != "combat":
		print("  [FAIL] Primary design was '%s', expected 'combat' (combat ranks above harvester)" % panel._primary_design_id)
		panel.queue_free()
		u_harvester.queue_free()
		u_combat.queue_free()
		u_ability.queue_free()
		return false

	panel.queue_free()
	u_harvester.queue_free()
	u_combat.queue_free()
	u_ability.queue_free()
	print("  [PASS] Primary subgroup priority correctly evaluates abilities > combat > harvester.")
	return true


func test_selection_panel_thumbnail_cache() -> bool:
	print("Running Test Suite: Selection Panel - Thumbnail Cache (Phase 9)...")
	SelectionPanelScript.clear_thumbnail_cache()

	var dummy_tex := PlaceholderTexture2D.new()
	SelectionPanelScript.cache_thumbnail("design_123", dummy_tex)

	var cached = SelectionPanelScript._thumbnail_cache.get("design_123", null)
	if cached != dummy_tex:
		print("  [FAIL] Thumbnail was not retrieved from cache")
		return false

	print("  [PASS] Portrait thumbnail cache operates cleanly.")
	return true
