extends SceneTree
# Dump the full CollisionShape3D tree of a spawned unit.
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_tree_shapes.gd

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

	var unit = battle.spawn_unit(design, battle.PLAYER_TEAM, Vector3.ZERO)
	if unit == null:
		print("[FAIL] spawn_unit returned null")
		quit(1)
		return

	await process_frame
	await process_frame

	print("=== FULL UNIT TREE (CollisionShape3D nodes only) ===")
	_print_shapes(unit, unit, 0)

	print("")
	print("=== SHAPE SUMMARY ===")
	var counts: Dictionary = {"total": 0, "on_body": 0, "under_hull_node": 0, "under_hull_surface": 0, "under_weapons": 0, "other": 0}
	_count_by_location(unit, unit, counts)
	for k in counts:
		print("  %-20s: %d" % [k, counts[k]])

	battle.queue_free()
	await process_frame
	quit(0)


func _print_shapes(node: Node, body: Node3D, indent: int) -> void:
	var prefix := "  ".repeat(indent)
	if node is CollisionShape3D:
		var parent_name: String = node.get_parent().name if node.get_parent() else "(null)"
		var shape_type: String = type_string(typeof(node.shape)) if node.shape else "null"
		print("%sCollisionShape3D [%s] shape=%s" % [prefix, parent_name, shape_type])
		return
	if node is PhysicsBody3D:
		print("%sPhysicsBody3D [%s]" % [prefix, node.name])
	if node is Area3D:
		print("%sArea3D [%s]" % [prefix, node.name])
	for c in node.get_children():
		_print_shapes(c, body, indent + 1)


func _count_by_location(node: Node, body: Node3D, out: Dictionary) -> void:
	if node is CollisionShape3D:
		out.total += 1
		var parent := node.get_parent()
		if parent == body:
			out.on_body += 1
		elif parent != null and parent.name.begins_with("HullSurface"):
			out.under_hull_surface += 1
		elif parent != null and (parent.name.begins_with("Hull") or parent.name.begins_with("hull")):
			out.under_hull_node += 1
		elif parent != null and (parent.name.begins_with("Weapon") or parent.name.begins_with("weapon") or parent.name.begins_with("Module")):
			out.under_weapons += 1
		else:
			out.other += 1
	for c in node.get_children():
		_count_by_location(c, body, out)
