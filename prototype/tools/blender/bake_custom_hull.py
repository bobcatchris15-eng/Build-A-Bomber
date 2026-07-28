"""
Blender script to bake custom hulls from Godot Hull Builder JSON exports.
Run headlessly with:
  blender.exe --background --python bake_custom_hull.py -- input.json output.glb output.json

This script:
1. Reads the Hull Builder JSON export
2. Creates corresponding Blender mesh objects for each primitive
3. Joins all objects into one mesh
4. Exports as .glb
5. Generates a sidecar .json metadata file
"""

import bpy
import bmesh
import json
import sys
import os
import math
import mathutils


def clear_scene():
    """Clear the current scene of all objects."""
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        if block.users == 0:
            bpy.data.meshes.remove(block)
    for block in list(bpy.data.materials):
        if block.users == 0:
            bpy.data.materials.remove(block)


def create_primitive_mesh(prim_type, position, rotation, scale, color):
    """Create a Blender mesh object for a primitive type."""

    # Godot to Blender coordinate conversion
    # Godot: X (right), Y (up), Z (depth/forward)
    # Blender: X (right), Y (depth/forward), Z (up)
    # So we swap Y and Z coordinates

    pos_b = (position[0], position[2], position[1])
    rot_b = (rotation[0], rotation[2], rotation[1])  # Euler angles
    scale_b = (scale[0], scale[2], scale[1])

    obj = None

    if prim_type == 0:  # BOX
        bpy.ops.mesh.primitive_cube_add(size=2.0, location=pos_b)
        obj = bpy.context.active_object
        obj.scale = scale_b
        obj.rotation_euler = rot_b

    elif prim_type == 1:  # SPHERE
        bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, location=pos_b)
        obj = bpy.context.active_object
        obj.scale = scale_b * 0.5  # Sphere radius = 0.5 in Godot
        obj.rotation_euler = rot_b

    elif prim_type == 2:  # CYLINDER
        bpy.ops.mesh.primitive_cylinder_add(radius=0.5, depth=1.0, location=pos_b)
        obj = bpy.context.active_object
        obj.scale = scale_b
        obj.rotation_euler = rot_b

    elif prim_type == 3:  # WEDGE (PrismMesh in Godot)
        bpy.ops.mesh.primitive_plane_add(size=2.0, location=pos_b)
        obj = bpy.context.active_object
        # Convert plane to a wedge shape
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        # Extrude to create wedge
        bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
        bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, 1.0))
        bm.to_mesh(obj.data)
        bm.free()
        obj.scale = scale_b
        obj.rotation_euler = rot_b

    elif prim_type == 4:  # CONE
        bpy.ops.mesh.primitive_cone_add(radius1=0.5, depth=1.0, location=pos_b)
        obj = bpy.context.active_object
        obj.scale = scale_b
        obj.rotation_euler = rot_b

    elif prim_type == 5:  # TORUS
        bpy.ops.mesh.primitive_torus_add(major_radius=0.6, minor_radius=0.3, location=pos_b)
        obj = bpy.context.active_object
        obj.scale = scale_b
        obj.rotation_euler = rot_b

    else:
        # Default to box
        bpy.ops.mesh.primitive_cube_add(size=2.0, location=pos_b)
        obj = bpy.context.active_object
        obj.scale = scale_b
        obj.rotation_euler = rot_b

    if obj:
        # Set material with color
        mat = bpy.data.materials.new(name="PrimitiveMaterial")
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
            bsdf.inputs["Metallic"].default_value = 0.2
            bsdf.inputs["Roughness"].default_value = 0.8
        if obj.data.materials:
            obj.data.materials[0] = mat
        else:
            obj.data.materials.append(mat)

    return obj


def export_glb(output_path):
    """Export the current scene as a GLB file."""
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        use_selection=True,
        export_format='GLB',
        export_yup=True,
        export_apply=True
    )
    print("Exported GLB: %s" % output_path)


def generate_sidecar_json(hull_name, primitives, output_path):
    """Generate the hull metadata sidecar JSON file."""

    # Calculate AABB from primitives
    min_x, min_y, min_z = float('inf'), float('inf'), float('inf')
    max_x, max_y, max_z = float('-inf'), float('-inf'), float('-inf')

    for prim in primitives:
        pos = prim["position"]
        scale = prim["scale"]
        # Calculate bounds for this primitive
        half_size = scale * 0.5
        p_min_x = pos[0] - half_size[0]
        p_min_y = pos[1] - half_size[1]
        p_min_z = pos[2] - half_size[2]
        p_max_x = pos[0] + half_size[0]
        p_max_y = pos[1] + half_size[1]
        p_max_z = pos[2] + half_size[2]

        min_x = min(min_x, p_min_x)
        min_y = min(min_y, p_min_y)
        min_z = min(min_z, p_min_z)
        max_x = max(max_x, p_max_x)
        max_y = max(max_y, p_max_y)
        max_z = max(max_z, p_max_z)

    size_x = max_x - min_x
    size_y = max_y - min_y
    size_z = max_z - min_z

    # Calculate average color from primitives
    avg_color = [0.7, 0.7, 0.8, 1.0]  # Default
    if primitives:
        total_r, total_g, total_b = 0.0, 0.0, 0.0
        for prim in primitives:
            color = prim["color"]
            total_r += color[0]
            total_g += color[1]
            total_b += color[2]
        avg_color = [
            total_r / len(primitives),
            total_g / len(primitives),
            total_b / len(primitives),
            1.0
        ]

    # Default stats based on volume
    volume = size_x * size_y * size_z
    base_hp = 100.0 + volume * 20.0
    base_weight = 50.0 + volume * 15.0
    base_metal = 20 + int(volume * 5.0)
    base_crystal = 5 + int(volume * 1.0)

    sidecar_data = {
        "name": hull_name,
        "hp": round(base_hp, 1),
        "weight": round(base_weight, 1),
        "metal": base_metal,
        "crystal": base_crystal,
        "size": [round(size_x, 3), round(size_y, 3), round(size_z, 3)],
        "color": [round(avg_color[0], 3), round(avg_color[1], 3), round(avg_color[2], 3), round(avg_color[3], 3)],
        "domain": domain,
        "base_energy": 50.0,
        "base_vision": 20.0,
        "is_foundation": (domain == "Static Defense"),
        "category": "hull"
    }

    with open(output_path, 'w') as f:
        json.dump(sidecar_data, f, indent=2)

    print("Generated sidecar JSON: %s" % output_path)
    return sidecar_data


def main():
    """Main entry point for the script."""
    print("Starting hull bake process...")

    # Parse command line arguments
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

    if len(argv) < 3:
        print("Usage: blender --background --python bake_custom_hull.py -- input.json output.glb output.json [domain]")
        sys.exit(1)

    input_path = argv[0]
    output_glb_path = argv[1]
    output_json_path = argv[2]
    domain = argv[3] if len(argv) > 3 else "Ground"

    print("Input: %s" % input_path)
    print("Output GLB: %s" % output_glb_path)
    print("Output JSON: %s" % output_json_path)

    # Load the input JSON
    with open(input_path, 'r') as f:
        assembly = json.load(f)

    hull_name = assembly.get("hull_name", "custom_hull")
    primitives = assembly.get("primitives", [])

    print("Building hull: %s with %d primitives" % (hull_name, len(primitives)))

    # Clear the scene
    clear_scene()

    # Create all primitive objects
    created_objects = []
    for i, prim in enumerate(primitives):
        prim_type = prim.get("type", 0)
        position = prim.get("position", [0, 0, 0])
        rotation = prim.get("rotation", [0, 0, 0])
        scale = prim.get("scale", [1, 1, 1])
        color = prim.get("color", [0.7, 0.7, 0.8, 1.0])

        obj = create_primitive_mesh(prim_type, position, rotation, scale, color)
        if obj:
            created_objects.append(obj)
            print("Created primitive %d: type=%d at %s" % (i, prim_type, position))

    if not created_objects:
        print("No objects created, nothing to export")
        sys.exit(1)

    # Join all objects into one
    for obj in created_objects[1:]:
        obj.select_set(True)

    created_objects[0].select_set(True)
    bpy.context.view_layer.objects.active = created_objects[0]
    bpy.ops.object.join()

    joined_obj = bpy.context.active_object
    joined_obj.name = hull_name

    print("Joined all primitives into single mesh")

    # Export GLB
    export_glb(output_glb_path)

    # Generate sidecar JSON
    generate_sidecar_json(hull_name, primitives, output_json_path)

    print("Hull bake complete!")


if __name__ == "__main__":
    main()
