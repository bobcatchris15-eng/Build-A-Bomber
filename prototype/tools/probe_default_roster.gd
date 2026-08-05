extends SceneTree
# Verifies every blueprint in the default roster loads, reconstructs, and produces
# a vehicle whose parts are actually attached to the hull.
#
# Written because the generated roster was broken in a way nothing caught: the
# blueprints parsed, listed and loaded fine, and the units spawned - they just
# looked wrong, with treads detached and weapons floating above the hull. No suite
# asserts anything about where a reconstructed part ends up.

const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const DesignStatsScript = preload("res://scripts/design_stats.gd")

func _init():
	var bm = BlueprintManagerScript.new()
	root.add_child(bm)

	var entries: Array = bm.list_blueprints(false)
	var roster: Array = []
	for e in entries:
		if str(e.get("path", "")).begins_with("res://assets/blueprints/default_roster/"):
			roster.append(e)

	if roster.is_empty():
		print("[FAIL] default roster is EMPTY - nothing in assets/blueprints/default_roster/")
		quit(1)
		return

	print("checking %d default blueprints\n" % roster.size())
	var failed := 0

	for e in roster:
		var path := str(e["path"])
		var data: Dictionary = bm.load_blueprint(path)
		var name := str(data.get("name", "?"))
		if data.is_empty():
			print("  [FAIL] %s did not load" % path)
			failed += 1
			continue

		var holder := Node3D.new()
		root.add_child(holder)
		var hull: Node3D = bm.reconstruct_vehicle(data, holder, false)
		if hull == null:
			print("  [FAIL] %s (%s) did not reconstruct" % [name, path.get_file()])
			failed += 1
			holder.free()
			continue

		# Every module must have ended up as a child of the hull, not orphaned.
		var module_children := 0
		for c in hull.get_children():
			if c.has_meta("module_data"):
				module_children += 1
		var expected: int = (data.get("modules", []) as Array).size()

		# And the design has to produce real stats - a unit with no drivetrain or
		# zero HP would be unfieldable regardless of how it looks.
		var stats: Dictionary = DesignStatsScript.analyze(hull)
		var problems: Array = []
		if module_children != expected:
			problems.append("reconstructed %d of %d modules" % [module_children, expected])
		if float(stats.get("hull_hp", 0.0)) <= 0.0:
			problems.append("hull_hp is %.1f" % stats.get("hull_hp", 0.0))
		var dt: Dictionary = stats.get("drivetrain", {})
		if not bool(dt.get("has_locomotion", false)):
			problems.append("no locomotion detected by Drivetrain.analyze")
		elif float(dt.get("move_speed", 0.0)) <= 0.0:
			problems.append("move_speed is %.2f" % dt.get("move_speed", 0.0))

		if problems.is_empty():
			print("  [ok]   %-24s %2d modules  hp=%6.1f  speed=%5.2f  %s"
				% [name, module_children, stats["hull_hp"], dt.get("move_speed", 0.0),
				   data.get("locomotion", {}).get("type_id", "")])
		else:
			print("  [FAIL] %s: %s" % [name, ", ".join(problems)])
			failed += 1

		holder.free()

	print("")
	if failed == 0:
		print("[PASS] every default blueprint loads, reconstructs and is fieldable.")
		quit(0)
	else:
		print("[FAIL] %d of %d default blueprints have problems." % [failed, roster.size()])
		quit(1)
