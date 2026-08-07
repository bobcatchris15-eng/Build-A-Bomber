extends SceneTree
# What actually stalls when something dies.
#
# Two different reports in one symptom ("a hitch when a building / unit is
# destroyed") and almost certainly two different causes, so they are measured
# separately rather than fixed together on a hunch:
#
#   BUILDING - _on_structure_died() marks the navmesh dirty, and the rebake is a
#     synchronous Recast pass over the whole map. It is already debounced to
#     end-of-frame so a blast killing three buildings costs one bake, but one
#     bake is still one bake.
#
#   UNIT - no listener on `died` at all; it is queue_free() plus whatever the
#     weapons still aiming at it do when their target vanishes. auto_weapon.gd
#     re-scans the tree-wide `damageable` group to re-acquire, so several weapons
#     losing one target in the same frame is several full scans.
#
# Reports the WORST single frame, not the mean. A hitch is by definition a
# one-frame outlier and a mean over 600 frames hides it completely.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_death_hitch.gd

const SETTLE := 90
const WATCH := 90


func _init():
	var packed = load("res://scenes/Battle.tscn")
	if packed == null:
		print("[FAIL] Battle.tscn did not load")
		quit(1)
		return
	var battle = packed.instantiate()
	root.add_child(battle)
	for _i in range(10):
		await process_frame

	var idle := await _worst_frame(WATCH)
	print("  idle worst frame:            %7.2f ms" % idle)

	# --- Kill a unit ---------------------------------------------------------
	var unit_spike := await _kill_and_watch(battle, _first_unit(battle))
	print("  worst frame killing a UNIT:  %7.2f ms  (%+.2f over idle)"
		% [unit_spike, unit_spike - idle])

	# --- Kill a building -----------------------------------------------------
	# A power plant, not the HQ: killing an HQ ends the match, and a director that
	# has stopped ticking measures nothing.
	var building_spike := await _kill_and_watch(battle, _expendable_structure(battle))
	print("  worst frame killing a BLDG:  %7.2f ms  (%+.2f over idle)"
		% [building_spike, building_spike - idle])

	print("")
	print("  Building deaths defer their navmesh rebake (NAV_LAZY_REBAKE_DELAY),")
	print("  because a dead building only FREES ground. Before that, this measured")
	print("  4139 ms on the frame a building died, against a ~5 ms idle worst case.")

	battle.queue_free()
	await process_frame
	quit(0)


func _first_unit(battle):
	for u in battle.get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and not u.is_dead:
			return u
	return null


func _expendable_structure(battle):
	for s in battle.get_team_structures(0):
		if is_instance_valid(s) and not s.is_dead and s.kind != "hq":
			return s
	return null


func _kill_and_watch(battle, victim) -> float:
	if victim == null:
		print("  (nothing to kill)")
		return 0.0
	for _i in range(SETTLE):
		await physics_frame
	# Killed outright through the real damage path, so every listener that a real
	# death fires also fires here.
	victim.take_damage(victim.max_hp * 10.0, "explosive", null)
	return await _worst_frame(WATCH)


# The worst single frame over `frames`, in milliseconds of physics + process.
func _worst_frame(frames: int) -> float:
	var worst := 0.0
	for _i in range(frames):
		await physics_frame
		var ms: float = 1000.0 * (
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
			+ Performance.get_monitor(Performance.TIME_PROCESS))
		worst = maxf(worst, ms)
	return worst
