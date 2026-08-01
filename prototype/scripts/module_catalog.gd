class_name ModuleCatalog

const HullLoader = preload("res://scripts/hull_loader.gd")
const GlobalConfigScript = preload("res://scripts/global_config.gd")

# --- Hull-level derived stats (FABLE_REVIEW.md 1.2 / 1.3 / 2.6) ---
# Single source of truth for what a hull's armor material, thickness slider,
# and scale handles actually DO - shared by combat (battle_unit/building),
# the economy (skirmish.blueprint_cost), and the Design Lab sidebar
# (stat_calculator), so the number a player sees is the number the sim uses.
# Before this, material/thickness multiplied HP for free (no cost, no combat
# weight - the weight increase existed only in the sidebar display) and
# hull_scale affected nothing but mounting area - both were solved dominant
# choices, the exact Forged-Battalion failure DESIGN_VISION.md warns about.

const ARMOR_MATERIAL_HP_MULT = {
	"hardened_steel": 1.0, "reactive_armor": 1.3, "ablative_ceramic": 1.6, "energy_shielding": 2.0,
}
const ARMOR_MATERIAL_WEIGHT_MULT = {
	"hardened_steel": 1.0, "reactive_armor": 1.2, "ablative_ceramic": 0.9, "energy_shielding": 0.5,
}
# Per-material cost multipliers - the advanced materials finally have a
# price. energy_shielding is deliberately crystal-hungry (3x): it keeps the
# best HP-per-weight in the roster, but now bottlenecks the scarcer
# resource instead of being a free strict upgrade.
const ARMOR_MATERIAL_COST_MULT = {
	"hardened_steel": {"metal": 1.0, "crystal": 1.0},
	"reactive_armor": {"metal": 1.3, "crystal": 1.6},
	"ablative_ceramic": {"metal": 1.25, "crystal": 1.9},
	"energy_shielding": {"metal": 1.5, "crystal": 3.0},
}

# Hull scale handle bounds (per axis). RTS_Unit_Designer_Concept.md always
# specced bounded scaling ("the size class dictates the upper and lower
# bounds of this scaling") - the gizmo previously only clamped the low end,
# so an unbounded max-size hull was free mounting real estate.
const HULL_SCALE_MIN: float = 0.5
const HULL_SCALE_MAX: float = 2.0

static func get_hull_volume_factor(hull_scale: Vector3) -> float:
	return hull_scale.x * hull_scale.y * hull_scale.z

# Sub-linear volume scaling, same GlobalConfig factors modules already use -
# a 2x-per-axis hull (8x volume) gets ~6.6x HP, ~8x weight, ~7.3x cost.
static func _volume_scaled(base: float, hull_scale: Vector3, factor: float) -> float:
	var v = get_hull_volume_factor(hull_scale)
	return base + base * (v - 1.0) * factor

# Armor mass model: roughly half a hull's mass is structure (unaffected by
# the armor sliders), half is armor (scales with thickness x material
# density, and is what the Industrialists' armor_weight_mult discounts).
static func compute_hull_max_hp(hull_type_id: String, thickness: float, material: String, hull_scale: Vector3 = Vector3.ONE) -> float:
	var base = get_module_data(hull_type_id).get("hp", 400.0)
	var hp_mult = ARMOR_MATERIAL_HP_MULT.get(material, 1.0)
	return _volume_scaled(base, hull_scale, GlobalConfigScript.hp_scale_factor) * thickness * hp_mult

static func compute_hull_weight(hull_type_id: String, thickness: float, material: String, hull_scale: Vector3 = Vector3.ONE, armor_weight_mult: float = 1.0) -> float:
	var base = get_module_data(hull_type_id).get("weight", 250.0)
	var wt_mult = ARMOR_MATERIAL_WEIGHT_MULT.get(material, 1.0)
	var armor_fraction = 0.5 + 0.5 * thickness * wt_mult * armor_weight_mult
	return _volume_scaled(base, hull_scale, GlobalConfigScript.weight_scale_factor) * armor_fraction

# Armor cost curve is deliberately SUPERLINEAR in thickness (t^1.5): each
# extra point of threshold/HP costs more than the last, so "max the slider"
# stops being the automatic answer (Damage_And_Armor_Model.md's own
# "drastically adding to weight and resource cost", implemented at last).
static func compute_hull_cost(hull_type_id: String, thickness: float, material: String, hull_scale: Vector3 = Vector3.ONE) -> Vector2i:
	var data = get_module_data(hull_type_id)
	var mat_mult = ARMOR_MATERIAL_COST_MULT.get(material, ARMOR_MATERIAL_COST_MULT["hardened_steel"])
	var armor_curve = 0.5 + 0.5 * pow(max(thickness, 0.0), 1.5)
	var m = _volume_scaled(float(data.get("metal", 100)), hull_scale, GlobalConfigScript.cost_scale_factor)
	var c = _volume_scaled(float(data.get("crystal", 0)), hull_scale, GlobalConfigScript.cost_scale_factor)
	m *= 0.5 + 0.5 * armor_curve * mat_mult.metal
	c *= 0.5 + 0.5 * armor_curve * mat_mult.crystal
	return Vector2i(int(round(m)), int(round(c)))

# Merged catalog cache (FABLE_REVIEW.md 3.5): get_catalog() used to rebuild
# the entire ~60-entry dict literal on every call - and it's called from
# genuinely hot paths (per-hit damage resolution, per-tick terrain/draught
# lookups). Built once and reused; invalidated automatically whenever
# HullLoader's own cache is rebuilt (reset_cache_for_tests/rescan returns a
# NEW Dictionary instance, detected by identity below), so the hull-modding
# tests' reset flow keeps working unchanged. Callers must treat returned
# entries as read-only - they're shared, not copies (that was already true
# for hull entries before this change).
static var _catalog_cache: Dictionary = {}
static var _cached_hull_dict: Dictionary = {}

# Returns a dictionary containing all module types. Hull entries (category
# "hull") are no longer hardcoded here - see hull_loader.gd, which lazily
# scans same-stem .glb+.json pairs from res://assets/models/hulls (built-in)
# and user://mods/hulls (player-added mods) once and caches the result
# (HULL_MODDING_PLAN.md §3).
static func get_catalog() -> Dictionary:
	var hulls = HullLoader.get_hulls()
	if not _catalog_cache.is_empty() and is_same(hulls, _cached_hull_dict):
		return _catalog_cache
	var catalog = _build_catalog_literal()
	for hull_id in hulls:
		catalog[hull_id] = hulls[hull_id]
	_catalog_cache = catalog
	_cached_hull_dict = hulls
	return _catalog_cache

# Real existence check for any catalog entry (weapon/module/locomotion/hull),
# mirroring hull_exists() below - reconstruct_vehicle uses this to SKIP an
# unknown module type_id instead of get_module_data()'s silent
# basic_cannon-weapon-data fallback (FABLE_REVIEW.md 3.4).
static func module_exists(type_id: String) -> bool:
	return get_catalog().has(type_id)

# --- Weapon fire profiles (balance harness migration) ---
# fire_rate/fire_range/laser_color used to live in a ~120-line if/elif chain
# in auto_weapon.gd's _ready(), which made them invisible to every balance
# tool: balance_report.gd scored weapons on `dps` alone, and `dps` is the
# LEAST interesting of the three, because the armor system gates on PER-SHOT
# damage and per-shot damage is `dps * fire_rate` (see auto_weapon.gd's
# _deal_weapon_damage callers). A weapon's threshold behaviour is therefore
# driven mostly by fire_rate, which nothing could see or tune.
#
# Kept as ONE contiguous table rather than folded into each catalog entry
# specifically so tools/run_simulations.gd can rewrite it mechanically after
# a sweep - a 21-entry block is patchable, 21 edits scattered through a
# 1700-line dict literal are not.
#
# fire_rate is a shot INTERVAL in seconds (lower = faster), not shots/sec.
# Merged into the catalog entries by _build_catalog_literal() below, so
# `get_module_data(id).fire_rate` is the single source of truth.
const WEAPON_FIRE_PROFILES = {
	"basic_cannon":       {"fire_rate": 1.8,  "fire_range": 25.0, "laser_color": Color.ORANGE},
	# 0.22 -> 0.66 is the largest single change the balance sweep asked for,
	# and the one most likely to need a feel check: at 0.22s the HMG's
	# per-shot damage (dps * fire_rate) was ~5.5, permanently under every
	# real armor threshold, so it spent the whole game in CHIP_THROUGH_FACTOR
	# territory dealing 15% damage to anything armored. At 0.66s it clears
	# the lighter thresholds and becomes a real gun - but it also fires 3x
	# slower, which reads more like a light autocannon than a machine gun.
	"heavy_machine_gun":  {"fire_rate": 0.66, "fire_range": 15.0, "laser_color": Color.GOLD},
	"rotary_cannon":      {"fire_rate": 0.05, "fire_range": 20.0, "laser_color": Color.GOLD},
	"gauss_railgun":      {"fire_rate": 3.5,  "fire_range": 45.0, "laser_color": Color.BLUE_VIOLET},
	"artillery":          {"fire_rate": 4.5,  "fire_range": 50.0, "laser_color": Color.SADDLE_BROWN},
	"mortar_array":       {"fire_rate": 2.0,  "fire_range": 28.0, "laser_color": Color.OLIVE},
	"guided_missile":     {"fire_rate": 3.0,  "fire_range": 35.0, "laser_color": Color.YELLOW},
	"missile_pod":        {"fire_rate": 2.8,  "fire_range": 30.0, "laser_color": Color.DARK_ORANGE},
	"drone_carrier":      {"fire_rate": 5.0,  "fire_range": 30.0, "laser_color": Color.NAVY_BLUE},
	"cluster_dispenser":  {"fire_rate": 3.0,  "fire_range": 24.0, "laser_color": Color.CHOCOLATE},
	"flamethrower":       {"fire_rate": 0.06, "fire_range": 9.0,  "laser_color": Color.CRIMSON},
	"heavy_laser":        {"fire_rate": 0.05, "fire_range": 22.0, "laser_color": Color.DARK_RED},
	"plasma_lobber":      {"fire_rate": 2.2,  "fire_range": 24.0, "laser_color": Color.MEDIUM_SPRING_GREEN},
	"tesla_coil":         {"fire_rate": 1.4,  "fire_range": 14.0, "laser_color": Color.LIGHT_SKY_BLUE},
	"arc_projector":      {"fire_rate": 0.9,  "fire_range": 10.0, "laser_color": Color.CYAN},
	"ion_cannon":         {"fire_rate": 3.2,  "fire_range": 32.0, "laser_color": Color.SKY_BLUE},
	# Cone denial. Short interval and low per-shot on purpose: it is not
	# supposed to kill things, it is supposed to make their electronics stop
	# working, which it does through the energy drain rather than the damage.
	"microwave_emitter":  {"fire_rate": 0.35, "fire_range": 13.0, "laser_color": Color(0.95, 0.85, 0.45)},
	# The slowest cycle in the roster by a wide margin, and the biggest energy
	# bill. 120 dps at a 5.5s interval is 660 per shot - well past even the
	# anti-materiel rifle - but you only get it every five and a half seconds
	# and only if the capacitor is charged.
	"particle_lance":     {"fire_rate": 5.5,  "fire_range": 34.0, "laser_color": Color(0.70, 0.90, 1.0)},
	"ciws":               {"fire_rate": 0.06, "fire_range": 14.0, "laser_color": Color.WHITE_SMOKE},
	"pd_laser":           {"fire_rate": 0.1,  "fire_range": 16.0, "laser_color": Color.LIGHT_CORAL},
	"flak_cannon":        {"fire_rate": 1.2,  "fire_range": 22.0, "laser_color": Color.DARK_GOLDENROD},
	# --- Roster expansion ---
	# Belt-fed: fast for a grenade weapon, slow for an autogun.
	"mk19_grenade_launcher": {"fire_rate": 0.5, "fire_range": 22.0, "laser_color": Color(0.55, 0.62, 0.30)},
	# The slowest direct-fire cycle in the roster bar the ballista - one
	# enormous HEAT round, then a long, exposed reload.
	"recoilless_rifle":   {"fire_rate": 3.2,  "fire_range": 28.0, "laser_color": Color(1.0, 0.72, 0.35)},
	# Roughly half gauss_railgun's 3.5s cycle at a shorter reach - the
	# turreted, affordable hitscan option.
	"coil_gun":           {"fire_rate": 1.6,  "fire_range": 34.0, "laser_color": Color(0.55, 0.85, 1.0)},
	"autocannon":         {"fire_rate": 0.28, "fire_range": 18.0, "laser_color": Color.GOLDENROD},
	# The roster's only PRECISION weapon. Everything else is DPS or splash;
	# this one is a single very large per-shot number, which is the most
	# interesting place on the damage curve because per-shot damage
	# (dps * fire_rate) is exactly what the armor thresholds gate on. At a
	# 4.5s interval its 78 dps becomes 351 per shot - straight through every
	# armor threshold in the table, and utterly wasted on a scout it can only
	# hit once every four and a half seconds.
	"anti_materiel_rifle": {"fire_rate": 4.5, "fire_range": 36.0, "laser_color": Color(0.95, 0.92, 0.80)},
	"napalm_mortar":      {"fire_rate": 2.6,  "fire_range": 26.0, "laser_color": Color(1.0, 0.45, 0.1)},
	# Short "range" because it is not really shooting - it lobs a mine a
	# short way ahead and leaves it there.
	"mine_layer":         {"fire_rate": 3.5,  "fire_range": 12.0, "laser_color": Color(0.62, 0.56, 0.30)},
	# The slowest weapon in the game, by a distance. A torsion frame does
	# not cycle quickly.
	"ballista":           {"fire_rate": 4.0,  "fire_range": 26.0, "laser_color": Color(0.60, 0.46, 0.30)},
	# Short-ranged and quick-cycling: a discharger lays a screen right in
	# front of its own vehicle, it doesn't shell a distant position. dps is
	# 0.0 in the catalog and every round it fires is a zero-damage
	# obscurant, so fire_rate here is purely "how fast can it re-screen".
	"smoke_discharger":   {"fire_rate": 2.5,  "fire_range": 18.0, "laser_color": Color(0.72, 0.72, 0.74)},
	"resource_harvester": {"fire_rate": 0.1,  "fire_range": 15.0, "laser_color": Color.GOLD},
	"repair_array":       {"fire_rate": 0.15, "fire_range": 12.0, "laser_color": Color.CYAN},
}
# Matches the old chain's trailing `else:` branch - any weapon-ish entry with
# no profile row (including modded/hull-loaded ones) still gets sane values.
const DEFAULT_FIRE_PROFILE = {"fire_rate": 1.0, "fire_range": 15.0, "laser_color": Color.WHITE}

static func get_fire_profile(type_id: String) -> Dictionary:
	return WEAPON_FIRE_PROFILES.get(type_id, DEFAULT_FIRE_PROFILE)

static func _build_catalog_literal() -> Dictionary:
	var catalog = {
		# --- BALLISTIC & KINETIC ---
		"basic_cannon": {
			"name": "Main Cannon",
			"category": "weapon",
			"hp": 100.0,
			"weight": 80.0,
			"metal": 30,
			"crystal": 0,
			"dps": 40.0,
			# Baseline turret traverse - every other weapon's agility is
			# reasoned relative to this 1.0 anchor.
			"traverse_agility": 1.0,
			"size": Vector3(0.6, 0.6, 2.0),
			"color": Color.DIM_GRAY
		},
		"heavy_machine_gun": {
			"name": "Heavy Machine Gun",
			"category": "weapon",
			"hp": 60.0,
			"weight": 40.0,
			"metal": 15,
			"crystal": 0,
			"dps": 32.5,
			# Pintle-mount eligibility (MOUNTING_AND_ARMOR_SPEC.md #3 second
			# correction - see PINTLE_MIN_UP_ALIGNMENT_DEFAULT's comment): a
			# small, light, classic pintle weapon in real life - bolts onto
			# almost anything short of a genuinely vertical wall.
			"pintle_min_up_alignment": 0.15,
			# Small, light gun on a light mount - swings fast, same real-world
			# intuition as its pintle tolerance above.
			"traverse_agility": 1.3,
			"size": Vector3(0.3, 0.3, 1.0),
			"color": Color.SLATE_GRAY
		},
		"rotary_cannon": {
			"name": "Rotary Gatling",
			"category": "weapon",
			"hp": 80.0,
			"weight": 110.0,
			"metal": 45,
			"crystal": 5,
			"dps": 105.0,
			# Compact gatling housing, same "bolts on anywhere" logic as
			# heavy_machine_gun.
			"pintle_min_up_alignment": 0.15,
			# Motor-driven gatling on a powered gimbal - agile but not as
			# featherweight-quick as the single-barrel MG.
			"traverse_agility": 1.2,
			"size": Vector3(0.5, 0.5, 1.5),
			"color": Color(0.2, 0.2, 0.2) # Charcoal
		},
		"gauss_railgun": {
			"name": "Gauss Railgun",
			"category": "weapon",
			"hp": 120.0,
			"weight": 180.0,
			"metal": 80,
			"crystal": 40,
			"dps": 99.0,
			# Frame_built (see get_mount_style_for_normal below), so it never
			# independently traverses in practice - this number only matters
			# if that override is ever lifted, kept low for consistency with
			# its long rigid accelerator rail.
			"traverse_agility": 0.4,
			"size": Vector3(0.6, 0.6, 2.8),
			"color": Color.BLUE_VIOLET
		},

		# --- INDIRECT FIRE ---
		"artillery": {
			"name": "Artillery",
			"category": "weapon",
			"hp": 150.0,
			"weight": 250.0,
			"metal": 100,
			"crystal": 10,
			"dps": 90.0,
			# Frame_built like gauss_railgun - traverse is moot in practice,
			# a low number matches its bulky fixed-elevation mount either way.
			"traverse_agility": 0.4,
			"size": Vector3(1.8, 1.8, 6.4),
			"color": Color.SADDLE_BROWN
		},
		"mortar_array": {
			"name": "Mortar Array",
			"category": "weapon",
			"hp": 80.0,
			"weight": 90.0,
			"metal": 40,
			"crystal": 0,
			"dps": 50.0,
			# Indirect-fire arc trajectory is calculated off a baseline
			# elevation - a mortar bolted onto a steep slope would be lobbing
			# shells at an already-skewed angle before the tube even elevates,
			# so this wants a much closer-to-level base than a direct-fire gun.
			"pintle_min_up_alignment": 0.55,
			# Indirect-fire tube array - traverses slowly and deliberately,
			# same "needs a level, stable aim" character as its pintle stance.
			"traverse_agility": 0.5,
			"size": Vector3(1.2, 0.6, 1.2),
			"color": Color.OLIVE
		},

		# --- MISSILES & DRONES ---
		"guided_missile": {
			"name": "Guided Missile TOW",
			"category": "weapon",
			"hp": 70.0,
			"weight": 60.0,
			"metal": 30,
			"crystal": 15,
			"dps": 55.0,
			# A single-rail launcher whose own guidance corrects for a
			# less-than-level launch angle mid-flight, so it tolerates a
			# steeper mounting slope than an unguided arcing weapon would.
			"pintle_min_up_alignment": 0.25,
			# Self-correcting guidance means the launch rail doesn't need to
			# snap-track a moving target the way a direct-fire gun does.
			"traverse_agility": 0.9,
			"size": Vector3(0.6, 0.4, 1.6),
			"color": Color.GOLD
		},
		"missile_pod": {
			"name": "Swarm Missile Pod",
			"category": "weapon",
			"hp": 100.0,
			"weight": 150.0,
			"metal": 50,
			"crystal": 10,
			"dps": 72.0,
			# A boxy multi-tube launcher, unguided at launch (swarm-fire, not
			# precision-guided per shot) - wants a more level base than a
			# single guided missile does, but nowhere near as strict as a
			# mortar's ballistic-arc requirement.
			"pintle_min_up_alignment": 0.35,
			# Boxy multi-tube launcher, unguided at launch - needs to actually
			# aim the whole pod rather than let guidance correct after the
			# fact, so it traverses slower than the guided missiles above.
			"traverse_agility": 0.8,
			"size": Vector3(1.2, 0.8, 1.5),
			"color": Color.DARK_ORANGE
		},
		"drone_carrier": {
			"name": "Drone Carrier Bay",
			"category": "module",
			"hp": 250.0,
			"weight": 350.0,
			"metal": 180,
			"crystal": 90,
			"dps": 85.0,
			"size": Vector3(2.0, 1.2, 3.0),
			"color": Color.NAVY_BLUE
		},

		# --- AOE & AREA DENIAL ---
		"cluster_dispenser": {
			"name": "Cluster Dispenser",
			"category": "weapon",
			"hp": 90.0,
			"weight": 100.0,
			"metal": 45,
			"crystal": 10,
			"dps": 65.0,
			# Lobs submunitions in an area pattern - close enough to
			# mortar_array's ballistic-arc reasoning to want a fairly level
			# base, though the shorter lob range makes it a bit more
			# forgiving than a dedicated indirect-fire mortar.
			"pintle_min_up_alignment": 0.45,
			# Lobbing arc weapon like mortar_array/plasma_lobber, but a
			# shorter lob range makes it a bit less deliberate to aim.
			"traverse_agility": 0.6,
			"size": Vector3(1.4, 0.8, 1.4),
			"color": Color.CHOCOLATE
		},
		"flamethrower": {
			"name": "Flamethrower Emitter",
			"category": "weapon",
			"hp": 70.0,
			"weight": 50.0,
			# A hose-fed nozzle, not a rigid ballistic tube - shrugs off a
			# steep mounting angle same as the light autoguns.
			"pintle_min_up_alignment": 0.15,
			# A free-swinging hose, not a rigid barrel - whips onto a target
			# fast, forgiving of imprecise aim since it hits an area anyway.
			"traverse_agility": 1.25,
			# Balance pass: value/cost was 5.49 against a 2.86 category
			# average - cheap for its dps relative to comparable short-range
			# weapons (heavy_machine_gun aside, which is an intentionally
			# cheap starter weapon and left alone).
			"metal": 35,
			"crystal": 15,
			"dps": 112.0,
			"size": Vector3(0.5, 0.5, 1.6),
			"color": Color.CRIMSON
		},

		# --- ENERGY WEAPONS ---
		# "energy" damage_class weapons (ENERGY_AND_BALANCE_SPEC.md #4) - the
		# only weapons that cost the firing unit's own current_energy per
		# shot and, for tesla_coil/ion_cannon, also drain the TARGET's
		# energy pool alongside HP damage.
		"tesla_coil": {
			"name": "Tesla Coil",
			"category": "weapon",
			"hp": 70.0,
			"weight": 70.0,
			"metal": 40,
			"crystal": 45,
			"dps": 72.0,
			# Tall and top-heavy (size.y=1.6 vs a 0.6x0.6 footprint) - a real
			# structure this slender wants a level base to not look/feel like
			# it's about to topple, so it's less tolerant of a steep slope
			# than the compact autoguns.
			"pintle_min_up_alignment": 0.4,
			# Tall, top-heavy precision emitter - deliberate, controlled
			# traverse rather than a fast snap-track.
			"traverse_agility": 0.8,
			"size": Vector3(0.5, 1.2, 0.5),
			"color": Color.LIGHT_SKY_BLUE
		},
		"ion_cannon": {
			"name": "Ion Cannon",
			"category": "weapon",
			"hp": 130.0,
			"weight": 150.0,
			# The heaviest, longest energy weapon (2.6 long, 150kg) - wants a
			# more stable base than the compact energy emitters, similar
			# reasoning to the heavier kinetic guns.
			"pintle_min_up_alignment": 0.4,
			# Heaviest, longest energy weapon - a stable, deliberate-aim
			# platform rather than a fast tracker.
			"traverse_agility": 0.75,
			# Balance pass: was the single worst value/cost weapon in the
			# game (1.03 vs 2.86 average) even before accounting for its
			# energy-drain utility (which this cost-model can't see) - the
			# heavy crystal cost was double-counted against a flagship
			# "grounded energy heavy-hitter" that's supposed to be a real
			# alternative to gauss_railgun/plasma_lobber, not strictly worse.
			"metal": 70,
			"crystal": 65,
			"dps": 97.5,
			"size": Vector3(0.8, 0.8, 2.8),
			"color": Color.SKY_BLUE
		},
		# Activating a module that was already 80% built: fire profile, fire
		# function, energy-drain maths, tweak specs and an authored mesh all
		# existed, but with no catalog entry it could never be placed. The
		# dedicated disabler - trivial HP damage, enormous energy drain.
		"arc_projector": {
			"name": "Arc Projector",
			"category": "weapon",
			"hp": 70.0,
			"weight": 85.0,
			"metal": 24,
			"crystal": 26,
			"dps": 22.0,
			"energy_capacity": 0.0,
			"traverse_agility": 0.9,
			"size": Vector3(0.5, 0.5, 1.0),
			"color": Color(0.30, 0.40, 0.48)
		},

		# Area denial by cooking electronics. The counter to energy-hungry
		# designs specifically, which nothing else in the roster targets.
		"microwave_emitter": {
			"name": "Microwave Emitter",
			"category": "weapon",
			"hp": 65.0,
			"weight": 105.0,
			"metal": 30,
			"crystal": 32,
			"dps": 30.0,
			"traverse_agility": 0.75,
			"size": Vector3(0.7, 0.6, 0.9),
			"color": Color(0.52, 0.50, 0.42)
		},

		# Charge, then one devastating beam. The heaviest and most expensive
		# weapon in the roster, and the only one that can be caught mid-charge.
		"particle_lance": {
			"name": "Particle Lance",
			"category": "weapon",
			"hp": 90.0,
			"weight": 220.0,
			"metal": 60,
			"crystal": 55,
			"dps": 120.0,
			"traverse_agility": 0.45,
			"size": Vector3(0.6, 0.6, 2.4),
			"color": Color(0.34, 0.44, 0.52)
		},

		"heavy_laser": {
			"name": "Continuous Laser",
			"category": "weapon",
			"hp": 75.0,
			"weight": 60.0,
			"metal": 30,
			"crystal": 20,
			"dps": 112.0,
			# A precision continuous beam over a long (2.5) housing benefits
			# from a stable base for sustained aim - same logic as heavy_laser's
			# kinetic-precision cousins.
			"pintle_min_up_alignment": 0.4,
			# Continuous-beam precision weapon over a long housing - benefits
			# from a stable, deliberate traverse for sustained aim.
			"traverse_agility": 0.75,
			"size": Vector3(0.7, 0.7, 2.4),
			"color": Color.DARK_RED
		},
		"plasma_lobber": {
			"name": "Plasma Lobber",
			"category": "weapon",
			"hp": 110.0,
			"weight": 120.0,
			"metal": 50,
			"crystal": 60,
			"dps": 95.0,
			# "Lobber" is in the name - an arcing projectile weapon, same
			# ballistic-baseline reasoning as mortar_array/cluster_dispenser.
			"pintle_min_up_alignment": 0.5,
			# Arcing lob weapon, same slow-deliberate character as the
			# mortars/cluster_dispenser.
			"traverse_agility": 0.55,
			"size": Vector3(0.6, 0.6, 1.6),
			"color": Color.MEDIUM_SPRING_GREEN
		},

		# --- POINT DEFENSE ---
		"ciws": {
			"name": "CIWS Gatling PD",
			"category": "weapon",
			"hp": 80.0,
			"weight": 90.0,
			"metal": 40,
			"crystal": 15,
			"dps": 10.0, # Visual DPS low, specialized vs ammo
			# Real-world CIWS mounts are routinely bolted to steeply angled
			# deck/superstructure positions and still track fine - tolerant.
			"pintle_min_up_alignment": 0.15,
			# Point defense lives and dies by how fast it can snap onto a
			# small, fast-moving threat - the quickest traverse in the roster.
			"traverse_agility": 1.8,
			"size": Vector3(0.6, 0.8, 0.6),
			"color": Color.WHITE_SMOKE
		},
		"pd_laser": {
			"name": "Point Defense Laser",
			"category": "weapon",
			"hp": 50.0,
			"weight": 35.0,
			"metal": 20,
			"crystal": 30,
			# Small, light PD turret - tolerant like the other compact
			# point-defense/autogun weapons.
			"pintle_min_up_alignment": 0.15,
			# Small, light PD laser - the second-fastest tracker after CIWS,
			# same reflex-driven point-defense logic.
			"traverse_agility": 1.6,
			"dps": 5.0,
			"size": Vector3(0.4, 0.5, 0.4),
			"color": Color.LIGHT_CORAL
		},
		"flak_cannon": {
			"name": "Flak Cannon PD",
			"category": "weapon",
			"hp": 90.0,
			"weight": 110.0,
			"metal": 45,
			"crystal": 10,
			"dps": 15.0,
			# Bulkier than the other PD weapons (110kg, boxier housing) but
			# still an anti-air mount that needs to swing to steep elevations
			# routinely - moderate tolerance, between the light PD guns and
			# the heavier precision/ballistic weapons.
			"pintle_min_up_alignment": 0.3,
			# Bulkier than the other PD weapons but still needs to swing to
			# steep anti-air elevations routinely - fast, just not CIWS-fast.
			"traverse_agility": 1.4,
			"size": Vector3(0.525, 0.525, 1.35),
			"color": Color.DARK_GOLDENROD
		},

		# --- ROSTER EXPANSION: new base archetypes ---------------------------
		# Each of these fills a gap the existing roster genuinely had rather
		# than being a stat-shifted copy of something already present - the
		# "arsenal pool is incredibly WIDE" principle in
		# Arsenal_Weapons_List.md's own preamble.

		# The hole between mortar_array (slow, heavy, high arc) and
		# heavy_machine_gun (fast, flat, no splash): belt-fed rapid-fire
		# grenades. Small blast per round, but a lot of rounds.
		"mk19_grenade_launcher": {
			"name": "MK19 Grenade Launcher",
			"category": "weapon",
			"hp": 70.0,
			"weight": 55.0,
			"metal": 28,
			"crystal": 0,
			"dps": 58.0,
			# Belt-fed and shoulder-height in real life - a classic pintle
			# weapon, though its low arc wants a slightly better stance than
			# a pure flat-shooting autogun.
			"pintle_min_up_alignment": 0.3,
			"traverse_agility": 1.1,
			"size": Vector3(0.4, 0.4, 1.1),
			"color": Color(0.32, 0.36, 0.22)
		},

		# Huge per-shot HEAT damage on a light, cheap mount, paid for with a
		# brutal reload AND a genuine backblast danger zone behind the
		# weapon (see auto_weapon.gd's _fire_recoilless_rifle) - the first
		# weapon in the roster where WHERE you mount it has a real
		# mechanical consequence, not just an arc consequence.
		"recoilless_rifle": {
			"name": "Recoilless Rifle",
			"category": "weapon",
			"hp": 80.0,
			"weight": 70.0,
			"metal": 40,
			"crystal": 5,
			"dps": 85.0,
			"pintle_min_up_alignment": 0.25,
			"traverse_agility": 0.9,
			"size": Vector3(0.35, 0.35, 2.0),
			"color": Color(0.42, 0.40, 0.34)
		},

		# The sane sibling to gauss_railgun: genuinely turreted (pintle, not
		# frame_built), less per-shot punch, roughly twice the cycle rate,
		# and far cheaper on crystal. Gives a mid-tier design a way into
		# hitscan kinetic without committing a whole hull to a fixed rail.
		"coil_gun": {
			"name": "Coil Gun",
			"category": "weapon",
			"hp": 90.0,
			"weight": 120.0,
			"metal": 55,
			"crystal": 30,
			"dps": 88.0,
			"pintle_min_up_alignment": 0.3,
			"traverse_agility": 0.7,
			"size": Vector3(0.5, 0.5, 2.2),
			"color": Color(0.45, 0.62, 0.78)
		},

		# The missing rung between heavy_machine_gun and basic_cannon -
		# rapid enough to matter against light armor, with real per-shot
		# weight behind it.
		"autocannon": {
			"name": "Autocannon",
			"category": "weapon",
			"hp": 75.0,
			"weight": 65.0,
			"metal": 26,
			"crystal": 0,
			"dps": 62.0,
			"pintle_min_up_alignment": 0.15,
			"traverse_agility": 1.25,
			"size": Vector3(0.35, 0.35, 1.4),
			"color": Color(0.28, 0.30, 0.32)
		},

		# The roster had no precision weapon at all. Deliberately expensive
		# in crystal (that is the sensor package, not the gun) and slow to
		# traverse - it is an ambush/overwatch piece, not something you
		# swing onto a target that is already close.
		"anti_materiel_rifle": {
			"name": "Anti-Materiel Rifle",
			"category": "weapon",
			"hp": 60.0,
			"weight": 95.0,
			"metal": 34,
			"crystal": 18,
			"dps": 78.0,
			"pintle_min_up_alignment": 0.20,
			"traverse_agility": 0.55,
			"size": Vector3(0.4, 0.4, 2.2),
			"color": Color(0.24, 0.28, 0.26)
		},

		# Area denial by fire rather than by fragments: modest impact
		# damage, but it leaves a large, long-lived burning pool that
		# makes ground genuinely expensive to stand on.
		"napalm_mortar": {
			"name": "Napalm Mortar",
			"category": "weapon",
			"hp": 85.0,
			"weight": 95.0,
			"metal": 42,
			"crystal": 12,
			"dps": 45.0,
			# Arcing tube, same ballistic-baseline reasoning as mortar_array.
			"pintle_min_up_alignment": 0.55,
			"traverse_agility": 0.5,
			"size": Vector3(0.7, 0.6, 0.7),
			"color": Color(0.78, 0.35, 0.12)
		},

		# Nothing in the roster could HOLD ground - every weapon had to keep
		# shooting to keep denying space. Mines persist without the layer,
		# survive its death, and punish a chokepoint indefinitely.
		"mine_layer": {
			"name": "Mine Layer",
			"category": "weapon",
			"hp": 90.0,
			"weight": 85.0,
			"metal": 45,
			"crystal": 5,
			"dps": 40.0,
			"pintle_min_up_alignment": 0.4,
			"traverse_agility": 0.8,
			"size": Vector3(0.9, 0.5, 0.9),
			"color": Color(0.48, 0.44, 0.26)
		},

		# Straight-faced absurdity, exactly where VISUAL_ART_DIRECTION.md
		# says it belongs: a torsion-spring bolt thrower, bolted to a
		# machine that also mounts railguns. Mechanically it earns its
		# place - enormous per-shot kinetic damage (so it clears armor
		# thresholds outright rather than chipping) at almost no crystal
		# cost, paid for with the slowest cycle in the roster. The cheap
		# answer to heavy armor for a design that can't afford a railgun.
		"ballista": {
			"name": "Ballista",
			"category": "weapon",
			"hp": 110.0,
			"weight": 140.0,
			"metal": 35,
			"crystal": 0,
			"dps": 70.0,
			# A big timber-and-torsion frame - it needs a level, solid base
			# the way a mortar does, for much the same reason.
			"pintle_min_up_alignment": 0.5,
			"traverse_agility": 0.45,
			"size": Vector3(1.2, 0.9, 2.4),
			"color": Color(0.44, 0.33, 0.20)
		},

		# The dedicated obscurant launcher (complement to shell-based smoke -
		# see WEAPON_AMMO_OPTIONS). Categorised "weapon" so it gets
		# auto_weapon.gd's targeting/firing logic like every other launcher,
		# but its dps is a real 0.0: it cannot hurt anything, ever. Its whole
		# value is denying sightlines, which the LOS systems now honour.
		# Cheap, light and small enough to bolt onto a corner of anything.
		"smoke_discharger": {
			"name": "Smoke Discharger",
			"category": "weapon",
			"hp": 40.0,
			"weight": 30.0,
			"metal": 18,
			"crystal": 0,
			"dps": 0.0,
			# A cluster of stubby mortar tubes on a light bracket - the
			# classic hull-corner discharger, bolts onto almost anything.
			"pintle_min_up_alignment": 0.15,
			# Light, small, and aiming a cloud rather than a point target -
			# it only needs to be pointed roughly the right way.
			"traverse_agility": 1.35,
			"size": Vector3(0.5, 0.4, 0.5),
			"color": Color(0.55, 0.56, 0.58)
		},

		# --- UTILITY & SUPPORT ---
		"resource_harvester": {
			"name": "Resource Harvester",
			"category": "module",
			"hp": 150.0,
			"weight": 80.0,
			"metal": 100,
			"crystal": 50,
			"dps": 0.0,
			"size": Vector3(1.5, 1.0, 1.5),
			"color": Color.DARK_GOLDENROD
		},
		"repair_array": {
			"name": "Repair Welder Array",
			"category": "module",
			"hp": 100.0,
			"weight": 70.0,
			"metal": 40,
			"crystal": 20,
			# Real dps: 0.0 - repair_array deals no damage. Its heal-per-
			# second rate is its own dedicated "heal_rate" stat (see
			# module_data.gd's get_heal_rate()), not a reuse of dps, so it
			# no longer pollutes the Design Lab's "Total DPS" aggregate.
			# Previously reused dps as a stopgap - see DECISIONS_NEEDED.md
			# for that history.
			"dps": 0.0,
			"heal_rate": 30.0,
			"targets_allies": true,
			"size": Vector3(0.8, 0.8, 1.0),
			"color": Color.DARK_TURQUOISE
		},
		"sensor_suite": {
			"name": "Radar Mast Suite",
			"category": "module",
			"hp": 60.0,
			"weight": 50.0,
			"metal": 30,
			"crystal": 30,
			"dps": 0.0,
			# Fog-of-war (built this pass): "Pushes back fog of war...
			# Mast Height: Drastically increases line-of-sight"
			# (Arsenal_Weapons_List.md) - previously stat-only cosmetic
			# flavor text with no actual vision system behind it. Scales
			# with the existing mast_height tweak in get_vision_bonus().
			"vision_bonus": 25.0,
			"size": Vector3(0.5, 2.5, 0.5),
			"color": Color.MEDIUM_PURPLE
		},

		"armor_plating": {
			"name": "Armor Plating",
			"category": "armor",
			"hp": 500.0,
			"weight": 100.0,
			"metal": 50,
			"crystal": 0,
			"dps": 0.0,
			"size": Vector3(2.0, 0.2, 2.0),
			"color": Color.SLATE_GRAY
		},

		# --- GENERATORS (Energy resource, ENERGY_AND_BALANCE_SPEC.md #1) ---
		# "generator" is its own module category, not a weapon/utility
		# variant - it contributes to a unit's max_energy (and a bit of
		# energy_regen) exactly like armor contributes to a facet's
		# threshold: a placeable design choice, not a fixed hull number.
		"fusion_generator": {
			"name": "Fusion Generator",
			"category": "generator",
			"hp": 140.0,
			"weight": 160.0,
			"metal": 90,
			"crystal": 60,
			"dps": 0.0,
			"energy_capacity": 60.0,
			"energy_regen": 8.0,
			"size": Vector3(1.4, 1.2, 1.8),
			"color": Color.ORANGE_RED
		},
		"capacitor_bank": {
			"name": "Capacitor Bank",
			"category": "generator",
			"hp": 60.0,
			"weight": 50.0,
			"metal": 35,
			"crystal": 25,
			"dps": 0.0,
			"energy_capacity": 25.0,
			"energy_regen": 4.0,
			"size": Vector3(0.8, 0.8, 1.0),
			"color": Color.GOLD
		},

		# --- LOCOMOTION ARCHETYPES ---
		"wheels": {
			"name": "Wheels",
			"category": "locomotion",
			"hp": 100.0,
			"weight": 50.0,
			"metal": 20,
			"crystal": 0,
			"dps": 0.0,
			# Weight capacity (task: "weight in excess of what a locomotor is
			# built for slows the unit down" - see get_base_weight_capacity()
			# below): a light, high-speed wheeled chassis handles poorly
			# overloaded - a real overloaded car sags and struggles - so this
			# tolerates less excess weight than the heavier ground types.
			"base_weight_capacity": 350.0,
			"size": Vector3(0.6, 0.6, 0.6),
			"color": Color.BLACK,
			"traits": ["ground_contact", "high_speed"]
		},
		"tracked_treads": {
			"name": "Tracked Treads",
			"category": "locomotion",
			"hp": 200.0,
			"weight": 120.0,
			"metal": 40,
			"crystal": 0,
			"dps": 0.0,
			# Heaviest, toughest ground locomotor - literally what tanks use
			# to carry heavy armor. Highest ground-type capacity.
			"base_weight_capacity": 700.0,
			"size": Vector3(0.8, 0.6, 2.5),
			"color": Color.DARK_OLIVE_GREEN,
			"traits": ["ground_contact"]
		},
		"helicopter_rotors": {
			"name": "Helicopter Rotors",
			"category": "locomotion",
			"hp": 30.0,
			"weight": 30.0,
			"metal": 30,
			"crystal": 10,
			"dps": 0.0,
			# Real helicopters have a notoriously strict max-takeoff-weight -
			# rotary lift is the most weight-sensitive locomotion in the
			# roster, so this gets the lowest capacity of all.
			"base_weight_capacity": 250.0,
			"size": Vector3(4.0, 0.2, 4.0),
			"color": Color.SILVER,
			"traits": ["airborne", "rotary_wing", "hovering"]
		},
		"hover_engine": {
			"name": "Hover Pad",
			"category": "locomotion",
			"hp": 50.0,
			"weight": 20.0,
			"metal": 20,
			"crystal": 40,
			"dps": 0.0,
			# Ground-effect lift is weight-sensitive like a real hovercraft,
			# though less extreme than a helicopter's rotor lift.
			"base_weight_capacity": 300.0,
			"size": Vector3(1.2, 0.3, 1.2),
			"color": Color.CYAN,
			"traits": ["hovering"]
		},
		"legs": {
			"name": "Mechanical Legs",
			"category": "locomotion",
			"hp": 120.0,
			"weight": 80.0,
			"metal": 40,
			"crystal": 10,
			"dps": 0.0,
			# A mech walker's legs are built to bear real structural load,
			# closer to tracked_treads than to a wheeled chassis.
			"base_weight_capacity": 500.0,
			"size": Vector3(0.5, 1.5, 0.5),
			"color": Color.DARK_RED,
			"traits": ["ground_contact"]
		},
		"fixed_wing_engine": {
			"name": "Fixed-Wing Engine",
			"category": "locomotion",
			"hp": 70.0,
			"weight": 60.0,
			"metal": 60,
			"crystal": 20,
			"dps": 0.0,
			# Fixed-wing lift scales with airspeed and wing area, giving it
			# more payload tolerance than rotary/hover lift, but it's still
			# a real aircraft weight budget, not a grounded vehicle's.
			"base_weight_capacity": 380.0,
			"size": Vector3(1.0, 0.5, 1.5),
			"color": Color.SLATE_BLUE,
			"traits": ["airborne", "fixed_wing", "high_speed"]
		},
		"ornithopter_wing": {
			"name": "Ornithopter Wing",
			"category": "locomotion",
			# Batch E task 3: a genuinely different airborne flavor -
			# flapping motion instead of a spinning prop/jet (fixed_wing_
			# engine) or a lighter-than-air gasbag (buoyant_envelope). Still
			# no aerodynamic lift simulation (standing rule) - mechanically
			# it's a simple hover-capable flier like helicopter_rotors/
			# hover_engine/anti_grav (deliberately NOT given the "fixed_wing"
			# trait, so it skips the banking/minimum-airspeed movement
			# paradigm and just arrives-and-stops like the rest of that
			# group) - the differentiation here is visual/flavor, per
			# Chris's explicit framing of this task, not a new physics model.
			"hp": 65.0,
			"weight": 55.0,
			"metal": 45,
			"crystal": 25,
			"dps": 0.0,
			# Between helicopter_rotors' strict hover-lift budget (250) and
			# fixed_wing_engine's generous airspeed-assisted one (380) - a
			# flapping wing generates real lift like a fixed wing, but not
			# as efficiently as one built for sustained forward flight.
			"base_weight_capacity": 300.0,
			"thrust_coefficient": 120.0,
			"size": Vector3(2.0, 0.2, 1.0),
			"color": Color(0.42, 0.32, 0.22),
			"traits": ["airborne", "flapping_wing"]
		},
		"naval_propeller": {
			"name": "Naval Propeller",
			"category": "locomotion",
			"hp": 90.0,
			"weight": 70.0,
			"metal": 35,
			"crystal": 0,
			"dps": 0.0,
			# Buoyancy carries the load, not the propeller - real ships
			# routinely carry far more weight than any ground/air vehicle.
			# Highest capacity in the roster.
			"base_weight_capacity": 800.0,
			"size": Vector3(0.5, 0.5, 0.8),
			"color": Color.TEAL,
			"traits": ["buoyant", "naval"]
		},
		"buoyant_envelope": {
			"name": "Buoyant Envelope Drive",
			"category": "locomotion",
			# Airship judgment call (see DECISIONS_NEEDED.md): a rigid
			# airship's lift comes from displacing air with a lighter-than-
			# air gasbag, not from a propeller/engine actively fighting
			# gravity like every other airborne locomotion type - so it
			# gets its own distinct locomotion flavor rather than reusing
			# fixed_wing_engine, specifically so that distinction can show
			# up in the two systems that just got built to care about it:
			# a very high base_weight_capacity (buoyancy scales generously
			# with envelope size, so it can carry proportionally far more
			# before the overload penalty) and a low thrust_coefficient
			# (small cruise/steering motors only - lift is free, so it
			# never needed big engines, and it's slow as a direct
			# consequence, not a hand-tuned speed stat).
			"hp": 40.0,
			"weight": 35.0,
			"metal": 25,
			"crystal": 15,
			"dps": 0.0,
			"base_weight_capacity": 1100.0,
			"thrust_coefficient": 55.0,
			"size": Vector3(1.0, 0.5, 1.0),
			"color": Color(0.75, 0.72, 0.6),
			"traits": ["airborne", "buoyant"]
		},
		"screw_drive": {
			"name": "Amphibious Screw Drive",
			"category": "locomotion",
			# Real historical "screw-propelled vehicle" (SPV) locomotion -
			# Soviet ZIL screw-drive trucks, the Fordson "Snow Devil" - twin
			# helical auger drums replace wheels/tracks entirely, letting
			# the vehicle churn through mud, snow, swamp, AND open water
			# using the exact same drums. Genuinely amphibious per the
			# no-hard-gating trait philosophy: carries BOTH "ground_contact"
			# (it drives on land like any tracked vehicle) and "amphibious"
			# (it also crosses water - routed onto a real combined
			# ground+water navmesh, see terrain_builder.gd's
			# build_navmeshes()/skirmish.gd's get_amphibious_nav_map()).
			# Slower and heavier than plain tracked_treads (churning
			# through mud/water is not a speed proposition) but tolerates
			# real payload like a tracked vehicle would.
			"hp": 160.0,
			"weight": 150.0,
			"metal": 55,
			"crystal": 15,
			"dps": 0.0,
			"base_weight_capacity": 600.0,
			"thrust_coefficient": 110.0,
			"size": Vector3(0.8, 0.8, 3.0),
			"color": Color(0.32, 0.3, 0.24),
			"traits": ["ground_contact", "amphibious"]
		},

		# --- STRUCTURAL PIECES (hull-space extenders) ---------------------------
		# Modules that provide attachment surfaces for other modules. Placed on
		# the hull (or on another structural piece), they carry their own
		# collision body on layer 16 (SURFACE_COLLISION_LAYER) so the
		# placement raycast can snap new modules onto them — effectively
		# extending the mounting area outward from the hull. They contribute no
		# special combat stats but do have weight and cost, so there's a
		# meaningful tradeoff: heavier-than-air vehicles in particular lose
		# payload capacity to structural over-extension.
		"structural_block": {
			"name": "Structure Block",
			"category": "structural",
			"hp": 200.0, "weight": 80.0,
			"metal": 20, "crystal": 0, "dps": 0.0,
			"size": Vector3(2.0, 2.0, 2.0),
			"color": Color(0.35, 0.30, 0.25),
			"hull": true
		},
		"structural_dome": {
			"name": "Dome Turret Base",
			"category": "structural",
			"hp": 150.0, "weight": 60.0,
			"metal": 15, "crystal": 5, "dps": 0.0,
			"size": Vector3(2.5, 1.5, 2.5),
			"color": Color(0.42, 0.36, 0.30),
			"hull": true
		},
		"structural_slab": {
			"name": "Armor Slab",
			"category": "structural",
			"hp": 300.0, "weight": 120.0,
			"metal": 30, "crystal": 0, "dps": 0.0,
			"size": Vector3(3.0, 0.5, 2.0),
			"color": Color(0.32, 0.28, 0.25),
			"hull": true
		},
		"structural_wedge": {
			"name": "Wedge Breech",
			"category": "structural",
			"hp": 180.0, "weight": 70.0,
			"metal": 25, "crystal": 0, "dps": 0.0,
			"size": Vector3(2.0, 1.0, 3.0),
			"color": Color(0.38, 0.32, 0.28),
			"hull": true
		},
		"structural_girder": {
			"name": "Support Girder",
			"category": "structural",
			"hp": 100.0, "weight": 40.0,
			"metal": 10, "crystal": 0, "dps": 0.0,
			"size": Vector3(0.4, 0.4, 4.0),
			"color": Color(0.30, 0.28, 0.22),
			"hull": true
		},
		"structural_i_beam": {
			"name": "I-Beam Frame",
			"category": "structural",
			"hp": 120.0, "weight": 50.0,
			"metal": 15, "crystal": 0, "dps": 0.0,
			"size": Vector3(0.6, 0.6, 4.0),
			"color": Color(0.33, 0.30, 0.25),
			"hull": true
		},
	}

	# Fold the fire profiles in so `get_module_data(id).fire_rate` works
	# everywhere - see WEAPON_FIRE_PROFILES for why they're authored as a
	# separate table instead of inline in each entry above.
	for profile_id in WEAPON_FIRE_PROFILES:
		if catalog.has(profile_id):
			for k in WEAPON_FIRE_PROFILES[profile_id]:
				catalog[profile_id][k] = WEAPON_FIRE_PROFILES[profile_id][k]

	return catalog

# --- Flavor text (VISUAL_ART_DIRECTION.md 1.2) ---
# The art doc restricts "where goofy lives" to DETAIL SCALE only, never
# silhouette or color-blocking. Copy is the cheapest detail-scale channel in
# the project - it costs no art production and no shader work - so the tone
# target (straight-faced military-industrial surface, cartoon absurdity
# underneath, per Chris's Starship Troopers / Tremors reference) lands here
# first, ahead of the decal atlas that will eventually carry the same voice
# visually.
#
# Voice rules, so this stays consistent as modules get added:
#  - Written as procurement/field-manual copy by someone with no sense of
#    humor about their job. The joke is never acknowledged by the writer.
#  - The absurdity is a FACT stated flatly, not a punchline ("rated for
#    continuous fire well past the point the crew compartment is habitable"),
#    never a wink at the player.
#  - Bureaucratic register: ratings, clearances, advisories, revisions,
#    liability-shaped hedging. Passive voice is correct here.
#  - One line, roughly <90 chars so the tooltip card doesn't reflow.
#
# Kept as a separate keyed block rather than a "flavor" key inside each of
# the 40 catalog literals above: one contiguous, reviewable place to tune
# voice, and it can't perturb the stat data the sim reads.
const MODULE_FLAVOR = {
	# Ballistic
	"basic_cannon": "Standard issue. Accurate, dependable, and entirely unremarkable in every after-action report.",
	"heavy_machine_gun": "Suppression rated. Barrel life is measured in engagements, not rounds. Spares are your problem.",
	"rotary_cannon": "Sustained fire well past the point the crew compartment remains habitable.",
	"gauss_railgun": "Capacitor discharge may interfere with nearby avionics, radios, and crew fillings.",
	"artillery": "Indirect fire. Observer required. Do not attempt to observe from the impact area.",
	"mortar_array": "Cheap, arcing, and imprecise. Effectiveness scales with quantity rather than skill.",
	# Guided
	"guided_missile": "Operator must maintain line of sight until impact. Operator discomfort is anticipated.",
	"missile_pod": "Fires everything at once. There is no partial-salvo setting. This was a design decision.",
	"drone_carrier": "Drones are considered expendable. Recovery is not a supported operation.",
	"cluster_dispenser": "Wide dispersal pattern. Confirm no friendly units are downrange, or thereabouts.",
	# Energy / exotic
	"flamethrower": "Short range by design. Crews are advised to be certain about wind direction.",
	"tesla_coil": "Arcs to the nearest conductive mass, which is not always the intended target.",
	"ion_cannon": "Draws heavily from base power. Scheduling with the generator crew is recommended.",
	"heavy_laser": "Continuous beam. Performance degrades in dust, smoke, rain, and general atmosphere.",
	"arc_projector": "Empties capacitors at range. Does almost no damage and is almost never forgiven.",
	"microwave_emitter": "Cooks electronics through armour. Crews report the taste of metal beforehand.",
	"particle_lance": "Five seconds of charging for one second of consequence. Do not be interrupted.",
	"plasma_lobber": "Containment is temporary by design. Everything downrange is briefly reclassified.",
	# Point defense
	"ciws": "Engages incoming ordnance automatically. Do not walk in front of it while powered.",
	"pd_laser": "Silent, precise, and invisible. Confirming that it is working is an ongoing challenge.",
	"flak_cannon": "Fills the sky with fragments. Aircraft are discouraged from entering that sky.",
	"smoke_discharger": "Produces concealment. Conceals friendly and hostile forces with equal diligence.",
	# Roster expansion
	"mk19_grenade_launcher": "Belt-fed grenades. Sustained fire is possible. Sustained resupply is not.",
	"recoilless_rifle": "Recoilless by design. The recoil is instead emitted rearward. Stand elsewhere.",
	"coil_gun": "Staged magnetic acceleration. Quieter than the rail. Everything else is unchanged.",
	"autocannon": "Intermediate calibre. Chosen because neither adjacent option was satisfactory either.",
	"anti_materiel_rifle": "One round, correctly placed, at considerable expense. The sight costs more than the gun.",
	"napalm_mortar": "Deploys thickened fuel. The affected area remains affected for some time.",
	"mine_layer": "Emplaces area denial. Minefield records are maintained to the extent practicable.",
	"ballista": "Torsion-spring bolt thrower. Procurement has twice declined to explain this line item.",
	# Support
	"resource_harvester": "Extracts and hauls. Slow, unarmed, and statistically the first thing shot at.",
	"repair_array": "Field repair. Restores structure. Does not restore crews, morale, or paperwork.",
	"sensor_suite": "Extends detection range. Emits constantly, and is therefore also easily detected.",
	"armor_plating": "Additional plate. Adds mass. Physics has been consulted and remains unsympathetic.",
	# Power
	"fusion_generator": "Supplies base power. Rated safe. Rating issued by the manufacturer.",
	"capacitor_bank": "Stores surplus power for demand spikes. Discharges spectacularly when destroyed.",
	# Locomotion
	"wheels": "Fast on hard ground. Enthusiasm for soft ground is not shared by the wheels.",
	"tracked_treads": "Slow, heavy, and indifferent to terrain. Throws a track at the worst opportunity.",
	"helicopter_rotors": "Vertical lift. Loud enough to announce arrival well ahead of arrival.",
	"hover_engine": "Ignores ground conditions entirely. Also ignores most attempts at braking.",
	"legs": "Walks over what others drive around. Complexity per kilometre is considerable.",
	"fixed_wing_engine": "Requires forward speed to stay airborne. Hovering is not among the options.",
	"ornithopter_wing": "Flaps. Reviewed twice by engineering. Approved twice. Nobody is entirely sure why.",
	"naval_propeller": "Water only. On land it is ballast with a maintenance schedule.",
	"buoyant_envelope": "Lighter than air, slower than everything, and a generously sized target.",
	"screw_drive": "Amphibious augers. Crosses land and water equally badly, which counts as versatility.",
	# Structural
	"structural_block": "Structural filler. Holds things apart at the distance you specified.",
	"structural_dome": "Turret base. Rotates. That is the entire specification.",
	"structural_slab": "Flat plate. Stops things. Stops fewer things after it has stopped some things.",
	"structural_wedge": "Angled breech. Deflects hits that arrive at the angle you were hoping for.",
	"structural_girder": "Load-bearing span. Rated for loads well beyond anything you should be mounting.",
	"structural_i_beam": "Frame member. Unglamorous, load-bearing, and quietly holding your design together.",
}

# Empty string when a module has no authored line - callers append
# conditionally, so a missing entry degrades to "no flavor row" rather than
# a blank row or an error.
static func get_module_flavor(type_id: String) -> String:
	return MODULE_FLAVOR.get(type_id, "")

static func is_foundation(type_id: String) -> bool:
	var data = get_module_data(type_id)
	return data.get("is_foundation", false)

# Real existence check for a hull id, distinct from get_module_data()'s
# always-succeeds-with-a-fallback contract - needed now that hulls are
# scanned from disk and a blueprint can reference a hull id that simply
# isn't installed (mod uninstalled, typo, hand-edited save). Callers that
# need to tell "this hull is really missing" apart from "this hull exists
# and happens to have field X at its default" must use this, not
# get_module_data(id).is_empty() (which is never empty - see get_module_data()).
static func hull_exists(type_id: String) -> bool:
	var cat = get_catalog()
	return cat.has(type_id) and cat[type_id].get("category", "") == "hull"

# Every authored hull mesh (Chris confirmed, 2026-07-19) visually faces the
# opposite way from the -Z front convention every other system in this
# codebase already agrees on (weapon mounting, movement, facet
# classification, AI targeting - none of that logic is wrong, only the
# authored mesh's visual nose direction is). Rather than re-export/re-author
# every .glb, this is a purely VISUAL yaw correction applied only to the
# MeshInstance3D the mesh is displayed on - it never touches the hull's
# collision shape, module local coordinates, or any gameplay-facing
# direction math, all of which already work correctly. Defaults to the
# 180-degree flip every current hull needs; a future hull authored with its
# nose already at -Z can opt out via its own "visual_yaw_offset_deg" catalog
# field (or JSON sidecar field, for HullLoader-scanned mod hulls).
const HULL_VISUAL_YAW_OFFSET_DEFAULT_DEG: float = 90.0
static func get_hull_visual_yaw_offset_deg(hull_type_id: String) -> float:
	return get_module_data(hull_type_id).get("visual_yaw_offset_deg", HULL_VISUAL_YAW_OFFSET_DEFAULT_DEG)

# --- Hull mesh orientation + fit (single source of truth) -------------------
#
# module_placer.gd (fresh hull placed in the Design Lab) and
# blueprint_manager.gd (hull reconstructed from a saved blueprint, in the lab
# or in battle) each used to compute this independently and DISAGREED, so the
# same design looked and collided differently depending on how it got on
# screen. Both call get_hull_mesh_fit() now.
#
# Two separate problems this solves, both found 2026-07-21:
#
# 1. ORIENTATION. The old code applied a blanket 90-degree yaw to every hull
#    (HULL_VISUAL_YAW_OFFSET_DEFAULT_DEG). That happens to be right for the
#    ~13 authored meshes whose long axis is X, but it is wrong for the ones
#    authored along Z (pillbox_foundation and the since-retired flying wing),
#    wrong for a mod hull authored correctly in the first place,
#    and useless for the ones standing on their tail with their long axis on
#    Y (interceptor_hull, fuselage_hull) - a yaw can never lay those down.
#    We now pick the axis-aligned orientation whose ASPECT RATIO best matches
#    the catalog size, which reproduces the old 90-degree answer wherever the
#    old answer was right and fixes it everywhere it wasn't.
#
# 2. FIT. The old code scaled uniformly so the mesh's LARGEST axis matched the
#    catalog's LARGEST axis. For any mesh whose proportions differ from the
#    catalog's that silently inflates the other two axes - interceptor_hull
#    rendered 7 units TALL and under 1 wide, naval_hull as a 12 x 1.76 x 1.76
#    pencil. Since the collision box, module placement, locomotion mounting,
#    armor auto-fit, clipping and stats are ALL defined in catalog space, the
#    visual has to occupy catalog space too or none of them line up. We fit
#    per-axis so the mesh exactly fills its catalog box.
#
# A hull whose .glb is authored at its true catalog dimensions (which is the
# convention) gets rotation 0 and scale 1
# here and is passed through untouched. Anything else is being corrected for
# a mis-authored source mesh; see get_hull_mesh_fit_warnings().
#
# An author can bypass the auto-detection entirely by setting any of
# "visual_yaw_offset_deg" / "visual_pitch_offset_deg" / "visual_roll_offset_deg"
# in the hull's catalog entry or .json sidecar - if any is present, those
# angles are used verbatim and no orientation search runs. That is the escape
# hatch for a mesh the AABB heuristic lands upside down (an axis-aligned
# bounding box cannot tell "nose up" from "nose down").
static func has_explicit_hull_orientation(hull_type_id: String) -> bool:
	var d = get_module_data(hull_type_id)
	return d.has("visual_yaw_offset_deg") or d.has("visual_pitch_offset_deg") or d.has("visual_roll_offset_deg")

# The axis-aligned orientations we search. Restricted to the 6 that map the
# mesh's three axes onto the hull's three axes without mirroring; the further
# 180-degree spins produce identical extents, so they cannot be distinguished
# by an AABB and are left to the explicit override above.
const _HULL_ORIENTATION_CANDIDATES: Array = [
	Vector3(0, 0, 0),
	Vector3(0, PI / 2.0, 0),
	Vector3(PI / 2.0, 0, 0),
	Vector3(PI / 2.0, PI / 2.0, 0),
	Vector3(0, 0, PI / 2.0),
	Vector3(0, PI / 2.0, PI / 2.0),
]

# Extents of an AABB after being rotated by an axis-aligned euler.
static func _oriented_extents(size: Vector3, euler: Vector3) -> Vector3:
	var b = Basis.from_euler(euler)
	var e = (b * Vector3(size.x, 0, 0)).abs() + (b * Vector3(0, size.y, 0)).abs() + (b * Vector3(0, 0, size.z)).abs()
	# Kill float fuzz from the 90-degree rotations so scale comes out exact.
	return Vector3(snappedf(e.x, 0.000001), snappedf(e.y, 0.000001), snappedf(e.z, 0.000001))

# Scale-invariant distance between two boxes' proportions: how far the
# per-axis scale factors are from being a single uniform scale. 0 means the
# mesh already has exactly the catalog's proportions.
static func _aspect_distance(extents: Vector3, target: Vector3) -> float:
	var ln := []
	for axis in ["x", "y", "z"]:
		if extents[axis] <= 0.0001 or target[axis] <= 0.0001:
			return INF
		ln.append(log(target[axis] / extents[axis]))
	var mean = (ln[0] + ln[1] + ln[2]) / 3.0
	return abs(ln[0] - mean) + abs(ln[1] - mean) + abs(ln[2] - mean)

# Returns {"rotation": Vector3 euler, "scale": Vector3, "position": Vector3}
# to apply to a MeshInstance3D so the authored mesh fills exactly `cat_size`,
# CENTERED on the hull's own origin. `extra_scale` (hull_scale * armor_bulk)
# is folded in for callers.
#
# "position" exists because an authored .glb's geometry is not necessarily
# centered on its own origin - medium_hull's sits about 0.32 units high after
# fitting. Nothing re-centered it, so the visible hull floated off-centre
# inside its own collision box, and every module placed against that box
# landed at a different height than the hull skin it was supposed to touch.
static func get_hull_mesh_fit(hull_type_id: String, mesh: Mesh, extra_scale: Vector3 = Vector3.ONE) -> Dictionary:
	var cat_size: Vector3 = get_module_data(hull_type_id).get("size", Vector3.ONE)
	if not mesh:
		return {"rotation": Vector3.ZERO, "scale": extra_scale, "position": Vector3.ZERO}
	var aabb = mesh.get_aabb()
	var aabb_size = aabb.size
	if aabb_size.x <= 0.0001 or aabb_size.y <= 0.0001 or aabb_size.z <= 0.0001:
		return {"rotation": Vector3.ZERO, "scale": extra_scale, "position": Vector3.ZERO}

	var euler: Vector3
	if has_explicit_hull_orientation(hull_type_id):
		var d = get_module_data(hull_type_id)
		euler = Vector3(
			deg_to_rad(d.get("visual_pitch_offset_deg", 0.0)),
			deg_to_rad(d.get("visual_yaw_offset_deg", 0.0)),
			deg_to_rad(d.get("visual_roll_offset_deg", 0.0)))
	else:
		var best = _HULL_ORIENTATION_CANDIDATES[0]
		var best_score = INF
		for candidate in _HULL_ORIENTATION_CANDIDATES:
			var score = _aspect_distance(_oriented_extents(aabb_size, candidate), cat_size)
			# Candidates run least-rotated first, and a challenger has to be
			# meaningfully better (not merely luckier on float noise) to
			# displace the incumbent. Without a real margin, a near-symmetric
			# mesh like airship_hull's cigar envelope - whose two minor axes
			# differ by under 10% - gets rolled onto its side for a scoring
			# gain small enough to be indistinguishable from rounding.
			if score < best_score - 0.05:
				best_score = score
				best = candidate
		euler = best

	# Godot composes a node's basis as rotation * scale, so `scale` is applied
	# along MESH-local axes and only then rotated into hull space. The fit
	# factors we just derived are per HULL axis, so they have to be permuted
	# back through the rotation before being handed to the node - otherwise
	# every hull needing a non-zero rotation gets its fit factors applied to
	# the wrong axes (which is exactly what the resulting-extents check in
	# run_tests.gd's hull suite now guards against).
	var oriented = _oriented_extents(aabb_size, euler)
	var hull_axis_fit = Vector3(cat_size.x / oriented.x, cat_size.y / oriented.y, cat_size.z / oriented.z)
	var mesh_axis_fit = (Basis.from_euler(euler).transposed() * hull_axis_fit).abs()
	var final_scale = mesh_axis_fit * extra_scale

	# Recentre: a node's transform maps a mesh point p to
	# position + R*S*p, so putting the geometry's own AABB centre on the hull
	# origin means position = -R*S*centre.
	var basis = Basis.from_euler(euler).scaled(final_scale)
	var position = -(basis * aabb.get_center())

	return {"rotation": euler, "scale": final_scale, "position": position}

# Diagnostic: hulls whose authored mesh proportions are far enough from their
# catalog size that get_hull_mesh_fit() has to stretch them noticeably. These
# are data problems (the .glb should be re-exported at its catalog
# dimensions), not code problems - surfaced so they stay visible instead of
# being silently absorbed by the per-axis fit.
static func get_hull_mesh_fit_warnings(tolerance: float = 1.5) -> Array:
	var out := []
	var MeshAssetLoaderScript = load("res://scripts/mesh_asset_loader.gd")
	for hull_id in get_catalog().keys():
		if get_catalog()[hull_id].get("category", "") != "hull":
			continue
		var mesh = MeshAssetLoaderScript.get_hull_mesh(hull_id)
		if not mesh:
			continue
		var fit = get_hull_mesh_fit(hull_id, mesh)
		var s: Vector3 = fit["scale"]
		var lo = min(s.x, min(s.y, s.z))
		var hi = max(s.x, max(s.y, s.z))
		if lo > 0.0001 and hi / lo > tolerance:
			out.append({
				"hull": hull_id,
				"stretch": hi / lo,
				"scale": s,
				"rotation_deg": fit["rotation"] * (180.0 / PI),
			})
	out.sort_custom(func(a, b): return a["stretch"] > b["stretch"])
	return out

# Energy resource (ENERGY_AND_BALANCE_SPEC.md #1): a hull's base_energy is
# the starting point for max_energy before any generator modules are
# mounted. Defaults to 0.0 for anything without a base_energy field
# (weapons/locomotion/etc - only hull/foundation entries carry this stat).
static func get_base_energy(hull_type_id: String) -> float:
	var data = get_module_data(hull_type_id)
	return data.get("base_energy", 0.0)

# Fog-of-war (built this pass, see PROGRESS.md): a hull's base_vision is
# the starting sight radius before any sensor_suite modules are mounted -
# same "hull base + module bonus" shape as Energy's base_energy.
static func get_base_vision(hull_type_id: String) -> float:
	var data = get_module_data(hull_type_id)
	return data.get("base_vision", 20.0)

# Whether this weapon-slot module's targeting should invert to same-team,
# HP-deficit candidates instead of hostiles (repair_array's real fix -
# previously it reused the universal hostile-only targeting and could never
# select an ally at all). Single source of truth so auto_weapon.gd doesn't
# need a hardcoded type_id check.
static func targets_allies(type_id: String) -> bool:
	var data = get_module_data(type_id)
	return data.get("targets_allies", false)

# Real bug found while fixing repair_array/drone_carrier for real (Energy
# batch): every _setup_weapons()-equivalent (battle_unit.gd, battlefield.gd,
# building.gd) only attaches auto_weapon.gd when category=="weapon" -
# repair_array and drone_carrier are catalogued as category="module" (like
# resource_harvester/sensor_suite/logistics_tank, which don't need the
# script - they're driven by other systems entirely). That meant neither
# module EVER got its firing/targeting script in real gameplay, only in
# synthetic tests that manually attached it, bypassing this gate. Single
# source of truth so the three spawn paths can't drift on this again.
static func needs_combat_script(type_id: String) -> bool:
	var data = get_module_data(type_id)
	if data.get("category", "") == "weapon":
		return true
	return type_id in ["repair_array", "drone_carrier"]

# Categories that count as a "legitimate non-combat purpose" - a design
# with one of these and no weapon is intentionally support/utility, not an
# accident. Anything else with zero weapons and none of these categories
# is a motionless, harmless brick the player almost certainly forgot to
# finish, not a deliberate build.
const SUPPORT_CATEGORIES = ["generator"]
const SUPPORT_TYPE_IDS = ["repair_array", "drone_carrier", "resource_harvester", "sensor_suite"]

# --- Roles (parts-menu grouping) -------------------------------------------
# `category` is a mechanical classification - it tells the placer which gizmo
# handles to show and the stat calculator how to score the part. It is far too
# coarse to browse by: 25 of the catalog's entries are category "weapon", which
# is one undifferentiated wall of buttons in the Design Lab sidebar.
#
# `role` is the BROWSING classification, and it lives here rather than in
# parts_menu.gd on purpose. A grouping table sitting in the UI layer is the
# exact failure HULL_MODDING_PLAN.md 4c calls out for hulls: a modded part
# would need a code change in a UI script to appear anywhere sensible. Kept
# next to the catalog, a mod that adds a part just declares its role like it
# already declares its category, and get_module_role()'s category fallback
# means one that declares nothing still lands somewhere reasonable instead of
# vanishing.
const MODULE_ROLES = {
	# Flat-trajectory barrels you point at what you want to hit.
	"heavy_machine_gun": "Direct-Fire Guns",
	"flamethrower": "Direct-Fire Guns",
	"autocannon": "Direct-Fire Guns",
	"anti_materiel_rifle": "Direct-Fire Guns",
	"recoilless_rifle": "Direct-Fire Guns",
	"basic_cannon": "Direct-Fire Guns",
	"rotary_cannon": "Direct-Fire Guns",
	"ballista": "Direct-Fire Guns",

	# Anything whose damage arrives as charge rather than mass - includes the
	# electromagnetic launchers, which fire a slug but are built, costed and
	# powered like energy weapons (crystal + capacitors, not a powder charge).
	"heavy_laser": "Energy & Electromagnetic",
	"arc_projector": "Energy & Electromagnetic",
	"microwave_emitter": "Energy & Electromagnetic",
	"particle_lance": "Energy & Electromagnetic",
	"tesla_coil": "Energy & Electromagnetic",
	"coil_gun": "Energy & Electromagnetic",
	"ion_cannon": "Energy & Electromagnetic",
	"gauss_railgun": "Energy & Electromagnetic",

	# Lobbed, arcing, or otherwise fired at something you cannot see.
	"mk19_grenade_launcher": "Indirect Fire",
	"mortar_array": "Indirect Fire",
	"napalm_mortar": "Indirect Fire",
	"cluster_dispenser": "Indirect Fire",
	"plasma_lobber": "Indirect Fire",
	"artillery": "Indirect Fire",

	"guided_missile": "Missiles",
	"missile_pod": "Missiles",

	"pd_laser": "Point Defense",
	"ciws": "Point Defense",
	"flak_cannon": "Point Defense",

	# Weapons that leave something behind on the field instead of resolving
	# damage at a target - the reason smoke_discharger (0 dps) and mine_layer
	# read as odd ducks in a flat weapon list.
	"smoke_discharger": "Deployables",
	"mine_layer": "Deployables",
	"drone_carrier": "Deployables",

	"armor_plating": "Armor",
	"capacitor_bank": "Power",
	"fusion_generator": "Power",
	"repair_array": "Support",
	"resource_harvester": "Support",
	"sensor_suite": "Support",

	"structural_girder": "Structural",
	"structural_i_beam": "Structural",
	"structural_dome": "Structural",
	"structural_wedge": "Structural",
	"structural_block": "Structural",
	"structural_slab": "Structural",
}

# Display order for the module tab's drawers. Roughly "things that shoot" ->
# "things that survive" -> "things that hold other things up", which is the
# order a build actually gets assembled in.
const MODULE_ROLE_ORDER = [
	"Direct-Fire Guns", "Energy & Electromagnetic", "Indirect Fire", "Missiles",
	"Point Defense", "Deployables", "Armor", "Power", "Support", "Structural",
]

# Fallback for anything MODULE_ROLES doesn't name (a mod, or a part added here
# and not yet given a role). Deliberately never returns "" - an unroled part
# must still land in a visible drawer, not silently disappear from the menu.
const ROLE_BY_CATEGORY = {
	"weapon": "Direct-Fire Guns",
	"armor": "Armor",
	"generator": "Power",
	"structural": "Structural",
	"module": "Support",
}

static func get_module_role(type_id: String, category: String = "") -> String:
	if MODULE_ROLES.has(type_id):
		return MODULE_ROLES[type_id]
	if category != "" and ROLE_BY_CATEGORY.has(category):
		return ROLE_BY_CATEGORY[category]
	return "Support"

# Build-legality gate (ENERGY_AND_BALANCE_SPEC.md #3/DECISIONS_NEEDED.md):
# a design must have a hull, must have a weapon or a legitimate support/
# utility purpose, and must have locomotion or be intentionally static
# (a foundation). Returns {"valid": bool, "reason": String} - reason is
# empty when valid, a player-facing explanation otherwise. Pure/static so
# both the Skirmish match-queue gate and (if ever needed) the Design Lab
# can call the exact same check.
static func validate_build_legality(blueprint_data: Dictionary) -> Dictionary:
	var hull_type = blueprint_data.get("hull_type", "")
	if hull_type == "" or not get_catalog().has(hull_type):
		return {"valid": false, "reason": "No hull selected."}

	var has_weapon = false
	var has_support = false
	var has_locomotion = false
	for mod in blueprint_data.get("modules", []):
		var type_id = mod.get("type_id", "")
		if type_id == "": continue
		var data = get_module_data(type_id)
		var category = data.get("category", "")
		if category == "weapon":
			has_weapon = true
		elif category in SUPPORT_CATEGORIES or type_id in SUPPORT_TYPE_IDS:
			has_support = true
		if category == "locomotion":
			has_locomotion = true

	if not has_weapon and not has_support:
		return {"valid": false, "reason": "No weapon or support module - this design doesn't do anything."}
	if not has_locomotion and not is_foundation(hull_type):
		return {"valid": false, "reason": "No locomotion - this design can't move (use a foundation hull for a static build)."}
	return {"valid": true, "reason": ""}

# --- Unit-class traits (MOUNTING_AND_ARMOR_SPEC.md addendum) ---
# Composable tags, not a hard ship/land/air/building enum, so a helicopter
# that behaves like a ground vehicle at scale and three different fixed-wing
# archetypes aren't forced into one box. DELIBERATELY NO VALIDATION HERE -
# traits describe whatever combination of hull+locomotion is actually
# present and let simulation code (movement, mounting, AI) branch on that;
# they never block a placement. A player can put treads on a naval hull if
# they want to - the traits would just describe a "ground_contact" trait on
# a hull that (once naval hulls exist) might also carry a "buoyant" trait,
# and whatever movement/behavior code reads those traits decides what to do
# with the combination. See DECISIONS_NEEDED.md.
static func get_traits(hull_type_id: String, locomotion_type_id: String = "") -> Array:
	var traits = []
	var hull_data = get_module_data(hull_type_id)
	for t in hull_data.get("traits", []):
		if t not in traits:
			traits.append(t)
	if is_foundation(hull_type_id) and "static" not in traits:
		traits.append("static")
	if locomotion_type_id != "":
		var loco_data = get_module_data(locomotion_type_id)
		for t in loco_data.get("traits", []):
			if t not in traits:
				traits.append(t)
	return traits

# Whether a hull supports independent weapon traverse (turrets/pintles/
# sponsons that aim separately from the hull) vs. everything mounted on it
# being fixed-forward, whole-vehicle-aims (see get_mount_style()'s
# "frame_built" - this is what generalizes that from weapon-type-gated to
# trait-gated). Defaults to true so every hull that exists today keeps its
# current mounting behavior unchanged; future hull types (e.g. a fixed-wing
# airframe) can set "turreted_capable": false in their catalog entry.
static func is_turreted_capable(hull_type_id: String) -> bool:
	var data = get_module_data(hull_type_id)
	return data.get("turreted_capable", true)

# Single source of truth for weapon mount style, shared between the runtime
# combat AI (auto_weapon.gd), the Design Lab placement code (module_placer.gd),
# and the Design Lab firing-arc visualizer - they must never drift apart,
# since the whole point is that they all agree on the same classification.
# Collapsed from an original 5-bucket system (turret / frame_built /
# pintle_top / pintle_bottom / sponson) to 3 buckets, then (2026-07-21) the
# visual side was simplified further: mount_style no longer drives HOW a
# weapon is placed (module_placer.gd flush-mounts every style the same way,
# rotating the module's authored mesh - post and all - flat against
# whichever facet it landed on) - it now only drives combat traverse.
#   "turret"      - existing enclosed-turret visual, unchanged (basic_cannon only), full traverse
#   "frame_built" - built into the vehicle frame; the whole vehicle aims, not the weapon, zero traverse
#   "pintle"      - independent-traverse mount, 360 azimuth
#
# hull_type_id generalizes "frame_built" from weapon-type-gated to
# turreted_capable-trait-gated (MOUNTING_AND_ARMOR_SPEC.md addendum): on a
# hull that doesn't support independent traverse, EVERYTHING mounts
# frame_built, including basic_cannon - nothing should carry visible
# independent-traverse hardware on a unit that can't actually traverse
# weapons independently. Omitting hull_type_id keeps the weapon-type-only
# behavior (used by the few legacy call sites that don't yet know the
# hull context).
static func get_mount_style(type_id: String, hull_type_id: String = "") -> String:
	if hull_type_id != "" and not is_turreted_capable(hull_type_id):
		return "frame_built"
	if type_id == "basic_cannon":
		return "turret"
	if type_id in ["gauss_railgun", "heavy_howitzer"]:
		return "frame_built"
	return "pintle"

# Per-weapon-type traverse character (task: "differentiate and tune weapon
# traversal rates per weapon type"). auto_weapon.gd's base traverse_speed
# formula (200.0/weight, clamped) is driven purely by weight - two weapons
# of similar weight but very different archetypes (a fast-tracking CIWS vs.
# a slow-lobbing mortar_array, both ~90kg) got IDENTICAL traverse speed
# despite being nothing alike in real-world handling. This multiplier is
# the type-specific character layered on top of the weight-driven base:
# point-defense weapons need to snap onto small fast targets (fastest,
# ~1.4-1.8), light autoguns are quick (~1.15-1.3), guided munitions don't
# need to snap-track since the warhead corrects after launch (~0.8-0.9),
# precision energy weapons favor a stable deliberate aim (~0.75-0.8), and
# indirect/ballistic-arc weapons traverse slowest since the arc itself
# depends on a controlled, deliberate aim (~0.5-0.6). Defaults to 1.0
# (no change from the base formula) for any weapon without an explicit
# entry, and for non-weapon modules (resource_harvester, repair_array,
# sensor_suite, logistics_tank, drone_carrier) which were deliberately
# left out of this per-type pass since they're not combat weapons being
# "aimed" in the same sense.
static func get_traverse_agility(type_id: String) -> float:
	return get_module_data(type_id).get("traverse_agility", 1.0)

# --- Projectile class (FABLE_REVIEW.md 1.4 - the evasion model) ---
# How a weapon's shot travels, which decides whether target SPEED can make
# it miss (auto_weapon.gd's _roll_hit()):
#   "hitscan"   - beams/rails: effectively instant, speed can't dodge them
#   "ballistic" - fast direct-fire shells: fast movers shake some hits
#   "arc"       - slow lobbed trajectories: the easiest to simply drive out
#                 from under - mortars are area/siege tools, not anti-scout
#   "guided"    - self-correcting: never misses from speed; its counter is
#                 point-defense interception (weapon_missile.gd), not dodging
const PROJECTILE_CLASS = {
	"gauss_railgun": "hitscan", "heavy_laser": "hitscan", "pd_laser": "hitscan",
	"tesla_coil": "hitscan", "ion_cannon": "hitscan",
	"arc_projector": "hitscan", "microwave_emitter": "hitscan", "particle_lance": "hitscan",
	"resource_harvester": "hitscan", "repair_array": "hitscan",
	"basic_cannon": "ballistic", "heavy_machine_gun": "ballistic", "rotary_cannon": "ballistic",
	"ciws": "ballistic", "flak_cannon": "ballistic", "flamethrower": "ballistic",
	"artillery": "arc", "mortar_array": "arc", "smoke_discharger": "arc",
	# Roster expansion: a coil gun accelerates a slug the same way a rail
	# does (hitscan); the recoilless/autocannon/ballista all throw a real
	# projectile fast and flat; the grenade launcher, napalm mortar and
	# mine layer all lob.
	"coil_gun": "hitscan",
	"recoilless_rifle": "ballistic", "autocannon": "ballistic", "ballista": "ballistic",
	"anti_materiel_rifle": "ballistic",
	"mk19_grenade_launcher": "arc", "napalm_mortar": "arc", "mine_layer": "arc",
	"cluster_dispenser": "arc", "plasma_lobber": "arc",
	"guided_missile": "guided", "missile_pod": "guided",
	"drone_carrier": "guided",
}

static func get_projectile_class(type_id: String) -> String:
	return PROJECTILE_CLASS.get(type_id, "ballistic")

# --- Ammunition types (cross-cutting payload selection) --------------------
#
# Chris's framing: "something firing a shell or payload can also do smoke or
# incendiary or HE". Ammo is a DESIGN-TIME choice per weapon module, stored
# as a plain string in the module's own `tweaks` dict - exactly the pattern
# armor_plating's "material" already uses (see stat_calculator.gd's
# ARMOR_MATERIALS block: "stored in the same tweaks dict so it rides the
# existing save/load path for free"). That choice is load-bearing:
#   - module_data.gd's get_weight()/get_cost()/get_dps() loops all gate on
#     `tweak_name in [...numeric names...]`, so a string under a NEW key
#     falls straight through untouched - no accidental stat corruption.
#   - blueprint_manager.gd copies the whole tweaks dict verbatim on save and
#     load, so persistence needs no new code at all.
#
# The real payoff is `damage_class`. damage_resolver.gd already carries a
# full armor-material x damage-class threshold table, but until now a
# weapon's class was hardcoded once in auto_weapon.gd's _ready() and never
# changed - so that whole matrix was a static property of WHICH GUN you
# bolted on. Ammo makes it a live counter-pick: the same cannon fires AP
# (kinetic - tears ablative_ceramic, bounces off hardened_steel) or HE
# (explosive - good against steel, eaten alive by reactive_armor) or
# incendiary (thermal - melts steel, useless against ablative). None of that
# resolution math is new; it was built and sitting idle.
#
# "standard" is deliberately the default and a genuine no-op (native damage
# class, all multipliers 1.0), so every blueprint saved before this system
# existed behaves EXACTLY as it did before - loading an old design must not
# silently re-tune its guns.
#
# Fields:
#   damage_class  - "" keeps the weapon's own native class, else overrides it
#   damage_mult   - per-shot damage multiplier (0.0 = deals no HP damage)
#   light_mult    - EXTRA multiplier against light/unarmoured targets only
#                   (drones, missiles, aircraft - see auto_weapon.gd's
#                   _is_light_target). This field is what stops the roster
#                   collapsing into one right answer, so it is not optional
#                   flavour: worked through against the real armor tables,
#                   AP came out a STRICT upgrade over standard on every
#                   armor material (81.6 vs 53.6 damage on hardened steel,
#                   94.8 vs 70.2 on ablative), with its only stated cost -
#                   no splash - being nearly free on a single-target gun.
#                   That is precisely the solved-dominant-choice failure
#                   DESIGN_VISION.md warns about. A solid penetrator
#                   over-penetrating a thin-skinned drone (0.4x) gives it a
#                   real class of target it is genuinely bad against, and
#                   makes it the exact mirror of flechette (3.5x) rather
#                   than a free damage upgrade.
#   aoe_mult      - blast radius multiplier (0.0 = no splash, single target)
#   weight_mult   - ammo stowage mass, applied to the module's weight
#   metal_mult /
#   crystal_mult  - per-round cost of the payload
const AMMO_TYPES = {
	"standard": {
		"label": "Standard",
		"damage_class": "", "damage_mult": 1.0, "light_mult": 1.0, "aoe_mult": 1.0,
		"weight_mult": 1.0, "metal_mult": 1.0, "crystal_mult": 1.0,
		"desc": "Balanced service round. No specialisation, no surprises.",
	},
	# Kinetic penetrator: all the energy in one spot, nothing left over for
	# splash. Best against ablative_ceramic (kinetic threshold 8, the lowest
	# in the table); worst against hardened_steel (15, the highest).
	"ap": {
		"label": "Armor-Piercing",
		"damage_class": "kinetic", "damage_mult": 1.25, "light_mult": 0.4, "aoe_mult": 0.0,
		"weight_mult": 1.15, "metal_mult": 1.25, "crystal_mult": 1.0,
		"desc": "Solid penetrator. Concentrates everything on one point and splashes nothing.",
	},
	# Blast round: trades per-shot punch for a much wider blast. Reactive
	# armor's explosive threshold is 30 - by far the hardest wall in the
	# table - so this is the round that gets genuinely countered.
	"he": {
		"label": "High-Explosive",
		"damage_class": "explosive", "damage_mult": 0.85, "light_mult": 1.3, "aoe_mult": 1.6,
		"weight_mult": 1.1, "metal_mult": 1.15, "crystal_mult": 1.0,
		"desc": "Blast-fragmentation filler. Wide effect, poor penetration against sloped plate.",
	},
	# Thermal: hardened_steel's thermal threshold is 5 (its softest row),
	# ablative_ceramic's is 25 (the hardest) - a clean inversion of AP.
	# Also leaves a lingering burn pool at the impact point.
	"incendiary": {
		"label": "Incendiary",
		"damage_class": "thermal", "damage_mult": 0.7, "light_mult": 1.2, "aoe_mult": 1.2,
		"weight_mult": 1.1, "metal_mult": 1.1, "crystal_mult": 1.3,
		"desc": "Thickened fuel filler. Burns on after impact. Ineffective against ablative plate.",
	},
	# Anti-swarm: a wide cone of sub-projectiles. Weak per fragment, but
	# carries a large bonus against unarmoured light targets (drones,
	# missiles, anything in the "missiles" group) - see auto_weapon.gd's
	# AMMO_LIGHT_TARGET_MULT.
	"flechette": {
		"label": "Flechette Canister",
		"damage_class": "kinetic", "damage_mult": 0.55, "light_mult": 3.5, "aoe_mult": 2.2,
		"weight_mult": 1.0, "metal_mult": 1.1, "crystal_mult": 1.0,
		"desc": "Sub-calibre dart canister. Devastating to light frames, irrelevant to armour.",
	},
	# Energy shell: drains the target's capacitor alongside light HP damage,
	# reusing the same drain_energy() contract tesla_coil/arc_projector use.
	# Gives ballistic weapons a door into the energy tier.
	"emp": {
		"label": "EMP Shell",
		"damage_class": "energy", "damage_mult": 0.5, "light_mult": 1.0, "aoe_mult": 1.0,
		"weight_mult": 1.05, "metal_mult": 1.0, "crystal_mult": 1.7,
		"desc": "Capacitor-discharge warhead. Strips power reserves. Barely scratches structure.",
	},
	# Utility rounds: no HP damage at all. That IS the tradeoff - a gun
	# loaded with smoke is not shooting anyone this reload.
	"smoke": {
		"label": "Smoke",
		"damage_class": "", "damage_mult": 0.0, "light_mult": 1.0, "aoe_mult": 1.0,
		"weight_mult": 0.95, "metal_mult": 0.8, "crystal_mult": 1.0,
		"desc": "Obscurant round. Deals no damage. Blocks sightlines and breaks missile lock.",
	},
	"illumination": {
		"label": "Illumination",
		"damage_class": "", "damage_mult": 0.0, "light_mult": 1.0, "aoe_mult": 1.0,
		"weight_mult": 0.95, "metal_mult": 0.8, "crystal_mult": 1.1,
		"desc": "Parachute flare. Deals no damage. Burns off fog of war where it lands.",
	},
}

const AMMO_DEFAULT: String = "standard"
# The tweaks-dict key ammo is stored under. Deliberately NOT any name in
# module_data.gd's numeric-tweak lists or LINEAR_SCALE_WEAPON_TWEAKS, so the
# string value can never be fed into a multiplication.
const AMMO_TWEAK_KEY: String = "ammo"

# Which weapons can load which rounds. A weapon absent from this table has
# no ammo selection at all - that's the correct answer for anything without
# a discrete shell or payload to swap (continuous beams, the flamethrower's
# fuel stream, tesla/arc/ion discharges, plasma's self-contained bolt) and
# for the support modules. Per-weapon lists rather than one global list
# because plenty of combinations are nonsense: a CIWS gatling has no
# business firing an illumination flare, and a railgun slug cannot be
# "high-explosive" in any meaningful sense.
const WEAPON_AMMO_OPTIONS = {
	# Full-service artillery pieces and general-purpose guns
	"basic_cannon":      ["standard", "ap", "he", "incendiary", "flechette", "emp", "smoke", "illumination"],
	"artillery":         ["standard", "he", "incendiary", "emp", "smoke", "illumination"],
	"mortar_array":      ["standard", "he", "incendiary", "smoke", "illumination"],
	"cluster_dispenser": ["standard", "he", "incendiary", "flechette", "smoke"],
	# Automatic weapons - small rounds, so no illumination/blast-filler
	"heavy_machine_gun": ["standard", "ap", "incendiary", "flechette"],
	"rotary_cannon":     ["standard", "ap", "incendiary", "flechette"],
	"ciws":              ["standard", "ap", "flechette"],
	"flak_cannon":       ["standard", "he", "flechette", "emp"],
	# A rail slug is a kinetic mass by definition - only variants that stay
	# kinetic-ish make sense.
	"gauss_railgun":     ["standard", "ap", "emp"],
	# Missiles swap warheads rather than shells, same idea mechanically
	"guided_missile":    ["standard", "he", "incendiary", "emp", "smoke"],
	"missile_pod":       ["standard", "he", "incendiary", "emp"],
	# Roster expansion
	"mk19_grenade_launcher": ["standard", "he", "incendiary", "flechette", "smoke"],
	"recoilless_rifle":  ["standard", "ap", "he", "incendiary", "smoke"],
	"coil_gun":          ["standard", "ap", "emp"],
	"autocannon":        ["standard", "ap", "incendiary", "flechette"],
	# No flechette and no smoke: a precision rifle firing a cloud of darts or
	# a screening round is fighting its own premise. AP listed first is
	# deliberate - it is the round this weapon is FOR.
	"anti_materiel_rifle": ["ap", "standard", "he", "incendiary", "emp"],
	# A dedicated fire weapon - incendiary is its DEFAULT, not an option,
	# hence it heading the list (get_ammo() falls back to options[0]).
	"napalm_mortar":     ["incendiary", "standard", "smoke"],
	"mine_layer":        ["standard", "he", "incendiary"],
	# Flaming ballista bolts are both period-appropriate and, per the
	# straight-faced tone rule, never acknowledged as funny by anyone.
	"ballista":          ["standard", "ap", "incendiary", "smoke"],
	# The dedicated obscurant launcher - the complement to the shell-based
	# smoke above, not a duplicate of it: far larger, faster-blooming clouds,
	# but it can do nothing else whatsoever.
	"smoke_discharger":  ["smoke", "illumination"],
}

static func get_ammo_options(type_id: String) -> Array:
	return WEAPON_AMMO_OPTIONS.get(type_id, [])

static func is_ammo_capable(type_id: String) -> bool:
	return WEAPON_AMMO_OPTIONS.has(type_id)

# Resolves the ammo a module is actually loaded with, validating it against
# that weapon's own allowed list. An unknown or illegal ammo id (a
# hand-edited blueprint, a save from a build where that weapon allowed a
# round it no longer does, a mod) degrades to the weapon's first legal
# option rather than erroring - same forgiving contract get_module_data()
# has for unknown type_ids.
static func get_ammo(type_id: String, tweaks: Dictionary) -> String:
	var options = get_ammo_options(type_id)
	if options.is_empty():
		return AMMO_DEFAULT
	var chosen = tweaks.get(AMMO_TWEAK_KEY, "")
	if typeof(chosen) == TYPE_STRING and chosen in options:
		return chosen
	return options[0]

static func get_ammo_profile(ammo_id: String) -> Dictionary:
	return AMMO_TYPES.get(ammo_id, AMMO_TYPES[AMMO_DEFAULT])

# Tweak names that scale a single part's physical size/mass (shared meaning
# with module_data.gd's get_weight() tweak list, weapon-relevant subset only
# - excludes non-weapon module tweaks like extractor_size/mast_height/
# tank_capacity, and excludes count-type tweaks like multi_barrel/
# barrel_count/tube_count/grid_size/hangar_size, which represent "more
# copies of a part" rather than "one bigger part" and so already affect
# traverse/range purely through the resulting weight change, not an
# additional direct penalty/bonus). Used by auto_weapon.gd to apply a
# consistent per-tweak traverse_speed effect across every weapon type that
# has ANY such tweak, instead of only the two tweak names (barrel_length,
# elevation) that happened to be wired up before.
const LINEAR_SCALE_WEAPON_TWEAKS = ["caliber", "barrel_length", "barrel_count", "drum_size", "motor_size", "rail_length", "rod_thickness", "engine_length", "seeker_size", "ascent_thruster", "payload_size", "nozzle_width", "pressure_valve", "lens_aperture", "containment", "radar_dish", "cooling_jacket", "dispersion", "elevation", "fuse_setting", "optic_power", "focal_length", "charge_rate", "burst_length", "burst_size", "arc_frequency", "surge_capacity", "tracking_speed"]

# Weight capacity fallback for any locomotion type_id missing its own
# "base_weight_capacity" entry - a reasonable middle ground between the
# most weight-sensitive type (helicopter_rotors, 250) and the most
# tolerant (naval_propeller, 800).
const BASE_WEIGHT_CAPACITY_DEFAULT: float = 400.0

# Per-locomotor-type weight capacity (task: "make the overall vehicle
# Weight stat actually matter" - build a formula, per locomotor type, for
# how much weight it's "built for" carrying, with weight in excess of that
# slowing the unit down). Real-world load-bearing intuition drives each
# value - full reasoning logged as a comment on each locomotion type's own
# catalog entry above. battle_unit.gd's _recalculate_move_speed() sums
# this across every locomotion module actually present (scaled by the same
# size/count factors already used for motor_thrust), then applies a speed
# penalty if the vehicle's total weight exceeds the sum.
static func get_base_weight_capacity(type_id: String) -> float:
	return get_module_data(type_id).get("base_weight_capacity", BASE_WEIGHT_CAPACITY_DEFAULT)

# Per-locomotor-type thrust output. Every existing locomotion type used the
# same flat 150.0-per-scaled-unit coefficient in battle_unit.gd's
# _recalculate_move_speed() - fine when every locomotor's propulsion was
# "an engine/motor fighting for speed," but buoyant_envelope's lift is
# free (buoyancy, not thrust), so its actual engines are small
# cruise/steering motors, not speed engines - it needed a genuinely lower
# coefficient to read as "slow but can carry a lot" rather than identical
# speed to everything else at the same weight. Defaults to the original
# universal 150.0 for every locomotion type that doesn't set its own
# (i.e. everything except buoyant_envelope/screw_drive) so this is a pure
# generalization, not a behavior change for the existing roster.
const THRUST_COEFFICIENT_DEFAULT: float = 150.0

static func get_thrust_coefficient(type_id: String) -> float:
	return get_module_data(type_id).get("thrust_coefficient", THRUST_COEFFICIENT_DEFAULT)

# Per-locomotor-type x per-surface-type speed multiplier (terrain variety
# task: "genuinely differentiate locomotor types" via terrain, not just
# elevation/water/obstacles). Only ground-contact locomotion types that
# actually touch the surface are listed - airborne types (helicopter_rotors/
# hover_engine/anti_grav/fixed_wing_engine/buoyant_envelope) skip ground
# navigation entirely already (battle_unit.gd's is_flying branch), so they
# never consult this table at all; that's what "hover/anti-grav ignore it"
# means mechanically, not a row of 1.0s here. naval_propeller doesn't touch
# land surface zones either (is_naval routes to water_map only). Any
# (locomotion_type, surface_type) pair not listed defaults to 1.0
# (unaffected) via get_terrain_speed_multiplier()'s fallback - covers those
# irrelevant types automatically and any future locomotion type added
# without terrain tuning.
#
# Real-world handling reasoning per surface, consistent across all four:
#   marsh/swamp   - screw_drive is BUILT for this (real screw-propelled
#                   vehicles are marketed on exactly this capability), gets
#                   a genuine bonus (1.1), not just "unaffected." wheels
#                   sink hardest, treads better but still bog, legs pick
#                   through reasonably (worst of the three, best-off).
#   rocky         - legs are the one locomotion type actually built for
#                   uneven point-contact ground, gets a slight bonus (1.1).
#                   treads spread load across broken rock reasonably.
#                   wheels are worst (a wheel needs a continuous surface).
#                   screw_drive's augers have nothing to dig into on solid
#                   rock - a real penalty, not its best terrain.
#   snow_mud      - wheels bog down hardest (per the task's explicit ask).
#                   treads are the best-suited (wide flotation, historically
#                   the reason tracked vehicles exist). legs sink less than
#                   wheels but still worse than treads. screw_drive does
#                   reasonably (augers grip mud/snow well, just not quite
#                   tread-level flotation).
#   sand          - same shape as snow_mud but slightly gentler penalties
#                   (dry sand isn't as immobilizing as deep mud) - wheels
#                   still worst, treads/legs both handle it well, screw_
#                   drive moderate (augers work best with real grip/water,
#                   dry sand offers less than mud does).
#
# RTS_CORE_ROADMAP.md B7 additions - cross-checked against OpenRA's own
# locomotor-speed convention as a balance reference (RA's Road tileset is
# a genuine speed BONUS over Clear for every locomotor, not just "less of
# a penalty"; Rough/dense terrain hits wheeled harder than tracked/legged):
#   gravel        - the one surface that's a genuine BONUS across the
#                   board (packed road-grade surface, matching RA's Road
#                   tiles), not just "least-penalized" - gives every
#                   surface_zones map a real reason to fight for specific
#                   ground instead of only ever avoiding bad ground.
#                   wheels benefit most (a wheel's ideal surface is
#                   exactly this), legs least (already at their own
#                   natural pace, gravel doesn't help bipedal footing
#                   much).
#   forest        - dense vegetation/undergrowth. Worst for wheels (can't
#                   push through trunks/roots), treads do reasonably
#                   (tracked vehicles historically log/clear terrain),
#                   legs pick through best (weave around obstacles a
#                   wheeled/tracked vehicle can't), screw_drive middling
#                   (augers aren't built for this, but aren't blocked
#                   either).
#   ice           - uniformly slippery - the one surface type that
#                   penalizes every locomotor at least somewhat (unlike
#                   the others, which always have one clear "winner"),
#                   since loss of traction is a whole-vehicle problem, not
#                   a locomotor-specific one. screw_drive suffers least
#                   (its auger bites into ice rather than relying on
#                   friction the way wheels/treads/legs all do).
const TERRAIN_SPEED_MULTIPLIERS = {
	"marsh": {"wheels": 0.25, "tracked_treads": 0.45, "legs": 0.6, "screw_drive": 1.1},
	"rocky": {"wheels": 0.35, "tracked_treads": 0.75, "legs": 1.1, "screw_drive": 0.5},
	"snow_mud": {"wheels": 0.2, "tracked_treads": 0.8, "legs": 0.75, "screw_drive": 0.7},
	"sand": {"wheels": 0.3, "tracked_treads": 0.85, "legs": 0.8, "screw_drive": 0.6},
	"gravel": {"wheels": 1.25, "tracked_treads": 1.1, "legs": 1.02, "screw_drive": 1.0},
	"forest": {"wheels": 0.3, "tracked_treads": 0.65, "legs": 0.95, "screw_drive": 0.55},
	"ice": {"wheels": 0.45, "tracked_treads": 0.5, "legs": 0.4, "screw_drive": 0.75},
}

static func get_terrain_speed_multiplier(locomotion_type_id: String, surface_type: String) -> float:
	return TERRAIN_SPEED_MULTIPLIERS.get(surface_type, {}).get(locomotion_type_id, 1.0)

# Hull draught (terrain variety task - "shallow water that doesn't allow
# deep-draught hulls" is specifically a hull property, not a locomotor
# one, since two hulls sharing the same naval_propeller locomotion can
# have wildly different real-world draught). Default (0.5) is deliberately
# UNDER the shallow-water threshold - a hull with no explicit "draught"
# entry (i.e. any hull other than the 3 purpose-built naval ones, if
# someone bolts naval_propeller onto a non-naval hull) is NOT blocked from
# shallow water by default, consistent with the no-hard-gating philosophy;
# only hulls that explicitly opt into a real deep-draught number
# (heavy_cruiser_hull) get the hard navmesh block.
# Baseline hull footprint used to derive hull-relative scale factors for
# locomotion visuals (module_placer.gd's underside_y_bias-style block below
# get_underside_y_bias()) - medium_hull's own size, since that's the hull
# every locomotion part's absolute size was originally eyeballed against.
const REFERENCE_HULL_SIZE: Vector3 = Vector3(4.0, 1.0, 6.0)

const HULL_DRAUGHT_DEFAULT: float = 0.5

# Deep-draught-vs-shallow-water cutoff. naval_hull (0.9) and small_boat_hull
# (0.35) both stay under this; heavy_cruiser_hull (1.8) is well over it -
# see battle_unit.gd's _setup_navigation() for where this actually routes
# a unit onto deep_water_map instead of water_map.
const SHALLOW_WATER_DRAUGHT_THRESHOLD: float = 1.0

static func get_hull_draught(hull_type_id: String) -> float:
	return get_module_data(hull_type_id).get("draught", HULL_DRAUGHT_DEFAULT)

# Size-tiered manufactories (base-building batch): which of the 3 production
# tiers (light/medium/heavy) a mobile hull belongs to, by its own base
# weight - domain-agnostic on purpose (a small_boat_hull and an
# interceptor_hull both land in "light" despite one being naval and one
# ground; a heavy_cruiser_hull and a heavy_hull both land in "heavy"), per
# Chris's explicit correction away from an earlier land/sea/air-specific
# shipyard/airfield idea. Foundations (pillbox/tower/fortress_wall) return
# "" - static defenses are built directly via the Armory placement flow,
# never queued from a manufactory at all, so a tier is meaningless for them.
# Breakpoints chosen to split the current 12 mobile hulls into even
# (4/4/4) groups - see DECISIONS_NEEDED.md for the exact per-hull mapping
# and reasoning.
const HULL_TIER_LIGHT_MAX_WEIGHT: float = 150.0
const HULL_TIER_MEDIUM_MAX_WEIGHT: float = 400.0

static func get_hull_size_tier(hull_type_id: String) -> String:
	var data = get_module_data(hull_type_id)
	if data.get("is_foundation", false):
		return ""
	var weight = data.get("weight", 0.0)
	if weight <= HULL_TIER_LIGHT_MAX_WEIGHT:
		return "light"
	elif weight <= HULL_TIER_MEDIUM_MAX_WEIGHT:
		return "medium"
	else:
		return "heavy"

# Visual bug pass finding: module_placer.gd's underside-mount locomotion
# placement (wheels/legs/hover_engine) assumes a hull's visual
# bottom sits exactly at its collision box's -halfHeight - true for the
# wedge/box-ish hulls (medium_hull, sponson_hull, etc.) but not for hulls
# whose mesh doesn't fill its box symmetrically (ship hulls' tapered keel,
# airship_hull's curved envelope). Default 0.0 - only the 4 hulls that
# actually need it carry a nonzero value; every box-ish hull is unaffected.
static func get_underside_y_bias(hull_type_id: String) -> float:
	return get_module_data(hull_type_id).get("underside_y_bias", 0.0)

# --- Running gear (locomotion chassis slab) --------------------------------
# Locomotion archetypes whose visible mount point is the underside of the
# hull, and which therefore benefit from a procedural running-gear slab to
# sit between hull and locomotion parts (the test arena's "vehicle slides on
# its belly" bug - the CharacterBody3D's collider was sized to the hull only,
# so a wheeled unit sat on the hull's underside with wheels dangling below
# the collider; a deterministic running-gear slab gives the unit a real flat
# bottom at the right height AND gives the side-mount types a chassis to
# visually attach to, not float against the hull skin).
#
# Excluded: helicopter_rotors, fixed_wing_engine, ornithopter_wing (all
# mounted ABOVE the hull, not on the underside), naval_propeller (stern),
# buoyant_envelope (under the envelope, not the hull). Foundation hulls
# (pillbox_foundation, fortress_wall_foundation, tower_foundation) take no
# locomotion at all, so they never need a running gear either.
const LOCOMOTION_TYPES_USING_RUNNING_GEAR: Array = [
	"wheels", "tracked_treads",
	"legs", "screw_drive", "hover_engine",
]

const LOCOMOTION_TWEAK_SPECS = {
	"wheels": [
		{"name": "wheel_size", "label": "Wheel Size", "min": 0.5, "max": 2.5, "step": 0.1, "default": 1.0},
		{"name": "num_axles", "label": "Axle Count", "min": 2.0, "max": 8.0, "step": 2.0, "default": 4.0},
		{"name": "wheels_per_axle", "label": "Wheels per Axle Side", "min": 1.0, "max": 3.0, "step": 1.0, "default": 1.0}
	],
	"helicopter_rotors": [
		{"name": "rotor_units", "label": "Rotor Units", "min": 1.0, "max": 4.0, "step": 1.0, "default": 1.0},
		{"name": "blade_count", "label": "Blades per Rotor", "min": 2.0, "max": 8.0, "step": 1.0, "default": 4.0},
		{"name": "blade_length", "label": "Blade Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "duct", "label": "Ducted Shroud", "type": "bool", "default": false}
	],
	"tracked_treads": [
		{"name": "tread_width", "label": "Tread Track Width", "min": 0.5, "max": 2.5, "step": 0.1, "default": 1.0},
		{"name": "drive_sprocket", "label": "Exposed Sprocket", "type": "bool", "default": true}
	],
	"legs": [
		{"name": "leg_count", "label": "Leg Count", "min": 2.0, "max": 8.0, "step": 2.0, "default": 4.0},
		{"name": "knee_height", "label": "Knee Height", "min": -0.5, "max": 1.5, "step": 0.05, "default": 0.375},
		{"name": "foot_size", "label": "Foot Pad Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"hover_engine": [
		{"name": "pad_count", "label": "Pad Count", "min": 4.0, "max": 8.0, "step": 1.0, "default": 4.0},
		{"name": "emv_level", "label": "Electron Megavoltage", "min": 0.5, "max": 2.5, "step": 0.1, "default": 1.0}
	],
	"fixed_wing_engine": [
		{"name": "engine_count", "label": "Engine Count", "min": 2.0, "max": 6.0, "step": 1.0, "default": 2.0},
		{"name": "turbine_compression", "label": "Turbine Compression", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "afterburner", "label": "Afterburner Ring", "type": "bool", "default": false}
	],
	"ornithopter_wing": [
		{"name": "wingspan", "label": "Wingspan", "min": 0.5, "max": 2.5, "step": 0.1, "default": 1.0},
		{"name": "wing_sweep", "label": "Wing Sweep Angle", "min": 0.5, "max": 1.5, "step": 0.1, "default": 1.0}
	],
	# naval_propeller and buoyant_envelope share an identical tweak set
	# (Chris's ask, 2026-07-24: pylon-mounted rebuild) - both now mount a
	# stern pylon reaching back from the hull's own center to a propeller
	# hub+blades assembly built from the same shared GLBs, "deformed"
	# (scaled/tilted) per instance rather than needing distinct authored
	# parts per type. prop_size/kort_nozzle/motor_size/tail_fins are gone,
	# not just defaulted differently - see the matching removals in
	# module_data.gd's weight/cost tweak tables and visual_builder.gd's
	# shared _build_pylon_mounted_propeller().
	"naval_propeller": [
		{"name": "prop_count", "label": "Propeller Count", "min": 1.0, "max": 5.0, "step": 1.0, "default": 2.0},
		{"name": "blade_count", "label": "Blades per Propeller", "min": 2.0, "max": 6.0, "step": 1.0, "default": 3.0},
		{"name": "blade_pitch", "label": "Blade Pitch", "min": 0.5, "max": 1.5, "step": 0.1, "default": 1.0}
	],
	"buoyant_envelope": [
		{"name": "prop_count", "label": "Propeller Count", "min": 1.0, "max": 5.0, "step": 1.0, "default": 2.0},
		{"name": "blade_count", "label": "Blades per Propeller", "min": 2.0, "max": 6.0, "step": 1.0, "default": 3.0},
		{"name": "blade_pitch", "label": "Blade Pitch", "min": 0.5, "max": 1.5, "step": 0.1, "default": 1.0}
	],
	# Rebuilt (Chris's ask, 2026-07-24): drum_count is gone - always one
	# drum per side now (like tracked_treads), spanning the hull's real
	# fore-aft length with a gearbox at each end instead of a fixed-length
	# floating shaft. drum_width renamed to drum_diameter; helix_depth is
	# new (picks among 3 discrete authored flighting-depth variants - see
	# _build_screw_drive()).
	"screw_drive": [
		{"name": "drum_diameter", "label": "Drum Diameter", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "helix_depth", "label": "Helix Depth", "min": 0.5, "max": 1.5, "step": 0.1, "default": 1.0}
	]
}

static func get_locomotion_contribs(type_id: String, settings: Dictionary) -> Dictionary:
	var thrust = 1.0
	var capacity = 0.0
	match type_id:
		"wheels":
			var num_axles = settings.get("num_axles", settings.get("count", 4.0) / 2.0)
			var w_per_axle = settings.get("wheels_per_axle", 1.0)
			var size = settings.get("wheel_size", settings.get("size", 1.0))
			thrust = (num_axles * w_per_axle * 2.0) / 4.0 * size
			capacity = (num_axles * w_per_axle * 2.0) / 4.0 * size * 100.0
		"tracked_treads":
			var width = settings.get("tread_width", settings.get("width", 1.0))
			thrust = width
			capacity = width * 150.0
		"legs":
			var count = settings.get("leg_count", settings.get("count", 4.0))
			var length = settings.get("leg_length", settings.get("size", 1.0))
			var foot_size = settings.get("foot_size", 1.0)
			thrust = (count / 4.0) * length
			capacity = (count / 4.0) * foot_size * 120.0
		"hover_engine":
			var count = settings.get("pad_count", 4.0)
			var emv = settings.get("emv_level", 1.0)
			thrust = count / 4.0
			capacity = (count / 4.0) * emv * 160.0
		"helicopter_rotors":
			var units = settings.get("rotor_units", settings.get("count", 1.0))
			var blades = settings.get("blade_count", 4.0)
			var length = settings.get("blade_length", settings.get("size", 1.0))
			var duct = settings.get("duct", false)
			thrust = units * (0.8 + 0.05 * blades) * length * (1.15 if duct else 1.0)
		"fixed_wing_engine":
			var count = settings.get("engine_count", settings.get("count", 2.0))
			var compression = settings.get("turbine_compression", 1.0)
			var afterburner = settings.get("afterburner", false)
			thrust = (count / 2.0) * compression * (1.3 if afterburner else 1.0)
		"ornithopter_wing":
			var wingspan = settings.get("wingspan", settings.get("size", 1.0))
			thrust = wingspan
		"naval_propeller":
			var count = settings.get("prop_count", settings.get("count", 2.0))
			var pitch = settings.get("blade_pitch", 1.0)
			thrust = (count / 2.0) * pitch
		"buoyant_envelope":
			# Same pylon-mounted prop formula as naval_propeller, but
			# attenuated (0.6x) - buoyancy does the lifting here, not the
			# motors (see the catalog entry's own comment), so a bigger
			# prop cluster shouldn't scale thrust as hard as it does for a
			# real thrust-driven boat screw.
			var count = settings.get("prop_count", settings.get("count", 2.0))
			var pitch = settings.get("blade_pitch", 1.0)
			thrust = (count / 2.0) * pitch * 0.6
		"screw_drive":
			# drum_count is gone (always a fixed pair now) - matches
			# tracked_treads' pattern, no count factor.
			var diameter = settings.get("drum_diameter", settings.get("drum_width", settings.get("size", 1.0)))
			thrust = diameter
			capacity = diameter * 160.0
	return {"thrust": thrust, "capacity": capacity}

# Per-axis scale of the running-gear slab relative to the hull footprint.
# 0.95 inset on XZ (so the chassis tucks inside the hull edge by 2.5% per
# side, a sensible default for a chassis that's not wider than the vehicle
# it supports) and a clamped fraction of hull height for Y (so tall hulls
# get a more prominent chassis without becoming comical, short hulls still
# get enough clearance for default-size wheels).
const RUNNING_GEAR_XZ_INSET: float = 0.95
const RUNNING_GEAR_HEIGHT_MIN: float = 0.2
const RUNNING_GEAR_HEIGHT_MAX: float = 0.6
const RUNNING_GEAR_HEIGHT_FRACTION: float = 0.4

static func needs_running_gear(locomotion_type: String) -> bool:
	return locomotion_type in LOCOMOTION_TYPES_USING_RUNNING_GEAR

# Deterministic running-gear dimensions for a given (already-scaled) hull
# size. Pure/static so battle_unit.gd can compute the chassis height for
# the CharacterBody3D's collider without needing the chassis to actually
# exist as a node yet - and so it stays in sync with whatever
# module_placer.gd / blueprint_manager.gd build.
static func get_running_gear_size(hull_size: Vector3) -> Vector3:
	return Vector3(
		hull_size.x * RUNNING_GEAR_XZ_INSET,
		clamp(hull_size.y * RUNNING_GEAR_HEIGHT_FRACTION, RUNNING_GEAR_HEIGHT_MIN, RUNNING_GEAR_HEIGHT_MAX),
		hull_size.z * RUNNING_GEAR_XZ_INSET
	)

# Continuous alternative to get_mount_style()'s discrete facet matching,
# from an early per-normal mount-hardware design that predates the current
# flush-rotate-to-surface placement (see module_placer.gd's _place_weapon()).
# (Unused now, kept as a stub for legacy blueprint reloads; new code should
# not call this.)
static func get_mount_style_for_normal(type_id: String, normal: Vector3, hull_type_id: String = "") -> String:
	return get_mount_style(type_id, hull_type_id)

# Facet = one of the hull's 6 axis-aligned box faces (see
# MOUNTING_AND_ARMOR_SPEC.md's "Known architecture constraint"). Shared
# between placement (module_placer.gd - armor centering, mount style) and
# combat (damage_resolver.gd - directional armor hit resolution), so both
# always agree on what "the front" or "the left side" means for a given
# local-space direction vector. "front" matches the -Z barrel-forward
# convention used throughout the codebase.
static func classify_facet(local_direction: Vector3) -> String:
	var abs_n = local_direction.abs()
	if abs_n.x > abs_n.y and abs_n.x > abs_n.z:
		return "right" if local_direction.x > 0 else "left"
	elif abs_n.z > abs_n.y:
		return "back" if local_direction.z > 0 else "front"
	else:
		return "top" if local_direction.y > 0 else "bottom"

# Single source of truth for weapon traverse limits, shared between the
# runtime combat AI (auto_weapon.gd) and the Design Lab firing-arc
# visualization (module_placer.gd) - they must never drift apart, since the
# whole point of the visualization is to show players what the weapon will
# actually do in combat. Per mount style (3 buckets, see get_mount_style()):
#   frame_built -> 0  (whole vehicle aims, the barrel is fixed)
#   turret      -> 2pi (basic_cannon's enclosed rotating structure - the
#                        existing tank-cannon visual stays, per spec)
#   pintle      -> 2pi (column-axis independent-traverse mount - 360 azimuth
#                        + 90 elevation away from the hull. This replaces
#                        the old per-facet dispatch where sponson got a
#                        60-degree arc and top/bottom pintles got 360. Now
#                        every independent-traverse mount is the same.)
# hull_type_id (optional) generalizes "frame_built" from weapon-type-gated
# to turreted_capable-trait-gated (MOUNTING_AND_ARMOR_SPEC.md addendum):
# on a hull that doesn't support independent traverse, EVERYTHING gets zero
# traverse - whole vehicle aims, no matter what the weapon type is.
# Omitting hull_type_id keeps the original weapon-type-only behavior.
# facet arg is kept for backward compat with any callers that still pass
# it; it's ignored now since the new model is mount-style-only.
static func get_traverse_limit_angle(type_id: String, _facet: String = "", hull_type_id: String = "") -> float:
	if hull_type_id != "" and not is_turreted_capable(hull_type_id):
		return 0.0
	var style = get_mount_style(type_id, hull_type_id)
	if style == "frame_built":
		return 0.0
	if style in ["turret", "pintle"]:
		return PI # 360 degrees
	return PI # 360 degrees (every other mount is a pintle, all get 360)

static func get_module_data(type_id: String) -> Dictionary:
	var cat = get_catalog()
	if cat.has(type_id):
		return cat[type_id]
	return cat["basic_cannon"] # Fallback
