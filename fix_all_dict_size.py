import os

scripts_dir = 'e:/Build-A-Bomber/prototype/scripts'

for filename in os.listdir(scripts_dir):
    if filename.endswith('.gd'):
        filepath = os.path.join(scripts_dir, filename)
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        if 'catalog_data.size' in content or 'hull_catalog_data.size' in content:
            content = content.replace('catalog_data.size', 'catalog_data.get("size", Vector3.ONE)')
            content = content.replace('hull_catalog_data.size', 'hull_catalog_data.get("size", Vector3.ONE)')
            
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(content)
