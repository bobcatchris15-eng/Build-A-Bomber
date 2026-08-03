extends SceneTree
# Scratch: checks the per-surface "winner" ordering that
# test_terrain_types_differentiate_locomotion asserts, using the same
# single-node / 80kg-locomotor setup that test builds, but comparing
# top_speed x terrain_multiplier directly instead of driving 140 physics
# frames. Far faster to iterate on than the real suite while retuning
# base_top_speed values, and the ordering is what the suite actually cares
# about.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_terrain_order.gd --path .

const Drivetrain = preload("res://scripts/drivetrain.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const ModuleDataScript = preload("res://scripts/module_data.gd")

const TYPES := ["wheels", "tracked_treads", "legs", "screw_drive",
	"rocker_bogie", "half_track", "pontoon_wheels"]

func _speed(loco_id: String) -> float:
	var hull := Node3D.new()
	hull.set_meta("type_id", "medium_hull")
	hull.set_meta("locomotion_type", loco_id)
	hull.set_meta("locomotion_settings", {})
	var c := Node3D.new()
	var d = ModuleDataScript.new()
	d.type_id = loco_id
	d.category = "locomotion"
	d.base_weight = 80.0
	c.set_meta("module_data", d)
	hull.add_child(c)
	var s: float = Drivetrain.analyze(hull)["move_speed"]
	hull.free()
	return s

func _init():
	var plain := {}
	for t in TYPES:
		plain[t] = _speed(t)

	print("=== plain-ground top speed (no terrain multiplier) ===")
	for t in TYPES:
		print("  %-18s %5.2f   (chassis rating %5.1f)" % [t, plain[t], ModuleCatalog.get_base_top_speed(t)])

	for surface in ["marsh", "rocky", "snow_mud", "sand", "gravel", "forest", "ice"]:
		var rows := []
		for t in TYPES:
			var m: float = ModuleCatalog.get_terrain_speed_multiplier(t, surface)
			rows.append([t, plain[t] * m, m])
		rows.sort_custom(func(a, b): return a[1] > b[1])
		var line := ""
		for r in rows:
			line += "%s %.2f (x%.2f)   " % [r[0], r[1], r[2]]
		print("")
		print("=== %s ===  WINNER: %s" % [surface.to_upper(), rows[0][0]])
		print("  " + line)

	# The specific assertions the suite makes.
	print("")
	print("=== SUITE ASSERTIONS ===")
	var chk = func(label: String, ok: bool) -> void:
		print("  [%s] %s" % ["ok  " if ok else "FAIL", label])
	var sp = func(t: String, s: String) -> float:
		return plain[t] * ModuleCatalog.get_terrain_speed_multiplier(t, s)
	chk.call("marsh: screw_drive > wheels x1.5", sp.call("screw_drive", "marsh") > sp.call("wheels", "marsh") * 1.5)
	chk.call("rocky: legs > wheels", sp.call("legs", "rocky") > sp.call("wheels", "rocky"))
	chk.call("sand: treads > wheels", sp.call("tracked_treads", "sand") > sp.call("wheels", "sand"))
	chk.call("gravel: wheels > plain x1.15", sp.call("wheels", "gravel") > plain["wheels"] * 1.15)
	chk.call("forest: legs > wheels x1.5", sp.call("legs", "forest") > sp.call("wheels", "forest") * 1.5)
	var ice_screw: float = sp.call("screw_drive", "ice")
	chk.call("ice: screw_drive beats wheels/legs/treads", \
		ice_screw > sp.call("wheels", "ice") and ice_screw > sp.call("legs", "ice") and ice_screw > sp.call("tracked_treads", "ice"))
	quit(0)
