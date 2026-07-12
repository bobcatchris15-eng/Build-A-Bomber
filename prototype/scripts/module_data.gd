class_name ModuleData
extends Resource

const GlobalConfig = preload("res://scripts/global_config.gd")

@export var type_id: String = ""
@export var module_name: String = "Unknown Module"
@export var category: String = "module"
@export var base_hp: float = 100.0
@export var base_weight: float = 50.0
@export var cost_metal: int = 10
@export var cost_crystal: int = 0
@export var base_dps: float = 0.0
@export var base_heal_rate: float = 0.0
@export var base_energy_capacity: float = 0.0
@export var base_energy_regen: float = 0.0
@export var tweaks: Dictionary = {}

var scale_multiplier: Vector3 = Vector3(1, 1, 1)

# Helper to get the volume multiplier based on scale
func _get_volume_mult() -> float:
	return scale_multiplier.x * scale_multiplier.y * scale_multiplier.z

func get_hp() -> float:
	var vol = _get_volume_mult()
	var hp = base_hp + (base_hp * (vol - 1.0) * GlobalConfig.hp_scale_factor)
	if tweaks.has("cooling_jacket"):
		hp *= tweaks["cooling_jacket"]
	return GlobalConfig.round_to_half(hp)

func get_weight() -> float:
	var vol = _get_volume_mult()
	var weight = base_weight + (base_weight * (vol - 1.0) * GlobalConfig.weight_scale_factor)
	
	for tweak_name in tweaks:
		var val = tweaks[tweak_name]
		if tweak_name in ["caliber", "barrel_length", "drum_size", "motor_size", "rail_length", "rod_thickness", "engine_length", "seeker_size", "ascent_thruster", "payload_size", "nozzle_width", "pressure_valve", "lens_aperture", "containment", "radar_dish", "cooling_jacket", "extractor_size", "mast_height", "tank_capacity", "dispersion", "elevation", "fuse_setting"]:
			if typeof(val) == TYPE_FLOAT or typeof(val) == TYPE_INT:
				weight *= val
		elif tweak_name == "multi_barrel" and val == true:
			weight *= 2.0
		elif tweak_name == "barrel_count":
			weight *= (val / 6.0)
		elif tweak_name == "tube_count":
			weight *= (val / 2.0)
		elif tweak_name == "grid_size":
			weight *= (val / 4.0)
		elif tweak_name == "welder_count":
			weight *= (val / 2.0)
		elif tweak_name == "hangar_size":
			# "Increases active drone count but takes up massive chassis
			# real estate" (Arsenal_Weapons_List.md) - weight scales with
			# drone count, same shape as barrel_count/tube_count above.
			weight *= (val / 2.0)
		elif tweak_name == "launch_catapult":
			# Faster launches need heavier catapult machinery - also
			# ensures this tweak actually changes a stat (test_no_dead_tweaks),
			# not just fire_rate deep inside auto_weapon.gd.
			weight *= val

	return GlobalConfig.round_to_half(weight)
	
func get_cost() -> Vector2i:
	var vol = _get_volume_mult()
	var m = cost_metal + int(cost_metal * (vol - 1.0) * GlobalConfig.cost_scale_factor)
	var c = cost_crystal + int(cost_crystal * (vol - 1.0) * GlobalConfig.cost_scale_factor)
	
	for tweak_name in tweaks:
		var val = tweaks[tweak_name]
		if tweak_name in ["caliber", "rail_length", "seeker_size", "payload_size", "radar_dish"]:
			if typeof(val) == TYPE_FLOAT or typeof(val) == TYPE_INT:
				m = int(m * val)
				c = int(c * val)
		elif tweak_name == "multi_barrel" and val == true:
			m *= 2
			c *= 2
		elif tweak_name == "barrel_count":
			m = int(m * (val / 6.0))
		elif tweak_name == "tube_count":
			m = int(m * (val / 2.0))
		elif tweak_name == "grid_size":
			m = int(m * (val / 4.0))
			c = int(c * (val / 4.0))
		elif tweak_name == "welder_count":
			m = int(m * (val / 2.0))
			c = int(c * (val / 2.0))
			
	return Vector2i(m, c)

func get_energy_capacity() -> float:
	var vol = _get_volume_mult()
	var cap = base_energy_capacity + (base_energy_capacity * (vol - 1.0) * GlobalConfig.hp_scale_factor)
	return GlobalConfig.round_to_half(cap)

func get_energy_regen() -> float:
	var vol = _get_volume_mult()
	var regen = base_energy_regen + (base_energy_regen * (vol - 1.0) * GlobalConfig.hp_scale_factor)
	return GlobalConfig.round_to_half(regen)

# Dedicated stat, not a reuse of dps (see DECISIONS_NEEDED.md for why that
# was a deliberate stopgap) - repair_array's heal-per-second, kept out of
# the Design Lab's "Total DPS" aggregate. Reuses welder_count's existing
# scaling shape ("adding more arms speeds up construction exponentially",
# Arsenal_Weapons_List.md) since that's the one tweak repair_array has.
func get_heal_rate() -> float:
	var vol = _get_volume_mult()
	var heal = base_heal_rate + (base_heal_rate * (vol - 1.0) * GlobalConfig.dps_scale_factor)
	if tweaks.has("welder_count"):
		heal *= (tweaks["welder_count"] / 2.0)
	return GlobalConfig.round_to_half(heal)

func get_dps() -> float:
	var vol = _get_volume_mult()
	var dps = base_dps + (base_dps * (vol - 1.0) * GlobalConfig.dps_scale_factor)
	
	for tweak_name in tweaks:
		var val = tweaks[tweak_name]
		if tweak_name in ["caliber", "rail_length", "rod_thickness", "payload_size", "pressure_valve", "lens_aperture", "cooling_jacket", "extractor_size"]:
			if typeof(val) == TYPE_FLOAT or typeof(val) == TYPE_INT:
				dps *= val
		elif tweak_name == "multi_barrel" and val == true:
			dps *= 2.0
		elif tweak_name == "barrel_count":
			dps *= (val / 6.0)
		elif tweak_name == "tube_count":
			dps *= (val / 2.0)
		elif tweak_name == "grid_size":
			dps *= (val / 4.0)
		elif tweak_name == "welder_count":
			dps *= (val / 2.0)

	return GlobalConfig.round_to_half(dps)
