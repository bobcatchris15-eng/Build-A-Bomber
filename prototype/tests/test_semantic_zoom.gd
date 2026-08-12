extends "res://tests/suite_base.gd"

const SemanticZoomServiceScript = preload("res://scripts/semantic_zoom_service.gd")

func test_semantic_zoom_service_thresholds() -> bool:
	print("Running Test Suite: Semantic Zoom Service Thresholds...")
	var svc = SemanticZoomServiceScript.new(10.0, 20.0)

	# Initial state should default to NORMAL
	if svc.current_level != SemanticZoomServiceScript.ZoomLevel.NORMAL:
		print("  [FAIL] Expected initial level to be NORMAL, got ", svc.get_level_name())
		return false

	# Update to distance < 10 (MICRO)
	var lvl = svc.update_distance(5.0)
	if lvl != SemanticZoomServiceScript.ZoomLevel.MICRO or svc.current_level != SemanticZoomServiceScript.ZoomLevel.MICRO:
		print("  [FAIL] Expected MICRO at distance 5.0, got ", svc.get_level_name())
		return false

	# Update to distance between 10 and 20 (NORMAL)
	lvl = svc.update_distance(15.0)
	if lvl != SemanticZoomServiceScript.ZoomLevel.NORMAL or svc.current_level != SemanticZoomServiceScript.ZoomLevel.NORMAL:
		print("  [FAIL] Expected NORMAL at distance 15.0, got ", svc.get_level_name())
		return false

	# Update to distance > 20 (MACRO)
	lvl = svc.update_distance(25.0)
	if lvl != SemanticZoomServiceScript.ZoomLevel.MACRO or svc.current_level != SemanticZoomServiceScript.ZoomLevel.MACRO:
		print("  [FAIL] Expected MACRO at distance 25.0, got ", svc.get_level_name())
		return false

	print("  [PASS] SemanticZoomService transitions correctly across thresholds.")
	return true

func test_semantic_zoom_signal_emission() -> bool:
	print("Running Test Suite: Semantic Zoom Signal Emission...")
	var svc = SemanticZoomServiceScript.new(10.0, 20.0)

	var emitted = [-1, -1.0]

	svc.zoom_level_changed.connect(func(level, dist):
		emitted[0] = level
		emitted[1] = dist
	)

	svc.update_distance(5.0) # Transitions from NORMAL to MICRO
	if emitted[0] != SemanticZoomServiceScript.ZoomLevel.MICRO or emitted[1] != 5.0:
		print("  [FAIL] Signal not emitted correctly on transition to MICRO. Got level %d distance %f" % [emitted[0], emitted[1]])
		return false

	# Updating with a distance that stays in MICRO should NOT emit signal
	emitted = [-1, -1.0]
	svc.update_distance(4.0)
	if emitted[0] != -1:
		print("  [FAIL] Signal emitted when no level transition occurred.")
		return false

	print("  [PASS] SemanticZoomService emits zoom_level_changed signal only on level transition.")
	return true

func test_lab_view_modes() -> bool:
	print("Running Test Suite: Lab View Modes Switching...")
	var LabViewModesScript = preload("res://scripts/lab_view_modes.gd")
	var dummy_node = Node3D.new()
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "Hull_Plate"
	dummy_node.add_child(mesh_inst)

	var vm = LabViewModesScript.new(dummy_node)
	if vm.current_mode != LabViewModesScript.ViewMode.DEFAULT:
		print("  [FAIL] Expected default mode DEFAULT")
		dummy_node.queue_free()
		return false

	var emitted = [false]
	vm.view_mode_changed.connect(func(mode): emitted[0] = true)

	vm.set_view_mode(LabViewModesScript.ViewMode.XRAY)
	if vm.current_mode != LabViewModesScript.ViewMode.XRAY or not emitted[0]:
		print("  [FAIL] Expected XRAY mode and signal emission. current_mode=%s, signal_emitted=%s" % [vm.current_mode, emitted[0]])
		dummy_node.queue_free()
		return false

	if mesh_inst.material_override == null:
		print("  [FAIL] VisualBuilder should set material_override for XRAY mode. mesh_children=%d" % dummy_node.find_children("*", "MeshInstance3D", true, false).size())
		dummy_node.queue_free()
		return false

	dummy_node.queue_free()
	print("  [PASS] LabViewModes correctly toggles modes and updates materials.")
	return true
