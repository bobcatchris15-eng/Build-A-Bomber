#!/usr/bin/env python3
import os
import shutil
import json

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    proto_dir = os.path.abspath(os.path.join(script_dir, ".."))
    root_dir = os.path.abspath(os.path.join(proto_dir, ".."))
    
    new_hulls_dir = os.path.join(root_dir, "New_hulls")
    target_dir = os.path.join(proto_dir, "assets", "models", "hulls")
    os.makedirs(target_dir, exist_ok=True)

    hulls_def = [
        {
            'src': 'hull_01_scout.glb',
            'stem': 'scout_hull_mod_4a2',
            'name': 'Scout Mod. 4A2',
            'hp': 160.0, 'weight': 75.0, 'metal': 35, 'crystal': 8,
            'base_energy': 35.0, 'base_vision': 26.0,
            'size': [2.2, 1.0, 4.5], 'color': [0.48, 0.52, 0.56, 1.0]
        },
        {
            'src': 'hull_02_light_tank.glb',
            'stem': 'light_hull_mod_4a3',
            'name': 'Light Mod. 4A3',
            'hp': 240.0, 'weight': 115.0, 'metal': 55, 'crystal': 12,
            'base_energy': 45.0, 'base_vision': 22.0,
            'size': [2.6, 1.3, 5.5], 'color': [0.52, 0.55, 0.6, 1.0]
        },
        {
            'src': 'hull_03_medium_tank.glb',
            'stem': 'medium_hull_mod_4a4',
            'name': 'Medium Mod. 4A4',
            'hp': 420.0, 'weight': 260.0, 'metal': 110, 'crystal': 22,
            'base_energy': 75.0, 'base_vision': 20.0,
            'size': [2.9, 1.45, 6.5], 'color': [0.58, 0.6, 0.64, 1.0]
        },
        {
            'src': 'hull_04_heavy_tank.glb',
            'stem': 'heavy_hull_mod_4a5',
            'name': 'Heavy Mod. 4A5',
            'hp': 850.0, 'weight': 580.0, 'metal': 220, 'crystal': 45,
            'base_energy': 130.0, 'base_vision': 18.0,
            'size': [4.55, 1.7, 7.5], 'color': [0.48, 0.5, 0.53, 1.0]
        },
        {
            'src': 'hull_05_medium_transport.glb',
            'stem': 'transport_hull_mod_4a6',
            'name': 'Transport Mod. 4A6',
            'hp': 380.0, 'weight': 210.0, 'metal': 85, 'crystal': 15,
            'base_energy': 60.0, 'base_vision': 22.0,
            'size': [2.7, 1.65, 6.8], 'color': [0.5, 0.54, 0.58, 1.0]
        },
        {
            'src': 'hull_06_heavy_transport.glb',
            'stem': 'heavy_transport_hull_mod_4a7',
            'name': 'Heavy Transport Mod. 4A7',
            'hp': 720.0, 'weight': 480.0, 'metal': 180, 'crystal': 35,
            'base_energy': 110.0, 'base_vision': 19.0,
            'size': [4.45, 1.9, 8.2], 'color': [0.44, 0.47, 0.5, 1.0]
        },
        {
            'src': 'hull_07_open_topped_transport.glb',
            'stem': 'open_transport_hull_mod_4a8',
            'name': 'Open Transport Mod. 4A8',
            'hp': 320.0, 'weight': 170.0, 'metal': 70, 'crystal': 12,
            'base_energy': 55.0, 'base_vision': 24.0,
            'size': [2.7, 1.486, 6.2], 'color': [0.54, 0.56, 0.6, 1.0]
        },
        {
            'src': 'hull_08_assault_vehicle.glb',
            'stem': 'assault_hull_mod_4a9',
            'name': 'Assault Mod. 4A9',
            'hp': 650.0, 'weight': 420.0, 'metal': 160, 'crystal': 30,
            'base_energy': 90.0, 'base_vision': 19.0,
            'size': [3.6, 1.7, 7.0], 'color': [0.42, 0.44, 0.48, 1.0]
        }
    ]

    for item in hulls_def:
        src_glb = os.path.join(new_hulls_dir, item['src'])
        dst_glb = os.path.join(target_dir, item['stem'] + '.glb')
        dst_json = os.path.join(target_dir, item['stem'] + '.json')
        
        shutil.copyfile(src_glb, dst_glb)
        
        sidecar = {
            'name': item['name'],
            'hp': item['hp'],
            'weight': item['weight'],
            'metal': item['metal'],
            'crystal': item['crystal'],
            'base_energy': item['base_energy'],
            'base_vision': item['base_vision'],
            'size': item['size'],
            'color': item['color'],
            'category': 'hull'
        }
        with open(dst_json, 'w') as f:
            json.dump(sidecar, f, indent=2)
        print(f"Imported {item['stem']}: {item['name']}")

if __name__ == "__main__":
    main()
