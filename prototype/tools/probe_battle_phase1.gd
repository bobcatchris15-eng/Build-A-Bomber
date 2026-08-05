extends SceneTree
# Phase 1 acceptance: does the command layer actually command?
#
# The pure math (formation geometry, steering, order semantics) is covered by
# tests/battle/. This probe answers the questions that need a REAL match - a
# baked navmesh, real hulls, real physics - and which therefore cannot live in a
# suite cheaply:
#
#   * does a group order spread units out instead of piling them on one point
#   * does the flow field build against the real navmesh and find a route
#   * do units under a group order actually arrive, spread out, and stay spread
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_battle_phase1.gd

const StanceScript = preload("res://scripts/battle/orders/stance.gd")
const FlowFieldServiceScript = preload("res://scripts/battle/movement/flow_field_service.gd")

# Enough to cross the flow field's own threshold, so the field path is the one
# under test rather than the per-agent fallback.
const SQUAD_SIZE := 12
const TICKS := 1800


func _init():
	var failures: Array = []

	var packed = load("res://scenes/Battle.tscn")
	if packed == null:
		print("[FAIL] Battle.tscn did not load")
		quit(1)
		return
	var battle = packed.instantiate()
	root.add_child(battle)
	for _i in range(4):
		await process_frame

	# --- Build a squad ------------------------------------------------------
	# One blueprint repeated, so any spread in the result is the formation's
	# doing and not a difference in hull size or speed.
	var blueprint: Dictionary = battle.bp_manager.load_blueprint("res://data/loadout/bulwark_mbt.json")
	if blueprint.is_empty():
		print("[FAIL] could not load the reference blueprint")
		_finish(battle, ["missing bulwark_mbt.json"])
		return

	var spawn: Array = battle.get_team_units(0)
	var origin: Vector3 = spawn[0].global_position if not spawn.is_empty() else Vector3.ZERO
	var squad: Array = []
	for i in range(SQUAD_SIZE):
		var at := origin + Vector3(float(i % 4) * 6.0, 0.0, float(i / 4) * 6.0 + 14.0)
		var u = battle.spawn_unit(blueprint, 0, at)
		if u != null:
			squad.append(u)
	for _i in range(4):
		await process_frame
	print("  squad size: %d" % squad.size())
	if squad.size() < FlowFieldServiceScript.FIELD_MIN_UNITS:
		failures.append("squad too small to exercise the flow field")
		_finish(battle, failures)
		return

	# --- Formation ----------------------------------------------------------
	# The destination is well clear of the spawn so the units have to travel.
	var destination := Vector3(origin.x + 10.0, 0.0, origin.z - 60.0)
	destination.y = battle.terrain_height_at(destination)
	var group: int = battle.orders.move(squad, destination)
	print("  group id: %d" % group)

	var slots: Array = []
	for u in squad:
		if u.current_order == null:
			failures.append("%s got no order from OrderService" % u.name)
			continue
		slots.append(u.current_order.position)
		if u.current_order.group_destination.distance_to(destination) > 0.01:
			failures.append("%s lost the group destination the flow field keys on" % u.name)

	# Every unit must have its OWN slot. Identical slots is precisely the old
	# behaviour - one Vector3 handed to everybody - that formations replace.
	var duplicates := 0
	for i in range(slots.size()):
		for j in range(i + 1, slots.size()):
			if slots[i].distance_to(slots[j]) < 0.5:
				duplicates += 1
	print("  duplicate slots: %d" % duplicates)
	if duplicates > 0:
		failures.append("%d pairs of units share a formation slot" % duplicates)

	# --- Flow field ---------------------------------------------------------
	var field = battle.flow_fields.field_for(destination, squad.size())
	if field == null:
		failures.append("no flow field built for a %d-unit group" % squad.size())
	else:
		print("  field dims: %dx%d" % [field.dims.x, field.dims.y])
		if not field.has_route(origin):
			failures.append("the field found no route from the spawn to the destination")
		var dir = field.direction_at(origin)
		if dir == Vector3.ZERO:
			failures.append("the field has no direction at the spawn")
		else:
			# The field should point roughly toward the destination from here -
			# not exactly, since it routes around terrain, but not backwards.
			var straight := (destination - origin)
			straight.y = 0.0
			if dir.normalized().dot(straight.normalized()) < 0.0:
				failures.append("the field points away from the destination (dot %.2f)"
					% dir.normalized().dot(straight.normalized()))

	# --- Shift-queueing -----------------------------------------------------
	# Impossible before orders were a type: there was no object to put in a list.
	var queued_target := destination + Vector3(20.0, 0.0, 0.0)
	battle.orders.move([squad[0]], queued_target, true)
	if squad[0].order_queue.size() != 1:
		failures.append("a queued order did not append (queue is %d)" % squad[0].order_queue.size())

	# --- Stances ------------------------------------------------------------
	battle.orders.set_stance(squad, StanceScript.Kind.AGGRESSIVE)
	for u in squad:
		if u.stance != StanceScript.Kind.AGGRESSIVE:
			failures.append("%s did not take the ordered stance" % u.name)
			break
	battle.orders.hold([squad[1]])
	if squad[1].stance != StanceScript.Kind.HOLD_POSITION:
		failures.append("hold() should also set the HOLD_POSITION stance")

	# --- Travel -------------------------------------------------------------
	# Re-issue cleanly (the stance/queue pokes above touched two units) and run.
	battle.orders.move(squad, destination)
	# Each unit's OWN slot, captured at issue time. Measuring against the group
	# destination instead would score the rear rank of a box formation as
	# "failed to arrive" when it is standing exactly where it was told to.
	var assigned: Dictionary = {}
	for u in squad:
		assigned[u] = u.current_order.position

	for _i in range(TICKS):
		await physics_frame

	var arrived := 0
	var closest_pair := 1.0e9
	var distances: Array = []
	for u in squad:
		var d: float = u.global_position.distance_to(assigned[u])
		distances.append(d)
		if d < 8.0:
			arrived += 1
	distances.sort()
	# The distribution, not just the count: "five stragglers at 31 m" and "five
	# wedged against a cliff at 120 m" are the same pass/fail but completely
	# different problems.
	print("  distance to own slot: min %.1f  median %.1f  max %.1f"
		% [distances[0], distances[distances.size() / 2], distances[-1]])
	var still_moving := 0
	for u in squad:
		if Vector2(u.velocity.x, u.velocity.z).length() > 0.5:
			still_moving += 1
	print("  still moving at cutoff: %d" % still_moving)
	for i in range(squad.size()):
		for j in range(i + 1, squad.size()):
			var a: Vector3 = squad[i].global_position
			var b: Vector3 = squad[j].global_position
			closest_pair = minf(closest_pair, Vector2(a.x - b.x, a.z - b.z).length())
	print("  at own slot (<8 m): %d/%d" % [arrived, squad.size()])
	print("  closest pair after arrival: %.2f m" % closest_pair)

	if arrived < squad.size() * 3 / 4:
		failures.append("fewer than three quarters of the squad reached its own formation slot")
	# The real regression this guards: units converging onto one point and
	# shoving. Two medium hulls at under 2 m are inside each other.
	if closest_pair < 2.0:
		failures.append("units ended up stacked (closest pair %.2f m)" % closest_pair)

	_finish(battle, failures)


func _finish(battle: Node, failures: Array) -> void:
	battle.queue_free()
	await process_frame
	if failures.is_empty():
		print("[PASS] battle phase 1")
		quit(0)
	else:
		for f in failures:
			print("  [FAIL] %s" % f)
		print("[FAIL] battle phase 1: %d problem(s)" % failures.size())
		quit(1)
