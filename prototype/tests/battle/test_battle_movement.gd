extends "res://tests/suite_base.gd"
# Suites for the rebuilt battle layer (scripts/battle/). Registration order lives
# in run_tests.gd's SUITE_ORDER, not here.
#
# These test PURE FUNCTIONS directly rather than driving a match. That is not a
# shortcut - headless Godot cannot simulate held mouse-button state
# (`Input.parse_input_event` leaves `is_mouse_button_pressed` false, confirmed
# empirically 2026-07-12), so a drag-select or a click-to-move can never be
# exercised end to end. Keeping the math in movement/steering.gd as value-in
# value-out functions is what makes it testable at all.

const SteeringScript = preload("res://scripts/battle/movement/steering.gd")
const OrderScript = preload("res://scripts/battle/orders/order.gd")


# THE REGRESSION THIS SUITE EXISTS FOR.
#
# yaw_for() shipped with atan2(x, z) instead of atan2(-x, -z) - exactly 180
# degrees out. Nothing about it looked wrong: units turned smoothly, drove
# smoothly, and went the wrong way. It was caught by measuring a unit that ended
# up 46.8 m from a destination 25 m away.
#
# The assertion is the round trip, not the formula: build a Basis from the
# returned yaw, take its forward vector, and require it to point back along the
# direction that was asked for. That stays true if the convention is ever
# reworked, and it fails immediately if a sign flips.
func test_steering_yaw_faces_the_requested_direction() -> bool:
	print("Running Test Suite: Steering - yaw_for() round-trips through a Basis...")
	var directions := [
		Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(1, 0, -1).normalized(), Vector3(-3, 0, 2).normalized(),
		# Y must be ignored: steering is horizontal, and a destination up a hill
		# must not tilt the unit or shorten its heading vector.
		Vector3(0.6, 9.0, -0.8),
	]
	for dir in directions:
		var yaw: float = SteeringScript.yaw_for(dir, 0.0)
		var forward: Vector3 = -Basis(Vector3.UP, yaw).z
		var flat := Vector3(dir.x, 0.0, dir.z).normalized()
		if forward.distance_to(flat) > 0.001:
			print("  [FAIL] yaw_for(%s) -> %.4f rad, whose forward is %s, expected %s"
				% [dir, yaw, forward, flat])
			return false

	# A degenerate direction must hold the current facing, not snap to north. A
	# unit that has arrived should keep pointing where it was pointing.
	if SteeringScript.yaw_for(Vector3(0, 5, 0), 1.234) != 1.234:
		print("  [FAIL] A zero horizontal direction should return the fallback yaw unchanged")
		return false
	print("  [PASS] Steering yaw convention")
	return true


func test_steering_arrival_and_turn_rate() -> bool:
	print("Running Test Suite: Steering - arrival ramp, turn limiting, heading throttle...")

	# Full speed outside the slow radius, linear ramp inside it, nothing at the
	# destination. Without the ramp a unit arrives at full speed, overshoots, and
	# re-enters its own approach from the far side - the orbit bug.
	if not is_equal_approx(SteeringScript.arrival_speed(50.0, 10.0, 8.0), 10.0):
		print("  [FAIL] Outside the slow radius should be full speed")
		return false
	if not is_equal_approx(SteeringScript.arrival_speed(4.0, 10.0, 8.0), 5.0):
		print("  [FAIL] Half-way into the slow radius should be half speed, got ",
			SteeringScript.arrival_speed(4.0, 10.0, 8.0))
		return false
	if SteeringScript.arrival_speed(0.0, 10.0, 8.0) != 0.0:
		print("  [FAIL] Zero distance should be zero speed")
		return false
	# A zero slow radius must not divide by zero.
	if not is_equal_approx(SteeringScript.arrival_speed(3.0, 10.0, 0.0), 10.0):
		print("  [FAIL] A zero slow radius should fall back to full speed, not NaN")
		return false

	# Turning takes the SHORT way around. Going from just under +PI to just over
	# -PI is a small step across the wrap, not a near-full rotation back.
	var stepped: float = SteeringScript.turn_toward(3.0, -3.0, 0.5)
	if absf(wrapf(stepped - 3.0, -PI, PI)) > 0.5 + 0.001:
		print("  [FAIL] turn_toward crossed the wrap the long way: 3.0 -> ", stepped)
		return false
	if signf(wrapf(stepped - 3.0, -PI, PI)) <= 0.0:
		print("  [FAIL] turn_toward should step UP across the +PI boundary, got ", stepped)
		return false
	# Within one step, snap exactly rather than creeping.
	if not is_equal_approx(SteeringScript.turn_toward(1.0, 1.1, 0.5), 1.1):
		print("  [FAIL] A target inside max_step should be reached exactly")
		return false

	# Throttle: full when aligned, zero at the cutoff, and monotonic between.
	if not is_equal_approx(SteeringScript.heading_throttle(0.0, 0.0), 1.0):
		print("  [FAIL] An aligned heading should be full throttle")
		return false
	if SteeringScript.heading_throttle(0.0, PI) != 0.0:
		print("  [FAIL] A reversed heading should be zero throttle")
		return false
	var quarter: float = SteeringScript.heading_throttle(0.0, PI * 0.25)
	if quarter <= 0.0 or quarter >= 1.0:
		print("  [FAIL] A 45-degree error should throttle partially, got ", quarter)
		return false
	print("  [PASS] Steering arrival and turning")
	return true


func test_order_vocabulary_and_completion() -> bool:
	print("Running Test Suite: Order - construction, destinations, completion...")

	var move := OrderScript.move(Vector3(10, 0, 0), 7)
	if move.type != OrderScript.Type.MOVE or move.group_id != 7:
		print("  [FAIL] Order.move() did not carry its type and group")
		return false
	if not move.has_destination():
		print("  [FAIL] MOVE should have a destination")
		return false
	if not OrderScript.attack_move(Vector3.ZERO).has_destination():
		print("  [FAIL] ATTACK_MOVE should have a destination")
		return false
	# An ATTACK closes on a target that moves, so its destination is not a fixed
	# point and the movement layer must not treat it as one.
	if OrderScript.attack(null).has_destination():
		print("  [FAIL] ATTACK should not report a fixed destination")
		return false

	# Completion is measured against the arrival radius, not exact equality.
	if move.is_complete(Vector3(10, 0, 0), 2.0) != true:
		print("  [FAIL] Standing on the destination should complete a MOVE")
		return false
	if move.is_complete(Vector3(50, 0, 0), 2.0) != false:
		print("  [FAIL] A MOVE 40 m out should not be complete")
		return false

	# A freed target completes the order rather than erroring. The thing the
	# order was about is gone, which is the same outcome as succeeding at it -
	# and this is the case that used to leave a unit staring at a null.
	var doomed := Node3D.new()
	var attack := OrderScript.attack(doomed)
	if attack.is_complete(Vector3.ZERO, 2.0):
		print("  [FAIL] An ATTACK on a live target should not be complete")
		return false
	doomed.free()
	if not attack.is_complete(Vector3.ZERO, 2.0):
		print("  [FAIL] An ATTACK whose target was freed should be complete")
		return false

	# HOLD and IDLE never self-complete: they are states the player leaves, not
	# tasks that finish. A HOLD that completed would pop the queue behind it and
	# silently resume whatever was ordered before.
	if OrderScript.hold().is_complete(Vector3.ZERO, 2.0):
		print("  [FAIL] HOLD should never complete on its own")
		return false
	if OrderScript.idle().is_complete(Vector3.ZERO, 2.0):
		print("  [FAIL] IDLE should never complete on its own")
		return false
	print("  [PASS] Order vocabulary")
	return true


# DIAGNOSTIC for the 2026-08-08 playtest report: "units just sit in one spot
# and go in a circle" on a real map at world_scale=4.0, still reproducing
# after the turning-radius fix to slow_radius. Everything else in this file
# tests pure functions because headless can't simulate input - but THIS is
# not an input problem, so a real Battle scene with a real baked navmesh and
# a real physics-ticked unit is exactly what's needed to catch whatever pure-
# function coverage missed. Prints real position/velocity/order state on
# failure instead of just pass/fail, since the point is to get numbers back
# out of a session that can't watch the game running.
func test_real_unit_actually_converges_toward_a_move_order_on_a_real_map() -> bool:
	print("Running Test Suite: DIAGNOSTIC - A Real Unit On A Real Map Converges Toward A Move Order...")
	var UnitScript = preload("res://scripts/battle/units/unit.gd")
	var BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
	var MapCatalogScript = preload("res://scripts/map_catalog.gd")
	MapCatalogScript.reset_cache_for_tests()

	var battle = preload("res://scenes/Battle.tscn").instantiate()
	battle.map_id = "open_plains"
	root.add_child(battle)
	current_scene = battle
	var guard := 0
	while not battle.world_is_ready and guard < 3000:
		await tree.process_frame
		guard += 1
	if not battle.world_is_ready or not await _await_nav_map(battle.ground_nav_map):
		print("  [FAIL] Test setup: Battle never finished building open_plains.")
		battle.queue_free()
		return false

	var bp_manager = BlueprintManagerScript.new()
	root.add_child(bp_manager)
	var unit = UnitScript.new()
	root.add_child(unit)
	# A REAL bundled design from the match's own roster, not a hand-rolled
	# minimal blueprint - a first version of this test used {"hull_type":
	# "block_main_meridian_a", "modules": [], "locomotion": {...}} directly and got
	# move_speed=0.0 (Drivetrain.analyze() reported has_locomotion=false),
	# which turned out to be an artifact of that skeletal blueprint missing
	# whatever the assembly pipeline actually needs, not a world_scale bug -
	# every real design in the roster assembles through the same path the
	# Design Lab and production use, so this is what the player actually
	# drives.
	var blueprint: Dictionary = _find_harvester_blueprint(battle)
	if blueprint.is_empty():
		for design in battle.roster:
			if not battle.is_defence_design(design):
				blueprint = design
				break
	if blueprint.is_empty():
		print("  [FAIL] Test setup: no non-defence design found in the roster.")
		bp_manager.queue_free()
		battle.queue_free()
		return false
	var ok: bool = unit.setup(blueprint, 0, bp_manager, battle)
	if not ok:
		print("  [FAIL] Test setup: unit failed to assemble.")
		bp_manager.queue_free()
		unit.queue_free()
		battle.queue_free()
		return false
	if unit.move_speed <= 0.0:
		print("  [FAIL] A real roster design assembled with move_speed=", unit.move_speed,
			" (design '", blueprint.get("name", "?"), "') - the unit can never move regardless ",
			"of navigation, a Drivetrain/assembly problem, not a steering/navmesh one.")
		bp_manager.queue_free()
		unit.queue_free()
		battle.queue_free()
		return false

	# Start well inside the map, order a real cross-map move - long enough to
	# need real pathing, short of the flow-field gate (FIELD_MIN_UNITS=8, a
	# single unit never qualifies) or MIN_TRIP_DISTANCE mattering, since
	# there's no group here.
	var start := Vector3(-150.0, 0.0, -150.0)
	var destination := Vector3(150.0, 0.0, 150.0)
	unit.global_position = start
	# Generous settling window (was 1 frame) - suite_base.gd's own _await_
	# nav_map() comment documents NavigationServer3D applying map/region
	# changes as QUEUED commands flushed on its own sync pass, not
	# immediately on call; testing whether a freshly-created NavigationAgent3D
	# needs the same kind of real settling time before target_position
	# changes actually take effect in get_next_path_position().
	for i in range(10):
		await tree.physics_frame
	unit.current_order = OrderScript.move(destination)
	for i in range(10):
		await tree.physics_frame
		if is_instance_valid(unit.nav_agent):
			print("    warmup tick ", i, " pos=", unit.global_position, " next_corner=", unit.nav_agent.get_next_path_position(), " target=", unit.nav_agent.target_position, " finished=", unit.nav_agent.is_navigation_finished())

	var initial_distance := start.distance_to(destination)
	var closest_distance := initial_distance
	var positions: Array = [start]
	# Fine-grained per-tick steering state for the first 30 ticks (0.5s) -
	# 1-per-second sampling couldn't distinguish "stuck" from "chattering
	# direction every tick", and those need different fixes.
	var tick_log: Array = []
	# 8 seconds of real physics ticks - generous against move_speed ~15-20
	# m/s covering ~300m of open ground, but bounded so a genuinely stuck
	# unit fails the suite instead of hanging it.
	for i in range(480):
		await tree.physics_frame
		var flat_pos := Vector3(unit.global_position.x, 0.0, unit.global_position.z)
		var d := flat_pos.distance_to(destination)
		closest_distance = minf(closest_distance, d)
		if i % 60 == 0:
			positions.append(flat_pos)
		if i < 30 and is_instance_valid(unit.nav_agent):
			tick_log.append({
				"i": i, "pos": flat_pos, "vel": Vector2(unit.velocity.x, unit.velocity.z),
				"yaw": unit.rotation.y,
				"nav_finished": unit.nav_agent.is_navigation_finished(),
				"next_corner": unit.nav_agent.get_next_path_position(),
				"target_pos": unit.nav_agent.target_position,
			})
		if d < 5.0:
			break

	var final_pos := Vector3(unit.global_position.x, 0.0, unit.global_position.z)
	var final_distance := final_pos.distance_to(destination)
	var progress := initial_distance - closest_distance

	bp_manager.queue_free()
	unit.queue_free()
	battle.queue_free()

	# The bar is "made real, substantial progress," not "arrived exactly" -
	# this is a regression guard against total pathing failure (sitting
	# still or looping in place), not a precision check.
	#
	# Measured against what this unit's OWN speed can cover in the window,
	# not against a fraction of the trip. The bar used to be half the trip
	# in 8 seconds, which silently assumed a unit crossing a 420m map at
	# 15-20 m/s. At world_scale=4 the map is four times wider while
	# move_speed is unit-space and deliberately unchanged, so half a trip
	# became physically impossible and the test failed on a unit that was
	# in fact pathing perfectly. Distance covered per second is the thing
	# that actually distinguishes "moving" from "stuck", and it does not
	# move with world scale.
	var window_seconds := 480.0 / 60.0
	var coverable: float = minf(unit.move_speed * window_seconds, initial_distance)
	if progress < coverable * 0.25:
		print("  [FAIL] Unit made only ", progress, "m of progress toward a ", initial_distance,
			"m trip in ", window_seconds, "s (it could cover ~", coverable,
			"m at move_speed ", unit.move_speed, "); closest approach ", closest_distance, "m, final ", final_distance,
			"m). Sampled positions (every 1s): ", positions,
			". current_order=", unit.current_order, " move_speed=", unit.move_speed,
			" nav_agent valid=", is_instance_valid(unit.nav_agent))
		for entry in tick_log:
			print("    tick ", entry)
		return false

	print("  [PASS] Unit covered ", progress, "m of a ", initial_distance, "m trip (closest approach ", closest_distance, "m).")
	return true
