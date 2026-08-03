extends SceneTree
# Scratch: what the range system ACTUALLY does today, before any retune.
#
# Chris, 2026-08-03: "even the high range weapons are engaging at about the
# same distance as everything else. The longest ranged ones should absolutely
# be range-able out beyond the unit's vision, i.e. the artillery can make use
# of a spotter."
#
# The hypothesis this probe tests is that the range NUMBERS are not the
# problem - the band is already 7..50 - and the reason they all feel the same
# is that two other systems clamp effective engagement long before fire_range
# ever binds:
#   1. fog of war: a weapon refuses to target anything fog_hidden, and fog is
#      driven by vision_range, so anything past vision is untargetable.
#   2. battle_unit._setup_weapons(): attack_range is the SHORTEST weapon's
#      range, so the unit drives into knife range regardless.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_range.gd --path .

const ModuleCatalog = preload("res://scripts/module_catalog.gd")

func _init():
	# --- 1. the weapon range band -----------------------------------------
	var rows := []
	for type_id in ModuleCatalog.get_catalog():
		var d = ModuleCatalog.get_module_data(type_id)
		if d.get("category", "") != "weapon":
			continue
		rows.append([type_id, ModuleCatalog.get_fire_profile(type_id).fire_range])
	rows.sort_custom(func(a, b): return a[1] > b[1])

	print("=== STOCK fire_range, longest first ===")
	for r in rows:
		print("  %-26s %6.1f" % [r[0], r[1]])
	var hi: float = rows[0][1]
	var lo: float = rows[rows.size() - 1][1]
	print("  band %.1f - %.1f, spread %.1fx, %d weapons" % [lo, hi, hi / lo, rows.size()])

	# --- 2. vision, per hull ----------------------------------------------
	print("")
	print("=== HULL base_vision (the cap that actually binds) ===")
	var hulls := []
	for type_id in ModuleCatalog.get_catalog():
		if ModuleCatalog.get_module_data(type_id).get("category", "") == "hull":
			hulls.append(type_id)
	var explicit := 0
	for h in hulls:
		var d = ModuleCatalog.get_module_data(h)
		var has_own: bool = d.has("base_vision")
		if has_own:
			explicit += 1
		print("  %-20s %6.1f%s" % [h, ModuleCatalog.get_base_vision(h),
			"" if has_own else "   <- DEFAULT, no per-hull value"])
	print("  %d of %d hulls declare their own base_vision" % [explicit, hulls.size()])

	# --- 3. how much of the range band is unreachable ----------------------
	print("")
	print("=== RANGE vs VISION ===")
	var vision: float = ModuleCatalog.get_base_vision("medium_hull")
	var over := 0
	var worst_waste: float = 0.0
	var worst_name := ""
	for r in rows:
		if r[1] > vision:
			over += 1
			var waste: float = r[1] - vision
			if waste > worst_waste:
				worst_waste = waste
				worst_name = r[0]
	print("  a stock medium_hull sees %.1f" % vision)
	print("  %d of %d weapons out-range that vision" % [over, rows.size()])
	print("  worst: %s reaches %.1f but can only acquire to %.1f" % [
		worst_name, worst_waste + vision, vision])
	print("  -> every unit of reach past %.1f is unusable without a spotter" % vision)

	# --- 4. sensor_suite, the only vision source --------------------------
	print("")
	var sensor = ModuleCatalog.get_module_data("sensor_suite")
	print("=== the only way to see further ===")
	print("  sensor_suite vision_bonus: %.1f (-> %.1f total)" % [
		sensor.get("vision_bonus", 0.0), vision + sensor.get("vision_bonus", 0.0)])

	quit(0)
