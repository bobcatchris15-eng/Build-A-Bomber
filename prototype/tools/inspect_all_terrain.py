import bpy
import bmesh
import os

terrain_dir = r"E:\Kitbash-Command\prototype\assets\models\terrain"

files = [f for f in os.listdir(terrain_dir) if f.endswith(".glb")]
print(f"Total GLB files in terrain: {len(files)}")

for fname in sorted(files):
    glb_path = os.path.join(terrain_dir, fname)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)

    objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for o in objs:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        open_edges = [e for e in bm.edges if len(e.link_faces) == 1]
        if open_edges:
            print(f"FAILED: {fname} -> {o.name} has {len(open_edges)} open edges (HOLES!)")
        else:
            print(f"OK: {fname} is closed manifold")
        bm.free()
