extends SceneTree
# Scratch: the retuned range system as a table - tiers, vision, spotter
# dependency, munition flight times, and what barrel_length does.
#
# Companion to probe_range.gd, which measured the BEFORE state (band 7-50,
# 26 of 45 weapons out-ranging their own hull's vision, so every point of
# reach past ~20 unusable).
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_range_after.gd --path .

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const ModuleDataScript = preload("res://scripts/module_data.gd")
const AutoWeapon = preload("res://scripts/auto_weapon.gd")

func _reach(type_id: String, tweaks: Dictionary) -> float:
	var parent := Node3D.new()
	var w := Node3D.new()
	w.set_script(AutoWeapon)
	parent.add_child(w)
	root.add_child(parent)
	var d = ModuleDataScript.new()
	d.type_id = type_id
	d.base_weight = ModuleCatalog.get_module_data(type_id).get("weight", 100.0)
	d.base_dps = 50.0
	d.tweaks = tweaks
	w.set_meta("module_data", d)
	w._ready()
	var r: float = w.fire_range
	parent.free()
	return r

func _init():
	var nominal: float = ModuleCatalog.NOMINAL_VISION
	var rows := []
	for type_id in ModuleCatalog.get_catalog():
		if ModuleCatalog.get_module_data(type_id).get("category", "") != "weapon":
			continue
		rows.append([type_id, ModuleCatalog.get_base_range(type_id)])
	rows.sort_custom(func(a, b): return a[1] > b[1])

	print("=== RANGE BY TIER (nominal vision %.0f) ===" % nominal)
	var last_tier := ""
	var per_tier := {}
	for r in rows:
		var tier: String = ModuleCatalog.get_range_tier(r[1])
		per_tier[tier] = per_tier.get(tier, 0) + 1
		if tier != last_tier:
			print("")
			print("  --- %s ---" % ModuleCatalog.get_range_tier_label(r[1]).to_upper())
			last_tier = tier
		print("    %-26s %6.1f  %5.2fx vision%s" % [
			r[0], r[1], r[1] / nominal,
			"   [indirect]" if ModuleCatalog.is_indirect_fire(r[0]) else ""])

	print("")
	print("=== BAND ===")
	print("  %.0f - %.0f, spread %.1fx (was 7 - 50, 7.1x)" % [
		rows[rows.size() - 1][1], rows[0][1], rows[0][1] / rows[rows.size() - 1][1]])
	for tier in ["point_blank", "close", "direct", "overwatch", "operational"]:
		print("  %-14s %d weapons" % [tier, per_tier.get(tier, 0)])

	print("")
	print("=== VISION (post VISION_SCALE %.2f) ===" % ModuleCatalog.VISION_SCALE)
	for h in ["scout_hull", "light_hull", "medium_hull", "heavy_hull"]:
		print("  %-14s %6.1f" % [h, ModuleCatalog.get_base_vision(h)])
	var sensor = ModuleCatalog.get_module_data("sensor_suite")
	print("  + sensor_suite %.1f -> a scout with a mast sees %.1f" % [
		sensor.get("vision_bonus", 0.0),
		ModuleCatalog.get_base_vision("scout_hull") + sensor.get("vision_bonus", 0.0)])

	print("")
	print("=== SPOTTER DEPENDENCY (vs its own medium_hull vision) ===")
	var vision: float = ModuleCatalog.get_base_vision("medium_hull")
	var self_sufficient := 0
	var spotter_helps := 0
	var spotter_only := 0
	for r in rows:
		if r[1] <= vision:
			self_sufficient += 1
		elif r[1] <= vision * 2.0:
			spotter_helps += 1
		else:
			spotter_only += 1
	print("  %2d finds its own targets unaided (reach <= vision %.0f)" % [self_sufficient, vision])
	print("  %2d out-reaches its eyes, a spotter extends it (<= 2x vision)" % spotter_helps)
	print("  %2d CANNOT self-acquire at full reach - spotter-only (> 2x vision)" % spotter_only)

	print("")
	print("=== BARREL LENGTH -> RANGE ===")
	print("  %-20s %-18s %8s" % ["weapon", "config", "reach"])
	for c in [
			["basic_cannon", "stock", {}],
			["basic_cannon", "2.5x barrel", {"barrel_length": 2.5}],
			["basic_cannon", "0.5x barrel", {"barrel_length": 0.5}],
			["artillery", "stock", {}],
			["artillery", "1.5x barrel", {"barrel_length": 1.5}],
			["gauss_railgun", "stock", {}],
			["gauss_railgun", "1.8x rail", {"rail_length": 1.8}],
			["anti_materiel_rifle", "stock", {}],
			["anti_materiel_rifle", "2x optic", {"optic_power": 2.0}]]:
		print("  %-20s %-18s %8.1f" % [c[0], c[1], _reach(c[0], c[2])])

	print("")
	print("=== MUNITION FLIGHT TIME (should be unchanged by the retune) ===")
	# _munition_speed(t) returns fire_range/t, so time = fire_range/speed = t
	# by construction. Printed as a sanity check that reach didn't decouple.
	for pair in [["missile_pod", 1.50], ["hypervelocity_missile", 0.55],
			["sam_launcher", 1.15], ["loitering_munition", 2.71],
			["anti_radiation_missile", 1.55], ["bunker_buster", 1.60],
			["cruise_missile", 4.67], ["guided_missile", 2.19]]:
		var reach: float = ModuleCatalog.get_base_range(pair[0])
		var speed: float = reach / pair[1]
		print("  %-24s reach %6.1f  speed %6.1f u/s  arrives in %.2fs" % [
			pair[0], reach, speed, reach / speed])

	quit(0)
