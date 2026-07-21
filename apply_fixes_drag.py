import re

with open('e:/Build-A-Bomber/prototype/scripts/drag_drop_manager.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix 1: Add var ghost_mesh_mirror
content = content.replace('var ghost_mesh: MeshInstance3D = null', 'var ghost_mesh: MeshInstance3D = null\nvar ghost_mesh_mirror: MeshInstance3D = null')

# Fix 2: Destroy mirror
content = content.replace(
    'ghost_mesh.queue_free()\n\t\tghost_mesh = null',
    'ghost_mesh.queue_free()\n\t\tghost_mesh = null\n\tif ghost_mesh_mirror:\n\t\tghost_mesh_mirror.queue_free()\n\t\tghost_mesh_mirror = null'
)

# Fix 3: Hide mirror
content = content.replace(
    'if ghost_mesh: ghost_mesh.visible = false',
    'if ghost_mesh: ghost_mesh.visible = false\n\t\tif ghost_mesh_mirror: ghost_mesh_mirror.visible = false'
)

# Fix 4: Create mirror in _update_ghost_mesh
update_mirror = '''\tif not ghost_mesh_mirror:
\t\tghost_mesh_mirror = MeshInstance3D.new()
\t\tget_node("/root/MainLab").add_child(ghost_mesh_mirror)
\t\tghost_mesh_mirror.material_override = mat

\tvar is_symmetric = catalog_data.get("is_symmetric", true)
\tif not is_symmetric and abs(result.position.x) > 0.1:
\t\tghost_mesh_mirror.visible = true
\t\tif not ghost_mesh_mirror.mesh or (ghost_mesh_mirror.mesh is BoxMesh and ghost_mesh_mirror.mesh.size != cat_size):
\t\t\tvar box2 = BoxMesh.new()
\t\t\tbox2.size = cat_size
\t\t\tghost_mesh_mirror.mesh = box2
\t\tghost_mesh_mirror.position = Vector3(-result.position.x, ghost_mesh.position.y, result.position.z)
\telse:
\t\tghost_mesh_mirror.visible = false'''

content = content.replace(
    'var box = BoxMesh.new()\n\t\tbox.size = catalog_data.size\n\t\tghost_mesh.mesh = box',
    'var cat_size = catalog_data.get("size", Vector3.ONE)\n\t\tvar box = BoxMesh.new()\n\t\tbox.size = cat_size\n\t\tghost_mesh.mesh = box'
)

content = content.replace(
    'ghost_mesh.mesh is BoxMesh and ghost_mesh.mesh.size != catalog_data.size',
    'ghost_mesh.mesh is BoxMesh and ghost_mesh.mesh.size != cat_size'
)

content = content.replace(
    'ghost_mesh.position = result.position + Vector3(0, catalog_data.size.y / 2.0, 0)',
    'ghost_mesh.position = result.position + Vector3(0, cat_size.y / 2.0, 0)\n' + update_mirror
)

with open('e:/Build-A-Bomber/prototype/scripts/drag_drop_manager.gd', 'w', encoding='utf-8') as f:
    f.write(content)
