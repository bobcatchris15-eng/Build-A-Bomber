extends RefCounted
# Single source of truth for how far a weapon reaches.
#
# Chris, 2026-08-03: "each weapon should have a base range stat, that is
# modified by tweaks, mainly barrel length here, longer barrel = greater
# velocity and range."
#
# This exists for the same reason drivetrain.gd does. The tweak chain below
# lived inline in auto_weapon._ready(), which meant COMBAT knew a weapon's real
# reach and nothing else did - the Design Lab sidebar showed no range at all,
# so the player could not see the stat they were being asked to trade against,
# and any readout added there would have had to re-implement two dozen
# multipliers and then drift from them. (That is precisely what happened to
# weight capacity: the sidebar's copy knew 4 locomotors while combat's knew 6,
# and 11 expansion types were in neither.)
#
# So the chain lives here once, and auto_weapon.gd and stat_calculator.gd both
# call it. Adding a range-affecting tweak means editing one function.

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")

# Deployed bipod: a big reach bonus that costs the ability to shoot on the
# move. See auto_weapon.gd's _bipod_blocks_firing() for the other half.
const BIPOD_RANGE_BONUS: float = 1.45

# Ceiling on post-tweak reach. Individually every multiplier below is a
# reasonable trade, but they compound: artillery's 140 base with a 2x
# barrel_length and a 2x elevation is 560, past the full width of every shipped
# map bar one, at which point the weapon is not long-ranged so much as map-wide
# and the tier system stops meaning anything. Sized at roughly twice the
# longest authored reach against map_half_extents of 135-550, so a
# deliberately over-barrelled gun is still a real and rewarded build.
const FIRE_RANGE_MAX: float = 260.0

# Tweaks that INCREASE reach, and why. A longer barrel or accelerator rail
# means more muzzle velocity; a bigger seeker locks on further out; a bigger
# ascent thruster gives a top-attack missile more reach; more fuel pressure
# pushes a flamethrower's stream further; a flak shell's proximity fuse setting
# IS its effective engagement range; a better sight is the whole reason a
# precision weapon reaches further than its barrel alone would justify.
#
# Left out deliberately: count-type tweaks (multi_barrel / barrel_count /
# tube_count / grid_size - "more copies", not "reaches further") and tweaks
# with no real range link (drum_size / motor_size are ammo capacity and spin
# torque; dispersion is spread pattern; cooling_jacket is sustained-fire
# capacity).
const RANGE_TWEAKS_UP := [
	"barrel_length", "elevation", "engine_length", "radar_dish", "caliber",
	"rail_length", "seeker_size", "ascent_thruster", "pressure_valve",
	"fuse_setting", "optic_power", "focal_length",
]

# Tweaks that REDUCE reach. Each is a real trade rather than a drawback: a
# wider dish or aperture spreads the same power over a broader cone, so it
# covers more ground and reaches less; a heavier rod or bigger payload is more
# mass to throw.
const RANGE_TWEAKS_DOWN := [
	"rod_thickness", "payload_size", "nozzle_width", "lens_aperture",
	"containment", "dish_aperture",
]

static func _num(tweaks: Dictionary, key: String) -> float:
	var v = tweaks.get(key, null)
	if v == null:
		return 0.0
	if typeof(v) == TYPE_BOOL:
		return 1.0 if v else 0.0
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return 0.0
	return float(v)

# A weapon's reach, from its authored base through every tweak that touches it.
# `faction` applies the roster-wide range_mult passive; pass "" to skip it.
static func compute(type_id: String, tweaks: Dictionary, faction: String = "") -> float:
	var reach: float = ModuleCatalog.get_base_range(type_id)

	for key in RANGE_TWEAKS_UP:
		var v: float = _num(tweaks, key)
		if v > 0.0:
			reach *= v
	for key in RANGE_TWEAKS_DOWN:
		var v: float = _num(tweaks, key)
		if v > 0.0:
			reach /= v

	if _num(tweaks, "bipod_deploy") >= 0.5:
		reach *= BIPOD_RANGE_BONUS

	if faction != "":
		reach *= FactionCatalog.get_passive(faction, "range_mult", 1.0)

	return minf(reach, FIRE_RANGE_MAX)

# The whole design's range picture, for the Design Lab readout. Mirrors
# Drivetrain.analyze()'s shape: one call, one dictionary, no caller-side maths.
#
# `vision` is the finished unit's real sight radius (hull base + sensor
# modules), which is what decides whether a given weapon can find its own
# targets or needs another unit to look for it.
static func analyze(hull_node: Node3D) -> Dictionary:
	var out := {
		"has_weapons": false,
		"shortest": 0.0,
		"longest": 0.0,
		"vision": 0.0,
		# Weapons whose reach exceeds the design's own vision. These still work,
		# but only out to what the unit itself can see unless the team spots for
		# them - so this is the number the warning panel is about.
		"spotter_assisted": [],
		# Weapons reaching past 2x vision. At that point the unit cannot
		# meaningfully self-acquire at range at all: the weapon is only useful
		# with a spotter, which is a design decision the player should be making
		# knowingly rather than discovering in a match.
		"spotter_required": [],
		"tier": "",
		"tier_label": "",
	}
	if hull_node == null or not is_instance_valid(hull_node):
		return out

	var hull_type: String = hull_node.get_meta("type_id", "medium_hull") if hull_node.has_meta("type_id") else "medium_hull"
	var faction: String = hull_node.get_meta("faction", "") if hull_node.has_meta("faction") else ""
	var vision: float = ModuleCatalog.get_base_vision(hull_type)

	# Same "hull base + sensor module bonus" sum battle_unit.gd's
	# _recalculate_vision() does, so the lab and the field agree.
	for child in hull_node.get_children():
		if not child.has_meta("module_data"):
			continue
		var data = child.get_meta("module_data")
		if data == null or data.type_id != "sensor_suite":
			continue
		vision += data.get_vision_bonus()
	if faction != "":
		vision *= FactionCatalog.get_passive(faction, "vision_mult", 1.0)
	out["vision"] = vision

	var shortest: float = INF
	var longest: float = 0.0
	for child in hull_node.get_children():
		if not child.has_meta("module_data"):
			continue
		var data = child.get_meta("module_data")
		if data == null or data.category != "weapon":
			continue
		# Zero-damage utility modules (smoke, decoys, chaff, beacons) have a
		# reach but are not what "weapon range" means to a player reading the
		# sidebar, and including them would peg the shortest figure to a smoke
		# discharger on an otherwise long-ranged design.
		if data.get_dps() <= 0.0:
			continue
		var reach: float = compute(data.type_id, data.tweaks, faction)
		out["has_weapons"] = true
		shortest = minf(shortest, reach)
		longest = maxf(longest, reach)
		var name: String = ModuleCatalog.get_module_data(data.type_id).get("name", data.type_id)
		if reach > vision * 2.0:
			out["spotter_required"].append({"name": name, "reach": reach})
		elif reach > vision:
			out["spotter_assisted"].append({"name": name, "reach": reach})

	if out["has_weapons"]:
		out["shortest"] = shortest
		out["longest"] = longest
		out["tier"] = ModuleCatalog.get_range_tier(longest)
		out["tier_label"] = ModuleCatalog.get_range_tier_label(longest)
	return out
