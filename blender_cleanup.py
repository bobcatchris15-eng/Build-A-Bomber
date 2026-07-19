import bpy
import sys
import os

# Append the directory containing module_sizes.py to sys.path
sys.path.append(r"E:\Build-A-Bomber")
try:
    from module_sizes import sizes
except ImportError:
    sizes = {}

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def process_model(input_path, output_path, base_name):
    clear_scene()
    
    # Import GLB
    print(f"Importing {input_path}")
    bpy.ops.import_scene.gltf(filepath=input_path)
    
    # Get imported objects (meshes)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    if not meshes:
        print("No meshes found in the imported file.")
        return
        
    # Join all meshes into one
    bpy.ops.object.select_all(action='DESELECT')
    for mesh in meshes:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
        
    obj = bpy.context.active_object
    
    # Decimate (Simplify)
    print("Decimating mesh...")
    mod = obj.modifiers.new(name="Decimate", type='DECIMATE')
    mod.ratio = 0.25 # Reduce to 25% of original faces
    bpy.ops.object.modifier_apply(modifier="Decimate")
    
    # Center Origin
    print("Centering origin...")
    bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
    obj.location = (0, 0, 0)
    
    # Find dimensions from sizes map
    # We try to match base_name in sizes keys
    dims_target = (2.0, 2.0, 2.0) # Default
    for key, val in sizes.items():
        if key in base_name or base_name in key:
            dims_target = val
            break
            
    # Scale to target size
    # target size is (width, height, length)
    # Blender axes: X=width, Y=length, Z=height
    target_x = dims_target[0] # width
    target_y = dims_target[2] # length
    target_z = dims_target[1] # height
    
    print(f"Scaling to exact dimensions: Width={target_x}, Height={target_z}, Length={target_y}")
    
    # Scale each axis independently to fit dimensions
    current_dims = obj.dimensions
    if current_dims.x > 0 and current_dims.y > 0 and current_dims.z > 0:
        scale_x = target_x / current_dims.x
        scale_y = target_y / current_dims.y
        scale_z = target_z / current_dims.z
        
        # To avoid extreme stretching if the model shape is very different from target proportions,
        # we can optionally scale uniformly based on the longest axis, or scale non-uniformly.
        # The user requested specific footprints, so we scale non-uniformly.
        obj.scale = (scale_x, scale_y, scale_z)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    
    # Export GLB
    print(f"Exporting to {output_path}")
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        use_selection=True,
        export_format='GLB'
    )

if __name__ == "__main__":
    # Blender passes all its own args, we need to look after "--"
    argv = sys.argv
    if "--" not in argv:
        print("Usage: blender -b -P blender_cleanup.py -- <input_glb> <output_glb> <base_name>")
        sys.exit(1)
        
    args = argv[argv.index("--") + 1:]
    if len(args) < 3:
        print("Usage: blender -b -P blender_cleanup.py -- <input_glb> <output_glb> <base_name>")
        sys.exit(1)
        
    in_glb = args[0]
    out_glb = args[1]
    base_name = args[2]
    
    try:
        process_model(in_glb, out_glb, base_name)
    except Exception as e:
        print(f"Error processing model: {e}")

