extends SceneTree
# Scratch: works out which of the legs/treads tweak assertions in
# test_locomotion_tweaks_have_real_visual_and_stat_effects are still reachable
# now that (a) node count is no longer double-counted and (b) each chassis has
# its own top-speed ceiling. Prints speed at a sweep of ballast weights so the
# regime each assertion needs can be chosen from data instead of guessed.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_legs_treads.gd --path .

const Drivetrain = preload("res://scripts/drivetrain.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const ModuleDataScript = preload("res://scripts/module_data.gd")
const LocomotionLayout = preload("res://scripts/locomotion_layout.gd")

func _nodes(loco_id: String, settings: Dictionary) -> int:
	var ctx := {
		"hull_size": ModuleCatalog.REFERENCE_HULL_SIZE,
		"running_gear_size": ModuleCatalog.REFERENCE_HULL_SIZE,
		"underside_y_bias": 0.0,
		"catalog_size": ModuleCatalog.get_module_data(loco_id).get("size", Vector3.ONE),
	}
	return maxi(1, LocomotionLayout.stations(loco_id, settings, ctx).size())

func _dt(loco_id: String, settings: Dictionary, ballast: float) -> Dictionary:
	var hull := Node3D.new()
	hull.set_meta("type_id", "medium_hull")
	hull.set_meta("locomotion_type", loco_id)
	hull.set_meta("locomotion_settings", settings)
	var n := _nodes(loco_id, settings)
	for _i in range(n):
		var c := Node3D.new()
		var d = ModuleDataScript.new()
		d.type_id = loco_id
		d.category = "locomotion"
		d.base_weight = 50.0
		c.set_meta("module_data", d)
		hull.add_child(c)
	var b := Node3D.new()
	var bd = ModuleDataScript.new()
	bd.type_id = "armor_plating"
	bd.category = "armor"
	bd.base_weight = ballast
	b.set_meta("module_data", bd)
	hull.add_child(b)
	var out = Drivetrain.analyze(hull)
	out["nodes"] = n
	hull.free()
	return out

func _sweep(tag: String, loco_id: String, a: Dictionary, b: Dictionary, label_a: String, label_b: String) -> void:
	print("=== %s ===" % tag)
	print("  ballast |  %-22s |  %-22s | winner" % [label_a, label_b])
	for ballast in [50.0, 200.0, 350.0, 500.0, 600.0, 800.0, 1000.0, 1200.0, 1600.0]:
		var da := _dt(loco_id, a, ballast)
		var db := _dt(loco_id, b, ballast)
		var win := label_a if da["move_speed"] > db["move_speed"] + 0.01 else (label_b if db["move_speed"] > da["move_speed"] + 0.01 else "TIE")
		print("  %7.0f | n%-2d spd %5.2f load %4.0f%% | n%-2d spd %5.2f load %4.0f%% | %s" % [
			ballast, da["nodes"], da["move_speed"], da["load_ratio"] * 100.0,
			db["nodes"], db["move_speed"], db["load_ratio"] * 100.0, win])

func _init():
	_sweep("WHEELS: 2 axles vs 8 axles", "wheels", {"num_axles": 2}, {"num_axles": 8}, "2 axles", "8 axles")
	print("")
	_sweep("LEGS: 2 vs 8", "legs", {"count": 2}, {"count": 8}, "2 legs", "8 legs")
	print("")
	_sweep("TREADS: narrow 0.5 vs wide 2.5", "tracked_treads", {"tread_width": 0.5}, {"tread_width": 2.5}, "narrow", "wide")
	print("")
	print("=== LEGS thrust PER NODE (the real per-leg tradeoff) ===")
	for n in [2, 4, 6, 8]:
		var d := _dt("legs", {"count": n}, 200.0)
		print("  %d legs: total thrust %7.1f   per leg %6.1f" % [n, d["thrust"], (d["thrust"] - Drivetrain.BASE_THRUST) / float(d["nodes"])])
	print("")
	print("=== TREADS thrust vs width (always 2 nodes) ===")
	for w in [0.5, 1.0, 1.5, 2.5]:
		var d := _dt("tracked_treads", {"tread_width": w}, 200.0)
		print("  width %.1f: thrust %7.1f  capacity %7.1f" % [w, d["thrust"], d["capacity"]])
	quit(0)
