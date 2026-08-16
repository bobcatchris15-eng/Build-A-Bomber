"""
Kitbash Command - Dedicated Power & Energy Module Mesh Builder
Authors multi-part .glb meshes for generation and storage modules:
  - fusion_generator:        fusion_generator_core / fusion_generator_radiator
  - diesel_generator:        diesel_generator_block / diesel_generator_vents
  - thermo_generator:        thermo_generator_casing / thermo_generator_pipes
  - capacitor_bank:          capacitor_bank_cells / capacitor_bank_busbar
  - flywheel_storage:        flywheel_storage_housing / flywheel_storage_rotor
  - solid_state_battery:     solid_state_battery_tray / solid_state_battery_cells

COORDINATE CONVENTION (same as build_meshes.py):
  Blender is authored Z-up. The glTF exporter's Y-up conversion maps:
    Godot_X = Blender_X,  Godot_Y = Blender_Z,  Godot_Z = Blender_Y
  GV(x, y, z) -> raw Blender (x, z, y)
  GS(sx, sy, sz) -> raw Blender (sx, sz, sy)
"""

import bpy
import bmesh
import math
import os
import mathutils

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
PARTS_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "parts")
os.makedirs(PARTS_DIR, exist_ok=True)


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        if block.users == 0:
            bpy.data.meshes.remove(block)
    for block in list(bpy.data.materials):
        if block.users == 0:
            bpy.data.materials.remove(block)


def _cone(bm, pos, r1, r2, depth, segments, rot=None):
    res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                                radius1=r1, radius2=r2, depth=depth)
    loc = mathutils.Vector(pos)
    for v in res['verts']:
        v.co = (rot @ v.co if rot else v.co) + loc


def add_cyl_z(bm, pos, radius, height, segments=16):
    """Vertical cylinder (Godot Y / Blender Z)."""
    _cone(bm, pos, radius, radius, height, segments)


def add_cone_z(bm, pos, r_bot, r_top, height, segments=16):
    """Frustum/cone along Blender Z."""
    _cone(bm, pos, r_top, r_bot, height, segments)


def add_cyl_y(bm, pos, radius, height, segments=16):
    """Horizontal cylinder along Blender Y (Godot -Z)."""
    rot = mathutils.Matrix.Rotation(math.radians(90), 4, 'X')
    _cone(bm, pos, radius, radius, height, segments, rot)


def add_cyl_x(bm, pos, radius, height, segments=16):
    """Horizontal cylinder along Blender X (Godot X)."""
    rot = mathutils.Matrix.Rotation(math.radians(90), 4, 'Y')
    _cone(bm, pos, radius, radius, height, segments, rot)


def add_box(bm, pos, size, bevel=0.0, bevel_segments=2, rot_z=0.0):
    """Box centred at pos with given size."""
    loc = mathutils.Vector(pos)
    res = bmesh.ops.create_cube(bm, size=1.0)
    rot = mathutils.Matrix.Rotation(rot_z, 4, 'Z')
    for v in res['verts']:
        v.co = rot @ mathutils.Vector((v.co.x * size[0],
                                       v.co.y * size[1],
                                       v.co.z * size[2])) + loc
    if bevel > 0.001:
        edges = [e for e in bm.edges if any(v in res['verts'] for v in e.verts)]
        try:
            bmesh.ops.bevel(bm, geom=edges, offset=bevel,
                            segments=max(1, bevel_segments), affect='EDGES')
        except Exception:
            pass


def export_bmesh(bm, object_name, filename, color=(0.35, 0.36, 0.38), metallic=0.75, roughness=0.35):
    me = bpy.data.meshes.new(object_name + "_mesh")
    bm.to_mesh(me)
    bm.free()

    obj = bpy.data.objects.new(object_name, me)
    bpy.context.collection.objects.link(obj)

    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    try:
        obj.data.use_auto_smooth = True
        obj.data.auto_smooth_angle = math.radians(35)
    except Exception:
        pass

    mat = bpy.data.materials.new(name=object_name + "_mat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs['Base Color'].default_value = (color[0], color[1], color[2], 1.0)
        bsdf.inputs['Metallic'].default_value = metallic
        bsdf.inputs['Roughness'].default_value = roughness
    obj.data.materials.append(mat)

    filepath = os.path.join(PARTS_DIR, filename)
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        use_selection=True,
        export_format='GLB',
        export_yup=True,
        export_apply=True,
    )
    print("Exported:", filepath)
    clear_scene()


# ===========================================================================
# 1. FUSION GENERATOR
# ===========================================================================
def build_fusion_generator_core():
    bm = bmesh.new()
    # Main toroidal / cylindrical magnetic containment core
    add_box(bm, (0, 0, 0.28), (1.1, 1.4, 0.50), bevel=0.06)
    # Cylindrical reactor drum
    add_cyl_y(bm, (0, 0, 0.35), 0.42, 1.35, segments=20)
    # Heavy containment end-caps
    for y in [-0.68, 0.68]:
        add_cyl_y(bm, (0, y, 0.35), 0.46, 0.08, segments=20)
        add_cyl_y(bm, (0, y, 0.35), 0.24, 0.14, segments=12)
    # Magnetic coil bands
    for y in [-0.45, -0.15, 0.15, 0.45]:
        add_cyl_y(bm, (0, y, 0.35), 0.47, 0.09, segments=20)
    # High-voltage junction conduit along flank
    add_cyl_y(bm, (0.46, 0, 0.22), 0.08, 1.2, segments=10)
    add_cyl_y(bm, (-0.46, 0, 0.22), 0.08, 1.2, segments=10)
    return bm

def build_fusion_generator_radiator():
    bm = bmesh.new()
    # Flank radiator fin bank array
    for side in [-1, 1]:
        bx = side * 0.62
        # Backing manifold
        add_box(bm, (bx, 0, 0.30), (0.12, 1.25, 0.42), bevel=0.02)
        # Transverse cooling fins
        for i in range(9):
            fy = -0.52 + i * 0.13
            add_box(bm, (bx + side * 0.08, fy, 0.30), (0.16, 0.025, 0.38))
    # Top exhaust vent cowl
    add_box(bm, (0, 0, 0.62), (0.45, 0.85, 0.12), bevel=0.03)
    for i in range(5):
        vy = -0.32 + i * 0.16
        add_box(bm, (0, vy, 0.64), (0.35, 0.04, 0.08))
    return bm


# ===========================================================================
# 2. DIESEL GENERATOR (TURBINE / ICE)
# ===========================================================================
def build_diesel_generator_block():
    bm = bmesh.new()
    # Heavy cast-iron engine block casing
    add_box(bm, (0, 0, 0.26), (1.15, 1.45, 0.48), bevel=0.05)
    # Center crankcase / turbine bulge
    add_box(bm, (0, 0, 0.38), (0.75, 1.30, 0.28), bevel=0.04)
    # Intake supercharger cowl at front
    add_cyl_y(bm, (0, 0.65, 0.36), 0.28, 0.22, segments=16)
    # Alternator drive housing at rear
    add_cyl_y(bm, (0, -0.65, 0.28), 0.32, 0.20, segments=16)
    # Flank oil pan & filter canisters
    add_cyl_z(bm, (0.48, 0.25, 0.24), 0.12, 0.35, segments=12)
    add_cyl_z(bm, (0.48, -0.25, 0.24), 0.12, 0.35, segments=12)
    return bm

def build_diesel_generator_vents():
    bm = bmesh.new()
    # Angled exhaust stacks (dual ports)
    for sx in [-0.22, 0.22]:
        add_cyl_z(bm, (sx, -0.45, 0.62), 0.09, 0.32, segments=12)
        add_cone_z(bm, (sx, -0.45, 0.76), 0.09, 0.12, 0.08, segments=12)
    # Top louvered cooling grille
    add_box(bm, (0, 0.15, 0.53), (0.60, 0.70, 0.06), bevel=0.02)
    for i in range(6):
        ly = -0.12 + i * 0.10
        add_box(bm, (0, ly, 0.55), (0.50, 0.035, 0.04))
    # Side intake louvers
    for side in [-1, 1]:
        for j in range(4):
            sy = -0.2 + j * 0.14
            add_box(bm, (side * 0.60, sy, 0.28), (0.05, 0.08, 0.18))
    return bm


# ===========================================================================
# 3. THERMOELECTRIC GENERATOR (STIRLING / HEAT PIPES)
# ===========================================================================
def build_thermo_generator_casing():
    bm = bmesh.new()
    # Compact faceted heat casing
    add_box(bm, (0, 0, 0.20), (0.85, 0.95, 0.36), bevel=0.04)
    # Center thermal core
    add_cyl_z(bm, (0, 0, 0.28), 0.30, 0.28, segments=16)
    # Hexagonal thermocouple collar
    add_cyl_z(bm, (0, 0, 0.32), 0.34, 0.14, segments=6)
    return bm

def build_thermo_generator_pipes():
    bm = bmesh.new()
    # Copper heat pipe loop runners
    for i in range(4):
        a = i * (math.pi / 2.0) + math.pi / 4.0
        px = math.cos(a) * 0.32
        py = math.sin(a) * 0.36
        add_cyl_z(bm, (px, py, 0.30), 0.045, 0.32, segments=8)
        add_cyl_x(bm, (px * 0.6, py, 0.44), 0.04, 0.22, segments=8)
    # Radial micro-cooling fins
    for side in [-1, 1]:
        for k in range(5):
            fy = -0.30 + k * 0.15
            add_box(bm, (side * 0.46, fy, 0.22), (0.09, 0.03, 0.26))
    return bm


# ===========================================================================
# 4. CAPACITOR BANK (SUPER-CAPACITOR CELLS)
# ===========================================================================
def build_capacitor_bank_cells():
    bm = bmesh.new()
    # Base tray plate
    add_box(bm, (0, 0, 0.08), (0.88, 1.15, 0.14), bevel=0.03)
    # 2x3 grid of cylindrical supercapacitor cells
    for row in [-0.34, 0.0, 0.34]:
        for col in [-0.24, 0.24]:
            add_cyl_z(bm, (col, row, 0.34), 0.18, 0.50, segments=16)
            add_cyl_z(bm, (col, row, 0.58), 0.15, 0.06, segments=16)
            # Terminal stud
            add_cyl_z(bm, (col, row, 0.62), 0.05, 0.05, segments=8)
    return bm

def build_capacitor_bank_busbar():
    bm = bmesh.new()
    # Heavy copper/brass busbar interlinks connecting cells
    for col in [-0.24, 0.24]:
        add_box(bm, (col, 0, 0.63), (0.07, 0.78, 0.03), bevel=0.01)
    # Cross connector bridge & monitoring shunt
    add_box(bm, (0, 0, 0.64), (0.52, 0.09, 0.035), bevel=0.01)
    add_box(bm, (0, 0, 0.67), (0.16, 0.16, 0.05), bevel=0.01)
    # End clamp lugs
    for row in [-0.34, 0.34]:
        add_box(bm, (0, row, 0.63), (0.50, 0.05, 0.025))
    return bm


# ===========================================================================
# 5. FLYWHEEL STORAGE (KINETIC BATTERY)
# ===========================================================================
def build_flywheel_storage_housing():
    bm = bmesh.new()
    # Heavy armored vacuum containment ring
    add_cyl_z(bm, (0, 0, 0.28), 0.56, 0.44, segments=24)
    # Armored hub base mount
    add_box(bm, (0, 0, 0.10), (1.20, 1.20, 0.18), bevel=0.05)
    # Perimeter reinforcement ribs
    for i in range(8):
        a = i * (math.pi / 4.0)
        rx = math.cos(a) * 0.58
        ry = math.sin(a) * 0.58
        add_box(bm, (rx, ry, 0.28), (0.12, 0.12, 0.40), bevel=0.02, rot_z=a)
    return bm

def build_flywheel_storage_rotor():
    bm = bmesh.new()
    # Magnetic bearing top cap & gyro spin indicator
    add_cyl_z(bm, (0, 0, 0.52), 0.34, 0.10, segments=20)
    add_cyl_z(bm, (0, 0, 0.58), 0.16, 0.08, segments=16)
    add_cyl_z(bm, (0, 0, 0.63), 0.06, 0.04, segments=10)
    # Vacuum extraction port & high-speed stator coils
    for i in range(4):
        a = i * (math.pi / 2.0)
        cx = math.cos(a) * 0.40
        cy = math.sin(a) * 0.40
        add_cyl_z(bm, (cx, cy, 0.50), 0.08, 0.09, segments=10)
    return bm


# ===========================================================================
# 6. SOLID-STATE BATTERY PACK
# ===========================================================================
def build_solid_state_battery_tray():
    bm = bmesh.new()
    # Low-profile hull-conforming battery enclosure tray
    add_box(bm, (0, 0, 0.15), (1.10, 1.35, 0.28), bevel=0.04)
    # Internal module divide bulkheads
    add_box(bm, (0, 0, 0.22), (1.02, 0.06, 0.18))
    add_box(bm, (0, -0.32, 0.22), (1.02, 0.06, 0.18))
    add_box(bm, (0, 0.32, 0.22), (1.02, 0.06, 0.18))
    return bm

def build_solid_state_battery_cells():
    bm = bmesh.new()
    # Four modular cell block packs nested inside tray
    for bay_y in [-0.48, -0.16, 0.16, 0.48]:
        add_box(bm, (0, bay_y, 0.24), (0.94, 0.22, 0.18), bevel=0.02)
        # Cooling channel slits between cells
        for j in range(4):
            cx = -0.36 + j * 0.24
            add_box(bm, (cx, bay_y, 0.31), (0.03, 0.18, 0.05))
    # BMS (Battery Management System) control box on flank
    add_box(bm, (0.50, 0, 0.22), (0.12, 0.45, 0.18), bevel=0.02)
    return bm


def main():
    clear_scene()
    print("==================================================")
    print("  BUILDING POWER & ENERGY MODULE MESHES           ")
    print("==================================================")

    # 1. Fusion Generator
    export_bmesh(build_fusion_generator_core(), "fusion_generator_core", "fusion_generator_core.glb",
                 color=(0.28, 0.29, 0.32), metallic=0.85, roughness=0.30)
    export_bmesh(build_fusion_generator_radiator(), "fusion_generator_radiator", "fusion_generator_radiator.glb",
                 color=(0.22, 0.24, 0.26), metallic=0.75, roughness=0.45)

    # 2. Diesel Generator
    export_bmesh(build_diesel_generator_block(), "diesel_generator_block", "diesel_generator_block.glb",
                 color=(0.32, 0.31, 0.30), metallic=0.80, roughness=0.40)
    export_bmesh(build_diesel_generator_vents(), "diesel_generator_vents", "diesel_generator_vents.glb",
                 color=(0.18, 0.18, 0.19), metallic=0.70, roughness=0.60)

    # 3. Thermoelectric Generator
    export_bmesh(build_thermo_generator_casing(), "thermo_generator_casing", "thermo_generator_casing.glb",
                 color=(0.30, 0.32, 0.35), metallic=0.75, roughness=0.35)
    export_bmesh(build_thermo_generator_pipes(), "thermo_generator_pipes", "thermo_generator_pipes.glb",
                 color=(0.48, 0.32, 0.18), metallic=0.90, roughness=0.25)

    # 4. Capacitor Bank
    export_bmesh(build_capacitor_bank_cells(), "capacitor_bank_cells", "capacitor_bank_cells.glb",
                 color=(0.20, 0.22, 0.26), metallic=0.50, roughness=0.40)
    export_bmesh(build_capacitor_bank_busbar(), "capacitor_bank_busbar", "capacitor_bank_busbar.glb",
                 color=(0.52, 0.40, 0.20), metallic=0.88, roughness=0.30)

    # 5. Flywheel Storage
    export_bmesh(build_flywheel_storage_housing(), "flywheel_storage_housing", "flywheel_storage_housing.glb",
                 color=(0.26, 0.27, 0.29), metallic=0.85, roughness=0.30)
    export_bmesh(build_flywheel_storage_rotor(), "flywheel_storage_rotor", "flywheel_storage_rotor.glb",
                 color=(0.38, 0.39, 0.42), metallic=0.90, roughness=0.20)

    # 6. Solid-State Battery
    export_bmesh(build_solid_state_battery_tray(), "solid_state_battery_tray", "solid_state_battery_tray.glb",
                 color=(0.28, 0.29, 0.31), metallic=0.65, roughness=0.45)
    export_bmesh(build_solid_state_battery_cells(), "solid_state_battery_cells", "solid_state_battery_cells.glb",
                 color=(0.16, 0.18, 0.22), metallic=0.45, roughness=0.35)

    print("ALL POWER MODULE MESHES EXPORTED CLEANLY.")


if __name__ == "__main__":
    main()
