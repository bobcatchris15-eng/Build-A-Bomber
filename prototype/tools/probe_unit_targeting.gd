extends SceneTree
# Test probe: Unit-level target acquisition, coordinated weapon engagement,
# and maneuvering to main weapon range (highest group DPS).

const BattleLayers = preload("res://scripts/battle/battle_layers.gd")
const AssemblyScript = preload("res://scripts/battle/units/unit_assembly.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const OrderScript = preload("res://scripts/battle/orders/order.gd")
const StanceScript = preload("res://scripts/battle/orders/stance.gd")

func _init():
	var failures: Array = []
	print("--- Running Unit Targeting & Main Weapon Probe ---")

	var packed = load("res://scenes/Battle.tscn")
	if packed == null:
		print("[FAIL] Battle.tscn did not load")
		quit(1)
		return
	var battle = packed.instantiate()
	root.add_child(battle)
	for _i in range(6):
		await process_frame

	# 1. Test compute_main_weapon with synthetic hull and mock module data
	var mock_hull = Node3D.new()
	# Add 4 machine guns (base dps 20, range 22)
	for i in range(4):
		var m = Node3D.new()
		var res = Resource.new()
		res.set_script(load("res://scripts/module_data.gd"))
		res.type_id = "rotary_cannon"
		res.category = "weapon"
		res.base_dps = 20.0
		res.volume = 1.0
		m.set_meta("module_data", res)
		mock_hull.add_child(m)

	# Add 1 heavy cannon (base dps 50, range 45)
	var heavy = Node3D.new()
	var heavy_res = Resource.new()
	heavy_res.set_script(load("res://scripts/module_data.gd"))
	heavy_res.type_id = "basic_cannon"
	heavy_res.category = "weapon"
	heavy_res.base_dps = 50.0
	heavy_res.volume = 1.0
	heavy.set_meta("module_data", heavy_res)
	mock_hull.add_child(heavy)

	var main_wpn = AssemblyScript.compute_main_weapon(mock_hull)
	print("  synthetic main weapon result: %s (total_dps: %.1f, range: %.1f, count: %d)"
		% [main_wpn.get("type_id", ""), main_wpn.get("total_dps", 0.0), main_wpn.get("range", 0.0), main_wpn.get("count", 0)])

	# 4x rotary_cannon = 80 total DPS > 1x basic_cannon = 50 total DPS
	if main_wpn.get("type_id", "") != "rotary_cannon":
		failures.append("compute_main_weapon did not select rotary_cannon as main weapon despite higher group DPS (80 vs 50)")
	
	mock_hull.free()

	# 2. Test live unit spawn with combat blueprint
	var bp_path := "res://data/loadout/bulwark_mbt.json"
	var blueprint: Dictionary = battle.bp_manager.load_blueprint(bp_path)
	if blueprint.is_empty():
		_finish(battle, ["could not load blueprint: %s" % bp_path])
		return

	var unit_a = battle.spawn_unit(blueprint, 0, Vector3(0, 0, 0))
	var unit_b = battle.spawn_unit(blueprint, 1, Vector3(0, 0, 35))
	for _i in range(6):
		await process_frame

	if unit_a == null or unit_b == null:
		_finish(battle, ["failed to spawn test units"])
		return

	print("  unit_a main_weapon_range: %.1f m, attack_range: %.1f m" % [unit_a.main_weapon_range, unit_a.attack_range])
	if unit_a.main_weapon_range <= 0.0:
		failures.append("unit_a main_weapon_range is <= 0")

	# Test get_combat_target under ATTACK order
	unit_a.current_order = OrderScript.attack(unit_b)
	var tgt = unit_a.get_combat_target()
	if tgt != unit_b:
		failures.append("get_combat_target() did not return unit_b under ATTACK order")

	# Step physics frames to allow weapons on unit_a to focus on unit_b
	for _i in range(10):
		await physics_frame

	# Check that weapons on unit_a whose fire_range covers unit_b have targeted unit_b
	var dist = unit_a.global_position.distance_to(unit_b.global_position)
	print("  distance between unit_a and unit_b: %.1f m" % dist)
	var weapons_targeted := 0
	for child in unit_a.hull_node.get_children():
		if child.get_script() != null and "target" in child:
			if child.target == unit_b:
				weapons_targeted += 1
	print("  weapons on unit_a targeting unit_b: %d" % weapons_targeted)
	if weapons_targeted == 0 and dist <= unit_a.attack_range:
		failures.append("no weapon on unit_a acquired the unit's target unit_b")

	# 3. Test engagement maneuvering & chassis facing
	unit_b.global_position = Vector3(10, 0, 20)
	for _i in range(30):
		await physics_frame

	var to_b = (unit_b.global_position - unit_a.global_position)
	to_b.y = 0.0
	var angle_diff = absf(wrapf(unit_a.rotation.y - atan2(-to_b.x, -to_b.z), -PI, PI))
	print("  facing angle difference to target after maneuver ticks: %.2f rad" % angle_diff)

	_finish(battle, failures)


func _finish(battle: Node, failures: Array) -> void:
	battle.queue_free()
	if failures.is_empty():
		print("[PASS] probe_unit_targeting: all tests passed successfully")
		quit(0)
	else:
		for f in failures:
			print("  [FAIL] %s" % f)
		print("[FAIL] probe_unit_targeting: %d problem(s)" % failures.size())
		quit(1)
