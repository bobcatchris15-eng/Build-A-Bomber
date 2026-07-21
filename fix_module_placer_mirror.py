import re

with open('e:/Build-A-Bomber/prototype/scripts/module_placer.gd', 'r', encoding='utf-8') as f:
    content = f.read()

bad_sig = '''func _place_weapon(type_id: String, pos: Vector3, normal: Vector3) -> Node3D:'''
good_sig = '''func _place_weapon(type_id: String, pos: Vector3, normal: Vector3, is_mirror: bool = false) -> Node3D:'''
content = content.replace(bad_sig, good_sig)

bad_mirror = '''\t\tVisualBuilder.rebuild_visual(module)
\t\tif _is_mirror_call:
\t\t\t_apply_mirror_flip(module)'''

good_mirror = '''\t\tVisualBuilder.rebuild_visual(module)
\t\tif is_mirror:
\t\t\t_apply_mirror_flip(module)'''

content = content.replace(bad_mirror, good_mirror)

# Also fix the call inside _place_weapon_from_ui
bad_call = '''\t\t\tvar mirrored = _place_weapon(type_id, mirrored_pos, mirrored_normal)
\t\t\tmirrored.set_meta("is_mirror", true)'''

good_call = '''\t\t\tvar mirrored = _place_weapon(type_id, mirrored_pos, mirrored_normal, true)
\t\t\tmirrored.set_meta("is_mirror", true)'''

content = content.replace(bad_call, good_call)

with open('e:/Build-A-Bomber/prototype/scripts/module_placer.gd', 'w', encoding='utf-8') as f:
    f.write(content)
