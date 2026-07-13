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
			"dps": 25.0,
			# Pintle-mount eligibility (MOUNTING_AND_ARMOR_SPEC.md #3 second
			# correction - see PINTLE_MIN_UP_ALIGNMENT_DEFAULT's comment): a
			# small, light, classic pintle weapon in real life - bolts onto
			# almost anything short of a genuinely vertical wall.
			"pintle_min_up_alignment": 0.15,
			# Small, light gun on a light mount - swings fast, same real-world
			# intuition as its pintle tolerance above.
			"traverse_agility": 1.3,
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
			# Compact gatling housing, same "bolts on anywhere" logic as
			# heavy_machine_gun.
			"pintle_min_up_alignment": 0.15,
			# Motor-driven gatling on a powered gimbal - agile but not as
			# featherweight-quick as the single-barrel MG.
			"traverse_agility": 1.2,
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
			# Frame_built (see get_mount_style_for_normal below), so it never
			# independently traverses in practice - this number only matters
			# if that override is ever lifted, kept low for consistency with
			# its long rigid accelerator rail.
			"traverse_agility": 0.4,
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
			# Frame_built like gauss_railgun - traverse is moot in practice,
			# a low number matches its bulky fixed-elevation mount either way.
			"traverse_agility": 0.4,
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
		"spigot_mortar": {
			"name": "Petard Spigot Mortar",
			"category": "weapon",
			"hp": 110.0,
			"weight": 140.0,
			"pintle_min_up_alignment": 0.55, # same indirect-fire reasoning as mortar_array
			"traverse_agility": 0.5, # same slow-deliberate reasoning as mortar_array
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
		"dual_stage_missile": {
			"name": "Top-Attack Javelin",
			"category": "weapon",
			"hp": 75.0,
			"weight": 70.0,
			"metal": 35,
			"crystal": 25,
			"dps": 70.0,
			"pintle_min_up_alignment": 0.25, # guided - same reasoning as guided_missile
			"traverse_agility": 0.85, # guided - same reasoning as guided_missile, slightly heavier launcher
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
			# Tall and top-heavy (size.y=1.6 vs a 0.6x0.6 footprint) - a real
			# structure this slender wants a level base to not look/feel like
			# it's about to topple, so it's less tolerant of a steep slope
			# than the compact autoguns.
			"pintle_min_up_alignment": 0.4,
			# Tall, top-heavy precision emitter - deliberate, controlled
			# traverse rather than a fast snap-track.
			"traverse_agility": 0.8,
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
			# Compact, low-profile emitter - tolerant like the light autoguns.
			"pintle_min_up_alignment": 0.2,
			# Compact, low-profile emitter, tolerant like the light autoguns -
			# it needs to chase down a target to disable it, so agility matters.
			"traverse_agility": 1.15,
			"size": Vector3(0.5, 0.5, 1.2),
			"color": Color.CYAN
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
			# A precision continuous beam over a long (2.5) housing benefits
			# from a stable base for sustained aim - same logic as heavy_laser's
			# kinetic-precision cousins.
			"pintle_min_up_alignment": 0.4,
			# Continuous-beam precision weapon over a long housing - benefits
			# from a stable, deliberate traverse for sustained aim.
			"traverse_agility": 0.75,
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
			# "Lobber" is in the name - an arcing projectile weapon, same
			# ballistic-baseline reasoning as mortar_array/cluster_dispenser.
			"pintle_min_up_alignment": 0.5,
			# Arcing lob weapon, same slow-deliberate character as the
			# mortars/cluster_dispenser.
			"traverse_agility": 0.55,
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
			# Real-world CIWS mounts are routinely bolted to steeply angled
			# deck/superstructure positions and still track fine - tolerant.
			"pintle_min_up_alignment": 0.15,
			# Point defense lives and dies by how fast it can snap onto a
			# small, fast-moving threat - the quickest traverse in the roster.
			"traverse_agility": 1.8,
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
			# Weight capacity (task: "weight in excess of what a locomotor is
			# built for slows the unit down" - see get_base_weight_capacity()
			# below): a light, high-speed wheeled chassis handles poorly
			# overloaded - a real overloaded car sags and struggles - so this
			# tolerates less excess weight than the heavier ground types.
			"base_weight_capacity": 350.0,
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
			# Heaviest, toughest ground locomotor - literally what tanks use
			# to carry heavy armor. Highest ground-type capacity.
			"base_weight_capacity": 700.0,
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
			# A mech walker's legs are built to bear real structural load,
			# closer to tracked_treads than to a wheeled chassis.
			"base_weight_capacity": 500.0,
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
			# Advanced repulsor tech rather than aerodynamic/ground-effect
			# lift - more forgiving of extra weight than the other hovering/
			# airborne types, though still not as tolerant as a grounded hull.
			"base_weight_capacity": 450.0,
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
			# Fixed-wing lift scales with airspeed and wing area, giving it
			# more payload tolerance than rotary/hover lift, but it's still
			# a real aircraft weight budget, not a grounded vehicle's.
			"base_weight_capacity": 380.0,
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
			# Buoyancy carries the load, not the propeller - real ships
			# routinely carry far more weight than any ground/air vehicle.
			# Highest capacity in the roster.
			"base_weight_capacity": 800.0,
			"size": Vector3(0.6, 0.6, 1.0),
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
			"size": Vector3(1.1, 0.9, 3.4),
			"color": Color(0.32, 0.3, 0.24),
			"traits": ["ground_contact", "amphibious"]
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
		},
		"naval_hull": {
			"name": "Naval Hull",
			"category": "hull",
			# Purpose-built ship hull for naval_propeller - a wedge hull
			# floating at the waterline worked mechanically but had nothing
			# boat-shaped to actually show for it.
			"hp": 550.0,
			"weight": 380.0,
			"metal": 145,
			"crystal": 25,
			"dps": 0.0,
			"base_energy": 70.0,
			"base_vision": 17.0,
			"size": Vector3(3.5, 1.6, 9.0),
			"color": Color(0.35, 0.38, 0.4)
		},
		"flying_wing_hull": {
			"name": "Flying Wing Hull",
			"category": "hull",
			# Blended-wing-body airframe for fixed_wing_engine - lightweight
			# and fast like interceptor_hull, but a genuinely different
			# silhouette rather than the same wedge-hull shape used on the
			# ground.
			"hp": 230.0,
			"weight": 140.0,
			"metal": 55,
			"crystal": 15,
			"dps": 0.0,
			"base_energy": 30.0,
			"base_vision": 24.0,
			"size": Vector3(5.0, 0.7, 3.6),
			"color": Color(0.5, 0.52, 0.56)
		},
		"sponson_hull": {
			"name": "Sponson Hull",
			"category": "hull",
			# Heavy ground hull with sponson stubs baked into the base
			# silhouette (wider mid-body, narrower fore/aft) rather than
			# sponsons being purely a mount-hardware visual added at
			# placement time - a genuinely different base shape to build on.
			"hp": 800.0,
			"weight": 650.0,
			"metal": 210,
			"crystal": 40,
			"dps": 0.0,
			"base_energy": 105.0,
			"base_vision": 17.0,
			"size": Vector3(6.5, 1.6, 7.5),
			"color": Color(0.38, 0.36, 0.32)
		},
		"small_boat_hull": {
			"name": "Small Boat Hull",
			"category": "hull",
			# A fast patrol boat - naval_hull's little sibling. Sharper bow
			# (bow_frac=0.5 vs naval_hull's 0.35) and a much smaller
			# footprint for a genuinely different niche (scout/raider) than
			# just a smaller version of the same silhouette.
			"hp": 220.0,
			"weight": 130.0,
			"metal": 55,
			"crystal": 10,
			"dps": 0.0,
			"base_energy": 30.0,
			"base_vision": 22.0,
			"size": Vector3(2.0, 1.0, 5.0),
			"color": Color(0.4, 0.42, 0.44)
		},
		"heavy_cruiser_hull": {
			"name": "Heavy Cruiser Hull",
			"category": "hull",
			# naval_hull's big sibling - layered superstructure, twin
			# funnels, real warship bulk. Sits above naval_hull in the same
			# way heavy_hull sits above medium_hull.
			"hp": 900.0,
			"weight": 680.0,
			"metal": 255,
			"crystal": 50,
			"dps": 0.0,
			"base_energy": 110.0,
			"base_vision": 15.0,
			"size": Vector3(4.4, 1.9, 10.5),
			"color": Color(0.3, 0.32, 0.34)
		},
		"fuselage_hull": {
			"name": "Fuselage Hull",
			"category": "hull",
			# Traditional plane: a tapered fuselage tube + separate attached
			# wing slab, unlike flying_wing_hull's blended-wing-body (no
			# fuselage/wing break at all). Positioned as the tougher/heavier
			# fixed-wing airframe - flying_wing_hull is the fast/light
			# interceptor-style airframe, this is the bomber/cargo-style one.
			"hp": 300.0,
			"weight": 210.0,
			"metal": 80,
			"crystal": 18,
			"dps": 0.0,
			"base_energy": 45.0,
			"base_vision": 20.0,
			"size": Vector3(4.2, 1.2, 6.2),
			"color": Color(0.6, 0.6, 0.62)
		},
		"airship_hull": {
			"name": "Airship Hull",
			"category": "hull",
			# Rigid dirigible: cigar/teardrop gasbag envelope + slung
			# gondola. Pairs with the new buoyant_envelope locomotion (see
			# its own catalog comment and DECISIONS_NEEDED.md) rather than
			# fixed_wing_engine - buoyant lift, not thrust fighting gravity,
			# so it wants a locomotion flavor with a very high
			# base_weight_capacity and a low thrust_coefficient, not just a
			# reskinned fixed-wing airframe.
			"hp": 480.0,
			"weight": 260.0,
			"metal": 95,
			"crystal": 30,
			"dps": 0.0,
			"base_energy": 55.0,
			"base_vision": 24.0,
			"size": Vector3(4.0, 3.0, 9.5),
			"color": Color(0.72, 0.7, 0.6)
		},
		"fortress_wall_foundation": {
			"name": "Fortress Wall Foundation",
			"category": "hull",
			"is_foundation": true,
			# A rampart, not a watchtower - tankier per-slot than the pillbox
			# (long battlement face, deliberately no roof to defend), but
			# doesn't see far like the tower.
			"hp": 1100.0,
			"weight": 0.0,
			"metal": 140,
			"crystal": 10,
			"dps": 0.0,
			"base_energy": 70.0,
			"base_vision": 14.0,
			"size": Vector3(6.0, 2.2, 1.3),
			"color": Color(0.42, 0.4, 0.36)
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
	# Legacy discrete-facet entry point - kept because get_traverse_limit_angle()
	# only ever needs this for the turret/frame_built gate (not the pintle-
	# vs-sponson distinction, which needs the continuous version below), so
	# rewiring every call site wasn't necessary. Delegates to
	# get_mount_style_for_normal() via a representative normal for whichever
	# facet was named, so the actual style logic lives in exactly one place.
	var normal = Vector3.ZERO
	match facet:
		"top": normal = Vector3.UP
		"bottom": normal = Vector3.DOWN
		"front": normal = Vector3.FORWARD
		"back": normal = Vector3.BACK
		"left": normal = Vector3.LEFT
		"right": normal = Vector3.RIGHT
	return get_mount_style_for_normal(type_id, normal, hull_type_id)

# Fallback slope-from-horizontal threshold for any weapon that doesn't
# carry its own "pintle_min_up_alignment" catalog entry (see
# get_pintle_min_up_alignment() below - every real weapon type_id has one
# as of this pass; this only matters for a future weapon someone forgets
# to set it on). 0.3 = cos(~72.5 deg) - a reasonable generic middle ground
# between the light-autogun (0.15) and ballistic-arc (0.5+) ends of the
# real per-type range.
const PINTLE_MIN_UP_ALIGNMENT_DEFAULT: float = 0.3

# Per-weapon-type pintle eligibility (MOUNTING_AND_ARMOR_SPEC.md #3,
# second correction): Chris's point was that a single geometric threshold
# applied to every weapon uniformly is wrong - a compact machine gun
# reasonably bolts onto almost any surface short of dead vertical, while a
# mortar's ballistic arc math wants a much closer-to-level base, and that's
# a judgment call about the WEAPON, not a property of the surface alone.
# Each weapon's own reasoning is logged as a comment on its catalog entry.
static func get_pintle_min_up_alignment(type_id: String) -> float:
	return get_module_data(type_id).get("pintle_min_up_alignment", PINTLE_MIN_UP_ALIGNMENT_DEFAULT)

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
# depends on a controlled, deliberate aim (~0.5-0.6) - the same real-world
# intuition already used for get_pintle_min_up_alignment() above. Defaults
# to 1.0 (no change from the base formula) for any weapon without an
# explicit entry, and for non-weapon modules (resource_harvester,
# repair_array, sensor_suite, logistics_tank, drone_carrier) which were
# deliberately left out of this per-type pass since they're not combat
# weapons being "aimed" in the same sense.
static func get_traverse_agility(type_id: String) -> float:
	return get_module_data(type_id).get("traverse_agility", 1.0)

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
const LINEAR_SCALE_WEAPON_TWEAKS = ["caliber", "barrel_length", "drum_size", "motor_size", "rail_length", "rod_thickness", "engine_length", "seeker_size", "ascent_thruster", "payload_size", "nozzle_width", "pressure_valve", "lens_aperture", "containment", "radar_dish", "cooling_jacket", "dispersion", "elevation", "fuse_setting"]

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

# Continuous alternative to get_mount_style()'s discrete facet matching,
# for real mount-hardware decisions (module_placer.gd's actual weapon
# placement, which has the real continuous surface normal, not just a
# coarse "top/bottom/front/back/left/right" bucket). A pintle-style mount
# (angled base plate conforming to the true local surface, world-vertical
# post, weapon level on top - see visual_builder.gd's add_mount_hardware())
# is available anywhere the surface has a meaningful upward OR downward
# component RELATIVE TO THIS SPECIFIC WEAPON'S OWN TOLERANCE - this is what
# makes a sloped glacis plate (interceptor_hull's nose, e.g.) a legitimate
# pintle mount for a compact machine gun instead of forcing it into an
# embedded sponson, while the same slope might still sponson-mount a mortar.
static func get_mount_style_for_normal(type_id: String, normal: Vector3, hull_type_id: String = "") -> String:
	if hull_type_id != "" and not is_turreted_capable(hull_type_id):
		return "frame_built"
	if type_id == "basic_cannon":
		return "turret"
	if type_id in ["gauss_railgun", "heavy_howitzer"]:
		return "frame_built"
	var min_up_alignment = get_pintle_min_up_alignment(type_id)
	var up_alignment = normal.normalized().dot(Vector3.UP) if normal.length() > 0.001 else 0.0
	if up_alignment >= min_up_alignment:
		return "pintle_top"
	elif up_alignment <= -min_up_alignment:
		return "pintle_bottom"
	else:
		return "sponson"

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
