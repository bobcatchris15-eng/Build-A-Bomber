extends SceneTree
# Scratch: isolates test_a4_world_hp_bar_and_selection_ring_real_wiring's unit
# half. That suite started failing in the same run as the drivetrain work, and
# _recalculate_move_speed() runs six lines before _create_hp_bar() in setup(),
# so "did the drivetrain change abort setup early?" has to be answered rather
# than assumed. Runs the check several times because the suite needs a real
# match to boot, which is the same shape as the project's known target_dummies
# flake.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_hp_bar.gd --path .

func _init():
	var passes := 0
	var runs := 4
	for attempt in range(runs):
		var skirmish = load("res://scenes/Skirmish.tscn").instantiate()
		root.add_child(skirmish)
		for _i in range(90):
			await process_frame

		var units = skirmish.get_team_units(skirmish.PLAYER_TEAM)
		if units.is_empty():
			print("attempt %d: NO PLAYER UNITS (match did not boot far enough)" % attempt)
			skirmish.queue_free()
			await process_frame
			continue
		var u = units[0]
		var bar_valid := is_instance_valid(u.hp_bar)
		var shader_ok := bar_valid and (u.hp_bar.material_override as ShaderMaterial) != null
		# If the drivetrain change had aborted setup(), move_speed would still
		# be at its declared default and the new fields would be untouched -
		# that is the discriminator between "setup died" and "flaky boot".
		print("attempt %d: units=%d  hp_bar=%s  shader=%s  move_speed=%.2f  weight=%.1f  capacity=%.1f  top=%.2f" % [
			attempt, units.size(), bar_valid, shader_ok,
			u.move_speed, u.total_weight, u.weight_capacity, u.top_speed])
		if bar_valid and shader_ok:
			passes += 1
		skirmish.queue_free()
		await process_frame

	print("RESULT %d/%d attempts had a shader-backed hp_bar" % [passes, runs])
	quit(0 if passes == runs else 1)
