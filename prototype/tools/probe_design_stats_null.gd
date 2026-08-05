extends SceneTree
# Reproduces the Design Lab load failure: clear_hull() -> update_stats(null) ->
# _update_drivetrain_readout(dt) reading dt["has_locomotion"].

func _init():
	var DesignStats = load("res://scripts/design_stats.gd")
	var fails := 0

	for label in ["null hull", "empty Node3D"]:
		var hull = null if label == "null hull" else Node3D.new()
		var s: Dictionary = DesignStats.analyze(hull)
		var dt: Dictionary = s["drivetrain"]
		var wr: Dictionary = s["weapon_range"]

		# The exact key the crash was on.
		if not dt.has("has_locomotion"):
			print("  [FAIL] %s: drivetrain dict missing 'has_locomotion'" % label)
			fails += 1
		# Every key _update_drivetrain_readout() and _update_range_readout() touch.
		for k in ["weight", "capacity", "load_ratio", "is_overloaded",
				"overload_multiplier", "top_speed", "move_speed",
				"speed_lost_to_overload", "capacity_limited"]:
			if not dt.has(k):
				print("  [FAIL] %s: drivetrain dict missing '%s'" % [label, k])
				fails += 1
		for k in ["has_weapons", "shortest", "longest", "vision",
				"spotter_assisted", "spotter_required", "tier", "tier_label"]:
			if not wr.has(k):
				print("  [FAIL] %s: weapon_range dict missing '%s'" % [label, k])
				fails += 1
		# And the flat figures the roster cards read.
		for k in ["hull_hp", "module_hp_pool", "dps", "weight", "move_speed",
				"longest_range", "has_weapons"]:
			if not s.has(k):
				print("  [FAIL] %s: stats missing '%s'" % [label, k])
				fails += 1
		if hull != null:
			hull.free()
		print("  checked %s" % label)

	if fails == 0:
		print("[PASS] DesignStats.analyze() returns fully-keyed dicts for an absent hull.")
		quit(0)
	else:
		print("[FAIL] %d problem(s)." % fails)
		quit(1)
