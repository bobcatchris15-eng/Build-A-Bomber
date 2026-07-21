import os

def fix_module_data(path):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Add the preload back at the top under extends Node3D/Node
    if 'extends Node3D' in content:
        content = content.replace('extends Node3D', 'extends Node3D\nconst ModuleDataResource = preload("res://scripts/module_data.gd")')
    elif 'extends Node' in content:
        content = content.replace('extends Node', 'extends Node\nconst ModuleDataResource = preload("res://scripts/module_data.gd")')

    content = content.replace('ModuleData.new()', 'ModuleDataResource.new()')
    content = content.replace('as ModuleData', 'as ModuleDataResource')
    content = content.replace('data: ModuleData', 'data: ModuleDataResource')

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

fix_module_data('e:/Build-A-Bomber/prototype/scripts/module_placer.gd')
fix_module_data('e:/Build-A-Bomber/prototype/scripts/stat_calculator.gd')
