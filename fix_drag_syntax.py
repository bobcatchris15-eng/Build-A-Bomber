import re

with open('e:/Build-A-Bomber/prototype/scripts/drag_drop_manager.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix 1: _update_ghost_mesh_hull
bad_1 = '''\tif not ghost_mesh.mesh or (ghost_mesh.mesh is BoxMesh and ghost_mesh.mesh.size != cat_size):
\t\tvar cat_size = catalog_data.get("size", Vector3.ONE)
\t\tvar box = BoxMesh.new()
\t\tbox.size = cat_size
\t\tghost_mesh.mesh = box'''

good_1 = '''\tvar cat_size = catalog_data.get("size", Vector3.ONE)
\tif not ghost_mesh.mesh or (ghost_mesh.mesh is BoxMesh and ghost_mesh.mesh.size != cat_size):
\t\tvar box = BoxMesh.new()
\t\tbox.size = cat_size
\t\tghost_mesh.mesh = box'''

content = content.replace(bad_1, good_1)

# Fix 2: _update_ghost_mesh
bad_2 = '''\tif not ghost_mesh.mesh or (ghost_mesh.mesh is BoxMesh and ghost_mesh.mesh.size != cat_size):
\t\tvar cat_size = catalog_data.get("size", Vector3.ONE)
\t\tvar box = BoxMesh.new()
\t\tbox.size = cat_size
\t\tghost_mesh.mesh = box'''

good_2 = '''\tvar cat_size = catalog_data.get("size", Vector3.ONE)
\tif not ghost_mesh.mesh or (ghost_mesh.mesh is BoxMesh and ghost_mesh.mesh.size != cat_size):
\t\tvar box = BoxMesh.new()
\t\tbox.size = cat_size
\t\tghost_mesh.mesh = box'''

content = content.replace(bad_2, good_2)

# Fix mat issue in mirror logic
# Wait, "mat not declared"
bad_mat = '''\t\t\tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
\t\t\tmat.albedo_color = Color(1, 1, 1, 0.4)'''

good_mat = '''\t\t\tvar mat = StandardMaterial3D.new()
\t\t\tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
\t\t\tmat.albedo_color = Color(1, 1, 1, 0.4)'''

content = content.replace(bad_mat, good_mat)

with open('e:/Build-A-Bomber/prototype/scripts/drag_drop_manager.gd', 'w', encoding='utf-8') as f:
    f.write(content)
