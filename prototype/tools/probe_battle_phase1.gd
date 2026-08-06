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
const TICKS := 4200


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
		# Laid out BEHIND the spawn point relative to the map centre, not in front
		# of it. The original layout ran +14..+20 m outward, which put the back rank
		# past the HQ and hard against the map boundary, where a unit has a valid
		# field direction and simply cannot travel. That produced a permanent
		# straggler and made the squad look like a movement failure it wasn't.
		var at := origin + Vector3(float(i % 4) * 6.0 - 9.0, 0.0, -float(i / 4) * 6.0 - 14.0)
		var u = battle.spawn_unit(blueprint, 0, at)
		if u != null:
			squad.append(u)
	for _i in range(4):
		await process_frame
	print("  squad size: %d" % squad.size())
	for s in battle.get_team_structures(0):
		var nearest := 1.0e9
		var who := -1
		for i in range(squad.size()):
			var d: float = Vector2(s.global_position.x - squad[i].global_position.x,
				s.global_position.z - squad[i].global_position.z).length()
			if d < nearest:
				nearest = d
				who = i
		print("    structure %s at %s - nearest squad member [%d] at %.1f m"
			% [s.kind, str(s.global_position.round()), who, nearest])
	if squad.size() < FlowFieldServiceScript.FIELD_MIN_UNITS:
		failures.append("squad too small to exercise the flow field")
		_finish(battle, failures)
		return

	# --- Formation ----------------------------------------------------------
	# The destination is the mirror of the spawn across the map, not a fixed
	# offset. The offset this used to use put the destination ~60 m away, under
	# FlowFieldService.MIN_TRIP_DISTANCE, so no field was ever built and the whole
	# probe silently measured the per-agent fallback - passing while the path it
	# exists to test never ran. A cross-map trip is the case a field is FOR.
	var destination := Vector3(origin.x, 0.0, -origin.z)
	destination.y = battle.terrain_height_at(destination)
	var trip: float = origin.distance_to(destination)
	print("  trip length: %.1f m (field gate is %.1f m)"
		% [trip, FlowFieldServiceScript.MIN_TRIP_DISTANCE])
	if trip < FlowFieldServiceScript.MIN_TRIP_DISTANCE:
		failures.append("trip is %.1f m, under the field gate - this probe would not test the field" % trip)
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
	var field = battle.flow_fields.field_for(destination, squad.size(), trip)
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
	var start_positions: Dictionary = {}
	for u in squad:
		assigned[u] = u.current_order.position
		start_positions[u] = u.global_position

	# Confirm the field is actually steering before spending 1800 ticks measuring
	# where everyone ended up. A zero direction here means the run below is the
	# per-agent fallback again, and its numbers say nothing about the blend.
	var probe_dir: Vector3 = battle.flow_direction_for(squad[0].current_order, squad[0].global_position)
	var probe_weight: float = FlowFieldServiceScript.field_weight(
		squad[0].global_position.distance_to(destination))
	print("  field at departure: dir %s  weight %.2f" % [str(probe_dir.normalized()), probe_weight])
	if probe_dir == Vector3.ZERO:
		failures.append("the field is not steering at departure - the travel run below is the fallback path")
	if probe_weight <= 0.0:
		failures.append("field weight is zero at departure (blend never engages)")

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
	# Per unit, so a single unit that never left the start line is distinguishable
	# from a squad that is merely slow - the summary statistics read the same.
	for i in range(squad.size()):
		var u = squad[i]
		var moved: float = start_positions[u].distance_to(u.global_position)
		var route: bool = field != null and field.has_route(start_positions[u])
		print("    [%2d] moved %6.1f m  to-slot %6.1f m  speed %4.1f  route-at-spawn %s"
			% [i, moved, u.global_position.distance_to(assigned[u]),
				Vector2(u.velocity.x, u.velocity.z).length(), str(route)])
		# Anything that commanded full throttle and went nowhere is the interesting
		# case: `velocity` above is the COMMANDED velocity, not the achieved one, so
		# a pinned unit and a cruising one read identically. Dump its real state.
		if moved < 20.0:
			var here: Vector3 = u.global_position
			var flow_here: Vector3 = battle.flow_direction_for(u.current_order, here)
			print("         STUCK at %s  on_wall %s  nav_finished %s  field-route-here %s  flow %s"
				% [str(here.round()), str(u.is_on_wall()),
					str(u.nav_agent.is_navigation_finished()) if is_instance_valid(u.nav_agent) else "no-agent",
					str(field != null and field.has_route(here)), str(flow_here.normalized().round())])
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
