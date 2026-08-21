import bpy
import bmesh
import os

glb_path = r"E:\Kitbash-Command\prototype\assets\models\terrain\boulder_0.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
for o in objs:
    bm = bmesh.new()
    bm.from_mesh(o.data)
    print(f"Before remove_doubles: verts={len(bm.verts)}, open_edges={len([e for e in bm.edges if len(e.link_faces) == 1])}")
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.001)
    print(f"After remove_doubles: verts={len(bm.verts)}, open_edges={len([e for e in bm.edges if len(e.link_faces) == 1])}")
