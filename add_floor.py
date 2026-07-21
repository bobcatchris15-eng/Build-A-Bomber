import sys

with open('prototype/scenes/MainLab.tscn', 'r') as f:
    lines = f.read().split('\n')

new_lines = []
inserted_mats = False
inserted_nodes = False

for line in lines:
    if line.startswith('[node name="MainLab"') and not inserted_mats:
        new_lines.extend([
            '[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_floor"]',
            'albedo_color = Color(0.2, 0.25, 0.3, 1)',
            '',
            '[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_crate"]',
            'albedo_color = Color(0.6, 0.4, 0.2, 1)',
            ''
        ])
        inserted_mats = True
        
    new_lines.append(line)
    
    if line.startswith('[node name="Camera3D"') and not inserted_nodes:
        # We need to skip to the end of the camera node before inserting
        pass
        
    if line.startswith('[node name="Hull"') and not inserted_nodes:
        # Insert before Hull
        new_lines.insert(-1, '')
        new_lines.insert(-1, '[node name="Floor" type="CSGBox3D" parent="."]')
        new_lines.insert(-1, 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -2, 0)')
        new_lines.insert(-1, 'size = Vector3(100, 1, 100)')
        new_lines.insert(-1, 'material = SubResource("StandardMaterial3D_floor")')
        new_lines.insert(-1, '')
        new_lines.insert(-1, '[node name="Crate1" type="CSGBox3D" parent="."]')
        new_lines.insert(-1, 'transform = Transform3D(0.866, 0, 0.5, 0, 1, 0, -0.5, 0, 0.866, -10, -0.5, -5)')
        new_lines.insert(-1, 'size = Vector3(2, 2, 2)')
        new_lines.insert(-1, 'material = SubResource("StandardMaterial3D_crate")')
        new_lines.insert(-1, '')
        new_lines.insert(-1, '[node name="Crate2" type="CSGBox3D" parent="."]')
        new_lines.insert(-1, 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 12, -0.5, 8)')
        new_lines.insert(-1, 'size = Vector3(2, 2, 4)')
        new_lines.insert(-1, 'material = SubResource("StandardMaterial3D_crate")')
        new_lines.insert(-1, '')
        new_lines.insert(-1, '[node name="Crate3" type="CSGBox3D" parent="."]')
        new_lines.insert(-1, 'transform = Transform3D(0.707, 0, -0.707, 0, 1, 0, 0.707, 0, 0.707, -8, -0.75, 12)')
        new_lines.insert(-1, 'size = Vector3(1.5, 1.5, 1.5)')
        new_lines.insert(-1, 'material = SubResource("StandardMaterial3D_crate")')
        new_lines.insert(-1, '')
        new_lines.insert(-1, '[node name="Crate4" type="CSGBox3D" parent="."]')
        new_lines.insert(-1, 'transform = Transform3D(0.965, 0, 0.258, 0, 1, 0, -0.258, 0, 0.965, 15, 0, -10)')
        new_lines.insert(-1, 'size = Vector3(3, 3, 3)')
        new_lines.insert(-1, 'material = SubResource("StandardMaterial3D_crate")')
        new_lines.insert(-1, '')
        inserted_nodes = True

with open('prototype/scenes/MainLab.tscn', 'w') as f:
    f.write('\n'.join(new_lines))
print("Added floor and crates to MainLab.tscn")
