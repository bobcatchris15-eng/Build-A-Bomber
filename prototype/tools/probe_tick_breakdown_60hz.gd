extends SceneTree
# Same as probe_unit_tick_breakdown.gd but skips the 30Hz force,
# giving a clean 60Hz baseline for comparison against Fix B.
const UNIT_COUNT := 16
const MEASURE_FRAMES := 300

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

	var first: Node3D = null
	for i in range(UNIT_COUNT):
		var ang := TAU * float(i) / float(UNIT_COUNT)
		var u = battle.spawn_unit(design, battle.PLAYER_TEAM,
			Vector3(cos(ang), 0.0, sin(ang)) * (20.0 + float(i)))
		if first == null:
			first = u
		await process_frame

	if first != null and is_instance_valid(first):
		var shapes := {"own": 0, "child_bodies": 0, "child_shapes": 0}
		_count_collision(first, first, shapes)
		print("=== COLLIDER SHAPE OF ONE UNIT ===")
		print("  shapes on the CharacterBody3D itself : %d" % shapes.own)
		print("  extra PhysicsBody children           : %d" % shapes.child_bodies)
		print("  shapes under those children          : %d" % shapes.child_shapes)
		print("")

	for _i in range(60):
		await physics_frame

	BattleProfiler.enabled = true
	BattleProfiler.reset()
	for _i in range(MEASURE_FRAMES):
		await physics_frame
	BattleProfiler.enabled = false

	print("=== unit.gd TICK BREAKDOWN (16 units, 300 frames, 60Hz) ===")
	print("%-24s %12s %12s %12s" % ["section", "mean ms", "worst ms", "total ms"])
	for row in BattleProfiler.sections():
		print("%-24s %12.3f %12.3f %12.1f"
			% [row.section, row.mean_ms, row.worst_ms, row.total_ms])

	var stats := BattleProfiler.frame_stats()
	if not stats.is_empty():
		print("")
		print("  frame  mean %.2f ms   p95 %.2f ms   worst %.2f ms"
			% [stats.mean, stats.p95, stats.worst])

	battle.queue_free()
	await process_frame
	quit(0)

func _count_collision(node: Node, owner_body: Node, out: Dictionary) -> void:
	for c in node.get_children():
		if c is CollisionShape3D:
			if node == owner_body:
				out.own += 1
			else:
				out.child_shapes += 1
		elif c is PhysicsBody3D:
			out.child_bodies += 1
		_count_collision(c, owner_body, out)
