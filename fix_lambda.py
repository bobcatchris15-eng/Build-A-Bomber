import re

with open('e:/Build-A-Bomber/prototype/scripts/module_placer.gd', 'r', encoding='utf-8') as f:
    content = f.read()

pattern = r"func _apply_mirror_flip.*?flip_meshes\.call\(module, flip_meshes\)"
replacement = '''func _apply_mirror_flip(module: Node3D):
\tif not module or not is_instance_valid(module): return
\tif not module.has_meta("scale_flip_x"): return
\tif not module.get_meta("scale_flip_x"): return
\tmodule.scale.x = abs(module.scale.x)
\tmodule.scale.z = abs(module.scale.z)
\t_flip_meshes_recursive(module)'''

new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)

with open('e:/Build-A-Bomber/prototype/scripts/module_placer.gd', 'w', encoding='utf-8', newline='\n') as f:
    f.write(new_content)
