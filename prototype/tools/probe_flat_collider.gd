extends SceneTree
# SKIRMISH_PERF_TROUBLESHOOTING.md §11.5 + §12.5.
#
# The §11.5 hypothesis: ground collision is the dominant per-unit cost in
# the late-game `units` bucket (16 ms/frame at 21 units, 17 ms/frame at
# 39 units). It was never actually measured - the previous run only
# changed ONE variable at a time and the ground collider was assumed
# not to be it. The fix at §12.3-D adds a `flat_ground_collider` map
# flag that swaps the heightmap collider for a flat box; this probe
# tests it headless, in isolation, on a real Battle with the real
# unit.gd, and reports the per-tick `unit.move_and_slide` delta.
#
# Method:
#   1. Boot the Battle scene, wait for world_is_ready (the match director
#      builds the heightmap collider during _setup_terrain).
#   2. Spawn N units of the same design.
#   3. Pass A: settle, then time 600 physics frames with the
#      heightmap collider in place. Read the BattleProfiler `unit.move_and_slide`
#      total / frame count.
#   4. Pass B: swap the ground `CollisionShape3D.shape` for a flat
#      `BoxShape3D` (the same swap match_director.gd does for the
#      `flat_ground_collider` flag), settle, time 600 frames. Read
#      the profiler again.
#   5. Pass C: re-swap back to the heightmap to confirm the round trip
#      is clean (the difference between A and C should be ~zero - if
#      it isn't, the swap is leaving residual state).
#
#   6. Report the three readings plus the A-B delta. The A-B delta
#      is the ground-heightmap contribution to `unit.move_and_slide`
#      per tick per N units. Divide by N for the per-unit coefficient.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_flat_collider.gd
#
# Skips itself with a clear message if the Battle scene can't build
# (e.g. running from a stale import cache); the user is expected to
# re-run after the godot --import that `run_tests.ps1` does first.

const UNIT_COUNT := 16
const SETTLE_FRAMES := 120
const MEASURE_FRAMES := 600


func _init() -> void:
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

	# Pick a real design from the roster. "Bulwark MBT" is the
	# mid-weight combat unit the other perf probes settled on; falling
	# back to the first roster entry is the safety net.
	var design: Dictionary = {}
	for d in battle.roster:
		if str(d.get("name", "")) == "Bulwark MBT":
			design = d
			break
	if design.is_empty() and battle.roster.size() > 0:
		design = battle.roster[0]

	# Find the ground. Battle.tscn has [node name="Ground" type="StaticBody3D"]
	# with a CollisionShape3D child carrying the heightmap the match
	# director built during _setup_terrain.
	var ground: StaticBody3D = battle.get_node_or_null("Ground") as StaticBody3D
	if ground == null:
		print("[FAIL] Battle has no Ground node")
		quit(1)
		return
	var ground_col: CollisionShape3D = ground.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if ground_col == null:
		print("[FAIL] Ground has no CollisionShape3D child")
		quit(1)
		return

	# Save the original heightmap so pass C can confirm the round trip.
	var original_shape: Shape3D = ground_col.shape
	if original_shape == null:
		print("[FAIL] Ground CollisionShape3D has no shape (match director didn't build it?)")
		quit(1)
		return

	# Spawn units on a ring outside the camera's frustum so the camera
	# itself doesn't show up as a variable. The exact positions don't
	# matter; the move_and_slide test fires the same way regardless of
	# where on the map the unit stands, as long as it's standing.
	var units: Array = []
	for i in range(UNIT_COUNT):
		var ang := TAU * float(i) / float(UNIT_COUNT)
		var u = battle.spawn_unit(design, battle.PLAYER_TEAM,
			Vector3(cos(ang) * 12.0, 0.0, sin(ang) * 12.0))
		if u != null:
			units.append(u)
		await process_frame

	for _i in range(SETTLE_FRAMES):
		await physics_frame

	print("=== FLAT GROUND COLLIDER A/B ===")
	print("  units = %d   settle = %d   measure = %d frames" % [
		units.size(), SETTLE_FRAMES, MEASURE_FRAMES])
	print("  ground original shape = %s" % original_shape.get_class())

	# Pass A: heightmap collider.
	var ms_a := await _measure_move_and_slide(MEASURE_FRAMES, units)
	var total_a := _profiler_total(battle, "unit.move_and_slide")
	var frames_a := _profiler_frames(battle, "unit.move_and_slide")
	var per_frame_a := (total_a / float(maxi(1, frames_a))) / 1000.0
	print("\n  A) heightmap collider")
	print("     wall      = %.2f ms/step" % ms_a)
	print("     unit.move_and_slide = %.2f ms/frame (%.1f us/frame)" % [
		per_frame_a, per_frame_a * 1000.0])
	if units.size() > 0:
		print("     per unit  = %.3f ms/unit/frame" % (per_frame_a / float(units.size())))

	# Pass B: swap to a flat box. This is the same swap the
	# match_director.gd's `flat_ground_collider` flag performs; doing
	# it inline means the only thing changing is the ground shape.
	var half: float = 80.0
	if battle.current_map != null and "map_half_extents" in battle.current_map:
		half = float(battle.current_map["map_half_extents"])
	var flat_box := BoxShape3D.new()
	flat_box.size = Vector3(half * 2.0, 1.0, half * 2.0)
	ground_col.shape = flat_box
	ground_col.scale = Vector3.ONE
	ground_col.position = Vector3(0.0, -0.5, 0.0)

	# A frame for the swap to settle, then a settle window.
	await process_frame
	for _i in range(SETTLE_FRAMES):
		await physics_frame

	var ms_b := await _measure_move_and_slide(MEASURE_FRAMES, units)
	var total_b := _profiler_total(battle, "unit.move_and_slide")
	var frames_b := _profiler_frames(battle, "unit.move_and_slide")
	var per_frame_b := (total_b / float(maxi(1, frames_b))) / 1000.0
	print("\n  B) flat box collider")
	print("     wall      = %.2f ms/step" % ms_b)
	print("     unit.move_and_slide = %.2f ms/frame (%.1f us/frame)" % [
		per_frame_b, per_frame_b * 1000.0])
	if units.size() > 0:
		print("     per unit  = %.3f ms/unit/frame" % (per_frame_b / float(units.size())))

	# Pass C: restore heightmap, confirm round trip is clean.
	ground_col.shape = original_shape
	ground_col.scale = battle.current_map.get("ground_collider_scale", Vector3.ONE) if battle.current_map != null and battle.current_map.has("ground_collider_scale") else Vector3.ONE
	ground_col.position = Vector3.ZERO
	await process_frame
	for _i in range(SETTLE_FRAMES):
		await physics_frame

	var ms_c := await _measure_move_and_slide(MEASURE_FRAMES, units)
	var total_c := _profiler_total(battle, "unit.move_and_slide")
	var frames_c := _profiler_frames(battle, "unit.move_and_slide")
	var per_frame_c := (total_c / float(maxi(1, frames_c))) / 1000.0
	print("\n  C) heightmap restored (round-trip check)")
	print("     wall      = %.2f ms/step" % ms_c)
	print("     unit.move_and_slide = %.2f ms/frame" % per_frame_c)

	# Diffs and verdict.
	var delta_ab := per_frame_a - per_frame_b
	var delta_ac := per_frame_a - per_frame_c
	var delta_pct: float = (delta_ab / maxf(0.001, per_frame_a)) * 100.0
	print("\n=== DIFFS ===")
	print("  A - B (heightmap - flat) = %.3f ms/frame (%+.1f%% of A)" % [
		delta_ab, delta_pct])
	print("  A - C (round-trip)       = %.3f ms/frame" % delta_ac)
	if units.size() > 0:
		print("  per unit contribution of the heightmap = %.3f ms/unit/frame" % (
			delta_ab / float(units.size())))

	# Verdict text. The §11.5 hypothesis was "ground collider is the
	# cost" - if A >> B, the hypothesis is confirmed and the per-tile
	# broadphase work is the right next step. If A ~ B, the cost is
	# elsewhere (likely the body-vs-body sweep, or the broadphase
	# itself dominating over the narrow phase).
	if delta_pct > 30.0:
		print("\n  VERDICT: heightmap IS a large share of the per-tick collision cost.")
		print("           The per-tile broadphase (§11.5 next step) is the right fix.")
	elif delta_pct > 5.0:
		print("\n  VERDICT: heightmap contributes measurably but is not dominant.")
		print("           Per-tile broadphase would help; look at body-vs-body sweep too.")
	else:
		print("\n  VERDICT: heightmap is NOT the cost. The §11.5 hypothesis is wrong;")
		print("           the per-unit collision cost is body-vs-body or body-vs-structure.")

	battle.queue_free()
	await process_frame
	quit(0)


# Time the wall-clock per physics step over `frames` physics ticks.
func _measure_move_and_slide(frames: int, _units: Array) -> float:
	var t0 := Time.get_ticks_usec()
	for _i in range(frames):
		await physics_frame
	return (float(Time.get_ticks_usec() - t0) / float(frames)) / 1000.0


# Read BattleProfiler.sections() for the named section and return the
# total time in microseconds. BattleProfiler is a singleton; the
# `battle` argument is a node ref kept for symmetry with other helpers
# even though the profiler is global.
func _profiler_total(_battle: Node, section_name: String) -> float:
	for s in BattleProfiler.sections():
		if s.get("section", "") == section_name:
			return float(s.get("total_ms", 0.0)) * 1000.0
	return 0.0


func _profiler_frames(_battle: Node, section_name: String) -> int:
	for s in BattleProfiler.sections():
		if s.get("section", "") == section_name:
			return int(s.get("frames", 0))
	return 0
