class_name ModuleCatalog

# Returns a dictionary containing all module types
static func get_catalog() -> Dictionary:
	return {
		# --- BALLISTIC & KINETIC ---
		"basic_cannon": {
			"name": "Main Cannon",
			"category": "weapon",
			"hp": 100.0,
			"weight": 80.0,
			"metal": 30,
			"crystal": 0,
			"dps": 40.0,
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
			"dps": 25.0,
			"size": Vector3(0.4, 0.4, 1.2),
			"color": Color.SLATE_GRAY
		},
		"rotary_cannon": {
			"name": "Rotary Gatling",
			"category": "weapon",
			"hp": 80.0,
			"weight": 110.0,
			"metal": 45,
			"crystal": 5,
			"dps": 75.0,
			"size": Vector3(0.7, 0.7, 1.8),
			"color": Color(0.2, 0.2, 0.2) # Charcoal
		},
		"gauss_railgun": {
			"name": "Gauss Railgun",
			"category": "weapon",
			"hp": 120.0,
			"weight": 180.0,
			"metal": 80,
			"crystal": 40,
			"dps": 110.0,
			"size": Vector3(0.4, 0.4, 3.0),
			"color": Color.BLUE_VIOLET
		},

		# --- INDIRECT FIRE ---
		"heavy_howitzer": {
			"name": "Heavy Howitzer",
			"category": "weapon",
			"hp": 150.0,
			"weight": 250.0,
			"metal": 100,
			"crystal": 10,
			"dps": 90.0,
			"size": Vector3(0.9, 0.9, 3.2),
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
			"size": Vector3(1.2, 0.6, 1.2),
			"color": Color.OLIVE
		},
		"spigot_mortar": {
			"name": "Petard Spigot Mortar",
			"category": "weapon",
			"hp": 110.0,
			"weight": 140.0,
			# Balance pass (tools/balance_report.gd, ENERGY_AND_BALANCE_SPEC.md
			# #6): had the highest raw dps in the game at less than half the
			# cost of comparable weapons (gauss_railgun/heavy_howitzer) -
			# value/cost was 6.31 against a category average of 2.86, more
			# than 2x an outlier. Cost raised, dps/hp untouched.
			"metal": 65,
			"crystal": 15,
			"dps": 130.0,
			"size": Vector3(1.0, 1.0, 1.0),
			"color": Color.DARK_KHAKI
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
			"size": Vector3(0.6, 0.4, 1.6),
			"color": Color.GOLD
		},
		"dual_stage_missile": {
			"name": "Top-Attack Javelin",
			"category": "weapon",
			"hp": 75.0,
			"weight": 70.0,
			"metal": 35,
			"crystal": 25,
			"dps": 70.0,
			"size": Vector3(0.7, 0.5, 1.8),
			"color": Color.YELLOW_GREEN
		},
		"missile_pod": {
			"name": "Swarm Missile Pod",
			"category": "weapon",
			"hp": 100.0,
			"weight": 150.0,
			"metal": 50,
			"crystal": 10,
			"dps": 60.0,
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
			"size": Vector3(1.4, 0.8, 1.4),
			"color": Color.CHOCOLATE
		},
		"flamethrower": {
			"name": "Flamethrower Emitter",
			"category": "weapon",
			"hp": 70.0,
			"weight": 50.0,
			# Balance pass: value/cost was 5.49 against a 2.86 category
			# average - cheap for its dps relative to comparable short-range
			# weapons (heavy_machine_gun aside, which is an intentionally
			# cheap starter weapon and left alone).
			"metal": 35,
			"crystal": 15,
			"dps": 80.0,
			"size": Vector3(0.5, 0.5, 1.6),
			"color": Color.CRIMSON
		},

		# --- ENERGY WEAPONS ---
		# "energy" damage_class weapons (ENERGY_AND_BALANCE_SPEC.md #4) - the
		# only weapons that cost the firing unit's own current_energy per
		# shot and, for tesla_coil/ion_cannon, also drain the TARGET's
		# energy pool alongside HP damage. arc_projector is the dedicated
		# pure-drain "disable" weapon (near-zero HP damage, big drain).
		"tesla_coil": {
			"name": "Tesla Coil",
			"category": "weapon",
			"hp": 70.0,
			"weight": 70.0,
			"metal": 40,
			"crystal": 45,
			"dps": 60.0,
			"size": Vector3(0.6, 1.6, 0.6),
			"color": Color.LIGHT_SKY_BLUE
		},
		"arc_projector": {
			"name": "Arc Projector",
			"category": "weapon",
			"hp": 55.0,
			"weight": 45.0,
			"metal": 25,
			"crystal": 35,
			"dps": 40.0,
			"size": Vector3(0.5, 0.5, 1.2),
			"color": Color.CYAN
		},
		"ion_cannon": {
			"name": "Ion Cannon",
			"category": "weapon",
			"hp": 130.0,
			"weight": 150.0,
			# Balance pass: was the single worst value/cost weapon in the
			# game (1.03 vs 2.86 average) even before accounting for its
			# energy-drain utility (which this cost-model can't see) - the
			# heavy crystal cost was double-counted against a flagship
			# "grounded energy heavy-hitter" that's supposed to be a real
			# alternative to gauss_railgun/plasma_lobber, not strictly worse.
			"metal": 70,
			"crystal": 65,
			"dps": 75.0,
			"size": Vector3(0.7, 0.7, 2.6),
			"color": Color.SKY_BLUE
		},
		"heavy_laser": {
			"name": "Continuous Laser",
			"category": "weapon",
			"hp": 75.0,
			"weight": 60.0,
			"metal": 30,
			"crystal": 20,
			"dps": 80.0,
			"size": Vector3(0.6, 0.6, 2.5),
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
			"size": Vector3(0.8, 0.8, 2.0),
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
			"size": Vector3(0.8, 1.0, 0.8),
			"color": Color.WHITE_SMOKE
		},
		"pd_laser": {
			"name": "Point Defense Laser",
			"category": "weapon",
			"hp": 50.0,
			"weight": 35.0,
			"metal": 20,
			"crystal": 30,
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
			"size": Vector3(0.7, 0.7, 1.8),
			"color": Color.DARK_GOLDENROD
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
		"logistics_tank": {
			"name": "Logistics Tank",
			"category": "module",
			"hp": 80.0,
			"weight": 120.0,
			"metal": 30,
			"crystal": 0,
			"dps": 0.0,
			"size": Vector3(1.2, 1.2, 1.8),
			"color": Color.DARK_CYAN
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
			"size": Vector3(0.8, 0.8, 0.8),
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
			"size": Vector3(1.0, 0.8, 3.0),
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
			"size": Vector3(1.5, 0.4, 1.5),
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
			"size": Vector3(0.6, 1.8, 0.6),
			"color": Color.DARK_RED,
			"traits": ["ground_contact"]
		},
		"anti_grav": {
			"name": "Anti-Grav Rings",
			"category": "locomotion",
			"hp": 60.0,
			"weight": 30.0,
			"metal": 50,
			"crystal": 80,
			"dps": 0.0,
			"size": Vector3(1.6, 0.3, 1.6),
			"color": Color.MEDIUM_BLUE,
			"traits": ["hovering", "airborne"]
		},
		"fixed_wing_engine": {
			"name": "Fixed-Wing Engine",
			"category": "locomotion",
			"hp": 70.0,
			"weight": 60.0,
			"metal": 60,
			"crystal": 20,
			"dps": 0.0,
			"size": Vector3(1.2, 0.6, 2.0),
			"color": Color.SLATE_BLUE,
			"traits": ["airborne", "fixed_wing", "high_speed"]
		},
		"naval_propeller": {
			"name": "Naval Propeller",
			"category": "locomotion",
			"hp": 90.0,
			"weight": 70.0,
			"metal": 35,
			"crystal": 0,
			"dps": 0.0,
			"size": Vector3(0.6, 0.6, 1.0),
			"color": Color.TEAL,
			"traits": ["buoyant", "naval"]
		},

		# --- HULL SIZE CLASSES ---
		"light_hull": {
			"name": "Light Hull",
			"category": "hull",
			"hp": 200.0,
			"weight": 100.0,
			"metal": 50,
			"crystal": 10,
			"dps": 0.0,
			"base_energy": 40.0,
			"base_vision": 22.0,
			"size": Vector3(3.0, 1.0, 4.0),
			"color": Color.LIGHT_GRAY
		},
		"medium_hull": {
			"name": "Medium Hull",
			"category": "hull",
			"hp": 400.0,
			"weight": 250.0,
			"metal": 100,
			"crystal": 20,
			"dps": 0.0,
			"base_energy": 70.0,
			"base_vision": 20.0,
			"size": Vector3(4.0, 1.0, 6.0),
			"color": Color.GRAY
		},
		"heavy_hull": {
			"name": "Heavy Hull",
			"category": "hull",
			"hp": 1000.0,
			"weight": 800.0,
			"metal": 250,
			"crystal": 50,
			"dps": 0.0,
			"base_energy": 130.0,
			"base_vision": 18.0,
			"size": Vector3(6.0, 1.5, 8.0),
			"color": Color.DARK_GRAY
		},
		"interceptor_hull": {
			"name": "Interceptor Hull",
			"category": "hull",
			"hp": 130.0,
			"weight": 65.0,
			"metal": 35,
			"crystal": 8,
			"dps": 0.0,
			"base_energy": 35.0,
			# Fast scout archetype gets the best base vision of any hull -
			# thematically consistent with its role even before a
			# sensor_suite is ever mounted.
			"base_vision": 26.0,
			"size": Vector3(2.4, 0.8, 3.2),
			"color": Color(0.55, 0.65, 0.78)
		},
		"assault_hull": {
			"name": "Assault Hull",
			"category": "hull",
			"hp": 650.0,
			"weight": 500.0,
			"metal": 170,
			"crystal": 35,
			"dps": 0.0,
			"base_energy": 90.0,
			"base_vision": 18.0,
			"size": Vector3(5.0, 1.3, 7.0),
			"color": Color(0.4, 0.32, 0.28)
		},

		# --- DEFENSIVE FOUNDATIONS (static structures, no locomotion) ---
		"pillbox_foundation": {
			"name": "Pillbox Foundation",
			"category": "hull",
			"is_foundation": true,
			"hp": 800.0,
			"weight": 0.0,
			"metal": 80,
			"crystal": 0,
			"dps": 0.0,
			"base_energy": 60.0,
			"base_vision": 16.0,
			"size": Vector3(3.0, 1.2, 3.0),
			"color": Color(0.45, 0.45, 0.4)
		},
		"tower_foundation": {
			"name": "Tower Foundation",
			"category": "hull",
			"is_foundation": true,
			"hp": 1400.0,
			"weight": 0.0,
			"metal": 160,
			"crystal": 20,
			"dps": 0.0,
			"base_energy": 100.0,
			# A watchtower should see far - height is the whole point of it.
			"base_vision": 28.0,
			"size": Vector3(3.0, 4.0, 3.0),
			"color": Color(0.5, 0.48, 0.44)
		}
	}

static func is_foundation(type_id: String) -> bool:
	var data = get_module_data(type_id)
	return data.get("is_foundation", false)

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
const SUPPORT_TYPE_IDS = ["repair_array", "drone_carrier", "resource_harvester", "sensor_suite", "logistics_tank"]

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

# Single source of truth for weapon traverse limits, shared between the
# runtime combat AI (auto_weapon.gd) and the Design Lab firing-arc
# visualization (module_placer.gd) - they must never drift apart, since the
# whole point of the visualization is to show players what the weapon will
# actually do in combat.
# MOUNTING_AND_ARMOR_SPEC.md #3: how a weapon/device physically sits
# depends on which hull facet it's mounted on. Single source of truth so
# module_placer.gd (positioning/embedding) and visual_builder.gd (mount
# hardware) agree on the same classification.
#   "turret"      - existing enclosed-turret visual, unchanged (basic_cannon only)
#   "frame_built" - built into the vehicle frame; the whole vehicle aims, not the weapon
#   "pintle_top"   - pintle base on the hull, weapon sits level on top
#   "pintle_bottom" - inverted: pintle reaches down from the hull, weapon hangs below
#   "sponson"     - embedded into the hull body, only the muzzle projects out
#
# hull_type_id (optional) generalizes "frame_built" from weapon-type-gated
# to turreted_capable-trait-gated (MOUNTING_AND_ARMOR_SPEC.md addendum): on
# a hull that doesn't support independent traverse, EVERYTHING mounts
# frame_built, including basic_cannon - nothing should carry visible
# independent-traverse hardware on a unit that can't actually traverse
# weapons independently. Omitting hull_type_id (or every hull that exists
# today, which all default turreted_capable=true) keeps the original
# weapon-type-only behavior unchanged.
static func get_mount_style(type_id: String, facet: String, hull_type_id: String = "") -> String:
	if hull_type_id != "" and not is_turreted_capable(hull_type_id):
		return "frame_built"
	if type_id == "basic_cannon":
		return "turret"
	if type_id in ["gauss_railgun", "heavy_howitzer"]:
		return "frame_built"
	match facet:
		"top": return "pintle_top"
		"bottom": return "pintle_bottom"
		_: return "sponson"

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

# facet/hull_type_id (optional, mirrors get_mount_style()'s signature): a
# frame_built weapon (AI/unit-AI pass, MOUNTING_AND_ARMOR_SPEC.md addendum)
# has ZERO independent traverse by definition - "built into the vehicle
# frame" means the barrel is fixed relative to the hull, and the WHOLE
# VEHICLE has to turn to aim it (see battle_unit.gd's whole-vehicle-aim
# logic). Omitting facet/hull_type_id keeps the original weapon-type-only
# angle (used by any call site that doesn't yet know the mount context).
static func get_traverse_limit_angle(type_id: String, facet: String = "", hull_type_id: String = "") -> float:
	if (facet != "" or hull_type_id != "") and get_mount_style(type_id, facet, hull_type_id) == "frame_built":
		return 0.0
	if type_id in ["basic_cannon", "ciws", "pd_laser"]:
		return PI # 360 degrees
	elif type_id == "heavy_howitzer":
		return PI / 3.0 # 60 degrees
	elif type_id in ["mortar_array", "spigot_mortar"]:
		return PI / 6.0 # 30 degrees
	else:
		return PI / 4.0 # 45 degrees

static func get_module_data(type_id: String) -> Dictionary:
	var cat = get_catalog()
	if cat.has(type_id):
		return cat[type_id]
	return cat["basic_cannon"] # Fallback
