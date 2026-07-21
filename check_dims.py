import bpy
import sys

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=r"E:\Build-A-Bomber\TRIPO_GEN_Meshes\assault_hull.glb")
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for mesh in meshes:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.active_object
    print(f"\nDIMS: X={obj.dimensions.x} Y={obj.dimensions.y} Z={obj.dimensions.z}")
    print(f"ROT: X={obj.rotation_euler.x} Y={obj.rotation_euler.y} Z={obj.rotation_euler.z}")

if __name__ == "__main__":
    main()
