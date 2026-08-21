extends SceneTree

const OrderScript = preload("res://scripts/battle/orders/order.gd")

func _init():
	print("--- Testing Squad Movement without Orbiting / Circling ---")
	var packed = load("res://scenes/Battle.tscn")
	var battle = packed.instantiate()
	root.add_child(battle)

	for _i in range(15):
		await process_frame

	var units: Array = battle.get_team_units(0)
	print("Found %d initial player units" % units.size())

	# Place units in a line
	for i in range(units.size()):
		var u = units[i]
		var spawn_p := Vector3(-15.0 + i * 6.0, 0.0, 90.0)
		spawn_p.y = battle.terrain_height_at(spawn_p)
		u.global_position = spawn_p
		u.velocity = Vector3.ZERO

	# Issue move order to distant point
	var target_pos := Vector3(0.0, 0.0, -30.0)
	target_pos.y = battle.terrain_height_at(target_pos)
	for u in units:
		u.current_order = OrderScript.move(target_pos)
	print("Ordered all units to %s" % target_pos)

	# Simulate 240 physics ticks
	var circling_count := 0
	var prev_headings: Array = []
	for u in units:
		prev_headings.append([])

	for f in range(240):
		await physics_frame
		for i in range(units.size()):
			var u = units[i]
			if is_instance_valid(u):
				var h_list: Array = prev_headings[i]
				h_list.append(u.rotation.y)
				if h_list.size() > 40:
					h_list.pop_front()
					var total_yaw_diff := 0.0
					for j in range(h_list.size() - 1):
						total_yaw_diff += absf(wrapf(h_list[j+1] - h_list[j], -PI, PI))
					# 40 frames doing multiple full spins
					if total_yaw_diff > TAU * 2.0 and u.velocity.length() > 2.0:
						print("[FAIL] Unit %d circling detected at frame %d! (speed=%.1f, yaw_diff=%.2f)" % [i, f, u.velocity.length(), total_yaw_diff])
						circling_count += 1

	for i in range(units.size()):
		var u = units[i]
		if is_instance_valid(u):
			var d_to_dest = Vector2(u.global_position.x - target_pos.x, u.global_position.z - target_pos.z).length()
			print("Unit %d final pos: (%.1f, %.1f, %.1f), dist_to_dest: %.1f m, order_done=%s" % [
				i, u.global_position.x, u.global_position.y, u.global_position.z, d_to_dest, u.current_order == null
			])

	if circling_count == 0:
		print("[SUCCESS] Zero units circled or orbited! All units navigated smoothly.")

	battle.queue_free()
	quit(0)
