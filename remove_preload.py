import re

def remove_line(path):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    content = content.replace('const ModuleData = preload("res://scripts/module_data.gd")', '')

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

remove_line('e:/Build-A-Bomber/prototype/scripts/module_placer.gd')
remove_line('e:/Build-A-Bomber/prototype/scripts/stat_calculator.gd')
