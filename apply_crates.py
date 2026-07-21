import re

with open('e:/Build-A-Bomber/prototype/scripts/module_placer.gd', 'r', encoding='utf-8') as f:
    content = f.read()

ready_func = '''func _ready():
\t# Spawn some scale reference boxes (1x1x1 meters)
\tfor x in [-8, 8]:
\t\tvar mesh_inst = MeshInstance3D.new()
\t\tvar box = BoxMesh.new()
\t\tbox.size = Vector3(1, 1, 1)
\t\tmesh_inst.mesh = box
\t\tvar mat = StandardMaterial3D.new()
\t\tmat.albedo_color = Color(0.8, 0.4, 0.2)
\t\tmesh_inst.material_override = mat
\t\tmesh_inst.position = Vector3(x, 0.5, -4)
\t\tadd_child(mesh_inst)'''

content = content.replace('var selected_module: Node3D = null', 'var selected_module: Node3D = null\n\n' + ready_func)

with open('e:/Build-A-Bomber/prototype/scripts/module_placer.gd', 'w', encoding='utf-8') as f:
    f.write(content)
