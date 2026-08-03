extends SceneTree
# Scratch: five movement suites started failing with "Unit given order_move()
# across the map barely moved" after the ride-height / collider / capacity
# changes. A real Skirmish unit measures 55% load at move_speed 12.0, so it is
# NOT the capacity retune - this narrows it to the vertical geometry changes by
# reporting, per tick, where the unit is and what its colliders look like.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_move_regress.gd --path .

func _init():
	var skirmish = load("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	for _i in range(90):
		await process_frame

	var units = skirmish.get_team_units(skirmish.PLAYER_TEAM)
	if units.is_empty():
		print("FAIL: no player units")
		quit(1)
		return
	var u = units[0]

	print("move_speed      = %.2f" % u.move_speed)
	print("load_ratio      = %.2f  (overloaded=%s)" % [u.load_ratio, u.is_overloaded])
	print("terrain mult    = %.2f" % u.terrain_speed_multiplier)
	print("is_flying       = %s   is_naval = %s" % [u.is_flying, u.is_naval])
	print("hull lift       = %.3f" % u.hull_node.position.y)
	print("parent has terrain_height_at = %s" % u.get_parent().has_method("terrain_height_at"))
	for c in u.get_children():
		if c is CollisionShape3D:
			var lo := INF
			if c.shape is BoxShape3D:
				lo = c.position.y - (c.shape as BoxShape3D).size.y * 0.5 * c.scale.y
			print("collider %-28s pos.y %6.3f  bottom %6.3f  shape %s" % [c.name, c.position.y, lo, c.shape])
	print("nav_agent       = %s" % u.nav_agent)
	print("")

	var start: Vector3 = u.global_position
	print("start position  = %s" % start)
	u.order_move(Vector3(40, 0.5, -180))
	for i in range(660):
		await process_frame
		if i % 120 == 0 or i == 659:
			var moved: float = u.global_position.distance_to(start)
			print("  tick %4d  pos %-34s moved %7.2f  vel %-28s on_floor=%s  order=%d" % [
				i, str(u.global_position.round()), moved, str(u.velocity.round()),
				u.is_on_floor(), u.order])
	print("")
	print("TOTAL MOVED %.2f" % u.global_position.distance_to(start))
	print("(the failing suites want this well past ~40)")
	quit(0)
