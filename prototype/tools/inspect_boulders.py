import bpy
import bmesh
import os

terrain_dir = r"E:\Kitbash-Command\prototype\assets\models\terrain"

for i in range(6):
    glb_path = os.path.join(terrain_dir, f"boulder_{i}.glb")
    if not os.path.exists(glb_path):
        print(f"File not found: {glb_path}")
        continue

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)

    objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    print(f"\n--- boulder_{i}.glb ---")
    for o in objs:
        mesh = o.data
        bm = bmesh.new()
        bm.from_mesh(mesh)
        print(f"Object: {o.name}, Verts: {len(bm.verts)}, Faces: {len(bm.faces)}")
        
        # Check for open edges (boundary edges with only 1 link face)
        open_edges = [e for e in bm.edges if len(e.link_faces) == 1]
        print(f"Open boundary edges (holes): {len(open_edges)}")
        
        # Check material backface culling or double sided
        for m in o.data.materials:
            print(f"Material: {m.name}, use_backface_culling: {getattr(m, 'use_backface_culling', None)}")
        bm.free()
