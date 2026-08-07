extends SceneTree
# PERF DRIFT. Chris, 2026-08-07: "FPS drops steadily from the beginning of the
# match, and for most of the play time it was under 10 FPS."
#
# STEADY degradation from frame one is the useful word in that report. A fixed
# cost that is simply too high would be slow at t=0 and no worse at t=300; a
# steady slide means something ACCUMULATES. So this probe does not try to time
# the frame - headless has no renderer and the number would be a fiction. It
# samples the things that can GROW, once every 10 s of match time, and prints
# them as a table so the growth curve is visible rather than inferred.
#
# Whatever is climbing without bound at t=300 is the bug.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_perf_drift.gd

const RUN_SECONDS := 300.0
const SAMPLE_SECONDS := 10.0


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

	print("=== PERF DRIFT over %.0fs ===" % RUN_SECONDS)
	print("%6s %8s %8s %8s %8s %8s %8s %8s"
		% ["t", "nodes", "orphans", "units", "projs", "fx", "sigconn", "physproc"])

	var ticks := int(RUN_SECONDS * 60.0)
	var per_sample := int(SAMPLE_SECONDS * 60.0)
	for i in range(ticks):
		await physics_frame
		if i % per_sample != 0:
			continue
		_sample(battle, float(i) / 60.0)

	print("")
	print("Anything monotonically climbing above is a leak, not load.")
	battle.queue_free()
	await process_frame
	quit(0)


func _sample(battle, t: float) -> void:
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	var counts := {"units": 0, "projs": 0, "fx": 0, "phys": 0, "conns": 0}
	_tally(root, counts)

	print("%6.0f %8d %8d %8d %8d %8d %8d %8d"
		% [t, nodes, orphans, counts.units, counts.projs, counts.fx,
			counts.conns, counts.phys])


# One walk, several counters - a separate get_nodes_in_group() per category
# would be cheaper but only sees things that remembered to join a group, and
# the whole question here is what is NOT being cleaned up.
func _tally(node: Node, counts: Dictionary) -> void:
	var n := node.get_name()
	if node.is_in_group("units") or node.get("is_harvester") != null:
		counts.units += 1
	if n.contains("Projectile") or n.contains("Shell") or n.contains("Missile"):
		counts.projs += 1
	if n.contains("Puff") or n.contains("Impact") or n.contains("Explosion") \
			or n.contains("Muzzle") or n.contains("Tracer") or node is GPUParticles3D:
		counts.fx += 1
	if node.is_physics_processing() or node.is_processing():
		counts.phys += 1
	for sig in node.get_signal_list():
		counts.conns += node.get_signal_connection_list(sig.name).size()
	for c in node.get_children():
		_tally(c, counts)
