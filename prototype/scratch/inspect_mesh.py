import bpy
import sys

def main():
    # Clear scene
    bpy.ops.wm.read_factory_settings(use_empty=True)
    
    # Import source file
    input_path = r"E:\Testing Example Grounded Gen\Hulls\fuselage_hull.glb"
    print(f"=== Inspecting Source: {input_path} ===")
    bpy.ops.import_scene.gltf(filepath=input_path)
    
    for obj in bpy.context.scene.objects:
        print(f"Object: {obj.name}")
        print(f"  Type: {obj.type}")
        print(f"  Rotation (Euler): {obj.rotation_euler}")
        print(f"  Scale: {obj.scale}")
        print(f"  Dimensions: {obj.dimensions}")
        if obj.parent:
            print(f"  Parent: {obj.parent.name}")
            
    print("=== Finished inspection ===")

if __name__ == "__main__":
    main()
