import re

with open('e:/Build-A-Bomber/prototype/scripts/module_placer.gd', 'r', encoding='utf-8') as f:
    content = f.read()

bad_col = '''\t\tif authored_mesh:
\t\t\tcol.shape = authored_mesh.create_convex_shape()
\t\t\tcol.scale = phys_mesh.scale
\t\t\tcol.rotation = phys_mesh.rotation
\t\telse:
\t\t\tcol.scale = Vector3.ONE
\t\t\tvar col_box = BoxShape3D.new()
\t\t\tcol_box.size = catalog_data.get("size", Vector3.ONE) * hull_scale * armor_bulk
\t\t\tcol.shape = col_box
\t\t\tcol.rotation = phys_mesh.rotation'''

good_col = '''\t\tcol.scale = Vector3.ONE
\t\tvar col_box = BoxShape3D.new()
\t\tcol_box.size = catalog_data.get("size", Vector3.ONE) * hull_scale * armor_bulk
\t\tcol.shape = col_box
\t\tcol.rotation = phys_mesh.rotation'''

content = content.replace(bad_col, good_col)

with open('e:/Build-A-Bomber/prototype/scripts/module_placer.gd', 'w', encoding='utf-8') as f:
    f.write(content)
