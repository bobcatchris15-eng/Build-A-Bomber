extends SceneTree
# Scratch: the new traverse model as a table - the whole roster's stock rates,
# and what tweaks do to a few representative guns.
#
# Chris, 2026-08-03: traverse differentiation should be meaningful, which meant
# dropping the whole catalog much lower so the fast ones still have a use case;
# base per weapon module; heavier = slower; longer barrel = slower.
#
# The risk this probe exists to check is the fast end: pd_laser / ciws /
# aps_interceptor have to snap onto incoming missiles, and if the global drop
# takes them too low they stop doing their job. Prints seconds-per-90-degrees
# alongside the rate, since that is the number that decides an interception.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_traverse.gd --path .

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const ModuleDataScript = preload("res://scripts/module_data.gd")
const AutoWeapon = preload("res://scripts/auto_weapon.gd")

func _rate(type_id: String, tweaks: Dictionary) -> float:
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
	var r: float = w.traverse_speed
	parent.free()
	return r

func _init():
	var weapons := []
	for type_id in ModuleCatalog.get_catalog():
		if ModuleCatalog.get_module_data(type_id).get("category", "") == "weapon":
			weapons.append(type_id)

	var rows := []
	for type_id in weapons:
		rows.append([type_id, _rate(type_id, {})])
	rows.sort_custom(func(a, b): return a[1] > b[1])

	print("=== STOCK RATES (no tweaks) ===")
	print("  %-26s %8s %8s %9s %9s" % ["weapon", "rad/s", "deg/s", "s per 90", "s per 360"])
	for r in rows:
		print("  %-26s %8.3f %8.1f %9.2f %9.1f" % [
			r[0], r[1], rad_to_deg(r[1]), (PI * 0.5) / r[1], TAU / r[1]])

	print("")
	print("=== POINT DEFENCE - can it still snap onto a target? ===")
	for pd in ["pd_laser", "ciws", "aps_interceptor", "flak_cannon", "aa_autocannon"]:
		var r: float = _rate(pd, {})
		print("  %-18s %6.2f deg/s   90 deg in %4.2fs   45 deg in %4.2fs" % [
			pd, rad_to_deg(r), (PI * 0.5) / r, (PI * 0.25) / r])

	print("")
	print("=== TWEAK RESPONSE ===")
	var cases := [
		["heavy_machine_gun", "stock", {}],
		["heavy_machine_gun", "2x drum (mass only)", {"drum_size": 2.0}],
		["heavy_machine_gun", "2x barrel_length", {"barrel_length": 2.0}],
		["heavy_machine_gun", "0.6x barrel_length", {"barrel_length": 0.6}],
		["basic_cannon", "stock", {}],
		["basic_cannon", "2.5x barrel_length", {"barrel_length": 2.5}],
		["basic_cannon", "0.5x barrel_length", {"barrel_length": 0.5}],
		["basic_cannon", "2x caliber (mass only)", {"caliber": 2.0}],
		["gauss_railgun", "stock", {}],
		["gauss_railgun", "1.8x rail_length", {"rail_length": 1.8}],
		["artillery", "stock", {}],
		["artillery", "2.5x barrel_length", {"barrel_length": 2.5}],
	]
	print("  %-18s %-24s %8s %8s" % ["weapon", "config", "rad/s", "deg/s"])
	for c in cases:
		var r: float = _rate(c[0], c[2])
		print("  %-18s %-24s %8.3f %8.1f" % [c[0], c[1], r, rad_to_deg(r)])

	print("")
	var lo: float = rows[rows.size() - 1][1]
	var hi: float = rows[0][1]
	print("band %.3f - %.3f rad/s (%.0f - %.0f deg/s), spread %.1fx" % [
		lo, hi, rad_to_deg(lo), rad_to_deg(hi), hi / lo])
	quit(0)
