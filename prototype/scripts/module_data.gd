class_name ModuleData
extends Resource

const GlobalConfig = preload("res://scripts/global_config.gd")
# Ammo selection (ModuleCatalog.AMMO_TYPES) carries real stowage weight and
# per-round cost. Safe to preload: module_catalog.gd does not preload this
# file, so there's no cycle.
const ModuleCatalogScript = preload("res://scripts/module_catalog.gd")

# Ammo's weight/cost multipliers. Kept as one helper rather than inlined
# into get_weight()/get_cost() twice so the two can never disagree about
# which round is loaded. Returns the neutral "standard" profile for any
# module with no ammo selection at all, which is every weapon absent from
# WEAPON_AMMO_OPTIONS plus every non-weapon module - so this is a strict
# no-op for them.
func _get_ammo_profile() -> Dictionary:
	if not ModuleCatalogScript.is_ammo_capable(type_id):
		return ModuleCatalogScript.AMMO_TYPES[ModuleCatalogScript.AMMO_DEFAULT]
	return ModuleCatalogScript.get_ammo_profile(ModuleCatalogScript.get_ammo(type_id, tweaks))

# Empty multipliers for anything that is not a leg, so get_weight() can apply
# this unconditionally the way it already does for ammo.
const _NO_LEG_PROFILE := {}

func _get_leg_profile() -> Dictionary:
	if type_id != "legs":
		return _NO_LEG_PROFILE
	return ModuleCatalogScript.get_leg_profile(ModuleCatalogScript.get_leg_type(tweaks))

@export var type_id: String = ""
@export var module_name: String = "Unknown Module"
@export var category: String = "module"
@export var base_hp: float = 100.0
@export var base_weight: float = 50.0
@export var cost_metal: int = 10
@export var cost_crystal: int = 0
@export var base_dps: float = 0.0
@export var base_heal_rate: float = 0.0
# Storage (energy) and generation (energy/sec) - two separate stats, and no
# module currently has both. See module_catalog.gd's generator entries.
@export var base_energy_capacity: float = 0.0
@export var base_power_output: float = 0.0
@export var base_vision_bonus: float = 0.0
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
	if tweaks.has("protectedness"):
		var p = tweaks["protectedness"]
		if typeof(p) == TYPE_FLOAT or typeof(p) == TYPE_INT:
			hp *= 1.0 + (p * 0.25)
	return GlobalConfig.round_to_half(hp)

func get_weight() -> float:
	var vol = _get_volume_mult()
	var weight = base_weight + (base_weight * (vol - 1.0) * GlobalConfig.weight_scale_factor)
	
	for tweak_name in tweaks:
		var val = tweaks[tweak_name]
		if tweak_name in ["caliber", "barrel_length", "drum_size", "motor_size", "rail_length", "rod_thickness", "engine_length", "seeker_size", "warhead_size", "motor_length", "ascent_thruster", "payload_size", "nozzle_width", "pressure_valve", "lens_aperture", "containment", "radar_dish", "cooling_jacket", "extractor_size", "bay_volume", "mast_height", "dispersion", "elevation", "fuse_setting", "dish_aperture", "charge_time", "focal_length", "wheel_size", "tread_width", "blade_length", "leg_length", "leg_width", "emv_level", "nacelle_size", "turbine_compression", "wingspan", "drum_width", "drum_diameter", "wheels_per_axle", "foot_size", "cutter_head", "arm_reach", "projector_diameter", "optic_aperture", "mast_extension", "radar_size", "busbar_gauge", "reactor_length", "cooling_radiator", "skirt_diameter", "plenum_pressure", "field_strength", "strut_height", "intake_size", "front_axle_size", "arm_length"]:
			if typeof(val) == TYPE_FLOAT or typeof(val) == TYPE_INT:
				weight *= val
		elif tweak_name == "multi_barrel" and val == true:
			weight *= 2.0
		elif tweak_name == "barrel_count":
			weight *= (val / 6.0)
		elif tweak_name in ["tube_count", "welder_count", "hangar_size", "prop_count", "engine_count", "array_faces", "nozzle_count", "foil_count"]:
			weight *= (val / 2.0)
		elif tweak_name in ["grid_size", "num_axles", "blade_count", "rotor_units", "leg_count", "pad_count", "coil_count", "bank_capacity", "bogie_count", "bogie_pairs", "lift_fan_count", "plate_count"]:
			weight *= (val / 4.0)
		elif tweak_name in ["afterburner", "duct", "stabilizer_ring", "reverser", "kort_nozzle"] and val == true:
			weight *= 1.25
		elif tweak_name == "launch_catapult":
			weight *= val
		elif tweak_name == "optic_power":
			# Deliberately NOT in the blanket linear list above. A 2x sight
			# doubling the entire weapon's mass is nonsense - the optic is a
			# fraction of the gun, so it scales a fraction of the weight.
			# Its real price is crystal, in get_cost() below.
			if typeof(val) == TYPE_FLOAT or typeof(val) == TYPE_INT:
				weight *= 1.0 + (float(val) - 1.0) * 0.35
		elif tweak_name == "bipod_deploy":
			# ADDITIVE, and deliberately not in any of the multiplier lists
			# above: this tweak ranges 0..1, so multiplying by it would make
			# an undeployed bipod zero out the module's entire weight. A
			# fitted bipod is real mass whether or not it's down.
			if typeof(val) == TYPE_FLOAT or typeof(val) == TYPE_INT:
				weight += base_weight * 0.06 * float(val)
		elif tweak_name == "protectedness":
			if typeof(val) == TYPE_FLOAT or typeof(val) == TYPE_INT:
				weight *= 1.0 + (val * 0.15)

	# Ammo stowage mass - AP penetrators and HE filler weigh more than a
	# plain service round, obscurant canisters slightly less.
	weight *= _get_ammo_profile().get("weight_mult", 1.0)

	# Leg set mass, the same idea one category over: a trussed Excavator limb on
	# hydraulic pistons is simply more machine than a Raptor's. Applied here
	# rather than by giving each set its own catalog weight, because there is one
	# "legs" entry and the set is a tweak on it.
	weight *= _get_leg_profile().get("weight_mult", 1.0)

	return GlobalConfig.round_to_half(weight)
	
func get_cost() -> Vector2i:
	var vol = _get_volume_mult()
	var m = cost_metal + int(cost_metal * (vol - 1.0) * GlobalConfig.cost_scale_factor)
	var c = cost_crystal + int(cost_crystal * (vol - 1.0) * GlobalConfig.cost_scale_factor)

	for tweak_name in tweaks:
		var val = tweaks[tweak_name]
		if tweak_name in ["caliber", "barrel_length", "drum_size", "motor_size", "rail_length", "rod_thickness", "engine_length", "seeker_size", "warhead_size", "motor_length", "ascent_thruster", "payload_size", "nozzle_width", "pressure_valve", "lens_aperture", "containment", "radar_dish", "cooling_jacket", "extractor_size", "bay_volume", "mast_height", "dispersion", "elevation", "fuse_setting", "dish_aperture", "charge_time", "focal_length", "wheel_size", "tread_width", "blade_length", "leg_length", "leg_width", "emv_level", "nacelle_size", "turbine_compression", "wingspan", "drum_width", "drum_diameter", "wheels_per_axle", "foot_size", "cutter_head", "arm_reach", "projector_diameter", "optic_aperture", "mast_extension", "radar_size", "busbar_gauge", "reactor_length", "cooling_radiator", "skirt_diameter", "plenum_pressure", "field_strength", "strut_height", "intake_size", "front_axle_size", "arm_length"]:
			if typeof(val) == TYPE_FLOAT or typeof(val) == TYPE_INT:
				m = int(m * val)
				c = int(c * val)
		elif tweak_name == "optic_power":
			# Where an optic actually costs you: crystal, hard. Metal barely
			# moves - a better sight is not more steel. This is the intended
			# shape of the trade, and the reason the rifle is the roster's
			# most crystal-hungry non-energy weapon.
			if typeof(val) == TYPE_FLOAT or typeof(val) == TYPE_INT:
				m = int(m * (1.0 + (float(val) - 1.0) * 0.20))
				c = int(c * (1.0 + (float(val) - 1.0) * 1.60))
		elif tweak_name == "multi_barrel" and val == true:
			m *= 2
			c *= 2
		elif tweak_name == "barrel_count":
			m = int(m * (val / 6.0))
			c = int(c * (val / 6.0))
		elif tweak_name in ["tube_count", "welder_count", "hangar_size", "prop_count", "engine_count", "array_faces", "nozzle_count", "foil_count"]:
			m = int(m * (val / 2.0))
			c = int(c * (val / 2.0))
		elif tweak_name in ["grid_size", "num_axles", "blade_count", "rotor_units", "leg_count", "pad_count", "coil_count", "bank_capacity", "bogie_count", "bogie_pairs", "lift_fan_count", "plate_count"]:
			m = int(m * (val / 4.0))
			c = int(c * (val / 4.0))
		elif tweak_name in ["afterburner", "duct", "stabilizer_ring", "reverser", "kort_nozzle"] and val == true:
			m = int(m * 1.25)
			c = int(c * 1.25)
		elif tweak_name == "launch_catapult":
			m = int(m * val)
			c = int(c * val)
		elif tweak_name == "protectedness":
			if typeof(val) == TYPE_FLOAT or typeof(val) == TYPE_INT:
				m = int(m * (1.0 + (val * 0.20)))
				c = int(c * (1.0 + (val * 0.20)))

	# Per-round payload cost. EMP shells are the crystal sink of the set
	# (1.7x), obscurants the cheapest - deliberately so that loading smoke
	# is an easy call and loading EMP is a real economic commitment.
	var ammo = _get_ammo_profile()
	m = int(m * ammo.get("metal_mult", 1.0))
	c = int(c * ammo.get("crystal_mult", 1.0))

	return Vector2i(m, c)

func get_energy_capacity() -> float:
	var vol = _get_volume_mult()
	var cap = base_energy_capacity + (base_energy_capacity * (vol - 1.0) * GlobalConfig.hp_scale_factor)
	if tweaks.has("bank_capacity"):
		cap *= (tweaks["bank_capacity"] / 4.0)
	if tweaks.has("busbar_gauge"):
		cap *= tweaks["busbar_gauge"]
	return GlobalConfig.round_to_half(cap)

# GENERATION - energy per second this module contributes to its unit's refill
# rate. Renamed from get_energy_regen() when generation and storage were split
# into separate stats (see the generator entries in module_catalog.gd): "regen"
# described a property of the POOL, which is exactly the conflation the split
# exists to end. A generator does not regenerate a buffer it has no part of; it
# produces power, and the buffer is somewhere else entirely.
#
# The two tweaks are unchanged and were always the right ones - they have only
# ever scaled this quantity. What changed is that fusion_generator, the module
# that owns them, now has generation as its ONLY output, so both are load
# bearing rather than tuning one of its two stats while the other sat inert.
func get_power_output() -> float:
	var vol = _get_volume_mult()
	var out = base_power_output + (base_power_output * (vol - 1.0) * GlobalConfig.hp_scale_factor)
	if tweaks.has("reactor_length"):
		out *= tweaks["reactor_length"]
	if tweaks.has("cooling_radiator"):
		out *= tweaks["cooling_radiator"]
	return GlobalConfig.round_to_half(out)

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
	if tweaks.has("arm_reach"):
		heal *= tweaks["arm_reach"]
	return GlobalConfig.round_to_half(heal)

# Fog-of-war (see PROGRESS.md): sensor_suite's vision contribution, scaled
# by the existing mast_height tweak ("Drastically increases line-of-sight",
# Arsenal_Weapons_List.md) - previously mast_height only affected the
# visual mesh, this is its first real functional effect.
func get_vision_bonus() -> float:
	var vol = _get_volume_mult()
	var bonus = base_vision_bonus + (base_vision_bonus * (vol - 1.0) * GlobalConfig.hp_scale_factor)
	if tweaks.has("mast_height"):
		bonus *= tweaks["mast_height"]
	if tweaks.has("dish_aperture"):
		bonus *= tweaks["dish_aperture"]
	if tweaks.has("optic_aperture"):
		bonus *= tweaks["optic_aperture"]
	if tweaks.has("mast_extension"):
		bonus *= tweaks["mast_extension"]
	if tweaks.has("radar_size"):
		bonus *= tweaks["radar_size"]
	if tweaks.has("array_faces"):
		bonus *= (tweaks["array_faces"] / 2.0)
	return GlobalConfig.round_to_half(bonus)

func get_dps() -> float:
	var vol = _get_volume_mult()
	var dps = base_dps + (base_dps * (vol - 1.0) * GlobalConfig.dps_scale_factor)
	
	for tweak_name in tweaks:
		var val = tweaks[tweak_name]
		if tweak_name in ["caliber", "barrel_length", "drum_size", "motor_size", "rail_length", "rod_thickness", "engine_length", "seeker_size", "warhead_size", "motor_length", "ascent_thruster", "payload_size", "nozzle_width", "pressure_valve", "lens_aperture", "containment", "radar_dish", "cooling_jacket", "extractor_size", "bay_volume", "mast_height", "dispersion", "elevation", "fuse_setting", "charge_time", "cutter_head", "projector_diameter", "coil_count"]:
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
