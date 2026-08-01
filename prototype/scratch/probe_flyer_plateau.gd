extends SceneTree
# Scratch: Chris reported that a flying unit colliding with a plateau slope
# dropped the whole game to ~4fps, permanently - a STATE change, not a spike.
#
# Hypothesis, from probe_error_logging_cost.gd: an engine error costs ~8ms to
# emit, so ~30 errors per frame is exactly 4fps. A flyer wedged against
# geometry that re-collides every physics tick would do that.
#
# Mechanism suspected from battle_unit.gd:879 - `target_altitude = 4.0` is an
# ABSOLUTE world Y, not height-above-terrain, while a flyer's collision_mask
# (1 | 8) still includes ground/obstacles. On a plateau whose top is at Y~3,
# the unit tries to hold Y=4 while move_and_slide() grinds it against
# whatever sits on that plateau.
#
# Measures frame time and errors-per-frame for a flyer flown deliberately
# into a plateau, against a control flyer over flat ground in the same run.
#
# Must run WITHOUT --headless (real physics + real error emission).
# Usage: ./godot.exe --script scratch/probe_flyer_plateau.gd --path .

const SAMPLE_FRAMES := 120

var _skirmish: Node = null

func _init():
	# lake_crossing (the default) is flat - its highest point is y=0.34, so
	# there is no plateau to collide with and the first run of this probe
	# measured nothing. twin_summits/highland_chokepoint/scattered_peaks are
	# the three maps with a real heightmap.
	_skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	# Set map_id on the instance BEFORE add_child (i.e. before _ready reads
	# it). Going through MatchConfig did not work: _ready only consults it
	# when map_id is still empty/default, and by then it is too late to set
	# from here anyway.
	_skirmish.map_id = "twin_summits"
	root.add_child(_skirmish)
	current_scene = _skirmish
	for i in range(30): await process_frame

	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for i in range(10): await process_frame

	var flyer = _find_flyer()
	if flyer == null:
		print("NO FLYING UNIT could be spawned from the roster - cannot reproduce.")
		print("Rosters present: player %d" % _skirmish.roster.size())
		for e in _skirmish.roster:
			print("   %s  traits=%s" % [e.blueprint.get("name", "?"), str(e.get("traits", "?"))])
		quit(1)
		return

	print("flyer: %s  is_flying=%s  collision_mask=%d  target_altitude=%s"
		% [flyer.name, flyer.is_flying, flyer.collision_mask, str(flyer.target_altitude)])

	# Control: level flight over open ground.
	await _measure("control (open flat ground)", flyer, Vector3(0, 0, 0), Vector3(30, 0, 0))

	# The repro: fly into the highest terrain on the map.
	var peak = _highest_point()
	print("highest terrain sample: %s (y=%.2f)" % [str(peak), peak.y])
	await _measure("flying INTO plateau", flyer, peak + Vector3(-25, 0, 0), peak)

	quit(0)

func _measure(label: String, flyer: Node, from: Vector3, to: Vector3) -> void:
	flyer.global_position = Vector3(from.x, 4.0, from.z)
	if flyer.has_method("order_move"):
		flyer.order_move(to)
	elif "move_target" in flyer:
		flyer.move_target = to
	for i in range(40): await process_frame

	var err_before := _error_count()
	# Wall-clock frame deltas, the same method scratch/perf_matrix.gd uses -
	# the first version of this probe read Performance.TIME_PROCESS and got
	# implausible 600ms figures while physics read 3ms, which is not a real
	# frame time. Measure what the player actually experiences.
	var frames := []
	var last := Time.get_ticks_usec()
	for i in range(SAMPLE_FRAMES):
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
	var err_after := _error_count()

	frames.sort()
	var median: float = frames[frames.size() / 2]
	print("  %-26s frame %7.2f ms (%6.1f fps) | physics %6.2f ms | errors %5d (%.1f/frame) | y=%.2f terrain_y=%.2f"
		% [label, median, 1000.0 / max(median, 0.001),
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			err_after - err_before, float(err_after - err_before) / SAMPLE_FRAMES,
			flyer.global_position.y,
			preload("res://scripts/terrain_builder.gd").terrain_height_at(_skirmish.current_map, flyer.global_position)])

# Godot exposes no error counter, so count log lines instead - file logging
# is enabled in project.godot, which makes the log the only reliable
# per-frame error tally available from inside the running game.
func _error_count() -> int:
	var f = FileAccess.open(ProjectSettings.get_setting("debug/file_logging/log_path", "user://godot_master.log"), FileAccess.READ)
	if not f:
		return 0
	var n := 0
	while not f.eof_reached():
		if f.get_line().find("ERROR") >= 0:
			n += 1
	f.close()
	return n

func _find_flyer() -> Node:
	for entry in _skirmish.roster:
		var u = _skirmish.spawn_unit(entry.blueprint, 0, Vector3(0, 0, 0))
		if u and "is_flying" in u and u.is_flying:
			print("  (flyer found in roster: %s)" % entry.blueprint.get("name", "?"))
			return u
		if u:
			u.queue_free()
	return null

func _highest_point() -> Vector3:
	var TerrainBuilder = preload("res://scripts/terrain_builder.gd")
	var map = _skirmish.current_map
	var half: float = map.get("map_half_extents", 80.0)
	var best := Vector3.ZERO
	var best_y := -1e9
	for i in range(80):
		for j in range(80):
			var x = -half + (half * 2.0) * i / 80.0
			var z = -half + (half * 2.0) * j / 80.0
			var y = TerrainBuilder.terrain_height_at(map, Vector3(x, 0, z))
			if y > best_y:
				best_y = y
				best = Vector3(x, y, z)
	return best
