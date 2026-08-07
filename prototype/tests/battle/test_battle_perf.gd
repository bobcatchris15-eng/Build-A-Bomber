extends "res://tests/suite_base.gd"
# Performance regressions that are CORRECTNESS bugs wearing a stopwatch.
#
# Chris, 2026-08-07, after three skirmish matches: "the FPS drops steadily from
# the beginning of the match, and for most of the play time it was under 10
# FPS." It was one line. unit.gd::_apply_vertical() writes global_position.y
# from the terrain heightmap every tick - the heightmap is authoritative - but
# unit_assembly.gd also masked BattleLayers.TERRAIN, so move_and_slide() then
# re-solved the same axis against the terrain's physics collider, which is only
# a subdivided approximation of the heightmap surface. The two never agree, so
# every unit was placed fractionally inside the mesh and depenetrated back out,
# every frame, against a full-map trimesh.
#
#     move_and_slide()  52.33 ms/frame -> 0.108 ms/frame   (16 units, headless)
#     whole frame       56.41 ms       -> 16.61 ms         (the 60 fps floor)
#
# WHY THIS IS ASSERTED AS A MASK AND NOT AS A FRAME TIME. A wall-clock budget
# in a suite that runs on whatever machine is free, alongside 225 other suites,
# is a flake generator - it fails on a loaded CI box and passes on a fast one,
# and neither result says anything about the bug. The mask bit is the actual
# invariant: whoever owns an axis owns it alone. That is exact, machine
# independent, and fails the instant someone re-adds TERRAIN to the mask.
#
# The second test is the other half of the same invariant, and the reason the
# mask cannot simply be dropped everywhere: with no controller to ask for a
# height, gravity is the fallback and the unit genuinely does need a floor.

const UnitScript = preload("res://scripts/battle/units/unit.gd")
const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")

# Everything this suite parents to the root, so both tests can clean up without
# leaking a half-built unit into whatever runs next.
var _spawned: Array = []


# A controller that answers terrain_height_at() and nothing else - which is
# precisely the capability _resolve_terrain_collision() keys on.
class HeightStub:
	extends Node
	var asked := 0
	func terrain_height_at(_p: Vector3) -> float:
		asked += 1
		return 3.0


func _track(node: Node) -> Node:
	root.add_child(node)
	_spawned.append(node)
	return node


func _cleanup() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()


func _spawn(controller: Node):
	var bp_manager = BlueprintManagerScript.new()
	_track(bp_manager)
	var unit = UnitScript.new()
	_track(unit)
	var blueprint := {
		"hull_type": "medium_hull",
		"modules": [],
		"locomotion": {"type_id": "wheels", "settings": {}},
	}
	var ok: bool = unit.setup(blueprint, 0, bp_manager, controller)
	return unit if ok else null


func test_heightmap_authority_removes_terrain_from_the_collision_mask() -> bool:
	print("Running Test Suite: Ground units do not fight the terrain they are placed on...")

	var stub := HeightStub.new()
	_track(stub)
	var unit = _spawn(stub)
	var ok := _check_heightmap_authority(unit, stub)
	_cleanup()
	return ok


func _check_heightmap_authority(unit, stub) -> bool:
	if unit == null:
		print("  [FAIL] unit failed to assemble")
		return false

	if unit.collision_mask & BattleLayers.TERRAIN:
		print("  [FAIL] TERRAIN is still masked while the heightmap owns Y - ",
			"move_and_slide() will depenetrate against the terrain collider every frame")
		return false

	# BUILDINGS must survive: it is the backstop for a unit already mid-path
	# when a structure goes up, and dropping it with TERRAIN would be a silent
	# collision regression rather than an optimisation.
	if not (unit.collision_mask & BattleLayers.BUILDINGS):
		print("  [FAIL] BUILDINGS was dropped from the mask along with TERRAIN")
		return false

	# And the heightmap really is driving Y - otherwise the mask change would
	# be removing the only thing holding the unit up.
	unit.global_position = Vector3(0.0, 50.0, 0.0)
	unit._apply_vertical(1.0 / 60.0)
	if absf(unit.global_position.y - 3.0) > 0.001:
		print("  [FAIL] heightmap did not place the unit: y=", unit.global_position.y,
			" expected 3.0")
		return false
	if stub.asked == 0:
		print("  [FAIL] _apply_vertical never consulted terrain_height_at()")
		return false

	print("  [PASS] Heightmap owns Y alone; TERRAIN is unmasked, BUILDINGS kept.")
	return true


func test_a_unit_with_no_controller_keeps_terrain_collision() -> bool:
	print("Running Test Suite: Without a heightmap to ask, a unit still has a floor...")

	var unit = _spawn(null)
	var ok := true
	if unit == null:
		print("  [FAIL] unit failed to assemble")
		ok = false
	elif not (unit.collision_mask & BattleLayers.TERRAIN):
		print("  [FAIL] TERRAIN was dropped with no controller to supply heights - ",
			"this unit falls forever")
		ok = false
	else:
		print("  [PASS] Gravity fallback keeps TERRAIN masked.")
	_cleanup()
	return ok
