import bpy
import sys
import os
from pathlib import Path

# Add project root to sys.path to import module_sizes
project_root = Path(__file__).resolve().parents[2]
sys.path.append(str(project_root))

try:
    from module_sizes import sizes
except ImportError:
    print('module_sizes.py not found')
    sizes = {}

# Define hull keys (those ending with '_hull')
hull_keys = [k for k in sizes.keys() if k.endswith('_hull')]

# Paths
source_dir = Path(r"E:\Testing Example Grounded Gen\Hulls")
output_dir = Path(r"E:\Build-A-Bomber\prototype\assets\models\hulls")
output_dir.mkdir(parents=True, exist_ok=True)

def clear_parents(obj):
    # Preserve world transform
    world_matrix = obj.matrix_world.copy()
    obj.parent = None
    obj.matrix_world = world_matrix
    # Delete any stray Empty objects (except camera target)
    for empty in [o for o in bpy.context.scene.objects if o.type == 'EMPTY' and o.name != "Camera_Target"]:
        bpy.data.objects.remove(empty)
    bpy.context.view_layer.update()

for hull_name in hull_keys:
    src_path = source_dir / f"{hull_name}.glb"
    if not src_path.exists():
        print(f"Source {src_path} missing, skipping")
        continue
    out_path = output_dir / f"{hull_name}.glb"
    # Clear scene
    bpy.ops.wm.read_factory_settings(use_empty=True)
    print(f"=== Processing {hull_name} ===")
    bpy.ops.import_scene.gltf(filepath=str(src_path))
    # Gather meshes
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    if not meshes:
        print(f"No mesh found in {src_path}, skipping")
        continue
    # Join meshes
    bpy.ops.object.select_all(action='DESELECT')
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.active_object
    # Unparent and clean empties
    clear_parents(obj)
    # Decimate (optional, keep as before)
    print("Decimating mesh...")
    mod = obj.modifiers.new(name="Decimate", type='DECIMATE')
    mod.ratio = 0.25
    bpy.ops.object.modifier_apply(modifier="Decimate")
    # Center origin
    print("Centering origin...")
    bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
    obj.location = (0,0,0)
    # Rotate hull 90deg about Z to align forward axis
    print("Rotating hull 90 degrees to align forward axis...")
    import math
    obj.rotation_euler.z += math.radians(90)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    bpy.context.view_layer.update()
    # Compute scaling factor based on target dimensions
    target_dims = sizes[hull_name]  # (width, height, length)
    current = obj.dimensions
    ratios = [target_dims[0]/current.x, target_dims[1]/current.y, target_dims[2]/current.z]
    scale_factor = max(ratios)
    print(f"Scaling uniformly by factor {scale_factor} (largest target dimension)")
    obj.scale = (scale_factor, scale_factor, scale_factor)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # Export
    print(f"Exporting to {out_path}")
    bpy.ops.export_scene.gltf(filepath=str(out_path), use_selection=True, export_format='GLB')
    print(f"Finished {hull_name}\n")
print("All hulls processed.")
