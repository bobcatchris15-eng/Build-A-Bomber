import re

def fix_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    # We might have catalog_data.size or hull_catalog_data.size
    content = content.replace('catalog_data.size', 'catalog_data.get("size", Vector3.ONE)')
    content = content.replace('hull_catalog_data.size', 'hull_catalog_data.get("size", Vector3.ONE)')

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

fix_file('e:/Build-A-Bomber/prototype/scripts/module_placer.gd')
fix_file('e:/Build-A-Bomber/prototype/scripts/drag_drop_manager.gd')
