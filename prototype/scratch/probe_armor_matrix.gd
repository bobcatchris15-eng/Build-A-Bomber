extends SceneTree
const DR = preload("res://scripts/damage_resolver.gd")
const MC = preload("res://scripts/module_catalog.gd")

func _init():
	var mats = ["hardened_steel","reactive_armor","ablative_ceramic","energy_shielding"]
	var classes = ["kinetic","thermal","explosive","energy"]
	# Sample per-shot values spanning the real roster: a rapid-fire chip hit,
	# a mid cannon shot, and a heavy one.
	var shots = [12.0, 60.0, 200.0]
	for shot in shots:
		print("\n=== incoming per-shot %.0f (damage TAKEN, lower is better) ===" % shot)
		print("%-18s %8s %8s %8s %8s  | %8s" % ["material","kinetic","thermal","explos","energy","AVG"])
		var best_avg = 1e9
		var best_name = ""
		var dominates = []
		var results = {}
		for m in mats:
			var row = []
			var total = 0.0
			for c in classes:
				var t = DR.get_material_threshold(m, c, 1.0)
				var taken = DR.compute_hull_damage(shot, t.x, t.y)
				row.append(taken)
				total += taken
			results[m] = row
			var avg = total / 4.0
			print("%-18s %8.1f %8.1f %8.1f %8.1f  | %8.1f" % [m, row[0], row[1], row[2], row[3], avg])
			if avg < best_avg:
				best_avg = avg
				best_name = m
		# Dominance: is any material best-or-equal in EVERY class?
		for m in mats:
			var dom = true
			for i in range(4):
				for other in mats:
					if other == m: continue
					if results[other][i] < results[m][i] - 0.001:
						dom = false
			if dom:
				dominates.append(m)
		print("  best average: %s   STRICTLY DOMINANT: %s" % [best_name, str(dominates) if dominates.size() > 0 else "none"])

	print("\n=== bolt-on plate bias (threshold multiplier) ===")
	for plate in MC.ARMOR_MODULE_BIAS.keys():
		var parts = []
		for c in classes:
			parts.append("%s x%.2f" % [c, MC.get_armor_module_bias(plate, c)])
		print("  %-18s %s" % [plate, ", ".join(parts)])
	quit()
