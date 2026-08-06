@tool
extends SceneTree

func _init():
	print("=== Running Support Modules Unit Test ===")
	_test_catalog_definitions()
	_test_visual_assembly()
	_test_fire_control_radar_vision()
	_test_energy_barrier_projector_shield()
	print("=== All Support Module Tests Passed Successfully! ===")
	quit(0)

func _test_catalog_definitions():
	var cat = ModuleCatalog.get_catalog()
	assert("laser_designator" in cat, "laser_designator catalog entry missing")
	assert("energy_barrier_projector" in cat, "energy_barrier_projector catalog entry missing")
	assert("fire_control_radar" in cat, "fire_control_radar catalog entry missing")
	assert("laser_designator" in ModuleCatalog.SUPPORT_TYPE_IDS, "laser_designator missing from SUPPORT_TYPE_IDS")
	assert("energy_barrier_projector" in ModuleCatalog.SUPPORT_TYPE_IDS, "energy_barrier_projector missing from SUPPORT_TYPE_IDS")
	assert("fire_control_radar" in ModuleCatalog.SUPPORT_TYPE_IDS, "fire_control_radar missing from SUPPORT_TYPE_IDS")
	print("  [PASS] Catalog definitions verified.")

func _test_visual_assembly():
	var VisualBuilder = load("res://scripts/visual_builder.gd")
	assert(VisualBuilder.MODULAR_ASSEMBLY_TYPES.get("laser_designator", false), "laser_designator missing from MODULAR_ASSEMBLY_TYPES")
	assert(VisualBuilder.MODULAR_ASSEMBLY_TYPES.get("energy_barrier_projector", false), "energy_barrier_projector missing from MODULAR_ASSEMBLY_TYPES")
	assert(VisualBuilder.MODULAR_ASSEMBLY_TYPES.get("fire_control_radar", false), "fire_control_radar missing from MODULAR_ASSEMBLY_TYPES")
	
	var parent = Node3D.new()
	VisualBuilder.build_visual("laser_designator", parent, Vector3(0.6, 0.7, 0.6), Color.PALE_VIOLET_RED, {})
	assert(parent.get_child_count() > 0, "laser_designator visual assembly empty")
	
	var parent2 = Node3D.new()
	VisualBuilder.build_visual("fire_control_radar", parent2, Vector3(0.7, 1.8, 0.7), Color.DODGER_BLUE, {})
	assert(parent2.get_child_count() > 0, "fire_control_radar visual assembly empty")
	print("  [PASS] Visual assembly verified.")

func _test_fire_control_radar_vision():
	var BattleUnitClass = load("res://scripts/battle_unit.gd")
	var unit = BattleUnitClass.new()
	var hull = Node3D.new()
	unit.hull_node = hull
	unit._hull_type_for_vision = "medium_hull"
	
	var mod = Node3D.new()
	var ModuleDataClass = load("res://scripts/module_data.gd")
	var data = ModuleDataClass.new()
	data.type_id = "fire_control_radar"
	mod.set_meta("module_data", data)
	hull.add_child(mod)
	
	unit.max_weapon_range = 140.0
	unit._recalculate_vision()
	assert(hull.has_meta("has_fire_control_radar") and hull.get_meta("has_fire_control_radar") == true, "fire_control_radar meta missing")
	assert(hull.get_meta("fire_control_max_range") >= 140.0, "fire_control_max_range incorrect")
	print("  [PASS] Fire control radar vision mechanics verified.")

func _test_energy_barrier_projector_shield():
	var VisualBuilder = load("res://scripts/visual_builder.gd")
	var aabb = AABB(Vector3(-2, -0.75, -3), Vector3(4, 1.5, 6))
	var shield_arc = VisualBuilder.build_shield_facet_arc("right", aabb, Transform3D.IDENTITY)
	assert(shield_arc != null, "build_shield_facet_arc returned null")
	assert(shield_arc.mesh != null, "shield_arc mesh missing")
	assert(shield_arc.material_override != null, "shield_arc shader material missing")
	print("  [PASS] Energy barrier projector shield arc generation verified.")
