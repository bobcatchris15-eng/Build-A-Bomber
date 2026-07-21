import json
import sys
import os
from pathlib import Path

# Load module_sizes.py dynamically
sys.path.append(r'E:\Build-A-Bomber')
import module_sizes

sizes = module_sizes.sizes

hulls_dir = Path(r'E:\Build-A-Bomber\prototype\assets\models\hulls')
for json_file in hulls_dir.glob('*.json'):
    hull_name = json_file.stem
    if hull_name in sizes:
        with open(json_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        s = sizes[hull_name]
        data['size'] = [s[0], s[1], s[2]]
        
        with open(json_file, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=4)
            
print("Updated all hull JSON files")
