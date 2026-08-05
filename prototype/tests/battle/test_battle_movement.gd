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
