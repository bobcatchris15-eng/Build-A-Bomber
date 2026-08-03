extends SceneTree
# Scratch: reproduces test_d2_unit_buttons_grey_out_without_a_live_manufactory_
# of_that_tier in isolation, to separate a real regression from the shared-process
# flake class run_tests.gd's header documents. Runs the same steps, alone, five
# times - a real break fails 5/5, a timing flake does not.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_d2_gating.gd --path .
func _init():
	var pass_count := 0
	for i in range(5):
		var ok = await _once(i)
		if ok:
			pass_count += 1
	print("PASSED %d/5" % pass_count)
	quit(0 if pass_count == 5 else 1)

func _once(n: int) -> bool:
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	for i in range(4):
		await process_frame

	var light := []
	for entry in skirmish._tier_gated_buttons:
		if entry.tier == "light":
			light.append(entry)
	if light.is_empty():
		print("  run %d: SKIP (no light-tier button)" % n)
		skirmish.queue_free()
		await process_frame
		return true

	var before_ok := true
	for e in light:
		if e.button == null or not is_instance_valid(e.button):
			print("  run %d: FAIL button is null - _add_build_button stopped returning it" % n)
			skirmish.queue_free()
			await process_frame
			return false
		if e.button.disabled:
			before_ok = false
	if not before_ok:
		print("  run %d: FAIL disabled while the manufactory is still alive" % n)
		skirmish.queue_free()
		await process_frame
		return false

	var f = skirmish.get_team_factory(skirmish.PLAYER_TEAM, "light")
	if f == null:
		print("  run %d: FAIL no light manufactory found to kill" % n)
		skirmish.queue_free()
		await process_frame
		return false
	f.is_dead = true
	for i in range(4):
		await process_frame

	var after_ok := true
	for e in light:
		if not e.button.disabled:
			after_ok = false
	print("  run %d: %s (has_factory_of_tier=%s)" % [
		n, "ok" if after_ok else "FAIL not disabled after death",
		skirmish.has_factory_of_tier(skirmish.PLAYER_TEAM, "light")])

	skirmish.queue_free()
	await process_frame
	return after_ok
