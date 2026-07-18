class_name DamageResolver
# Shared armor/threshold resolution for battle_unit.gd (Skirmish),
# player_vehicle.gd (Test Range), and building.gd (defense structures).
# Previously this math was duplicated inline across all three and already
# drifted once (had to be manually kept in sync when the armor-module bonus
# was added) - single source of truth from here on. See DECISIONS_NEEDED.md
# for the phased directional-armor build-out plan this is part of.

const ModuleCatalogScript = preload("res://scripts/module_catalog.gd")

# Elevation combat advantage (multi-map pass): shooting down at a target on
# meaningfully lower ground pierces more easily - real armor doesn't
# protect top-down as well as face-on, and it gives holding a hill a real
# combat payoff on top of the vision bonus (skirmish.gd's
# _recalc_fog_of_war()). Threshold-based (lowers how much armor blocks
# entirely), not a flat damage multiplier, so it composes with everything
# else resolve() already does. Reads directly off hit_origin/defender's
# real Y coordinates - no map/zone awareness needed here, since
# terrain_builder.gd's terrain_height_at() is the only place elevation Y
# ever gets set in the first place.
const ELEVATION_COMBAT_THRESHOLD: float = 2.0
const ELEVATION_COMBAT_PIERCE_MULTIPLIER: float = 0.85

# damage_type -> [base_threshold, reduction] per armor material.
#
# "energy" row added this pass (ENERGY_AND_BALANCE_SPEC.md #4 follow-up):
# previously there was no "energy" key at all, so any weapon dealing
# damage_class=="energy" (tesla_coil/arc_projector/ion_cannon) silently fell
# through get_material_threshold()'s row.get(damage_type, row["explosive"])
# fallback and actually resolved as EXPLOSIVE damage - a real bug, not just
# a missing feature, found while scoping the energy-weapon-reclassification
# work. energy_shielding gets a genuinely strong energy threshold (its own
# name is the thematic justification); hardened_steel/reactive_armor are
# weak against it (plate steel and reactive plates don't stop directed
# energy); ablative_ceramic is moderate (ablative/heat-resistant materials
# have some real answer to it, just not a dedicated one).
const ARMOR_TABLE = {
	"hardened_steel": {"kinetic": [15.0, 0.7], "thermal": [5.0, 0.9], "explosive": [10.0, 0.8], "energy": [8.0, 0.85]},
	"reactive_armor": {"kinetic": [10.0, 0.8], "thermal": [10.0, 0.8], "explosive": [30.0, 0.4], "energy": [8.0, 0.85]},
	"ablative_ceramic": {"kinetic": [8.0, 0.9], "thermal": [25.0, 0.3], "explosive": [10.0, 0.7], "energy": [15.0, 0.6]},
	"energy_shielding": {"kinetic": [20.0, 0.5], "thermal": [20.0, 0.5], "explosive": [20.0, 0.5], "energy": [35.0, 0.3]},
}

# --- Hit damage math (FABLE_REVIEW.md 1.1 / 3.6 / 2.5) ---
# Shared by battle_unit.gd / player_vehicle.gd / building.gd so the three
# take_damage() implementations can't drift (same reason resolve() exists).
#
# CHIP_THROUGH_FACTOR: a hit below the armor threshold is no longer fully
# negated - it deals a small "chip" fraction of its post-reduction damage.
# This is the fix for the review's headline finding: per-shot damage is
# dps*fire_rate, so every rapid-fire weapon (rotary/HMG/CIWS/laser/flamer)
# landed under every real threshold and dealt literally zero damage to any
# armored hull, deleting the whole sustained-fire archetype. At 0.15, armor
# still blanks ~90% of sub-threshold fire (thresholds remain the dominant
# mechanic and heavy alpha still rules head-on), but massed small guns now
# grind - the Damage_And_Armor_Model.md action-economy counter actually
# exists.
const CHIP_THROUGH_FACTOR: float = 0.15
# Brute Force Rule (Damage_And_Armor_Model.md, documented since the start
# but never implemented): an overwhelmingly large hit "punches straight
# through the mitigation multipliers." From BRUTE_FORCE_RATIO x threshold
# upward, the reduction multiplier blends linearly toward 1.0 (full damage),
# reaching at most BRUTE_FORCE_MAX_BLEND of the way there at 2x that ratio.
const BRUTE_FORCE_RATIO: float = 4.0
const BRUTE_FORCE_MAX_BLEND: float = 0.75
# Subsystem strips deal a fraction of the raw hit instead of the old flat
# `amount - 5.0` (which rounded rapid-fire strip damage to zero and made the
# doc's "swarms strip exposed modules" counter impossible). Modules stay
# threshold-exempt - they're exposed hardware, that's the whole point.
const MODULE_STRIP_DAMAGE_FACTOR: float = 0.75

static func compute_hull_damage(amount: float, threshold: float, reduction: float) -> float:
	if threshold > 0.0 and amount < threshold:
		return amount * reduction * CHIP_THROUGH_FACTOR
	var eff_reduction = reduction
	if threshold > 0.0 and amount >= threshold * BRUTE_FORCE_RATIO:
		var brute_t = clamp((amount / threshold - BRUTE_FORCE_RATIO) / BRUTE_FORCE_RATIO, 0.0, 1.0)
		eff_reduction = lerpf(reduction, 1.0, brute_t * BRUTE_FORCE_MAX_BLEND)
	return amount * eff_reduction

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

		# Phase 4: true angle-of-incidence sloped armor. A shot that grazes
		# the surface at a shallow angle is more survivable than one that
		# hits square-on (real tank-armor ballistics) - multiplies
		# threshold, since slope is about whether the hit penetrates at
		# all, not how much of the damage that does get through is
		# mitigated (that's what `reduction` represents).
		threshold *= compute_slope_multiplier(defender, hit_origin as Vector3)
	else:
		var armor_module_hp = 0.0
		for m in active_modules:
			var m_data = m.get_meta("module_data")
			if m_data and m_data.category == "armor":
				armor_module_hp += m_data.get_hp()
		if armor_module_hp > 0.0:
			threshold += armor_module_hp * 0.1
			reduction = clamp(reduction * 0.9, 0.2, 1.0)

	if defender != null and hit_origin != null:
		var height_advantage = (hit_origin as Vector3).y - defender.global_position.y
		if height_advantage >= ELEVATION_COMBAT_THRESHOLD:
			threshold *= ELEVATION_COMBAT_PIERCE_MULTIPLIER

	return Vector2(threshold, reduction)

# Real raycast from the attacker to the defender's hull, reading the actual
# surface normal at impact - not an analytical shortcut off the facet's
# canonical axis. This matters because hull placement/collision is
# currently a single BoxShape3D (see MOUNTING_AND_ARMOR_SPEC.md's "Known
# architecture constraint"), so today this produces the same result as the
# canonical-normal shortcut would - but a real raycast against the hull's
# actual collision geometry means this starts reflecting true sloped
# surfaces automatically the moment hull collision becomes mesh-accurate,
# with no changes needed here. Effective thickness = base / cos(angle),
# the standard sloped-armor formula; clamped so a razor-thin grazing angle
# doesn't produce an absurd multiplier.
static func compute_slope_multiplier(defender: Node3D, hit_origin: Vector3) -> float:
	if not is_instance_valid(defender):
		return 1.0
	var world = defender.get_world_3d()
	if not world:
		return 1.0
	var space_state = world.direct_space_state
	var target_point = defender.global_position + Vector3(0, 0.1, 0)
	var query = PhysicsRayQueryParameters3D.create(hit_origin, target_point)
	query.collision_mask = 1 # Hull layer
	var result = space_state.intersect_ray(query)
	if result.is_empty() or not result.has("normal"):
		return 1.0
	var incoming_dir = (target_point - hit_origin).normalized()
	var hit_normal = result.normal as Vector3
	var cos_angle = clamp(abs(hit_normal.dot(-incoming_dir)), 0.15, 1.0)
	return 1.0 / cos_angle
