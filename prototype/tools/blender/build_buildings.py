import bpy
import bmesh
import math
import os
import mathutils

# Authored base-building meshes: hq, refinery, power_plant, and the three
# manufactory tiers.
#
# WHY THESE ARE BEING REBUILT FROM SCRATCH
# ---------------------------------------------------------------------------
# The previous set came from run_tripo.py - raw image-to-3D marching-cubes
# output, shipped without ever passing through decimate_building_glb.py. The
# result was 30-71 MB per file at 360k-845k triangles for a building the
# player sees at RTS zoom, versus 5-6k tris for the two that WERE processed.
# Measured consequences, not guesses (scratch/probe_base_spawn.gd):
#
#   hq                  9170 ms to spawn   446,782 tris
#   heavy_manufactory   4265 ms            845,412 tris
#   light_manufactory   1734 ms            362,002 tris
#   refinery              83 ms              5,949 tris
#
# _spawn_bases() came to 27.4s of a 34.6s match load, most of it inside
# hull_decals' projection raycasts, which test every triangle of the host
# mesh in GDScript. Decimating the Tripo output was the obvious fix and is
# the wrong one: it was never good geometry, just a lot of it - a noisy
# marching-cubes blob has no clean silhouette to preserve, and decimating to
# 6k leaves a lumpy approximation of a lump.
#
# So these are authored the same way every weapon module in this directory
# is: primitives assembled into deliberate, readable shapes, at a triangle
# budget chosen for the camera distance they are actually viewed from.
#
# CONVENTIONS (identical to build_structural.py / build_hmg.py)
#   - Blender +Z is UP, +Y is FORWARD (Godot -Z), so the glTF import lands in
#     the same axis space as every other asset here.
#   - Authored at roughly true proportions, centred on the origin footprint.
#     building.gd's _setup_building_glb_mesh() rescales each mesh onto its
#     PREFAB_STATS size by AABB, so exact dimensions do not matter - the
#     PROPORTIONS do. And it fits each axis INDEPENDENTLY, so authoring a
#     building taller than its PREFAB_STATS height does not crop it, it
#     squashes it: the first build made the HQ 6.1 units tall against a
#     declared height of 4 and every mast and chimney came out stubby.
#     Author to roughly the declared aspect and the silhouette survives.
#     Current PREFAB_STATS sizes (x, y, z):
#       hq 7x4x7   refinery 5x3x5   power_plant 4x3x4
#       light 5x2.4x6   medium 6x3x8   heavy 7.5x3.8x10
#   - Silhouette stays straight-faced industrial; the goofiness lives at
#     detail scale (VISUAL_ART_DIRECTION.md 1.2).
#   - Low-segment cylinders (8-12) throughout. At RTS zoom nothing reads as
#     faceted, and the budget is what makes decal projection affordable.

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "..", "assets", "models", "buildings"))


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        if block.users == 0:
            bpy.data.meshes.remove(block)
    for block in list(bpy.data.materials):
        if block.users == 0:
            bpy.data.materials.remove(block)


def add_box(bm, center, size):
    """Axis-aligned box. center/size are (x, y, z) with Z up."""
    m = mathutils.Matrix.Translation(mathutils.Vector(center)) @ mathutils.Matrix.Diagonal(
        mathutils.Vector((size[0], size[1], size[2], 1.0)))
    bmesh.ops.create_cube(bm, size=1.0, matrix=m)


def add_cyl(bm, center, radius, height, axis='Z', segments=10):
    """Cylinder along the given axis."""
    m = mathutils.Matrix.Translation(mathutils.Vector(center))
    if axis == 'X':
        m = m @ mathutils.Matrix.Rotation(math.radians(90), 4, 'Y')
    elif axis == 'Y':
        m = m @ mathutils.Matrix.Rotation(math.radians(-90), 4, 'X')
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                          radius1=radius, radius2=radius, depth=height, matrix=m)


def add_taper(bm, center, r_bottom, r_top, height, segments=10):
    """Truncated cone, Z up - cooling towers, silo caps, chimneys."""
    m = mathutils.Matrix.Translation(mathutils.Vector(center))
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                          radius1=r_bottom, radius2=r_top, depth=height, matrix=m)


def add_pipe_run(bm, start, end, radius, segments=8):
    """A straight pipe between two points, with a flange at each end."""
    s = mathutils.Vector(start)
    e = mathutils.Vector(end)
    d = e - s
    length = d.length
    if length < 1e-5:
        return
    mid = (s + e) * 0.5
    up = mathutils.Vector((0, 0, 1))
    rot = up.rotation_difference(d.normalized()).to_matrix().to_4x4()
    m = mathutils.Matrix.Translation(mid) @ rot
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                          radius1=radius, radius2=radius, depth=length, matrix=m)
    for p in (s, e):
        fm = mathutils.Matrix.Translation(p) @ rot
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                              radius1=radius * 1.45, radius2=radius * 1.45, depth=radius * 0.5,
                              matrix=fm)


def add_roof_ribs(bm, center, span_x, span_y, z, count, rib=0.10):
    """Evenly spaced ribs across a roof - the cheapest way to make a big flat
    slab read as a built structure rather than a solid block."""
    for i in range(count):
        t = (i + 0.5) / count - 0.5
        add_box(bm, (center[0], center[1] + t * span_y, z), (span_x, rib, rib * 1.6))


def add_railing(bm, center, span_x, span_y, z, posts=6, h=0.30):
    """Perimeter rail around a roof or catwalk: corner posts plus a top rail."""
    for i in range(posts):
        t = (i / (posts - 1.0)) - 0.5
        add_box(bm, (center[0] + t * span_x, center[1] - span_y / 2, z + h / 2), (0.06, 0.06, h))
        add_box(bm, (center[0] + t * span_x, center[1] + span_y / 2, z + h / 2), (0.06, 0.06, h))
    add_box(bm, (center[0], center[1] - span_y / 2, z + h), (span_x, 0.05, 0.05))
    add_box(bm, (center[0], center[1] + span_y / 2, z + h), (span_x, 0.05, 0.05))


def add_vents(bm, center, count, spacing, z, w=0.5, d=0.35, h=0.22):
    for i in range(count):
        t = (i - (count - 1) / 2.0) * spacing
        add_box(bm, (center[0] + t, center[1], z + h / 2), (w, d, h))


def add_sphere(bm, center, radius, segments=12, rings=8):
    m = mathutils.Matrix.Translation(mathutils.Vector(center))
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings,
                              radius=radius, matrix=m)


def add_door(bm, center, w, h, depth=0.12):
    """A recessed roll-up door: frame plus slats."""
    add_box(bm, (center[0], center[1], center[2] + h / 2), (w + 0.3, depth, h + 0.25))
    slats = max(3, int(h / 0.35))
    for i in range(slats):
        z = center[2] + (i + 0.5) * (h / slats)
        add_box(bm, (center[0], center[1] - depth * 0.6, z), (w, depth * 0.5, h / slats * 0.75))


def export_bmesh(bm, object_name, filename, color=(0.55, 0.54, 0.50, 1.0),
                 metallic=0.35, roughness=0.72):
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

    # UV UNWRAP IS NOT OPTIONAL HERE.
    #
    # The first build of these meshes shipped without one, and the buildings
    # came back covered in white speckle: hull_material_builder.gd's faction
    # shader samples wear/grime/panel-line textures by UV, and with no UV
    # layer every lookup reads the same degenerate coordinate, so the noise
    # texture resolves to garbage across whole faces. Cube projection is the
    # right unwrap for architecture made of axis-aligned boxes and cylinders -
    # it keeps texel density even on every wall without the seam-scattering
    # smart-project does on this kind of geometry.
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.cube_project(cube_size=2.0)
    bpy.ops.object.mode_set(mode='OBJECT')

    mat = bpy.data.materials.new(name=object_name + "_mat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs['Base Color'].default_value = color
        bsdf.inputs['Metallic'].default_value = metallic
        bsdf.inputs['Roughness'].default_value = roughness
    obj.data.materials.append(mat)

    tris = sum(max(0, len(p.vertices) - 2) for p in me.polygons)
    filepath = os.path.join(OUT_DIR, filename)
    bpy.ops.export_scene.gltf(filepath=filepath, use_selection=True, export_format='GLB')
    print("Exported: %-28s %6d tris" % (filename, tris))
    clear_scene()


# ---------------------------------------------------------------------------
# HQ - a command bunker: heavy sloped base, set-back upper storey, comms mast
# and dish. Reads as "the important one" from the silhouette alone.
# ---------------------------------------------------------------------------
def build_hq():
    bm = bmesh.new()
    add_box(bm, (0, 0, 0.65), (7.0, 7.0, 1.3))         # bunker plinth
    add_box(bm, (0, 0, 1.50), (6.0, 6.0, 0.5))         # chamfer course
    add_box(bm, (0, -0.4, 2.25), (4.6, 4.4, 1.0))      # upper storey
    add_box(bm, (0, -0.4, 2.88), (5.0, 4.8, 0.25))     # roof cap

    for sx in (-1, 1):                                  # corner buttresses
        for sy in (-1, 1):
            add_box(bm, (sx * 3.2, sy * 3.2, 0.80), (0.75, 0.75, 1.6))
    add_door(bm, (0, -3.5, 0.0), 1.6, 1.5)
    add_vents(bm, (0, 2.6), 4, 1.2, 1.80)
    add_railing(bm, (0, -0.4, 0), 4.8, 4.6, 3.02)

    add_cyl(bm, (1.7, 1.6, 3.75), 0.13, 1.6)            # comms mast
    for i in range(3):                                  # mast collars
        add_cyl(bm, (1.7, 1.6, 3.20 + i * 0.55), 0.22, 0.10, segments=8)
    add_taper(bm, (-1.6, 1.4, 3.35), 0.9, 0.15, 0.4, segments=12)  # dish
    add_cyl(bm, (-1.6, 1.4, 3.10), 0.14, 0.5)
    export_bmesh(bm, "hq", "hq.glb", color=(0.62, 0.60, 0.48, 1.0))


# ---------------------------------------------------------------------------
# REFINERY - twin silos, pipework, flare stack. Silhouette is deliberately
# vertical and round where everything else is boxy.
# ---------------------------------------------------------------------------
def build_refinery():
    bm = bmesh.new()
    add_box(bm, (0, 0, 0.35), (5.0, 5.0, 0.7))          # slab
    for sx in (-1.3, 1.3):                              # silos
        add_cyl(bm, (sx, -0.6, 1.55), 1.15, 1.9, segments=12)
        add_taper(bm, (sx, -0.6, 2.72), 1.15, 0.35, 0.45, segments=12)
        for i in range(3):                              # banding
            add_cyl(bm, (sx, -0.6, 0.85 + i * 0.62), 1.22, 0.09, segments=12)
    add_pipe_run(bm, (-1.3, -0.6, 2.45), (1.3, -0.6, 2.45), 0.16)
    add_pipe_run(bm, (1.3, -0.6, 1.2), (2.2, 1.8, 1.2), 0.14)
    add_pipe_run(bm, (-1.3, -0.6, 1.2), (-2.2, 1.8, 1.2), 0.14)

    add_box(bm, (0, 1.9, 1.0), (2.6, 1.5, 1.4))         # control shed
    add_vents(bm, (0, 1.9), 3, 0.7, 1.7, w=0.4, d=0.3)
    add_door(bm, (0, 1.15, 0.7), 0.9, 1.1)

    add_cyl(bm, (2.0, 1.9, 1.95), 0.22, 2.5, segments=10)  # flare stack
    add_taper(bm, (2.0, 1.9, 3.30), 0.30, 0.20, 0.3, segments=10)
    export_bmesh(bm, "refinery", "refinery.glb", color=(0.50, 0.56, 0.62, 1.0))


# ---------------------------------------------------------------------------
# POWER PLANT - turbine hall plus two cooling towers and a transformer yard.
# ---------------------------------------------------------------------------
def build_power_plant():
    bm = bmesh.new()
    add_box(bm, (0, 0, 0.3), (5.5, 5.0, 0.6))
    add_box(bm, (-0.6, 0, 1.5), (3.4, 4.2, 1.8))        # turbine hall
    add_roof_ribs(bm, (-0.6, 0), 3.5, 4.2, 2.5, 6)
    add_door(bm, (-0.6, -2.15, 0.6), 1.2, 1.3)

    for sy in (-1.2, 1.2):                              # cooling towers
        add_taper(bm, (2.0, sy, 1.45), 1.05, 0.70, 1.8, segments=12)
        add_cyl(bm, (2.0, sy, 2.42), 0.75, 0.16, segments=12)

    for i in range(3):                                  # transformers
        add_box(bm, (-2.4, -1.6 + i * 1.6, 1.0), (0.8, 0.9, 0.8))
        add_cyl(bm, (-2.4, -1.6 + i * 1.6, 1.55), 0.10, 0.35, segments=8)
    add_pipe_run(bm, (-1.9, -1.6, 1.5), (-1.9, 1.6, 1.5), 0.09)
    export_bmesh(bm, "power_plant", "power_plant.glb", color=(0.48, 0.52, 0.55, 1.0))


# ---------------------------------------------------------------------------
# MANUFACTORIES - one shared hangar silhouette, escalating in size, roof
# clutter and stack count so the three tiers read apart at a glance without
# needing three unrelated designs.
# ---------------------------------------------------------------------------
def build_manufactory(name, sx, sy, sz, stacks, bays, color):
    bm = bmesh.new()
    add_box(bm, (0, 0, 0.3), (sx + 0.6, sy + 0.6, 0.6))            # apron
    add_box(bm, (0, 0, 0.6 + sz * 0.5), (sx, sy, sz))              # shed
    add_box(bm, (0, 0, 0.6 + sz + 0.15), (sx + 0.4, sy + 0.4, 0.3))  # roof lip
    add_roof_ribs(bm, (0, 0), sx + 0.3, sy, 0.6 + sz + 0.3, bays + 2)

    # Vehicle door on +Y, the exit_facing direction PREFAB_STATS declares.
    add_door(bm, (0, sy / 2, 0.6), sx * 0.42, sz * 0.72)

    for i in range(stacks):                                        # chimneys
        t = (i - (stacks - 1) / 2.0) * (sx / max(stacks, 2)) * 0.9
        add_cyl(bm, (t, -sy * 0.28, 0.6 + sz + 0.45), 0.22, 0.75, segments=8)
        add_cyl(bm, (t, -sy * 0.28, 0.6 + sz + 0.86), 0.30, 0.14, segments=8)

    add_vents(bm, (0, sy * 0.25), bays, sx / (bays + 1.0), 0.6 + sz + 0.3)
    add_railing(bm, (0, 0, 0), sx, sy, 0.6 + sz + 0.3)

    for sxx in (-1, 1):                                            # buttresses
        for i in range(bays):
            t = (i - (bays - 1) / 2.0) * (sy / bays)
            add_box(bm, (sxx * sx / 2, t, 0.6 + sz * 0.45), (0.22, 0.30, sz * 0.9))

    add_cyl(bm, (sx * 0.32, sy * 0.30, 0.6 + sz + 0.35), 0.10, 0.7)  # gantry post
    add_pipe_run(bm, (sx * 0.32, sy * 0.30, 0.6 + sz + 0.65),
                 (-sx * 0.32, sy * 0.30, 0.6 + sz + 0.65), 0.07)
    export_bmesh(bm, name, name + ".glb", color=color)


# ---------------------------------------------------------------------------
# TECH LABS - three unlock buildings, none of them feeding a production queue
# (BuildingCatalog.CONTRIBUTORS has no entry for them). Each gates a tier of
# ModuleCatalog parts via required_building (see design_costing.gd); the
# silhouette escalates with the tier so "how far up the tree is this base" is
# readable from the RTS camera without opening a menu.
# ---------------------------------------------------------------------------

# TECH LAB - a workshop shed with a roof-mounted sensor dish array. The
# baseline unlock: unassuming, close to the manufactory silhouette it feeds
# parts into.
def build_tech_lab():
    bm = bmesh.new()
    add_box(bm, (0, 0, 0.3), (4.4, 4.4, 0.6))            # apron
    add_box(bm, (0, 0, 0.6 + 1.1), (3.6, 3.6, 2.2))      # workshop shed
    add_box(bm, (0, 0, 0.6 + 2.2 + 0.15), (3.9, 3.9, 0.3))  # roof lip
    add_roof_ribs(bm, (0, 0), 3.6, 3.6, 0.6 + 2.2 + 0.3, 4)
    add_door(bm, (0, -1.8, 0.6), 1.3, 1.4)
    add_vents(bm, (1.0, 1.85), 2, 0.8, 1.7, w=0.35, d=0.25)

    for sx in (-0.9, 0.9):                                # dish mast pair
        add_cyl(bm, (sx, 0, 0.6 + 2.2 + 0.55), 0.09, 1.0)
        add_taper(bm, (sx, 0, 0.6 + 2.2 + 1.15), 0.55, 0.10, 0.3, segments=10)
    add_railing(bm, (0, 0, 0), 3.6, 3.6, 0.6 + 2.2 + 0.3)
    export_bmesh(bm, "tech_lab", "tech_lab.glb", color=(0.42, 0.55, 0.58, 1.0))


# PHYSICS LAB - the tech lab's shed with a particle-ring collector bolted to
# the roof, reading as a step up in ambition rather than a new building
# language.
def build_physics_lab():
    bm = bmesh.new()
    add_box(bm, (0, 0, 0.3), (4.8, 4.8, 0.6))
    add_box(bm, (0, -0.3, 0.6 + 1.3), (4.0, 3.8, 2.6))   # taller shed
    add_box(bm, (0, -0.3, 0.6 + 2.6 + 0.15), (4.3, 4.1, 0.3))
    add_roof_ribs(bm, (0, -0.3), 4.0, 3.8, 0.6 + 2.6 + 0.3, 5)
    add_door(bm, (0, -2.2, 0.6), 1.4, 1.5)
    add_vents(bm, (1.2, 1.55), 2, 0.9, 2.0, w=0.4, d=0.3)

    add_cyl(bm, (0, 1.9, 0.6 + 2.6 + 0.85), 0.12, 1.1)   # ring support mast
    ring_z = 0.6 + 2.6 + 1.55
    for i in range(10):                                   # collector ring
        ang = (i / 10.0) * math.tau
        add_box(bm, (0, 1.9 + 0.85 * math.cos(ang), ring_z + 0.85 * math.sin(ang)),
                (0.5, 0.16, 0.16))
    add_railing(bm, (0, -0.3, 0), 4.0, 3.8, 0.6 + 2.6 + 0.3)
    export_bmesh(bm, "physics_lab", "physics_lab.glb", color=(0.45, 0.48, 0.62, 1.0))


# EXOTICS LAB - the top of the tree: a hexagonal containment chamber holding a
# levitated sphere, ringed by an emitter collar. The one building on this list
# that is not a shed with a thing on the roof - it earns a distinct shape for
# being the last stop.
def build_exotics_lab():
    bm = bmesh.new()
    add_box(bm, (0, 0, 0.3), (5.4, 5.4, 0.6))
    add_cyl(bm, (0, 0, 0.6 + 1.4), 2.2, 2.8, segments=8)  # octagonal-ish drum
    add_taper(bm, (0, 0, 0.6 + 2.8 + 0.35), 2.2, 1.5, 0.7, segments=8)  # domed cap
    add_door(bm, (0, -2.35, 0.6), 1.3, 1.5)
    add_vents(bm, (0, 2.35), 3, 0.9, 1.4, w=0.35, d=0.25)

    add_sphere(bm, (0, 0, 0.6 + 1.4), 0.9, segments=14, rings=10)  # containment core
    collar_z = 0.6 + 1.4
    for i in range(12):                                    # emitter collar
        ang = (i / 12.0) * math.tau
        add_box(bm, (1.35 * math.cos(ang), 1.35 * math.sin(ang), collar_z),
                (0.18, 0.18, 0.45))
    add_railing(bm, (0, 0, 0), 4.4, 4.4, 0.6 + 2.8 + 0.65)
    export_bmesh(bm, "exotics_lab", "exotics_lab.glb", color=(0.55, 0.38, 0.58, 1.0))


if __name__ == "__main__":
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(OUT_DIR, exist_ok=True)
    build_hq()
    build_refinery()
    build_power_plant()
    build_manufactory("light_manufactory", 5.0, 6.0, 2.2, 2, 3, (0.66, 0.58, 0.42, 1.0))
    build_manufactory("medium_manufactory", 6.0, 8.0, 2.8, 3, 4, (0.70, 0.53, 0.40, 1.0))
    build_manufactory("heavy_manufactory", 7.5, 10.0, 3.6, 4, 5, (0.58, 0.41, 0.34, 1.0))
    build_tech_lab()
    build_physics_lab()
    build_exotics_lab()
    print("All building meshes rebuilt.")
