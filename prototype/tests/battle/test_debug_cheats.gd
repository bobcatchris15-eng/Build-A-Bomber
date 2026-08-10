extends "res://tests/suite_base.gd"

const EconomyServiceScript = preload("res://scripts/battle/economy/economy_service.gd")
const ProductionServiceScript = preload("res://scripts/battle/economy/production_service.gd")
const VisionServiceScript = preload("res://scripts/battle/vision/vision_service.gd")
const DebugSettingsScript = preload("res://scripts/debug_settings.gd")


func _get_or_create_debug_settings() -> Node:
	var target_root: Window = root
	if target_root == null:
		var main_tree = tree if tree != null else (Engine.get_main_loop() as SceneTree)
		if main_tree != null:
			target_root = main_tree.root
	if target_root != null:
		var ds = target_root.get_node_or_null("DebugSettings")
		if ds != null:
			return ds
		ds = DebugSettingsScript.new()
		ds.name = "DebugSettings"
		target_root.add_child(ds)
		return ds
	return DebugSettingsScript.new()


func test_infinite_resources_cheat() -> bool:
	print("Running Test: Infinite Resources Cheat...")
	var ds = _get_or_create_debug_settings()

	ds.infinite_player_resources = true
	var econ = EconomyServiceScript.new()
	econ.add_team(0, 100)

	if econ.credits(0) != 999999:
		print("  [FAIL] Expected credits(0) to be 999999 when cheat active, got ", econ.credits(0))
		ds.infinite_player_resources = false
		return false

	if not econ.can_afford(0, 50000):
		print("  [FAIL] Expected can_afford(0, 50000) to return true")
		ds.infinite_player_resources = false
		return false

	if not econ.spend(0, 50000):
		print("  [FAIL] Expected spend(0, 50000) to return true")
		ds.infinite_player_resources = false
		return false

	ds.infinite_player_resources = false
	if econ.credits(0) != 100:
		print("  [FAIL] Expected credits(0) to revert to 100 after turning cheat off, got ", econ.credits(0))
		return false

	print("  [PASS] Infinite Resources Cheat")
	return true


func test_instant_build_cheat() -> bool:
	print("Running Test: Instant Build Cheat...")
	var ds = _get_or_create_debug_settings()

	ds.instant_build = true
	var econ = EconomyServiceScript.new()
	econ.add_team(0, 1000)

	var prod = ProductionServiceScript.new()
	prod.setup(econ, null)
	prod.add_team(0)

	var bp := {"name": "TEST_UNIT", "hull_type": "light_tank"}
	var job := prod.enqueue_unit(0, bp, 100, 20.0, "light")

	if job.is_empty():
		print("  [FAIL] Enqueue failed")
		ds.instant_build = false
		return false

	if job["time_left"] > 0.01:
		print("  [FAIL] Expected instant build time_left ~ 0.001, got ", job["time_left"])
		ds.instant_build = false
		return false

	prod.tick(0.01)
	if not job["done"]:
		print("  [FAIL] Expected job to be marked done after tick")
		ds.instant_build = false
		return false

	ds.instant_build = false
	print("  [PASS] Instant Build Cheat")
	return true


func test_reveal_all_fog_cheat() -> bool:
	print("Running Test: Reveal All Fog Cheat...")
	var ds = _get_or_create_debug_settings()

	ds.reveal_all_fog = true
	var vision = VisionServiceScript.new()

	var dummy := Node3D.new()
	dummy.set_meta("team", 1)

	if not vision.is_visible_to_team(dummy, 0):
		print("  [FAIL] Expected dummy to be visible to team 0 when reveal_all_fog is active")
		dummy.queue_free()
		ds.reveal_all_fog = false
		return false

	if not vision.cell_explored(10.0, 10.0):
		print("  [FAIL] Expected cell_explored to return true when reveal_all_fog is active")
		dummy.queue_free()
		ds.reveal_all_fog = false
		return false

	dummy.queue_free()
	ds.reveal_all_fog = false
	print("  [PASS] Reveal All Fog Cheat")
	return true
