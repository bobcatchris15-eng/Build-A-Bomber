extends SceneTree
# Scratch: does a unit actually REACH an ordered point, or orbit it?
#
# Drives a real battle_unit through real physics ticks with no nav agent
# (direct steering - the same code path a nav-guided unit uses for its final
# approach) and reports closest approach vs. final distance. An orbiting unit
# gets close once and then stays at a roughly constant radius forever, so
# comparing "closest" against "final" separates arriving from circling far
# more reliably than a single end-state distance does.
#
# Sweeps speed because the bug is speed-dependent: turning radius is
# v / (rotate_speed * heading_error), so it only exceeds the arrival radius
# on fast units. A test that only exercises a slow unit sees nothing wrong.

const BattleUnitScript = preload("res://scripts/battle_unit.gd")
# Short-range order: this is where turning radius can exceed the distance to
# the target, which is the geometry that produces an orbit.
const SHORT_DIST := 5.0

func _init():
	print("%-8s %-10s %-10s %-10s %s" % ["speed", "closest", "final", "ticks", "verdict"])
	for speed in [3.0, 6.0, 10.0, 14.0, 18.0]:
		await _run(speed)
	quit(0)

func _run(speed: float) -> void:
	var unit = CharacterBody3D.new()
	unit.set_script(BattleUnitScript)
	root.add_child(unit)
	await process_frame

	unit.move_speed = speed
	unit.rotate_speed = 4.0
	unit.terrain_speed_multiplier = 1.0
	unit.global_position = Vector3.ZERO
	# Start facing +X while the destination is +Z: a 90 degree heading error,
	# which is where the old full-throttle-while-turning behaviour swept
	# widest and was most likely to miss.
	unit.look_at(Vector3(10, 0, 0), Vector3.UP)

	var dest := Vector3(0, 0, SHORT_DIST)
	unit.order_move(dest)

	var closest := INF
	var arrived_tick := -1
	var ticks := 900
	for i in range(ticks):
		unit._physics_process(1.0 / 60.0)
		# Integrate manually instead of calling move_and_slide().
		#
		# move_and_slide() only does real work inside an engine physics step;
		# driven from a plain loop it advanced the body by a fraction of the
		# commanded velocity, and by a DIFFERENT fraction between runs - which
		# made a working steering fix look speed-dependently broken. The thing
		# under test here is the steering output (heading and throttle), so
		# integrating it directly is both sufficient and deterministic.
		unit.global_position += Vector3(unit.velocity.x, 0.0, unit.velocity.z) * (1.0 / 60.0)
		var d := Vector2(unit.global_position.x - dest.x, unit.global_position.z - dest.z).length()
		closest = minf(closest, d)
		if arrived_tick < 0 and unit.order == BattleUnitScript.OrderType.IDLE:
			arrived_tick = i
		if false:
			print("    t=%-4d pos=(%6.2f,%6.2f) order=%s vel=(%5.2f,%5.2f) speed_var=%.2f" % [
				i, unit.global_position.x, unit.global_position.z,
				str(unit.order), unit.velocity.x, unit.velocity.z, unit.move_speed])

	var final_d := Vector2(unit.global_position.x - dest.x, unit.global_position.z - dest.z).length()
	var verdict := "ARRIVED @ tick %d" % arrived_tick if arrived_tick >= 0 else "NEVER ARRIVED (circling?)"
	print("%-8.1f %-10.2f %-10.2f %-10d %s" % [speed, closest, final_d, ticks, verdict])

	unit.queue_free()
	await process_frame
