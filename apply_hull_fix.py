import re

with open('e:/Build-A-Bomber/prototype/scripts/drag_drop_manager.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix 1: _update_ghost_mesh_hull
old_hull_func = '''func _update_ghost_mesh_hull(type_id: String):
\tif not ghost_mesh:
\t\tghost_mesh = MeshInstance3D.new()
\t\tget_node("/root/MainLab").add_child(ghost_mesh)
\t\t
\t\t# Setup ghost material
\t\tvar mat = StandardMaterial3D.new()
\t\tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
\t\tmat.albedo_color = Color(1, 1, 1, 0.4)
\t\tghost_mesh.material_override = mat
\t\t
\tghost_mesh.visible = true
\tvar ModuleCatalog = preload("res://scripts/module_catalog.gd")
\tvar catalog_data = ModuleCatalog.get_module_data(type_id)
\t
\tif not ghost_mesh.mesh or (ghost_mesh.mesh is BoxMesh and ghost_mesh.mesh.size != catalog_data.size):
\t\tvar box = BoxMesh.new()
\t\tbox.size = catalog_data.size
\t\tghost_mesh.mesh = box
\t\t
\tghost_mesh.position = Vector3(0, catalog_data.size.y / 2.0, 0)'''

new_hull_func = '''func _update_ghost_mesh_hull(type_id: String):
\tif not ghost_mesh:
\t\tghost_mesh = MeshInstance3D.new()
\t\tget_node("/root/MainLab").add_child(ghost_mesh)
\t\t
\t\t# Setup ghost material
\t\tvar mat = StandardMaterial3D.new()
\t\tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
\t\tmat.albedo_color = Color(1, 1, 1, 0.4)
\t\tghost_mesh.material_override = mat
\t\t
\tghost_mesh.visible = true
\tif ghost_mesh_mirror: ghost_mesh_mirror.visible = false
\tvar ModuleCatalog = preload("res://scripts/module_catalog.gd")
\tvar catalog_data = ModuleCatalog.get_module_data(type_id)
\tvar cat_size = catalog_data.get("size", Vector3.ONE)
\t
\tif not ghost_mesh.mesh or (ghost_mesh.mesh is BoxMesh and ghost_mesh.mesh.size != cat_size):
\t\tvar box = BoxMesh.new()
\t\tbox.size = cat_size
\t\tghost_mesh.mesh = box
\t\t
\tghost_mesh.position = Vector3(0, cat_size.y / 2.0, 0)'''

content = content.replace(old_hull_func, new_hull_func)

with open('e:/Build-A-Bomber/prototype/scripts/drag_drop_manager.gd', 'w', encoding='utf-8') as f:
    f.write(content)
