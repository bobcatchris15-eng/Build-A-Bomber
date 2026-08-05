import json
import time
import os

blueprint_dir = "e:/Kitbash-Command/prototype/assets/blueprints/default_roster"
os.makedirs(blueprint_dir, exist_ok=True)

# Helper for standard weapon config
def make_weapon(name, type_id, facet, pos, rot=(0,0,0), scale=1.0, yaw=0.0):
    return {
        "facet": facet,
        "mount_normal": {"x": 0.0, "y": 1.0 if facet=="top" else 0.0, "z": 0.0},
        "mount_style": "pintle",
        "name": name,
        "position": {"x": pos[0], "y": pos[1], "z": pos[2]},
        "rotation": {"x": rot[0], "y": rot[1], "z": rot[2]},
        "scale": {"x": scale, "y": scale, "z": scale},
        "scale_flip_x": False,
        "sponson": False,
        "type_id": type_id,
        "yaw_offset": yaw,
        "stats": {"cost_crystal": 10, "cost_metal": 100, "dps": 10.0, "hp": 100.0, "weight": 100.0},
        "tweaks": {"barrel_count": 1.0, "barrel_length": 1.0, "caliber": 1.0, "protectedness": 0.0}
    }

units = [
    {
        "id": "bp_default_scout",
        "name": "M41 Jackrabbit Scout Buggy",
        "hull_type": "scout_hull",
        "locomotion_type": "wheels",
        "locomotion_settings": {"num_axles": 2, "wheel_size": 1.0, "wheels_per_axle": 2},
        "weapons": [
            make_weapon("machine_gun", "machine_gun", "top", (0, 0.5, 0))
        ]
    },
    {
        "id": "bp_default_light_tank",
        "name": "M22 Poodle Light Tank",
        "hull_type": "light_hull",
        "locomotion_type": "tracked_treads",
        "locomotion_settings": {"tread_width": 1.0},
        "weapons": [
            make_weapon("basic_cannon", "basic_cannon", "top", (0, 0.5, 0))
        ]
    },
    {
        "id": "bp_default_medium_tank",
        "name": "M4 Sherman-Rex Medium Tank",
        "hull_type": "medium_hull",
        "locomotion_type": "tracked_treads",
        "locomotion_settings": {"tread_width": 1.2},
        "weapons": [
            make_weapon("heavy_cannon", "heavy_cannon", "top", (0, 0.6, 0))
        ]
    },
    {
        "id": "bp_default_main_battle_tank",
        "name": "M100 Thunder-Toad MBT",
        "hull_type": "heavy_hull",
        "locomotion_type": "tracked_treads",
        "locomotion_settings": {"tread_width": 1.5},
        "weapons": [
            make_weapon("heavy_cannon", "heavy_cannon", "top", (0, 0.8, -0.5)),
            make_weapon("machine_gun", "machine_gun", "top", (0, 0.8, 0.5))
        ]
    },
    {
        "id": "bp_default_heavy_brawler",
        "name": "M33 Rhino-Puncher",
        "hull_type": "assault_hull",
        "locomotion_type": "tracked_treads",
        "locomotion_settings": {"tread_width": 1.8},
        "weapons": [
            make_weapon("rotary_cannon", "rotary_cannon", "top", (0, 1.0, 0))
        ]
    },
    {
        "id": "bp_default_anti_air",
        "name": "ZSU-44 Sky-Swatter",
        "hull_type": "medium_hull",
        "locomotion_type": "wheels",
        "locomotion_settings": {"num_axles": 4, "wheel_size": 1.2, "wheels_per_axle": 2},
        "weapons": [
            make_weapon("anti_air_missile", "anti_air_missile", "top", (0, 0.5, 0))
        ]
    },
    {
        "id": "bp_default_artillery",
        "name": "M88 Boom-Lobber",
        "hull_type": "medium_hull",
        "locomotion_type": "tracked_treads",
        "locomotion_settings": {"tread_width": 1.2},
        "weapons": [
            make_weapon("artillery_cannon", "artillery_cannon", "top", (0, 0.5, -0.5))
        ]
    },
    {
        "id": "bp_default_siege",
        "name": "M120 Crater-Maker",
        "hull_type": "heavy_hull",
        "locomotion_type": "tracked_treads",
        "locomotion_settings": {"tread_width": 1.5},
        "weapons": [
            make_weapon("heavy_cannon", "heavy_cannon", "top", (-0.5, 0.8, -0.5)),
            make_weapon("heavy_cannon", "heavy_cannon", "top", (0.5, 0.8, -0.5))
        ]
    },
    {
        "id": "bp_default_attack_chopper",
        "name": "AH-66 Whirly-Dirge",
        "hull_type": "medium_hull",
        "locomotion_type": "helicopter_rotors",
        "locomotion_settings": {"size": 1.5, "count": 4},
        "weapons": [
            make_weapon("rocket_artillery", "rocket_artillery", "top", (0, 0.5, 0)),
            make_weapon("rotary_cannon", "rotary_cannon", "top", (0, -0.5, 1.5))
        ]
    },
    {
        "id": "bp_default_drone_carrier",
        "name": "CV-99 Hive-Mind",
        "hull_type": "assault_hull",
        "locomotion_type": "hover_engine",
        "locomotion_settings": {},
        "weapons": [
            make_weapon("radar_dish", "radar_dish", "top", (0, 1.0, 0))
        ]
    },
    {
        "id": "bp_default_ew_radar",
        "name": "M195 Batfrog Electronic Warfare Vehicle",
        "hull_type": "scout_hull",
        "locomotion_type": "wheels",
        "locomotion_settings": {"num_axles": 2, "wheel_size": 1.1, "wheels_per_axle": 2},
        "weapons": [
            make_weapon("radar_dish", "radar_dish", "top", (0, 0.8, 0))
        ]
    },
    {
        "id": "bp_default_heavy_bomber",
        "name": "B-52 Carpet-Bagger",
        "hull_type": "assault_hull",
        "locomotion_type": "fixed_wing_engine",
        "locomotion_settings": {"size": 2.0, "count": 4},
        "weapons": [
            make_weapon("rocket_artillery", "rocket_artillery", "top", (-1.0, 0.5, 0.0)),
            make_weapon("rocket_artillery", "rocket_artillery", "top", (1.0, 0.5, 0.0))
        ]
    }
]

for unit in units:
    data = {
        "id": unit["id"],
        "name": unit["name"],
        "version": 1,
        "modified_unix": time.time(),
        "hull_type": unit["hull_type"],
        "hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
        "hull_size": {"x": 2.0, "y": 1.0, "z": 2.0},
        "armor_material": "hardened_steel",
        "armor_thickness": 1.0,
        "faction": "industrialists",
        "locomotion": {
            "type_id": unit["locomotion_type"],
            "settings": unit["locomotion_settings"]
        },
        "paint_job": {
            "primary_color": {"r": 0.3, "g": 0.3, "b": 0.2, "a": 1.0},
            "trim_color": {"r": 0.1, "g": 0.1, "b": 0.1, "a": 1.0},
            "camoflage_color": {"r": 0.4, "g": 0.3, "b": 0.2, "a": 1.0},
            "decal_color": {"r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0},
            "camoflage_pattern": "none",
            "decal_pattern": "stripes"
        },
        "modules": unit["weapons"]
    }
    
    with open(os.path.join(blueprint_dir, unit["id"] + ".json"), "w") as f:
        json.dump(data, f, indent=4)
        
print("Generated 12 default blueprints.")
