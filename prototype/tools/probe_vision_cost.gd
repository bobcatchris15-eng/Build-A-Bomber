extends SceneTree
# VISION SERVICE COST.
#
# The vision service runs on a 3.3Hz Timer (VisionTick child of the director),
# not _physics_process. Each tick fires O(viewers × targets) raycasts per team
# and may rebuild the shroud mesh if visibility changed. Invisible in averages
# (amortized over 300ms) but spikes are visible.
#
# This probe stops the VisionTick timer to disable the scan and measures the
# wall-clock delta.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_vision_cost.gd

const UNIT_COUNT := 16
const SETTLE_FRAMES := 120
const MEASURE_STEPS := 300  # physics steps per pass (5s at 60Hz)


func _init():
	await process_frame

	var battle = preload("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	var guard := 0
	while not battle.world_is_ready and guard < 3000:
		await process_frame
		guard += 1
	if not battle.world_is_ready:
		print("[FAIL] Battle never built its world")
		quit(1)
		return

	var design: Dictionary = {}
	for d in battle.roster:
		if str(d.get("name", "")) == "Bulwark MBT":
			design = d
			break
	if design.is_empty() and battle.roster.size() > 0:
		design = battle.roster[0]

	# Spawn units on both teams so vision scan has real work
	var red: Array = []
	var blue: Array = []
	for i in range(UNIT_COUNT / 2):
		var r: Node3D = battle.spawn_unit(design, battle.PLAYER_TEAM,
			Vector3(cos(float(i) * 0.8) * 15.0, 0.0, -10.0 + float(i)))
		var b: Node3D = battle.spawn_unit(design, battle.ENEMY_TEAM,
			Vector3(cos(float(i) * 0.8) * 15.0, 0.0, 10.0 - float(i)))
		if r != null: red.append(r)
		if b != null: blue.append(b)
		await process_frame

	for _i in range(SETTLE_FRAMES):
		await physics_frame

	# Locate the VisionTick timer (child of the director)
	var vision_timer: Node = battle.get_node_or_null("VisionTick")
	var timer_was_running := false
	if vision_timer != null and vision_timer is Timer:
		timer_was_running = (vision_timer as Timer).is_processing()
		print("=== VISION COST (%d units, both teams, 3.3Hz scan) ===" % UNIT_COUNT)
		print("  VisionTick found: was_processing=%s" % str(timer_was_running))
	else:
		print("=== VISION COST (%d units, both teams) ===" % UNIT_COUNT)
		print("  [INFO] VisionTick timer not found — fog may be disabled in this scene")

	# Pass A — vision ON (normal)
	var ms_normal := await _time_physics_steps(MEASURE_STEPS)
	var fps_normal := 1000.0 / maxf(0.001, ms_normal)
	print("  vision ON   : %.2f ms/step  (%.0f fps)" % [ms_normal, fps_normal])

	# Pass B — vision OFF
	if vision_timer != null and vision_timer is Timer:
		(vision_timer as Timer).stop()
	for _i in range(SETTLE_FRAMES):
		await physics_frame
	var ms_no_vision := await _time_physics_steps(MEASURE_STEPS)
	var fps_no_vision := 1000.0 / maxf(0.001, ms_no_vision)
	var delta_ms := ms_normal - ms_no_vision
	var delta_pct := (delta_ms / maxf(0.001, ms_normal)) * 100.0
	print("  vision OFF  : %.2f ms/step  (%.0f fps)" % [ms_no_vision, fps_no_vision])
	print("  delta       : %+.2f ms/step  (%+.1f%%)" % [delta_ms, delta_pct])
	if delta_pct > 5.0:
		print("  NOTE: vision scan costs >5%% of physics step budget")

	# Restore timer
	if vision_timer != null and vision_timer is Timer and timer_was_running:
		(vision_timer as Timer).start()

	battle.queue_free()
	await process_frame
	quit(0)


func _time_physics_steps(steps: int) -> float:
	var start_us := Time.get_ticks_usec()
	for _i in range(steps):
		await physics_frame
	return (float(Time.get_ticks_usec() - start_us) / float(steps)) / 1000.0
