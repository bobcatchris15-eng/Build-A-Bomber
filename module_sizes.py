# Module sizes dictionary
# Format: "module_name": (width, height, length) in meters.
# In Unity/glTF terms: X=width, Y=height, Z=length (Z is forward).

sizes = {
    # Weapons (Z is barrel-forward axis)
    "basic_cannon": (0.6, 0.6, 2.0),
    "heavy_machine_gun": (0.4, 0.4, 1.2),
    "rotary_cannon": (0.7, 0.7, 1.8),
    "gauss_railgun": (0.4, 0.4, 3.0),
    "heavy_howitzer": (0.9, 0.9, 3.2),
    "mortar_array": (1.2, 0.6, 1.2),
    "spigot_mortar": (1.0, 1.0, 1.0),
    "guided_missile": (0.6, 0.4, 1.6),
    "dual_stage_missile": (0.7, 0.5, 1.8),
    "missile_pod": (1.2, 0.8, 1.5),
    "cluster_dispenser": (1.4, 0.8, 1.4),
    "flamethrower": (0.5, 0.5, 1.6),
    "heavy_laser": (0.6, 0.6, 2.5),
    "plasma_lobber": (0.8, 0.8, 2.0),
    "ciws": (0.8, 1.0, 0.8),
    "pd_laser": (0.4, 0.5, 0.4),
    "flak_cannon": (0.7, 0.7, 1.8),
    "tesla_coil": (0.6, 1.6, 0.6),
    "arc_projector": (0.5, 0.5, 1.2),
    "ion_cannon": (0.7, 0.7, 2.6),
    "drone_carrier": (2.0, 1.2, 3.0),

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
    "wheels": (0.8, 0.8, 0.8),
    "omni_wheels": (0.8, 0.8, 0.8),
    "tracked_treads": (1.0, 0.8, 3.0),
    "rhomboid_treads": (1.1, 2.6, 6.5),
    "legs": (0.6, 1.8, 0.6),
    "hover_engine": (1.5, 0.4, 1.5),
    "anti_grav": (1.6, 0.3, 1.6),
    "helicopter_rotors": (4.0, 0.2, 4.0),
    "fixed_wing_engine": (1.2, 0.6, 2.0),
    "ornithopter_wing": (1.6, 0.5, 2.2),
    "naval_propeller": (0.6, 0.6, 1.0),
    "buoyant_envelope": (1.0, 0.5, 1.0),
    "screw_drive": (1.1, 0.9, 3.4),

    # Hulls
    "light_hull": (3.0, 1.5, 4.0),
    "medium_hull": (4.0, 2.0, 6.0),
    "heavy_hull": (6.0, 3.0, 9.0),
    "assault_hull": (4.0, 2.0, 6.0),
    "airship_hull": (5.0, 5.0, 15.0),
    "flying_wing_hull": (12.0, 1.5, 8.0),
    "heavy_cruiser_hull": (5.0, 4.0, 12.0),
    "fuselage_hull": (3.0, 3.0, 10.0),
    "naval_hull": (4.0, 3.0, 12.0),
    "small_boat_hull": (2.0, 1.5, 5.0),
    "sponson_hull": (1.5, 1.5, 3.0),
    "fortress_wall_foundation": (4.0, 3.0, 4.0),
    "pillbox_foundation": (3.0, 2.0, 3.0),
    "tower_foundation": (3.0, 6.0, 3.0),
    "interceptor_hull": (3.0, 1.5, 5.0),
}
