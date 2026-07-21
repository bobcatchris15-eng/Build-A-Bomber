with open('e:/Build-A-Bomber/prototype/scripts/module_placer.gd', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace('\r\n', '\n').replace('\r', '\n')

with open('e:/Build-A-Bomber/prototype/scripts/module_placer.gd', 'w', encoding='utf-8', newline='\n') as f:
    f.write(content)
