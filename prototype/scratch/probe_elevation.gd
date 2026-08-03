extends SceneTree
# Scratch: per-weapon elevation as a table, and a real acquisition test at
# several target elevations.
#
# Chris, 2026-08-03: "PD weapons should absolutely be able to point straight up
# and target units or missiles directly above. Machine gun and gatling too, as
# well as SAM launcher and Anti-radiation missile. Then it needs to move down
# from there, an artillery piece isn't being used to engage things above you."
#
# The second half matters more than the table: before this, acquisition gated on
# a yaw cone with no vertical term, so EVERY pintle weapon could hit something
# directly overhead. This probe puts a target at 0/30/45/60/89 degrees of
# elevation and reports which weapons actually accept it.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_elevation.gd --path .

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const ModuleDataScript = preload("res://scripts/module_data.gd")
const AutoWeapon = preload("res://scripts/auto_weapon.gd")

var _carrier: Node3D = null

func _weapon(type_id: String, tweaks: Dictionary = {}) -> Node3D:
	var w := Node3D.new()
	w.set_script(AutoWeapon)
	_carrier.add_child(w)
	var d = ModuleDataScript.new()
	d.type_id = type_id
	d.base_weight = ModuleCatalog.get_module_data(type_id).get("weight", 100.0)
	d.base_dps = 50.0
	d.tweaks = tweaks
	w.set_meta("module_data", d)
	w._ready()
	return w

func _init():
	_carrier = Node3D.new()
	_carrier.set_meta("team", 0)
	_carrier.add_to_group("damageable")
	root.add_child(_carrier)

	var weapons: Array = []
	for type_id in ModuleCatalog.get_catalog():
		if ModuleCatalog.get_module_data(type_id).get("category", "") == "weapon":
			weapons.append(type_id)

	var rows := []
	for type_id in weapons:
		rows.append([
			type_id,
			rad_to_deg(ModuleCatalog.get_elevation_up(type_id)),
			rad_to_deg(ModuleCatalog.get_elevation_down(type_id)),
			ModuleCatalog.can_engage_overhead(type_id),
			ModuleCatalog.ELEVATION_LIMITS.has(type_id)])
	rows.sort_custom(func(a, b): return a[1] > b[1])

	print("=== ELEVATION LIMITS (degrees from the weapon's own horizon) ===")
	print("  %-26s %6s %6s  %s" % ["weapon", "up", "down", "overhead-capable"])
	var undeclared := 0
	for r in rows:
		if not r[4]:
			undeclared += 1
		print("  %-26s %6.0f %6.0f  %s%s" % [
			r[0], r[1], r[2], "YES" if r[3] else "no",
			"   <- DEFAULT, not declared" if not r[4] else ""])
	print("  %d of %d weapons use the shared default" % [undeclared, rows.size()])

	# --- the named groups ------------------------------------------------
	print("")
	print("=== CHRIS'S NAMED GROUPS ===")
	var must_reach_up := ["pd_laser", "ciws", "aps_interceptor",
		"heavy_machine_gun", "rotary_cannon", "sam_launcher",
		"anti_radiation_missile"]
	for type_id in must_reach_up:
		var up: float = rad_to_deg(ModuleCatalog.get_elevation_up(type_id))
		print("  %-24s %5.0f deg  %s" % [type_id, up,
			"OK - can point straight up" if up >= 89.0 else "*** NOT VERTICAL ***"])
	print("")
	for type_id in ["basic_cannon", "artillery"]:
		var up: float = rad_to_deg(ModuleCatalog.get_elevation_up(type_id))
		print("  %-24s %5.0f deg  overhead-capable=%s" % [
			type_id, up, ModuleCatalog.can_engage_overhead(type_id)])

	# --- real acquisition, not just the table ----------------------------
	print("")
	print("=== ACQUISITION vs TARGET ELEVATION (does the weapon accept it?) ===")
	var elevations := [0.0, 30.0, 45.0, 60.0, 89.0]
	var probe_set := ["pd_laser", "ciws", "heavy_machine_gun", "rotary_cannon",
		"sam_launcher", "anti_radiation_missile", "aa_autocannon",
		"autocannon", "heavy_laser", "basic_cannon", "gauss_railgun",
		"mortar_array", "artillery"]
	var header := "  %-24s" % "weapon"
	for e in elevations:
		header += "%8s" % ("%.0f deg" % e)
	print(header)
	for type_id in probe_set:
		var w := _weapon(type_id)
		var line := "  %-24s" % type_id
		for e in elevations:
			var rad: float = deg_to_rad(e)
			# Target at that elevation, straight ahead in azimuth (-Z).
			var dir := Vector3(0, sin(rad), -cos(rad)).normalized()
			line += "%8s" % ("hit" if w._within_elevation(dir) else "-")

		print(line)
		w.free()

	# --- the elevation tweak ---------------------------------------------
	print("")
	print("=== `elevation` TWEAK RAISES THE CEILING (capped at 90) ===")
	for type_id in ["basic_cannon", "artillery", "pd_laser"]:
		var base: float = rad_to_deg(ModuleCatalog.get_elevation_up(type_id))
		var tweaked: float = rad_to_deg(ModuleCatalog.get_elevation_up(type_id, {"elevation": 2.0}))
		print("  %-20s %5.0f -> %5.0f deg  (2x elevation tweak)" % [type_id, base, tweaked])

	# --- depression, the other half --------------------------------------
	print("")
	print("=== DEPRESSION: can it shoot at something BELOW it? ===")
	for type_id in ["pd_laser", "basic_cannon", "artillery", "sam_launcher"]:
		var w := _weapon(type_id)
		var down_deg: float = rad_to_deg(ModuleCatalog.get_elevation_down(type_id))
		var at_30_below := Vector3(0, -sin(deg_to_rad(30.0)), -cos(deg_to_rad(30.0))).normalized()
		print("  %-20s down limit %4.0f deg   target 30 deg below: %s" % [
			type_id, down_deg, "hit" if w._within_elevation(at_30_below) else "-"])
		w.free()

	quit(0)
