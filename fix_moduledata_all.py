import os

def fix_module_data(path):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Add the preload if not present
    if 'ModuleDataResource' not in content:
        if 'extends Node' in content:
            content = content.replace('extends Node', 'extends Node\nconst ModuleDataResource = preload("res://scripts/module_data.gd")')
        elif 'extends Control' in content:
            content = content.replace('extends Control', 'extends Control\nconst ModuleDataResource = preload("res://scripts/module_data.gd")')

    content = content.replace('ModuleData.new()', 'ModuleDataResource.new()')
    content = content.replace('as ModuleData', 'as ModuleDataResource')
    content = content.replace('data: ModuleData', 'data: ModuleDataResource')

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

fix_module_data('e:/Build-A-Bomber/prototype/scripts/blueprint_manager.gd')
fix_module_data('e:/Build-A-Bomber/prototype/scripts/debug_tuning_panel.gd')
fix_module_data('e:/Build-A-Bomber/prototype/scripts/skirmish.gd')
