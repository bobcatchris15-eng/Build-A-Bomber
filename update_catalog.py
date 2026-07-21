import re
import sys
import os

# Load module_sizes.py dynamically
sys.path.append(r'E:\Build-A-Bomber')
import module_sizes

sizes = module_sizes.sizes

catalog_path = r'E:\Build-A-Bomber\prototype\scripts\module_catalog.gd'
with open(catalog_path, 'r', encoding='utf-8') as f:
    content = f.read()

def replace_size(match):
    module_name = match.group(1)
    if module_name in sizes:
        s = sizes[module_name]
        return f'"{module_name}": {{\n{match.group(2)}"size": Vector3({s[0]}, {s[1]}, {s[2]})'
    return match.group(0)

# The dictionary in GDScript is structured like:
# "module_name": {
#     ...
#     "size": Vector3(x, y, z),
#     ...
# }
# We need a regex that finds the module name, then finds its "size" key inside the block.
# Since regex across multiple lines is tricky, let's just do a simple string replace for each known module.
for mod_name, s in sizes.items():
    # Find the block for this module
    pattern = r'("' + mod_name + r'":\s*\{.*?"size":\s*Vector3\()([^)]+)(\))'
    content = re.sub(pattern, f'\\g<1>{s[0]}, {s[1]}, {s[2]}\\3', content, flags=re.DOTALL)

with open(catalog_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Updated module_catalog.gd")
