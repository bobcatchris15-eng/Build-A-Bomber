import re

with open('e:/Build-A-Bomber/prototype/scripts/drag_drop_manager.gd', 'r', encoding='utf-8') as f:
    content = f.read()

bad_mat = '''\t\tget_node("/root/MainLab").add_child(ghost_mesh_mirror)
\t\tghost_mesh_mirror.material_override = mat'''

good_mat = '''\t\tget_node("/root/MainLab").add_child(ghost_mesh_mirror)
\t\tghost_mesh_mirror.material_override = ghost_mesh.material_override'''

content = content.replace(bad_mat, good_mat)

with open('e:/Build-A-Bomber/prototype/scripts/drag_drop_manager.gd', 'w', encoding='utf-8') as f:
    f.write(content)
