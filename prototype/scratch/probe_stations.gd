extends SceneTree
# Scratch: how many locomotion NODES does a design actually spawn per type and
# per count tweak? Drivetrain.analyze() sums capacity/thrust per locomotion
# child AND multiplies by a count-derived tweak factor, so if the child count
# already tracks the count tweak, capacity is quadratic in it. This answers
# that with the real layout code rather than an assumption.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_stations.gd --path .

const LocomotionLayout = preload("res://scripts/locomotion_layout.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")

func _count(type_id: String, settings: Dictionary) -> int:
	var ctx := {
		"hull_size": ModuleCatalog.REFERENCE_HULL_SIZE,
		"running_gear_size": ModuleCatalog.REFERENCE_HULL_SIZE,
		"underside_y_bias": 0.0,
		"catalog_size": ModuleCatalog.get_module_data(type_id).get("size", Vector3.ONE),
	}
	return LocomotionLayout.stations(type_id, settings, ctx).size()

func _init():
	print("wheels   num_axles=2 ->", _count("wheels", {"num_axles": 2}))
	print("wheels   num_axles=4 ->", _count("wheels", {"num_axles": 4}))
	print("wheels   num_axles=8 ->", _count("wheels", {"num_axles": 8}))
	print("wheels   axles=4 wpa=2 ->", _count("wheels", {"num_axles": 4, "wheels_per_axle": 2}))
	print("treads   {} ->", _count("tracked_treads", {}))
	print("treads   width=2.5 ->", _count("tracked_treads", {"tread_width": 2.5}))
	print("legs     count=2 ->", _count("legs", {"count": 2}))
	print("legs     count=4 ->", _count("legs", {"count": 4}))
	print("legs     count=8 ->", _count("legs", {"count": 8}))
	print("rotors   count=4 ->", _count("helicopter_rotors", {"count": 4}))
	print("rotors   count=8 ->", _count("helicopter_rotors", {"count": 8}))
	print("hover    pad_count=4 ->", _count("hover_engine", {"pad_count": 4}))
	print("hover    pad_count=8 ->", _count("hover_engine", {"pad_count": 8}))
	print("fixedwng engine_count=2 ->", _count("fixed_wing_engine", {"engine_count": 2}))
	print("fixedwng engine_count=6 ->", _count("fixed_wing_engine", {"engine_count": 6}))
	print("naval    prop_count=2 ->", _count("naval_propeller", {"prop_count": 2}))
	print("naval    prop_count=5 ->", _count("naval_propeller", {"prop_count": 5}))
	print("buoyant  prop_count=2 ->", _count("buoyant_envelope", {"prop_count": 2}))
	print("screw    {} ->", _count("screw_drive", {}))
	print("hydrofoil {} ->", _count("hydrofoil", {}))
	print("skirt    fans=3 ->", _count("air_cushion_skirt", {"lift_fan_count": 3}))
	print("skirt    fans=6 ->", _count("air_cushion_skirt", {"lift_fan_count": 6}))
	print("antigrav plates=4 ->", _count("anti_grav_plate", {"plate_count": 4}))
	print("antigrav plates=8 ->", _count("anti_grav_plate", {"plate_count": 8}))
	print("waterjet nozzles=2 ->", _count("water_jet", {"nozzle_count": 2}))
	print("waterjet nozzles=4 ->", _count("water_jet", {"nozzle_count": 4}))
	print("halftrk  bogie=3 ->", _count("half_track", {"bogie_count": 3}))
	print("halftrk  bogie=6 ->", _count("half_track", {"bogie_count": 6}))
	print("rocker   pairs=3 ->", _count("rocker_bogie", {"bogie_pairs": 3}))
	print("rocker   pairs=6 ->", _count("rocker_bogie", {"bogie_pairs": 6}))
	print("pontoon  axles=4 ->", _count("pontoon_wheels", {"axle_count": 4}))
	print("pontoon  axles=8 ->", _count("pontoon_wheels", {"axle_count": 8}))
	print("orni     wingspan=2 ->", _count("ornithopter_wing", {"wingspan": 2.0}))
	quit(0)
