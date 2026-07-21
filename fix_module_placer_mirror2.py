import re

with open('e:/Build-A-Bomber/prototype/scripts/module_placer.gd', 'r', encoding='utf-8') as f:
    content = f.read()

bad_sig2 = '''func _reclassify_module_after_drag(module: Node3D, normal: Vector3, _is_mirror_call: bool = false):'''
good_sig2 = '''func _reclassify_module_after_drag(module: Node3D, normal: Vector3, is_mirror: bool = false):'''
content = content.replace(bad_sig2, good_sig2)

bad_check2 = '''\tif not _is_mirror_call and module.has_meta("mirrored_counterpart"):'''
good_check2 = '''\tif not is_mirror and module.has_meta("mirrored_counterpart"):'''
content = content.replace(bad_check2, good_check2)

with open('e:/Build-A-Bomber/prototype/scripts/module_placer.gd', 'w', encoding='utf-8') as f:
    f.write(content)
