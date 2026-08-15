import bpy
import bmesh
import math
import os
import mathutils

# Authored base-building meshes for Cold-War Kitbash RTS:
# HQ, Refinery, Power Plant, Light/Medium/Heavy Manufactories, Tech/Physics/Exotics Labs.
# Authored with distinct architectural silhouettes, multi-material industrial textures,
# gantry cranes, piping manifolds, radar domes, cooling towers, and bunker plinths.

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "..", "assets", "models", "buildings"))
os.makedirs(OUT_DIR, exist_ok=True)


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        if block.users == 0:
            bpy.data.meshes.remove(block)
    for block in list(bpy.data.materials):
        if block.users == 0:
            bpy.data.materials.remove(block)


def get_building_materials():
    """Builds standard Cold-War architectural materials."""
    # 0: Weathered concrete foundation / blast walls
    mat_concrete = bpy.data.materials.new("Mat_Concrete")
    mat_concrete.use_nodes = True
    b0 = mat_concrete.node_tree.nodes.get("Principled BSDF")
    if b0:
        b0.inputs['Base Color'].default_value = (0.44, 0.45, 0.42, 1.0)
        b0.inputs['Metallic'].default_value = 0.02
        b0.inputs['Roughness'].default_value = 0.94

    # 1: Military drab steel panels / siding (Livery / Team Accent Slot)
    mat_metal = bpy.data.materials.new("Mat_MetalPanels")
    mat_metal.use_nodes = True
    b1 = mat_metal.node_tree.nodes.get("Principled BSDF")
    if b1:
        b1.inputs['Base Color'].default_value = (0.34, 0.38, 0.32, 1.0)
        b1.inputs['Metallic'].default_value = 0.15
        b1.inputs['Roughness'].default_value = 0.78

    # 2: Dark industrial steel / pipes / trusses
    mat_dark_iron = bpy.data.materials.new("Mat_DarkIron")
    mat_dark_iron.use_nodes = True
    b2 = mat_dark_iron.node_tree.nodes.get("Principled BSDF")
    if b2:
        b2.inputs['Base Color'].default_value = (0.16, 0.17, 0.18, 1.0)
        b2.inputs['Metallic'].default_value = 0.45
        b2.inputs['Roughness'].default_value = 0.82

    # 3: Industrial hazard yellow / blast doors
    mat_hazard = bpy.data.materials.new("Mat_HazardDoors")
    mat_hazard.use_nodes = True
    b3 = mat_hazard.node_tree.nodes.get("Principled BSDF")
    if b3:
        b3.inputs['Base Color'].default_value = (0.80, 0.62, 0.12, 1.0)
        b3.inputs['Metallic'].default_value = 0.05
        b3.inputs['Roughness'].default_value = 0.75

    # 4: Radar antenna / sensor silver
    mat_sensor = bpy.data.materials.new("Mat_Sensors")
    mat_sensor.use_nodes = True
    b4 = mat_sensor.node_tree.nodes.get("Principled BSDF")
    if b4:
        b4.inputs['Base Color'].default_value = (0.68, 0.70, 0.72, 1.0)
        b4.inputs['Metallic'].default_value = 0.55
        b4.inputs['Roughness'].default_value = 0.50

    return [mat_concrete, mat_metal, mat_dark_iron, mat_hazard, mat_sensor]


def add_box(bm, center, size, mat_idx=0):
    start_faces = len(bm.faces)
    m = mathutils.Matrix.Translation(mathutils.Vector(center)) @ mathutils.Matrix.Diagonal(
        mathutils.Vector((size[0], size[1], size[2], 1.0)))
    bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    for f in bm.faces[start_faces:]:
        f.material_index = mat_idx
    return bm.faces[start_faces:]


def add_cyl(bm, center, radius, height, axis='Z', segments=12, mat_idx=2):
    start_faces = len(bm.faces)
    m = mathutils.Matrix.Translation(mathutils.Vector(center))
    if axis == 'X':
        m = m @ mathutils.Matrix.Rotation(math.radians(90), 4, 'Y')
    elif axis == 'Y':
        m = m @ mathutils.Matrix.Rotation(math.radians(-90), 4, 'X')
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                          radius1=radius, radius2=radius, depth=height, matrix=m)
    for f in bm.faces[start_faces:]:
        f.material_index = mat_idx
    return bm.faces[start_faces:]


def add_taper(bm, center, r_bottom, r_top, height, segments=12, mat_idx=0):
    start_faces = len(bm.faces)
    m = mathutils.Matrix.Translation(mathutils.Vector(center))
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                          radius1=r_bottom, radius2=r_top, depth=height, matrix=m)
    for f in bm.faces[start_faces:]:
        f.material_index = mat_idx
    return bm.faces[start_faces:]


def add_sphere(bm, center, radius, segments=14, rings=10, mat_idx=1):
    start_faces = len(bm.faces)
    m = mathutils.Matrix.Translation(mathutils.Vector(center))
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings,
                              radius=radius, matrix=m)
    for f in bm.faces[start_faces:]:
        f.material_index = mat_idx
    return bm.faces[start_faces:]


def add_pipe_run(bm, start, end, radius=0.14, segments=8, mat_idx=2):
    s = mathutils.Vector(start)
    e = mathutils.Vector(end)
    d = e - s
    length = d.length
    if length < 1e-5:
        return
    mid = (s + e) * 0.5
    axis = d.normalized()
    up = mathutils.Vector((0, 0, 1))
    if abs(axis.dot(up)) > 0.99:
        up = mathutils.Vector((0, 1, 0))
    right = axis.cross(up).normalized()
    real_up = right.cross(axis).normalized()
    rot = mathutils.Matrix((right, real_up, axis)).transposed().to_4x4()
    m = mathutils.Matrix.Translation(mid) @ rot
    start_faces = len(bm.faces)
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                          radius1=radius, radius2=radius, depth=length, matrix=m)
    for f in bm.faces[start_faces:]:
        f.material_index = mat_idx


def add_door(bm, center, w, h, depth=0.18, mat_idx=3):
    add_box(bm, (center[0], center[1], center[2] + h / 2), (w + 0.35, depth, h + 0.25), mat_idx=2)
    add_box(bm, (center[0], center[1] - depth * 0.4, center[2] + h / 2), (w, depth * 0.4, h), mat_idx=mat_idx)


def add_gantry(bm, center, span_x, span_y, height, post_r=0.15, mat_idx=2):
    # 4 vertical steel posts + top frame
    hx, hy = span_x * 0.5, span_y * 0.5
    cx, cy, cz = center[0], center[1], center[2]
    for px in (-hx, hx):
        for py in (-hy, hy):
            add_cyl(bm, (cx + px, cy + py, cz + height * 0.5), post_r, height, 'Z', 6, mat_idx)
    # top perimeter beams
    add_box(bm, (cx, cy - hy, cz + height), (span_x, post_r * 2.2, post_r * 2.2), mat_idx)
    add_box(bm, (cx, cy + hy, cz + height), (span_x, post_r * 2.2, post_r * 2.2), mat_idx)
    add_box(bm, (cx - hx, cy, cz + height), (post_r * 2.2, span_y, post_r * 2.2), mat_idx)
    add_box(bm, (cx + hx, cy, cz + height), (post_r * 2.2, span_y, post_r * 2.2), mat_idx)


def export_building(bm, object_name, filename):
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    me = bpy.data.meshes.new(object_name + "_mesh")
    bm.to_mesh(me)
    bm.free()

    obj = bpy.data.objects.new(object_name, me)
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_flat()

    # Apply materials
    mats = get_building_materials()
    for m in mats:
        obj.data.materials.append(m)

    # UV Unwrap
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.cube_project(cube_size=2.5)
    bpy.ops.object.mode_set(mode='OBJECT')

    tris = sum(max(0, len(p.vertices) - 2) for p in me.polygons)
    filepath = os.path.join(OUT_DIR, filename)
    bpy.ops.export_scene.gltf(filepath=filepath, use_selection=True, export_format='GLB')
    print("Exported: %-28s %6d tris" % (filename, tris))
    clear_scene()


# ---------------------------------------------------------------------------
# 1. HQ: Heavily Fortified Cold-War Command Bunker & Comms Array
# ---------------------------------------------------------------------------
def build_hq():
    bm = bmesh.new()
    # 0: Concrete bunker bastion base (sloped blast walls)
    add_box(bm, (0, 0, 0.7), (7.4, 7.4, 1.4), mat_idx=0)
    add_box(bm, (0, 0, 1.6), (6.4, 6.4, 0.6), mat_idx=0)
    
    # Angled corner bastions
    for sx in (-1, 1):
        for sy in (-1, 1):
            add_box(bm, (sx * 3.4, sy * 3.4, 0.9), (1.1, 1.1, 1.8), mat_idx=0)
            add_box(bm, (sx * 3.4, sy * 3.4, 1.9), (0.9, 0.9, 0.4), mat_idx=2)

    # Upper operations block (military drab metal panels)
    add_box(bm, (0, -0.4, 2.4), (5.0, 4.8, 1.2), mat_idx=1)
    add_box(bm, (0, -0.4, 3.05), (5.3, 5.1, 0.25), mat_idx=2) # roof lip

    # Heavy blast doors + guard walk
    add_door(bm, (0, -3.7, 0.0), 2.2, 1.7, mat_idx=3)
    add_door(bm, (0, 3.7, 0.0), 1.8, 1.6, mat_idx=3)

    # Gantry roof structures & Comms Mast with Dish
    add_cyl(bm, (1.8, 1.5, 4.0), 0.18, 2.2, 'Z', 8, mat_idx=2)
    add_taper(bm, (-1.8, 1.2, 3.8), 1.1, 0.2, 0.55, 14, mat_idx=4) # Satellite Dish
    add_cyl(bm, (-1.8, 1.2, 3.4), 0.20, 0.6, 'Z', 8, mat_idx=2)
    add_sphere(bm, (0.0, -0.8, 3.6), 0.75, 12, 8, mat_idx=4)      # Radar Radome

    # HVAC vents & generators
    for vx in (-1.8, -0.6, 0.6, 1.8):
        add_box(bm, (vx, 2.6, 1.9), (0.8, 0.5, 0.4), mat_idx=2)

    export_building(bm, "hq", "hq.glb")


# ---------------------------------------------------------------------------
# 2. REFINERY: Dual Chemical Spheres, Distillation Column & Flare Stack
# ---------------------------------------------------------------------------
def build_refinery():
    bm = bmesh.new()
    # Concrete bund / catchment slab
    add_box(bm, (0, 0, 0.35), (5.6, 5.6, 0.7), mat_idx=0)
    add_box(bm, (0, -2.6, 0.5), (5.6, 0.4, 0.4), mat_idx=0)
    add_box(bm, (0, 2.6, 0.5), (5.6, 0.4, 0.4), mat_idx=0)

    # Twin heavy pressurized chemical storage tanks
    for sx in (-1.5, 1.5):
        add_cyl(bm, (sx, -0.8, 1.6), 1.2, 2.0, 'Z', 14, mat_idx=1)
        add_taper(bm, (sx, -0.8, 2.8), 1.2, 0.3, 0.5, 14, mat_idx=1)
        for b in (0.9, 1.5, 2.1):
            add_cyl(bm, (sx, -0.8, b), 1.26, 0.12, 'Z', 14, mat_idx=2)

    # Vertical distillation column
    add_cyl(bm, (0, 1.2, 2.4), 0.8, 3.6, 'Z', 12, mat_idx=1)
    add_taper(bm, (0, 1.2, 4.3), 0.8, 0.25, 0.4, 12, mat_idx=2)

    # Pipe manifold matrix
    add_pipe_run(bm, (-1.5, -0.8, 2.5), (1.5, -0.8, 2.5), 0.18, mat_idx=2)
    add_pipe_run(bm, (-1.5, -0.8, 1.2), (0, 1.2, 1.2), 0.16, mat_idx=2)
    add_pipe_run(bm, (1.5, -0.8, 1.2), (0, 1.2, 1.2), 0.16, mat_idx=2)

    # Control station & pumping shed
    add_box(bm, (-2.0, 1.8, 0.9), (1.4, 1.6, 1.2), mat_idx=1)
    add_door(bm, (-2.0, 0.95, 0.35), 0.8, 1.1, mat_idx=3)

    # Flare stack with ignition pilot
    add_cyl(bm, (2.1, 1.9, 2.2), 0.22, 3.2, 'Z', 8, mat_idx=2)
    add_taper(bm, (2.1, 1.9, 3.9), 0.32, 0.18, 0.35, 8, mat_idx=2)

    export_building(bm, "refinery", "refinery.glb")


# ---------------------------------------------------------------------------
# 3. POWER PLANT: Reinforced Turbine Hall, Twin Hyperboloid Cooling Towers
# ---------------------------------------------------------------------------
def build_power_plant():
    bm = bmesh.new()
    # Foundation plinth
    add_box(bm, (0, 0, 0.3), (5.8, 5.2, 0.6), mat_idx=0)

    # Main generator / turbine hall with gabled clerestory roof
    add_box(bm, (-0.8, 0, 1.5), (3.6, 4.4, 1.8), mat_idx=1)
    add_box(bm, (-0.8, 0, 2.45), (3.8, 4.5, 0.2), mat_idx=2) # roof cornice
    for i in range(5):
        y_pos = -1.8 + i * 0.9
        add_box(bm, (-0.8, y_pos, 2.65), (2.8, 0.5, 0.35), mat_idx=2) # roof vents

    # Twin concrete cooling towers
    for sy in (-1.3, 1.3):
        add_taper(bm, (2.0, sy, 1.1), 1.15, 0.82, 1.5, 14, mat_idx=0)
        add_taper(bm, (2.0, sy, 2.1), 0.82, 0.96, 0.6, 14, mat_idx=0)
        add_cyl(bm, (2.0, sy, 2.42), 0.98, 0.08, 'Z', 14, mat_idx=2) # rim collar

    # Transformer substation yard
    for tx in (-2.4, -2.4):
        for ty in (-1.2, 0.0, 1.2):
            add_box(bm, (tx, ty, 0.8), (0.7, 0.7, 0.8), mat_idx=2)
            add_cyl(bm, (tx, ty, 1.35), 0.12, 0.4, 'Z', 6, mat_idx=4) # insulators

    add_door(bm, (-0.8, -2.25, 0.6), 1.4, 1.4, mat_idx=3)
    export_building(bm, "power_plant", "power_plant.glb")


# ---------------------------------------------------------------------------
# 4. LIGHT MANUFACTORY: Corrugated Assembly Shed & Exterior Gantry Crane
# ---------------------------------------------------------------------------
def build_light_manufactory():
    bm = bmesh.new()
    add_box(bm, (0, 0, 0.3), (5.4, 6.4, 0.6), mat_idx=0)

    # Main workshop hangar
    add_box(bm, (-0.4, 0, 1.5), (4.2, 5.6, 1.8), mat_idx=1)
    # Sawtooth industrial skylights
    for i in range(4):
        y_pos = -1.8 + i * 1.2
        add_box(bm, (-0.4, y_pos, 2.55), (3.6, 0.8, 0.4), mat_idx=2)

    # Large vehicle rollout bay with hazard stripes
    add_door(bm, (-0.4, -2.85, 0.3), 2.6, 1.8, mat_idx=3)

    # Overhead exterior gantry crane framework
    add_gantry(bm, (2.1, 0, 0.6), 1.2, 5.4, 2.6, post_r=0.12, mat_idx=2)
    # Hoist trolley
    add_box(bm, (2.1, -0.6, 3.1), (0.7, 0.7, 0.3), mat_idx=3)

    # Exhaust filtration stacks
    for sy in (1.6, 2.2):
        add_cyl(bm, (-2.4, sy, 1.6), 0.22, 2.2, 'Z', 8, mat_idx=2)

    export_building(bm, "light_manufactory", "light_manufactory.glb")


# ---------------------------------------------------------------------------
# 5. MEDIUM MANUFACTORY: Twin Fabrication Bays, Crane Trolley & Blast Stack
# ---------------------------------------------------------------------------
def build_medium_manufactory():
    bm = bmesh.new()
    add_box(bm, (0, 0, 0.35), (6.4, 8.4, 0.7), mat_idx=0)

    # Twin fabrication halls (high bay + low bay)
    add_box(bm, (-0.8, 0, 1.8), (4.4, 7.4, 2.4), mat_idx=1)
    add_box(bm, (1.8, 0, 1.3), (2.2, 6.8, 1.6), mat_idx=1)

    # Roof trusses & ventilation banks
    add_box(bm, (-0.8, 0, 3.05), (4.6, 7.6, 0.2), mat_idx=2)
    for i in range(5):
        y_pos = -2.6 + i * 1.3
        add_box(bm, (-0.8, y_pos, 3.3), (2.8, 0.8, 0.4), mat_idx=2)

    # Dual reinforced rollout blast gates
    add_door(bm, (-0.8, -3.75, 0.35), 3.0, 2.2, mat_idx=3)
    add_door(bm, (1.8, -3.45, 0.35), 1.6, 1.6, mat_idx=3)

    # Heavy crane gantry
    add_gantry(bm, (0, 0, 0.7), 5.8, 7.8, 3.4, post_r=0.16, mat_idx=2)

    # Smelting furnace chimney
    add_cyl(bm, (-2.6, 2.8, 2.4), 0.45, 3.6, 'Z', 10, mat_idx=2)
    add_taper(bm, (-2.6, 2.8, 4.3), 0.55, 0.35, 0.4, 10, mat_idx=2)

    export_building(bm, "medium_manufactory", "medium_manufactory.glb")


# ---------------------------------------------------------------------------
# 6. HEAVY MANUFACTORY: Massive Industrial Foundry & Dual Gantry Cranes
# ---------------------------------------------------------------------------
def build_heavy_manufactory():
    bm = bmesh.new()
    add_box(bm, (0, 0, 0.4), (7.8, 10.4, 0.8), mat_idx=0)

    # Massive central foundry complex
    add_box(bm, (0, 0, 2.2), (6.4, 9.2, 3.0), mat_idx=1)
    add_box(bm, (0, 0, 3.75), (6.7, 9.5, 0.25), mat_idx=2)

    # Twin heavy smelting exhaust chimneys
    for sx in (-2.4, 2.4):
        add_cyl(bm, (sx, 3.6, 2.8), 0.55, 4.4, 'Z', 12, mat_idx=2)
        add_taper(bm, (sx, 3.6, 5.1), 0.65, 0.4, 0.45, 12, mat_idx=2)

    # Heavy armor rolling doors
    add_door(bm, (0, -4.65, 0.4), 4.2, 2.8, mat_idx=3)

    # Massive dual overhead crane bridge
    add_gantry(bm, (0, 0, 0.8), 7.2, 9.8, 4.2, post_r=0.22, mat_idx=2)
    add_box(bm, (0, -1.5, 4.8), (6.8, 0.8, 0.5), mat_idx=3)
    add_box(bm, (0, 1.5, 4.8), (6.8, 0.8, 0.5), mat_idx=3)

    # Slag holding tanks & industrial pipework
    for sx in (-3.4, 3.4):
        for sy in (-2.0, 0.5):
            add_cyl(bm, (sx, sy, 1.4), 0.65, 1.8, 'Z', 10, mat_idx=1)
            add_pipe_run(bm, (sx, sy, 2.0), (sx * 0.7, sy, 2.0), 0.16, mat_idx=2)

    export_building(bm, "heavy_manufactory", "heavy_manufactory.glb")


# ---------------------------------------------------------------------------
# 7. TECH LAB: Signals Intelligence Post, Triple Dipole Array & Radome
# ---------------------------------------------------------------------------
def build_tech_lab():
    bm = bmesh.new()
    add_box(bm, (0, 0, 0.35), (5.0, 5.0, 0.7), mat_idx=0)
    add_box(bm, (0, 0, 1.4), (4.0, 4.0, 1.4), mat_idx=1)
    add_box(bm, (0, 0, 2.15), (4.3, 4.3, 0.2), mat_idx=2)

    # Large rotating surveillance dish & Radome
    add_sphere(bm, (-0.8, -0.8, 2.8), 0.9, 14, 10, mat_idx=4)
    add_taper(bm, (1.1, 0.9, 3.2), 1.2, 0.2, 0.6, 14, mat_idx=4)
    add_cyl(bm, (1.1, 0.9, 2.6), 0.18, 0.9, 'Z', 8, mat_idx=2)

    # Triple dipole antenna array
    for i, px in enumerate((-1.4, 0.0, 1.4)):
        add_cyl(bm, (px, 1.6, 3.4), 0.08, 2.4, 'Z', 6, mat_idx=4)
        add_box(bm, (px, 1.6, 4.4), (0.7, 0.06, 0.06), mat_idx=4)

    add_door(bm, (0, -2.05, 0.35), 1.1, 1.3, mat_idx=3)
    export_building(bm, "tech_lab", "tech_lab.glb")


# ---------------------------------------------------------------------------
# 8. PHYSICS LAB: Magnetic Containment Dome & Cryo Coolant Tanks
# ---------------------------------------------------------------------------
def build_physics_lab():
    bm = bmesh.new()
    add_box(bm, (0, 0, 0.35), (5.4, 5.4, 0.7), mat_idx=0)

    # Octagonal bunker block
    add_cyl(bm, (0, 0, 1.2), 2.4, 1.4, 'Z', 8, mat_idx=0)
    # Reinforced geodesic dome
    add_sphere(bm, (0, 0, 1.8), 1.8, 14, 10, mat_idx=1)

    # Magnetic confinement coils wrapping dome
    for z in (2.0, 2.7, 3.3):
        add_cyl(bm, (0, 0, z), 1.88, 0.12, 'Z', 14, mat_idx=2)

    # Exterior cryogenic coolant reservoirs & piping
    for sx, sy in ((-1.9, -1.9), (1.9, -1.9), (-1.9, 1.9), (1.9, 1.9)):
        add_cyl(bm, (sx, sy, 1.2), 0.45, 1.6, 'Z', 10, mat_idx=4)
        add_pipe_run(bm, (sx, sy, 1.6), (sx * 0.4, sy * 0.4, 1.6), 0.12, mat_idx=2)

    add_door(bm, (0, -2.45, 0.35), 1.2, 1.4, mat_idx=3)
    export_building(bm, "physics_lab", "physics_lab.glb")


# ---------------------------------------------------------------------------
# 9. EXOTICS LAB: Underground Silo Cap, High-Voltage Induction Focus Rings
# ---------------------------------------------------------------------------
def build_exotics_lab():
    bm = bmesh.new()
    add_box(bm, (0, 0, 0.35), (5.6, 5.6, 0.7), mat_idx=0)

    # Heavy subterranean silo ring
    add_cyl(bm, (0, 0, 1.1), 2.4, 1.2, 'Z', 12, mat_idx=0)
    add_cyl(bm, (0, 0, 1.8), 2.0, 0.4, 'Z', 12, mat_idx=2)

    # Central particle / beam emitter column with hovering focus rings
    add_cyl(bm, (0, 0, 2.5), 0.75, 2.0, 'Z', 10, mat_idx=1)
    for z in (2.3, 2.9, 3.5):
        add_cyl(bm, (0, 0, z), 1.35, 0.14, 'Z', 12, mat_idx=4)

    # 4 high-voltage transformer capacitors on corner pads
    for sx, sy in ((-2.1, -2.1), (2.1, -2.1), (-2.1, 2.1), (2.1, 2.1)):
        add_box(bm, (sx, sy, 0.9), (0.9, 0.9, 0.9), mat_idx=2)
        add_cyl(bm, (sx, sy, 1.55), 0.15, 0.5, 'Z', 6, mat_idx=4)

    add_door(bm, (0, -2.45, 0.35), 1.3, 1.5, mat_idx=3)
    export_building(bm, "exotics_lab", "exotics_lab.glb")


if __name__ == "__main__":
    clear_scene()
    print("Building Cold-War RTS Base Buildings...")
    build_hq()
    build_refinery()
    build_power_plant()
    build_light_manufactory()
    build_medium_manufactory()
    build_heavy_manufactory()
    build_tech_lab()
    build_physics_lab()
    build_exotics_lab()
    print("Building generation complete!")
