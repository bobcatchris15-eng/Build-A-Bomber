import bpy
import os

# Create directories if they don't exist
os.makedirs("E:/Build-A-Bomber/prototype/assets/meshes", exist_ok=True)

# Helper to clear scene
def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

def export_obj(filepath):
    try:
        # Blender 3.0+ OBJ export
        bpy.ops.wm.obj_export(filepath=filepath, export_selected=True)
        print(f"Exported: {filepath}")
    except Exception as e:
        try:
            # Older Blender OBJ export
            bpy.ops.export_scene.obj(filepath=filepath, use_selection=True)
            print(f"Exported (fallback): {filepath}")
        except Exception as e2:
            print(f"Failed to export OBJ: {e} | {e2}")

# 1. Modular Pintle Mount
clear_scene()
bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.4, depth=0.2, location=(0, 0, 0.1))
base = bpy.context.active_object
base.name = "PintleBase"

bpy.ops.mesh.primitive_cube_add(size=1.0, location=(-0.25, 0, 0.6))
arm_l = bpy.context.active_object
arm_l.scale = (0.1, 0.3, 0.6)

bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.25, 0, 0.6))
arm_r = bpy.context.active_object
arm_r.scale = (0.1, 0.3, 0.6)

bpy.ops.object.select_all(action='DESELECT')
base.select_set(True)
arm_l.select_set(True)
arm_r.select_set(True)
bpy.context.view_layer.objects.active = base
bpy.ops.object.join()
bpy.ops.object.transform_apply(scale=True)

# Add bevel to make it look smooth and refined
bpy.ops.object.modifier_add(type='BEVEL')
base.modifiers["Bevel"].width = 0.03
base.modifiers["Bevel"].segments = 2
bpy.ops.object.modifier_apply(modifier="Bevel")

export_obj("E:/Build-A-Bomber/prototype/assets/meshes/modular_pintle_mount.obj")

# 2. Modular Gun Barrel
clear_scene()
bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.14, depth=0.5, location=(0, 0, 0.25))
sleeve = bpy.context.active_object
sleeve.name = "BarrelSleeve"

bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.08, depth=1.8, location=(0, 0, 1.4))
pipe = bpy.context.active_object

# Apply subtle taper
for vert in pipe.data.vertices:
    if vert.co.z > 0: # tip
        vert.co.x *= 0.65
        vert.co.y *= 0.65

bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.13, depth=0.25, location=(0, 0, 2.4))
brake = bpy.context.active_object

bpy.ops.object.select_all(action='DESELECT')
sleeve.select_set(True)
pipe.select_set(True)
brake.select_set(True)
bpy.context.view_layer.objects.active = sleeve
bpy.ops.object.join()
bpy.ops.object.transform_apply(scale=True)
export_obj("E:/Build-A-Bomber/prototype/assets/meshes/modular_barrel.obj")

# 3. Heavy Howitzer Barrel
clear_scene()
bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.22, depth=0.8, location=(0, 0, 0.4))
how_sleeve = bpy.context.active_object
how_sleeve.name = "HowitzerSleeve"

bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.16, depth=1.5, location=(0, 0, 1.55))
how_pipe = bpy.context.active_object

# Add massive recoil buffer chambers on sides
bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.08, depth=0.7, location=(-0.25, 0, 0.45))
rec1 = bpy.context.active_object
bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.08, depth=0.7, location=(0.25, 0, 0.45))
rec2 = bpy.context.active_object

bpy.ops.object.select_all(action='DESELECT')
how_sleeve.select_set(True)
how_pipe.select_set(True)
rec1.select_set(True)
rec2.select_set(True)
bpy.context.view_layer.objects.active = how_sleeve
bpy.ops.object.join()
bpy.ops.object.transform_apply(scale=True)
export_obj("E:/Build-A-Bomber/prototype/assets/meshes/modular_howitzer_barrel.obj")

# 4. Modular Missile Body
clear_scene()
bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.07, depth=1.5, location=(0, 0, 0.75))
missile = bpy.context.active_object
missile.name = "MissileBody"

# Fix: Use radius1 instead of radius for primitive_cone_add in Blender
bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.07, depth=0.3, location=(0, 0, 1.65))
cone = bpy.context.active_object

# Join missile core
bpy.ops.object.select_all(action='DESELECT')
missile.select_set(True)
cone.select_set(True)
bpy.context.view_layer.objects.active = missile
bpy.ops.object.join()

# Rear Fins (cross fins)
for rot in [0.0, 90.0]:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.15))
    fin = bpy.context.active_object
    fin.scale = (0.35, 0.01, 0.25)
    fin.rotation_euler = (0, 0, rot * 3.14159 / 180.0)
    bpy.ops.object.select_all(action='DESELECT')
    missile.select_set(True)
    fin.select_set(True)
    bpy.context.view_layer.objects.active = missile
    bpy.ops.object.join()

bpy.ops.object.transform_apply(scale=True, rotation=True)
export_obj("E:/Build-A-Bomber/prototype/assets/meshes/modular_missile_body.obj")

# 5. Wedge Hull
clear_scene()
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
hull_w = bpy.context.active_object
hull_w.scale = (2.0, 3.2, 0.5)
bpy.ops.object.transform_apply(scale=True)
# Deform front to make a clean wedge shape
for v in hull_w.data.vertices:
    if v.co.y > 0.5: # forward part
        v.co.x *= 0.35
        v.co.z *= 0.25
        
# Bevel the edges
bpy.ops.object.modifier_add(type='BEVEL')
hull_w.modifiers["Bevel"].width = 0.08
hull_w.modifiers["Bevel"].segments = 2
bpy.ops.object.modifier_apply(modifier="Bevel")
export_obj("E:/Build-A-Bomber/prototype/assets/meshes/hull_wedged.obj")

# 6. Octagonal Hull
clear_scene()
bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=1.3, depth=1.0, location=(0, 0, 0))
hull_o = bpy.context.active_object
hull_o.scale = (1.5, 2.4, 0.7)
bpy.ops.object.transform_apply(scale=True)
hull_o.rotation_euler = (0, 0, 22.5 * 3.14159 / 180.0)
bpy.ops.object.transform_apply(rotation=True)
# Add some side skirts / visual cuts by beveling
bpy.ops.object.modifier_add(type='BEVEL')
hull_o.modifiers["Bevel"].width = 0.05
hull_o.modifiers["Bevel"].segments = 2
bpy.ops.object.modifier_apply(modifier="Bevel")
export_obj("E:/Build-A-Bomber/prototype/assets/meshes/hull_octagonal.obj")

# 7. Aerodynamic Fuselage Hull
clear_scene()
# Blender 3.0 cylinder depth is along Z axis. To taper front/back, we taper along Z!
bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.8, depth=4.0, location=(0, 0, 0))
hull_a = bpy.context.active_object
for v in hull_a.data.vertices:
    dist_factor = 1.0 - (abs(v.co.z) / 2.2)
    v.co.x *= max(0.12, dist_factor)
    v.co.y *= max(0.12, dist_factor)
hull_a.scale = (1.5, 0.7, 1.1)
bpy.ops.object.transform_apply(scale=True)
# Rotate it so depth goes along Y axis
hull_a.rotation_euler = (1.570796, 0, 0)
bpy.ops.object.transform_apply(rotation=True)
export_obj("E:/Build-A-Bomber/prototype/assets/meshes/hull_aerodynamic.obj")

# 8. Flatbed Truck Hull
clear_scene()
# Cab
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 1.1, 0.5))
cab = bpy.context.active_object
cab.scale = (1.8, 1.0, 1.1)
# Flatbed back
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.9, 0.05))
bed = bpy.context.active_object
bed.scale = (1.9, 3.0, 0.2)

bpy.ops.object.select_all(action='DESELECT')
cab.select_set(True)
bed.select_set(True)
bpy.context.view_layer.objects.active = cab
bpy.ops.object.join()
bpy.ops.object.transform_apply(scale=True)
export_obj("E:/Build-A-Bomber/prototype/assets/meshes/hull_flatbed.obj")

print("All meshes generated successfully!")
