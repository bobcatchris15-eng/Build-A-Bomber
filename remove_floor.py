import re

with open('e:/Build-A-Bomber/prototype/scenes/MainLab.tscn', 'r', encoding='utf-8') as f:
    content = f.read()

# Define the exact text block for the Floor node
floor_block = '''[node name="Floor" type="CSGBox3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -2, 0)
size = Vector3(100, 1, 100)
material = SubResource("StandardMaterial3D_floor")'''

if floor_block in content:
    content = content.replace(floor_block, '')
else:
    print("Floor block not found exactly as expected.")

with open('e:/Build-A-Bomber/prototype/scenes/MainLab.tscn', 'w', encoding='utf-8') as f:
    f.write(content)
