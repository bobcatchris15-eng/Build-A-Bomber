import re

with open('e:/Build-A-Bomber/prototype/scripts/stat_calculator.gd', 'r', encoding='utf-8') as f:
    content = f.read()

if 'const ModuleDataResource' not in content:
    content = content.replace('extends Control', 'extends Control\nconst ModuleDataResource = preload("res://scripts/module_data.gd")')

with open('e:/Build-A-Bomber/prototype/scripts/stat_calculator.gd', 'w', encoding='utf-8') as f:
    f.write(content)
