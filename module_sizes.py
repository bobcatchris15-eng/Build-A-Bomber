# Module sizes dictionary
# Format: "module_name": (width, height, length) in meters.
# In Unity/glTF terms: X=width, Y=height, Z=length (Z is forward).

sizes = {
    # Weapons (Z is barrel-forward axis)
    # Ballistic & Projectile Weapons
    "heavy_machine_gun": (0.3, 0.3, 1.0),
    "rotary_cannon": (0.5, 0.5, 1.5),
    "basic_cannon": (0.6, 0.6, 2.0),
    "heavy_howitzer": (0.9, 0.9, 3.2),
    "gauss_railgun": (0.6, 0.6, 2.8),
    "flak_cannon": (0.7, 0.7, 1.8),
    "ciws": (0.6, 0.8, 0.6),
    "dual_stage_missile": (0.7, 0.5, 1.8),
    "missile_pod": (1.2, 0.8, 1.5),
    "cluster_dispenser": (1.4, 0.8, 1.4),
    "flamethrower": (0.5, 0.5, 1.6),
    # Energy & Beam Weapons
    "heavy_laser": (0.7, 0.7, 2.4),
    "pd_laser": (0.4, 0.5, 0.4),
    "plasma_lobber": (0.6, 0.6, 1.6),
    "tesla_coil": (0.5, 1.2, 0.5),
    "arc_projector": (0.4, 0.4, 1.0),
    "ion_cannon": (0.8, 0.8, 2.8),
    "drone_carrier": (2.0, 1.2, 3.0),
    "mortar_array": (1.2, 0.6, 1.2),
    "spigot_mortar": (1.0, 1.0, 1.0),
    "guided_missile": (0.6, 0.4, 1.6),

    # Support modules
    "resource_harvester": (1.5, 1.0, 1.5),
    "repair_array": (0.8, 0.8, 1.0),
    "sensor_suite": (0.5, 2.5, 0.5),
    "logistics_tank": (1.2, 1.2, 1.8),
    "wing": (1.6, 0.16, 0.6),
    "thruster": (0.5, 0.5, 0.9),
    "propeller_prop": (0.5, 0.5, 0.5),
    "pusher_prop": (0.5, 0.5, 0.5),
    "paddle_wheel": (0.5, 0.9, 0.9),
    "ship_screw": (0.4, 0.4, 0.5),

    # Armor & generators
    "armor_plating": (2.0, 0.2, 2.0),
    "fusion_generator": (1.4, 1.2, 1.8),
    "capacitor_bank": (0.8, 0.8, 1.0),

    # Locomotion
    "wheels": (0.6, 0.6, 0.6),
    "omni_wheels": (0.6, 0.6, 0.6),
    "tracked_treads": (0.8, 0.6, 2.5),
    "rhomboid_treads": (1.0, 2.0, 5.0),
    "legs": (0.5, 1.5, 0.5),
    "hover_engine": (1.2, 0.3, 1.2),
    "anti_grav": (1.2, 0.3, 1.2),
    "helicopter_rotors": (4.0, 0.2, 4.0),
    "fixed_wing_engine": (1.0, 0.5, 1.5),
    "ornithopter_wing": (2.0, 0.2, 1.0),
    "naval_propeller": (0.5, 0.5, 0.8),
    "buoyant_envelope": (1.0, 0.5, 1.0),
    "screw_drive": (0.8, 0.8, 3.0),

    # Hulls
    "light_hull": (2.5, 1.5, 4.0),
    "medium_hull": (3.0, 1.8, 5.5),
    "heavy_hull": (4.0, 2.5, 8.0),
    "assault_hull": (3.0, 2.0, 6.0),
    "airship_hull": (6.0, 4.0, 16.0),
    "flying_wing_hull": (10.0, 1.5, 6.0),
    "heavy_cruiser_hull": (5.0, 3.0, 16.0),
    "fuselage_hull": (6.0, 2.0, 10.0),
    "naval_hull": (4.0, 2.5, 12.0),
    "small_boat_hull": (3.0, 1.5, 8.0),
    "sponson_hull": (1.5, 1.2, 3.0),
    "fortress_wall_foundation": (4.0, 3.0, 4.0),
    "pillbox_foundation": (3.0, 2.0, 3.0),
    "tower_foundation": (3.0, 5.0, 3.0),
    "interceptor_hull": (4.0, 1.2, 7.0),

    # Prefab Buildings (Width x Height x Length)
    "hq": (8.0, 4.0, 8.0),
    "refinery": (6.0, 3.5, 6.0),
    "light_manufactory": (5.0, 2.5, 6.0),
    "medium_manufactory": (6.5, 3.0, 8.0),
    "heavy_manufactory": (8.0, 3.5, 10.0),
    "power_plant": (5.0, 4.0, 5.0),
}
