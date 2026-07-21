import re

with open('e:/Build-A-Bomber/prototype/scripts/module_placer.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix 1: Add _flip_meshes_recursive at the end
flip_func = '''
func _flip_meshes_recursive(node: Node):
\tif node is MeshInstance3D:
\t\tnode.scale.z = -abs(node.scale.z)
\tfor child in node.get_children():
\t\t_flip_meshes_recursive(child)

func _apply_mirror_flip(module: Node3D):
\tif not module or not is_instance_valid(module): return
\tif not module.has_meta("scale_flip_x"): return
\tif not module.get_meta("scale_flip_x"): return
\tmodule.scale.x = abs(module.scale.x)
\tmodule.scale.z = abs(module.scale.z)
\t_flip_meshes_recursive(module)
'''
content += flip_func

# Fix 2: Add mirror flips to wheels/treads
content = content.replace(
    'if wheel.has_meta("module_data"):\n\t\t\t\t\t\twheel.get_meta("module_data").scale_multiplier = wheel.scale\n\t\t\t\t\tspawned_wheels.append(wheel)',
    'if wheel.has_meta("module_data"):\n\t\t\t\t\t\twheel.get_meta("module_data").scale_multiplier = wheel.scale\n\t\t\t\t\tif side < 0:\n\t\t\t\t\t\twheel.set_meta("scale_flip_x", true)\n\t\t\t\t\t\t_apply_mirror_flip(wheel)\n\t\t\t\t\tspawned_wheels.append(wheel)'
)
content = content.replace(
    'if tread.has_meta("module_data"):\n\t\t\t\t\ttread.get_meta("module_data").scale_multiplier = tread.scale\n\t\t\t\tspawned_wheels.append(tread)',
    'if tread.has_meta("module_data"):\n\t\t\t\t\ttread.get_meta("module_data").scale_multiplier = tread.scale\n\t\t\t\tif side < 0:\n\t\t\t\t\ttread.set_meta("scale_flip_x", true)\n\t\t\t\t\t_apply_mirror_flip(tread)\n\t\t\t\tspawned_wheels.append(tread)'
)
content = content.replace(
    'if loop.has_meta("module_data"):\n\t\t\t\t\tloop.get_meta("module_data").scale_multiplier = loop.scale\n\t\t\t\tspawned_wheels.append(loop)',
    'if loop.has_meta("module_data"):\n\t\t\t\t\tloop.get_meta("module_data").scale_multiplier = loop.scale\n\t\t\t\tif side < 0:\n\t\t\t\t\tloop.set_meta("scale_flip_x", true)\n\t\t\t\t\t_apply_mirror_flip(loop)\n\t\t\t\tspawned_wheels.append(loop)'
)
content = content.replace(
    'if drum.has_meta("module_data"):\n\t\t\t\t\tdrum.get_meta("module_data").scale_multiplier = drum.scale\n\t\t\t\tspawned_wheels.append(drum)',
    'if drum.has_meta("module_data"):\n\t\t\t\t\tdrum.get_meta("module_data").scale_multiplier = drum.scale\n\t\t\t\tif side < 0:\n\t\t\t\t\tdrum.set_meta("scale_flip_x", true)\n\t\t\t\t\t_apply_mirror_flip(drum)\n\t\t\t\tspawned_wheels.append(drum)'
)

# Fix 3: Hull scaling in update_hull_appearance
old_scale = 'phys_mesh.scale = hull_scale * armor_bulk'
new_scale = '''var aabb = authored_mesh.get_aabb().size
\t\tvar cat_size = catalog_data.get("size", Vector3.ONE)
\t\tvar max_target = max(cat_size.x, max(cat_size.y, cat_size.z))
\t\tvar max_authored = max(aabb.x, max(aabb.y, aabb.z))
\t\tvar fit_scale = max_target / max_authored if max_authored > 0.0 else 1.0
\t\tphys_mesh.scale = Vector3(fit_scale, fit_scale, fit_scale) * hull_scale * armor_bulk'''
content = content.replace(old_scale, new_scale)

# Fix 4: Hull collision scale
old_col = 'col.scale = hull_scale * armor_bulk'
new_col = 'col.scale = phys_mesh.scale'
content = content.replace(old_col, new_col)

# Fix 5: Apply mirror to visual builder updates
old_visual = 'VisualBuilder.rebuild_visual(mirror)'
new_visual = 'VisualBuilder.rebuild_visual(mirror)\n\t\t\t\t_apply_mirror_flip(mirror)'
content = content.replace(old_visual, new_visual)

old_visual2 = 'VisualBuilder.rebuild_visual(module)'
new_visual2 = 'VisualBuilder.rebuild_visual(module)\n\t\tif _is_mirror_call:\n\t\t\t_apply_mirror_flip(module)'
content = content.replace(old_visual2, new_visual2)

with open('e:/Build-A-Bomber/prototype/scripts/module_placer.gd', 'w', encoding='utf-8') as f:
    f.write(content)
