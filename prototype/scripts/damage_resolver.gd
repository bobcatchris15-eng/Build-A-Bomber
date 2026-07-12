class_name DamageResolver
# Shared armor/threshold resolution for battle_unit.gd (Skirmish),
# player_vehicle.gd (Test Range), and building.gd (defense structures).
# Previously this math was duplicated inline across all three and already
# drifted once (had to be manually kept in sync when the armor-module bonus
# was added) - single source of truth from here on. See DECISIONS_NEEDED.md
# for the phased directional-armor build-out plan this is part of.

const ModuleCatalogScript = preload("res://scripts/module_catalog.gd")

# damage_type -> [base_threshold, reduction] per armor material.
const ARMOR_TABLE = {
	"hardened_steel": {"kinetic": [15.0, 0.7], "thermal": [5.0, 0.9], "explosive": [10.0, 0.8]},
	"reactive_armor": {"kinetic": [10.0, 0.8], "thermal": [10.0, 0.8], "explosive": [30.0, 0.4]},
	"ablative_ceramic": {"kinetic": [8.0, 0.9], "thermal": [25.0, 0.3], "explosive": [10.0, 0.7]},
	"energy_shielding": {"kinetic": [20.0, 0.5], "thermal": [20.0, 0.5], "explosive": [20.0, 0.5]},
}

static func get_material_threshold(material: String, damage_type: String, thickness: float) -> Vector2:
	var row = ARMOR_TABLE.get(material, ARMOR_TABLE["hardened_steel"])
	var pair = row.get(damage_type, row["explosive"])
	return Vector2(pair[0] * thickness, pair[1])

# Resolves the full threshold/reduction pair for a hit, given the hull's
# baseline material+thickness plus any placed armor modules. active_modules
# is the list of module nodes with module_data meta (from get_active_modules()).
#
# defender + hit_origin (both optional) enable directional resolution: if
# both are given, only the armor module covering the FACET actually facing
# the attacker matters - armor on the far side of the hull no longer helps.
# If that module has its own material choice (phase 3 - a plate can be
# reactive on the front and ablative on the sides), that material REPLACES
# the hull baseline for this hit, since the attack strikes the plate, not
# the bare hull under it. Omitting either defender or hit_origin falls back
# to the old aggregate-everything-against-the-hull-baseline behavior
# (AoE, or callers that don't have direction info).
static func resolve(hull: Node3D, active_modules: Array, damage_type: String, defender: Node3D = null, hit_origin = null) -> Vector2:
	var hull_mat = "hardened_steel"
	var hull_thick = 1.0
	if is_instance_valid(hull) and hull.has_meta("armor_material") and hull.has_meta("armor_thickness"):
		hull_mat = hull.get_meta("armor_material")
		hull_thick = hull.get_meta("armor_thickness")
	var baseline = get_material_threshold(hull_mat, damage_type, hull_thick)
	var threshold = baseline.x
	var reduction = baseline.y

	var hit_facet = ""
	if defender != null and hit_origin != null:
		var local_dir = defender.global_transform.basis.inverse() * ((hit_origin as Vector3) - defender.global_position)
		hit_facet = ModuleCatalogScript.classify_facet(local_dir)

	if hit_facet != "":
		for m in active_modules:
			var m_data = m.get_meta("module_data")
			if m_data and m_data.category == "armor" and m.get_meta("facet", "") == hit_facet:
				var plate_material = m_data.tweaks.get("material", "") if "tweaks" in m_data else ""
				if plate_material != "":
					var plate_t = get_material_threshold(plate_material, damage_type, 1.0)
					threshold = plate_t.x
					reduction = plate_t.y
				threshold += m_data.get_hp() * 0.1
				if plate_material == "":
					reduction = clamp(reduction * 0.9, 0.2, 1.0)
				break # a facet only ever has one plate (see mirror-centering skip logic)
	else:
		var armor_module_hp = 0.0
		for m in active_modules:
			var m_data = m.get_meta("module_data")
			if m_data and m_data.category == "armor":
				armor_module_hp += m_data.get_hp()
		if armor_module_hp > 0.0:
			threshold += armor_module_hp * 0.1
			reduction = clamp(reduction * 0.9, 0.2, 1.0)

	return Vector2(threshold, reduction)
