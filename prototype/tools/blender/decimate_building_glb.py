"""
Fixes bloated Tripo-generated building GLBs (run_tripo.py's raw marching-cubes
output, 900k-2.5M vertices each, 30-73MB per file - vs. every other GLB in the
project at 3-90KB) by decimating down to a game-reasonable triangle budget in
Blender before re-exporting.

Run: UPBGE-0.30-windows-x86_64\\blender.exe --background --python tools\\blender\\decimate_building_glb.py -- <in.glb> <out.glb> [target_tris]
"""
import bpy
import sys
import os

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
in_path = argv[0]
out_path = argv[1]
target_tris = int(argv[2]) if len(argv) > 2 else 6000

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=in_path)

mesh_objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
if not mesh_objs:
    print(f"ERROR: no mesh objects imported from {in_path}")
    sys.exit(1)

bpy.ops.object.select_all(action='DESELECT')
for o in mesh_objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = mesh_objs[0]
if len(mesh_objs) > 1:
    bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active

total_tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
print(f"{in_path}: {len(obj.data.vertices)} verts, {total_tris} tris before decimate")

# Raw TripoSG marching-cubes output is frequently NOT one clean watertight
# blob - some generations scatter disconnected noise fragments (stray
# shards floating around the main solid). Decimating the whole mess
# proportionally shreds the main shape into confetti along with the
# noise. Fix: split into loose parts, keep only the largest (by vertex
# count - the actual building), discard the rest, THEN decimate just that.
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.separate(type='LOOSE')
bpy.ops.object.mode_set(mode='OBJECT')
parts = [o for o in bpy.context.scene.objects if o.type == 'MESH']
if len(parts) > 1:
    parts.sort(key=lambda o: len(o.data.vertices), reverse=True)
    largest = parts[0]
    dropped_verts = sum(len(o.data.vertices) for o in parts[1:])
    print(f"{in_path}: {len(parts)} loose islands - keeping largest ({len(largest.data.vertices)} verts), dropping {len(parts) - 1} noise fragments ({dropped_verts} verts)")
    for o in parts[1:]:
        bpy.data.objects.remove(o, do_unlink=True)
    obj = largest
bpy.context.view_layer.objects.active = obj
obj.select_set(True)

total_tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
print(f"{in_path}: {len(obj.data.vertices)} verts, {total_tris} tris after dropping noise islands")

if total_tris > target_tris:
    ratio = target_tris / total_tris
    mod = obj.modifiers.new(name="Decimate", type='DECIMATE')
    mod.decimate_type = 'COLLAPSE'
    mod.ratio = ratio
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)

# Marching-cubes output has no real face structure - recalculate normals
# and merge coincident verts (decimate can leave near-duplicates) so the
# result shades correctly instead of flat/faceted from stale normals.
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.0001)
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode='OBJECT')

final_tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
print(f"{in_path}: {len(obj.data.vertices)} verts, {final_tris} tris after decimate")

os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB', use_selection=False)
print(f"Exported {out_path}")
