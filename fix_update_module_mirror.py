import re

with open('e:/Build-A-Bomber/prototype/scripts/module_placer.gd', 'r', encoding='utf-8') as f:
    content = f.read()

bad_mirror_check = '''\t\tVisualBuilder.rebuild_visual(module)
\t\tif is_mirror:
\t\t\t_apply_mirror_flip(module)'''

good_mirror_check = '''\t\tVisualBuilder.rebuild_visual(module)
\t\tif module.get_meta("is_mirror", false):
\t\t\t_apply_mirror_flip(module)'''

content = content.replace(bad_mirror_check, good_mirror_check)

with open('e:/Build-A-Bomber/prototype/scripts/module_placer.gd', 'w', encoding='utf-8') as f:
    f.write(content)
