# probe_sensor_suites.gd
# Comprehensive test probe for expanded sensor suites

@tool
extends SceneTree

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const ModuleData = preload("res://scripts/module_data.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")
const VisionService = preload("res://scripts/battle/vision/vision_service.gd")

func _init() -> void:
	print("--- EXTENDED SENSOR SUITES PROBE ---")
	var success := true
	var root = Node3D.new()
	get_root().add_child(root)

	# 1. Test Catalog Registration
	var sensor_ids := ["sensor_suite", "directional_radar", "topographic_radar", "seismic_sensor", "thermal_imager"]
	for tid in sensor_ids:
		if not ModuleCatalog.module_exists(tid):
			print("FAIL: Module not found in catalog: ", tid)
			success = false
		else:
			var data = ModuleCatalog.get_module_data(tid)
			print("PASS: Found in catalog: ", tid, " (", data.get("name"), ")")

	# 2. Test ModuleData & Tweak Calculations
	var dir_mod = ModuleData.new()
	dir_mod.type_id = "directional_radar"
	dir_mod.base_vision_bonus = 85.0
	dir_mod.tweaks = {"scan_arc": 60.0, "mast_height": 1.0}
	var base_bonus = dir_mod.get_vision_bonus()
	dir_mod.tweaks = {"scan_arc": 40.0, "mast_height": 1.0}
	var narrow_bonus = dir_mod.get_vision_bonus()
	if narrow_bonus <= base_bonus:
		print("FAIL: Narrow scan_arc did not increase directional vision bonus!")
		success = false
	else:
		print("PASS: Directional radar scan_arc narrow focusing works: ", base_bonus, " -> ", narrow_bonus)

	var topo_mod = ModuleData.new()
	topo_mod.type_id = "topographic_radar"
	topo_mod.tweaks = {"survey_radius": 1.5, "pylon_height": 1.2}
	var survey_r = topo_mod.get_survey_radius()
	if survey_r <= 140.0:
		print("FAIL: Topographic survey radius calculation failed: ", survey_r)
		success = false
	else:
		print("PASS: Topographic survey radius calculated: ", survey_r)

	var seis_mod = ModuleData.new()
	seis_mod.type_id = "seismic_sensor"
	seis_mod.tweaks = {"ground_coupling": 1.4, "housing_girth": 1.1}
	var seis_r = seis_mod.get_seismic_range()
	if seis_r <= 75.0:
		print("FAIL: Seismic range calculation failed: ", seis_r)
		success = false
	else:
		print("PASS: Seismic range calculated: ", seis_r)

	var therm_mod = ModuleData.new()
	therm_mod.type_id = "thermal_imager"
	therm_mod.base_vision_bonus = 35.0
	therm_mod.tweaks = {"optic_aperture": 1.5, "mast_height": 1.2}
	var therm_bonus = therm_mod.get_vision_bonus()
	if therm_bonus <= 35.0 or not therm_mod.is_thermal_sensor():
		print("FAIL: Thermal imager calculation failed: ", therm_bonus)
		success = false
	else:
		print("PASS: Thermal imager bonus calculated: ", therm_bonus)

	# 3. Test Visual Builder Assembly
	var dummy_parent = Node3D.new()
	root.add_child(dummy_parent)
	for tid in sensor_ids:
		var node = Node3D.new()
		dummy_parent.add_child(node)
		VisualBuilder.build_visual(tid, node, Vector3.ONE, Color.WHITE, {
			"mast_height": 1.5, "scan_arc": 90.0, "survey_radius": 1.2,
			"ground_coupling": 1.3, "housing_girth": 1.1, "optic_aperture": 1.4, "dish_aperture": 1.2
		})
		if node.get_child_count() == 0:
			print("FAIL: Visual builder produced no children for ", tid)
			success = false
		else:
			print("PASS: Visual builder assembled ", tid, " with ", node.get_child_count(), " parts.")
		node.queue_free()

	# 4. Test VisionService Simulator Behaviors
	var vs = VisionService.new()
	vs.setup(root, 0, 100.0, 1.0)

	# Mock Viewer Unit with Directional Radar facing -Z (North)
	var viewer = Node3D.new()
	root.add_child(viewer)
	viewer.position = Vector3.ZERO
	viewer.set_meta("team", 0)
	viewer.set_meta("vision_range", 20.0)
	viewer.set_meta("directional_sensors", [{
		"range": 100.0,
		"arc_deg": 60.0,
		"arc_rad": deg_to_rad(60.0)
	}])
	viewer.set_meta("seismic_range", 60.0)
	viewer.set_meta("topographic_range", 80.0)
	viewer.set_meta("has_thermal_sight", true)

	# Target directly ahead (in 60 deg cone) at 70m
	var target_front = Node3D.new()
	root.add_child(target_front)
	target_front.position = Vector3(0, 0, -70)
	target_front.set_meta("team", 1)

	# Target directly behind at 70m
	var target_behind = Node3D.new()
	root.add_child(target_behind)
	target_behind.position = Vector3(0, 0, 70)
	target_behind.set_meta("team", 1)

	var spotted_front = vs._is_spotted(target_front, [viewer], [], false)
	var spotted_behind = vs._is_spotted(target_behind, [viewer], [], false)

	if not spotted_front:
		print("FAIL: Directional radar failed to spot target inside forward sector!")
		success = false
	else:
		print("PASS: Directional radar spotted target inside forward sector at 70m.")

	if spotted_behind:
		print("FAIL: Directional radar erroneously spotted target outside sector (behind)!")
		success = false
	else:
		print("PASS: Directional radar correctly ignored target outside sector (behind).")

	# Test Seismic Sensor (Moving ground target vs stationary target)
	var target_moving = Node3D.new()
	root.add_child(target_moving)
	target_moving.position = Vector3(40, 0, 0)
	target_moving.set_meta("team", 1)
	target_moving.set_meta("velocity", Vector3(5, 0, 0))

	var target_stationary = Node3D.new()
	root.add_child(target_stationary)
	target_stationary.position = Vector3(40, 0, 0)
	target_stationary.set_meta("team", 1)
	target_stationary.set_meta("velocity", Vector3.ZERO)

	var target_moving_air = Node3D.new()
	root.add_child(target_moving_air)
	target_moving_air.position = Vector3(40, 10, 0)
	target_moving_air.set_meta("team", 1)
	target_moving_air.set_meta("velocity", Vector3(5, 0, 0))
	target_moving_air.set_meta("is_flying", true)

	# Viewer with only seismic sensor (no omni/dir sight)
	var seismic_viewer = Node3D.new()
	root.add_child(seismic_viewer)
	seismic_viewer.position = Vector3.ZERO
	seismic_viewer.set_meta("team", 0)
	seismic_viewer.set_meta("vision_range", 0.0)
	seismic_viewer.set_meta("seismic_range", 50.0)

	var spotted_seis_moving = vs._is_spotted(target_moving, [seismic_viewer], [], false)
	var spotted_seis_stat = vs._is_spotted(target_stationary, [seismic_viewer], [], false)
	var spotted_seis_air = vs._is_spotted(target_moving_air, [seismic_viewer], [], false)

	if not spotted_seis_moving:
		print("FAIL: Seismic sensor failed to detect moving ground vehicle!")
		success = false
	else:
		print("PASS: Seismic sensor detected moving ground vehicle.")

	if spotted_seis_stat:
		print("FAIL: Seismic sensor erroneously detected stationary vehicle!")
		success = false
	else:
		print("PASS: Seismic sensor correctly ignored stationary vehicle.")

	if spotted_seis_air:
		print("FAIL: Seismic sensor erroneously detected flying aircraft!")
		success = false
	else:
		print("PASS: Seismic sensor correctly ignored flying aircraft.")

	# Test Topographic Shroud Mapping
	var topo_viewer = Node3D.new()
	root.add_child(topo_viewer)
	topo_viewer.position = Vector3.ZERO
	topo_viewer.set_meta("team", 0)
	topo_viewer.set_meta("vision_range", 10.0)
	topo_viewer.set_meta("topographic_range", 60.0)

	vs._update_shroud([topo_viewer], [])
	var cell_inside_survey = vs.cell_explored(30.0, 30.0)
	var cell_outside_survey = vs.cell_explored(85.0, 85.0)

	if not cell_inside_survey:
		print("FAIL: Topographic surveyor did not mark cell inside survey radius as explored!")
		success = false
	else:
		print("PASS: Topographic surveyor marked cell inside survey radius as explored.")

	if cell_outside_survey:
		print("FAIL: Cell outside survey radius was erroneously marked explored!")
		success = false
	else:
		print("PASS: Cell outside survey radius remains unexplored.")

	# Clean up
	root.queue_free()

	if success:
		print(">>> ALL SENSOR SUITE VERIFICATION TESTS COMPLETED SUCCESSFULLY! <<<")
	else:
		print(">>> SOME SENSOR SUITE TESTS FAILED! <<<")
	quit(0 if success else 1)
