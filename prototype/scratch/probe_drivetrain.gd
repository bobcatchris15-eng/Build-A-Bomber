extends SceneTree
# Scratch: prints the drivetrain table for every locomotor at a few loadouts,
# so the base_top_speed / capacity / overload numbers can be eyeballed as a
# balance set rather than one design at a time. The headless suite can assert
# relationships ("treads tolerate more than wheels") but it cannot tell me
# whether the whole roster still lands in a sensible band.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_drivetrain.gd --path .

const Drivetrain = preload("res://scripts/drivetrain.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const ModuleDataScript = preload("res://scripts/module_data.gd")

const TYPES := ["wheels", "tracked_treads", "legs", "half_track", "rocker_bogie",
	"pontoon_wheels", "screw_drive", "hover_engine", "air_cushion_skirt",
	"anti_grav_plate", "helicopter_rotors", "fixed_wing_engine",
	"ornithopter_wing", "buoyant_envelope", "naval_propeller", "hydrofoil",
	"water_jet"]

const LocomotionLayout = preload("res://scripts/locomotion_layout.gd")

# Spawns as many locomotion children as the REAL layout would for these
# settings. A one-child mock is not representative: analyze() sums per child,
# and 8 axles is 8 nodes. The first version of this probe used a single child
# and reported a bare helicopter design as already overloaded, which is not
# what the game does - four rotor nodes carry four times the load.
func _station_count(loco_id: String, settings: Dictionary) -> int:
	var ctx := {
		"hull_size": ModuleCatalog.REFERENCE_HULL_SIZE,
		"running_gear_size": ModuleCatalog.REFERENCE_HULL_SIZE,
		"underside_y_bias": 0.0,
		"catalog_size": ModuleCatalog.get_module_data(loco_id).get("size", Vector3.ONE),
	}
	return maxi(1, LocomotionLayout.stations(loco_id, settings, ctx).size())

func _make_hull(loco_id: String, extra_weight: float, settings: Dictionary) -> Node3D:
	var hull := Node3D.new()
	hull.set_meta("type_id", "medium_hull")
	hull.set_meta("locomotion_type", loco_id)
	hull.set_meta("locomotion_settings", settings)
	for _i in range(_station_count(loco_id, settings)):
		var loco := Node3D.new()
		var d = ModuleDataScript.new()
		d.type_id = loco_id
		d.category = "locomotion"
		d.base_weight = ModuleCatalog.get_module_data(loco_id).get("weight", 50.0)
		loco.set_meta("module_data", d)
		hull.add_child(loco)
	if extra_weight > 0.0:
		var extra := Node3D.new()
		var e = ModuleDataScript.new()
		e.type_id = "artillery"
		e.category = "weapon"
		e.base_weight = extra_weight
		extra.set_meta("module_data", e)
		hull.add_child(extra)
	return hull

func _row(loco_id: String, payload: float, settings: Dictionary) -> void:
	var hull := _make_hull(loco_id, payload, settings)
	var dt = Drivetrain.analyze(hull)
	print("  %-19s n%-2d wt %6.0f  cap %6.0f  load %5.0f%%  chassis %5.1f  power %5.1f  top %5.1f  MOVE %5.2f  %s" % [
		loco_id, _station_count(loco_id, settings),
		dt["weight"], dt["capacity"], dt["load_ratio"] * 100.0,
		dt["chassis_top_speed"], dt["power_top_speed"], dt["top_speed"],
		dt["move_speed"],
		("OVERLOADED" if dt["is_overloaded"] else ("chassis-capped" if dt["capacity_limited"] else ""))])
	hull.free()

func _init():
	print("=== BARE (locomotion only, medium_hull) ===")
	for t in TYPES:
		_row(t, 0.0, {})
	print("")
	print("=== +200kg payload ===")
	for t in TYPES:
		_row(t, 200.0, {})
	print("")
	print("=== +500kg payload (heavy) ===")
	for t in TYPES:
		_row(t, 500.0, {})
	print("")
	# Payloads solved against the type's REAL capacity and REAL bare weight, so
	# each row lands on the intended load percentage. Hardcoding them against a
	# single-node capacity of 350 put the whole "curve" between 38% and 75%.
	print("=== OVERLOAD CURVE (wheels, 4 axles) ===")
	var bare := _make_hull("wheels", 0.0, {})
	var bare_dt = Drivetrain.analyze(bare)
	var cap: float = bare_dt["capacity"]
	var bare_wt: float = bare_dt["weight"]
	bare.free()
	for pct in [100, 105, 110, 125, 150, 175, 200, 250, 300]:
		_row("wheels", maxf(0.0, cap * float(pct) / 100.0 - bare_wt), {})
	print("")
	print("=== TWEAK RESPONSE ===")
	print("  wheels, axles 4->8 (thrust+capacity both up):")
	_row("wheels", 300.0, {"num_axles": 4, "wheels_per_axle": 1})
	_row("wheels", 300.0, {"num_axles": 8, "wheels_per_axle": 1})
	_row("wheels", 300.0, {"num_axles": 8, "wheels_per_axle": 2})
	print("  tracked_treads, width 0.5/1.0/2.5 (capacity up, thrust down):")
	for w in [0.5, 1.0, 2.5]:
		_row("tracked_treads", 400.0, {"tread_width": w})
	print("  legs, count 2/4/8 (capacity up, thrust down):")
	for n in [2, 4, 8]:
		_row("legs", 300.0, {"count": n})
	print("  hover_engine, emv 1.0/2.5 (capacity only):")
	for e in [1.0, 2.5]:
		_row("hover_engine", 300.0, {"pad_count": 4, "emv_level": e})
	print("  buoyant_envelope, prop 2/6 (thrust only, capacity flat):")
	for p in [2, 6]:
		_row("buoyant_envelope", 400.0, {"prop_count": p})
	quit(0)
