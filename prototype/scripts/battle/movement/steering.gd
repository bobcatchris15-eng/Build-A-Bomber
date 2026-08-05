class_name Steering
extends RefCounted
# Pure movement math. No nodes, no scene tree, no state.
#
# WHY PURE. Headless Godot cannot simulate held mouse-button state (established
# empirically 2026-07-12 - `Input.parse_input_event` leaves
# `is_mouse_button_pressed` false), so end-to-end input tests are not available
# and the math has to be testable directly instead. Everything here takes values
# and returns values, so a suite can assert on arrival curves and turn rates
# without instantiating a unit at all.
#
# The old runtime's equivalent was `_steer_towards()`, a method on the 1,701-line
# unit that read and wrote a dozen fields and could only be exercised by building
# a whole vehicle.

# Below this, a unit is close enough that chasing the remaining distance just
# makes it jitter around the point.
const ARRIVE_EPSILON := 0.05


# Classic arrival: full speed until `slow_radius`, then a linear ramp down so the
# unit settles instead of overshooting and oscillating back.
#
# `slow_radius` should scale with speed - a unit doing 18 m/s covers 0.3 m per
# 60 Hz tick and needs to start braking much earlier than a slow one. A fixed
# radius is what made fast designs circle their destination.
static func arrival_speed(distance: float, max_speed: float, slow_radius: float) -> float:
	if distance <= ARRIVE_EPSILON:
		return 0.0
	if slow_radius <= 0.0 or distance >= slow_radius:
		return max_speed
	return max_speed * (distance / slow_radius)


# The horizontal velocity that carries `from` toward `to` at an arrival-damped
# speed. Y is dropped: ground units follow the terrain via their own snapping,
# and steering toward a point's height would drive them into hillsides.
static func seek(from: Vector3, to: Vector3, max_speed: float, slow_radius: float) -> Vector3:
	var offset := to - from
	offset.y = 0.0
	var distance := offset.length()
	if distance <= ARRIVE_EPSILON:
		return Vector3.ZERO
	return (offset / distance) * arrival_speed(distance, max_speed, slow_radius)


# Rotates `current_yaw` toward `target_yaw` by at most `max_step` radians, taking
# the short way around.
#
# Turning is rate-limited rather than instant because these are vehicles. It also
# prevents the visual snap the old runtime had when a resting basis and a
# tracking basis disagreed (the sponson bug, PROGRESS.md 2026-08-04).
static func turn_toward(current_yaw: float, target_yaw: float, max_step: float) -> float:
	var delta := wrapf(target_yaw - current_yaw, -PI, PI)
	if absf(delta) <= max_step:
		return wrapf(target_yaw, -PI, PI)
	return wrapf(current_yaw + signf(delta) * max_step, -PI, PI)


# The yaw that faces `direction`. Returns `fallback` for a degenerate direction
# so a stopped unit keeps its current facing instead of snapping to north.
static func yaw_for(direction: Vector3, fallback: float) -> float:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		return fallback
	# BOTH ARGUMENTS ARE NEGATED, and that is the whole content of this function.
	#
	# Rotating by yaw t about Y gives basis.z = (sin t, 0, cos t), and a Node3D's
	# forward is -basis.z = (-sin t, 0, -cos t). Setting that equal to the desired
	# direction d gives sin t = -d.x and cos t = -d.z, hence atan2(-x, -z).
	#
	# The unnegated atan2(x, z) is exactly 180 degrees out, and it fails silently:
	# the unit turns smoothly, drives smoothly, and goes the wrong way. Caught by
	# tools/probe_battle_phase0.gd, which measured a unit ending up 46.8 m from a
	# destination 25 m away.
	return atan2(-flat.x, -flat.z)


# Push away from crowding neighbours, weighted so the nearest shove hardest.
#
# WHY THIS AND NOT NavigationAgent3D's OWN AVOIDANCE. The built-in avoidance
# (RVO) treats every nearby agent as an obstacle to swerve around. In a formation
# that is exactly backwards: the neighbour a unit is deliberately lining up
# beside is the thing avoidance most wants to escape, so the formation is
# perpetually shoved apart by the system meant to keep it tidy. `avoidance_enabled`
# is off in unit_assembly.gd for this reason.
#
# Separation is weaker and dumber, which is what is wanted: it resolves genuine
# overlap without opinions about where anyone is going.
#
# Returns an unnormalised push. Scale it against move_speed at the call site so a
# fast unit is not shoved proportionally harder than a slow one.
static func separation(position: Vector3, neighbours: Array, radius: float) -> Vector3:
	if radius <= 0.0:
		return Vector3.ZERO
	var push := Vector3.ZERO
	for other in neighbours:
		var other_pos: Vector3 = other
		var offset := position - other_pos
		offset.y = 0.0
		var distance := offset.length()
		if distance >= radius:
			continue
		if distance < 0.001:
			# Exactly coincident. Any direction beats NaN, and a deterministic one
			# beats a random one - two stacked units would otherwise pick
			# opposing random directions every frame and vibrate.
			push += Vector3(0.01, 0.0, 0.0)
			continue
		# Linear falloff. Inverse-square is the textbook choice and it is wrong
		# here: it makes contact forces enormous, which turns a tight formation
		# into an explosion.
		push += (offset / distance) * (1.0 - distance / radius)
	return push


# How much a unit should be slowed for pointing the wrong way. A vehicle that has
# to turn 180 degrees should pivot roughly in place rather than carving a wide
# arc through whatever is behind it.
#
# Returns 1.0 when aligned, falling to 0 at `cutoff` radians off-heading.
static func heading_throttle(current_yaw: float, target_yaw: float, cutoff: float = PI * 0.5) -> float:
	if cutoff <= 0.0:
		return 1.0
	var off := absf(wrapf(target_yaw - current_yaw, -PI, PI))
	if off >= cutoff:
		return 0.0
	return 1.0 - (off / cutoff)
