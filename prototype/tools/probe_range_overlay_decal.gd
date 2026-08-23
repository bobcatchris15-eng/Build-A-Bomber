extends SceneTree
# Test probe: Range and Vision overlay Decals, terrain reach computation, and target acquisition.

const BattleLayers = preload("res://scripts/battle/battle_layers.gd")

func _init():
	var failures: Array = []
	print("--- Running Range Overlay Decal & LOS Probe ---")

	var packed = load("res://scenes/Battle.tscn")
	if packed == null:
		print("[FAIL] Battle.tscn did not load")
		quit(1)
		return
	var battle = packed.instantiate()
	root.add_child(battle)
	for _i in range(6):
		await process_frame

	var bp_path := "res://data/loadout/bulwark_mbt.json"
	var blueprint: Dictionary = battle.bp_manager.load_blueprint(bp_path)
	if blueprint.is_empty():
		_finish(battle, ["could not load %s" % bp_path])
		return

	# 1. Spawn unit and verify overlay creation
	var unit = battle.spawn_unit(blueprint, 0, Vector3(0, 0, 0))
	for _i in range(6):
		await process_frame

	if unit == null:
		_finish(battle, ["spawn_unit returned null"])
		return

	print("  spawned unit: attack_range=%.1f m, vision_range=%.1f m" % [unit.attack_range, unit.vision_range])

	# Select unit
	unit.set_selected(true)
	for _i in range(4):
		await process_frame

	# Check overlays
	var targetable = unit._targetable_overlay
	var visible_ov = unit._visible_overlay

	if targetable == null or not (targetable is Decal):
		failures.append("_targetable_overlay is not a Decal")
	else:
		print("  _targetable_overlay Decal: size=%s, visible=%s, texture=%s" % [
			targetable.size, targetable.visible, targetable.texture_albedo != null
		])
		if not targetable.visible:
			failures.append("_targetable_overlay is not visible when selected")
		if targetable.texture_albedo == null:
			failures.append("_targetable_overlay texture_albedo is null")
		if targetable.size.x <= 0.0 or targetable.size.z <= 0.0:
			failures.append("_targetable_overlay decal size is invalid")

	if visible_ov == null or not (visible_ov is Decal):
		failures.append("_visible_overlay is not a Decal")
	else:
		print("  _visible_overlay Decal: size=%s, visible=%s, texture=%s" % [
			visible_ov.size, visible_ov.visible, visible_ov.texture_albedo != null
		])
		if not visible_ov.visible:
			failures.append("_visible_overlay is not visible when selected")
		if visible_ov.texture_albedo == null:
			failures.append("_visible_overlay texture_albedo is null")

	# 2. Test toggling range overlay visibility
	unit.set_range_overlay_visible(false)
	if targetable != null and targetable.visible:
		failures.append("_targetable_overlay remained visible after set_range_overlay_visible(false)")
	if visible_ov != null and visible_ov.visible:
		failures.append("_visible_overlay remained visible after set_range_overlay_visible(false)")

	unit.set_range_overlay_visible(true)
	if targetable != null and not targetable.visible:
		failures.append("_targetable_overlay not visible after set_range_overlay_visible(true)")

	# 3. Test deselecting unit
	unit.set_selected(false)
	if targetable != null and targetable.visible:
		failures.append("_targetable_overlay visible when deselected")
	if visible_ov != null and visible_ov.visible:
		failures.append("_visible_overlay visible when deselected")

	# 4. Test 2.5D heightmap reach calculation
	var reaches = unit._compute_terrain_reach(50.0, 32, false)
	print("  computed terrain reaches sample count: %d, min=%.1f, max=%.1f" % [
		reaches.size(), reaches.min(), reaches.max()
	])
	if reaches.size() != 32:
		failures.append("reaches size mismatch: expected 32, got %d" % reaches.size())
	if reaches.max() <= 0.0:
		failures.append("reaches max <= 0.0")

	_finish(battle, failures)


func _finish(battle: Node, failures: Array) -> void:
	battle.queue_free()
	if failures.is_empty():
		print("[PASS] probe_range_overlay_decal: all checks passed")
		quit(0)
	else:
		for f in failures:
			print("  [FAIL] %s" % f)
		print("[FAIL] probe_range_overlay_decal: %d failures" % failures.size())
		quit(1)
