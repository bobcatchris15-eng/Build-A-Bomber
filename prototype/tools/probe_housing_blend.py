import bpy, sys, os
# After `--`, args are at sys.argv. Blender's own args consume some; try
# the last arg as the GLB path.
glb_path = None
for a in sys.argv[1:]:
    if a.endswith(".glb") and os.path.isfile(a):
        glb_path = a
        break
if not glb_path:
    # Fall back: find any *.glb in the parts dir
    parts_dir = os.path.join(os.path.dirname(__file__), "..", "assets", "models", "parts")
    for name in ["missile_pod_housing.glb", "missile_pod_missile.glb", "missile_pod_pintle_mount.glb"]:
        candidate = os.path.join(parts_dir, name)
        if os.path.isfile(candidate):
            glb_path = candidate
            break
print("Loading:", glb_path)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)
for obj in bpy.context.scene.objects:
    if obj.type == "MESH":
        mesh = obj.data
        coords = [v.co[:] for v in mesh.vertices]
        xs = [c[0] for c in coords]
        ys = [c[1] for c in coords]
        zs = [c[2] for c in coords]
        print(f"OBJECT {obj.name} verts={len(coords)} faces={len(mesh.polygons)}")
        print(f"  min=({min(xs):.3f}, {min(ys):.3f}, {min(zs):.3f})")
        print(f"  max=({max(xs):.3f}, {max(ys):.3f}, {max(zs):.3f})")
