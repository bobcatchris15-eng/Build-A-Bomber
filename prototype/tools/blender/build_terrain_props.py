"""Authored Organic Terrain Assets Generator (Trees, Boulders, Spires, Scree, Cliffs, Grass, Shrubs).

Generates real, beautiful, organic low-poly 3D meshes using Blender's bmesh API and exports
them as .glb binaries into assets/models/terrain/ for Kitbash Command.

COORDINATE CONVENTION:
  - In Blender native space: Z is UP, X is RIGHT, Y is FORWARD.
  - Ground level is Z = 0.
  - export_yup=True automatically maps Blender +Z to Godot +Y (Up) so all models stand perfectly upright.

Run via:
    blender.exe --background --python tools/blender/build_terrain_props.py
"""

import os
import sys
import math
import random
import bpy
import bmesh
from mathutils import Vector, Matrix

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TERRAIN_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "terrain")


# ---------------------------------------------------------------------------
# Procedural 3D Organic Noise & Math Functions
# ---------------------------------------------------------------------------

def organic_noise_3d(x, y, z, seed=0):
    """Multi-octave continuous 3D harmonic noise for realistic rock & bark weathering."""
    sx = x * 1.2 + seed * 13.17
    sy = y * 1.2 + seed * 29.53
    sz = z * 1.2 + seed * 47.81
    
    # Octave 1: Major geological mass
    n1 = math.sin(sx * 1.4 + sy * 0.8) * math.cos(sz * 1.3 + sx * 0.5)
    n1 += math.sin(sy * 1.7 + sz * 1.5) * math.cos(sx * 0.9 - sy * 0.4)
    
    # Octave 2: Secondary fissures & ledges
    n2 = math.sin(sx * 3.1 - sz * 2.2) * math.cos(sy * 2.8 + sx * 1.7)
    n2 += math.sin(sz * 3.7 + sy * 2.5) * math.cos(sx * 2.9 + sz * 1.1)
    
    # Octave 3: High-frequency surface roughness
    n3 = math.sin(sx * 7.3 + sz * 6.5) * math.cos(sy * 6.9 - sx * 5.1)
    
    return n1 * 0.55 + n2 * 0.32 + n3 * 0.13


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.textures, bpy.data.images):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def new_material(name, color=(0.5, 0.5, 0.5), metallic=0.0, roughness=0.9):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        base_color_input = bsdf.inputs.get("Base Color")
        if base_color_input:
            base_color_input.default_value = (color[0], color[1], color[2], 1.0)
        roughness_input = bsdf.inputs.get("Roughness")
        if roughness_input:
            roughness_input.default_value = roughness
        metallic_input = bsdf.inputs.get("Metallic")
        if metallic_input:
            metallic_input.default_value = metallic
    return mat


def finalize_mesh(bm, name, color=(0.42, 0.40, 0.38), metallic=0.05, roughness=0.9, smooth=True, auto_smooth_angle=35):
    mesh_data = bpy.data.meshes.new(name + "_mesh")
    bm.to_mesh(mesh_data)
    bm.free()

    obj = bpy.data.objects.new(name, mesh_data)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    if smooth:
        bpy.ops.object.shade_smooth()
        try:
            obj.data.use_auto_smooth = True
            obj.data.auto_smooth_angle = math.radians(auto_smooth_angle)
        except Exception:
            pass
    else:
        bpy.ops.object.shade_flat()

    mat = new_material(name + "_mat", color=color, metallic=metallic, roughness=roughness)
    obj.data.materials.append(mat)
    return obj


def finalize_mesh_dual(bm, name, mat0_color=(0.32, 0.22, 0.15), mat1_color=(0.18, 0.35, 0.15),
                       mat0_roughness=0.95, mat1_roughness=0.85, smooth=True, auto_smooth_angle=35):
    mesh_data = bpy.data.meshes.new(name + "_mesh")
    bm.to_mesh(mesh_data)
    bm.free()

    obj = bpy.data.objects.new(name, mesh_data)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    if smooth:
        bpy.ops.object.shade_smooth()
        try:
            obj.data.use_auto_smooth = True
            obj.data.auto_smooth_angle = math.radians(auto_smooth_angle)
        except Exception:
            pass
    else:
        bpy.ops.object.shade_flat()

    mat0 = new_material(name + "_mat0", color=mat0_color, roughness=mat0_roughness)
    mat1 = new_material(name + "_mat1", color=mat1_color, roughness=mat1_roughness)
    obj.data.materials.append(mat0)
    obj.data.materials.append(mat1)
    return obj


def export_glb(obj, filepath):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        use_selection=True,
        export_format='GLB',
        export_yup=True,
        export_apply=True
    )
    print("Exported GLB: %s" % filepath)
    mesh_data = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh_data and mesh_data.users == 0:
        bpy.data.meshes.remove(mesh_data)


# ---------------------------------------------------------------------------
# BMesh Primitive Helpers in Blender Z-Up Space
# ---------------------------------------------------------------------------

def add_cylinder_z(bm, center, radius_bottom, height, segments=8, radius_top=None):
    """Creates a vertical cylinder along +Z axis from center.z - height/2 to center.z + height/2."""
    r_bot = radius_bottom
    r_top = radius_bottom if radius_top is None else radius_top
    half_h = height * 0.5
    z_bot = center[2] - half_h
    z_top = center[2] + half_h

    bot_verts = []
    top_verts = []
    for i in range(segments):
        theta = (2.0 * math.pi * i) / segments
        cx, cy = math.cos(theta), math.sin(theta)
        bot_verts.append(bm.verts.new((center[0] + cx * r_bot, center[1] + cy * r_bot, z_bot)))
        if r_top > 0.001:
            top_verts.append(bm.verts.new((center[0] + cx * r_top, center[1] + cy * r_top, z_top)))

    bm.verts.ensure_lookup_table()
    created_faces = []

    if r_top > 0.001:
        for i in range(segments):
            i_next = (i + 1) % segments
            created_faces.append(bm.faces.new([bot_verts[i], bot_verts[i_next], top_verts[i_next], top_verts[i]]))
        created_faces.append(bm.faces.new(top_verts))
    else:
        apex = bm.verts.new((center[0], center[1], z_top))
        for i in range(segments):
            i_next = (i + 1) % segments
            created_faces.append(bm.faces.new([bot_verts[i], bot_verts[i_next], apex]))

    created_faces.append(bm.faces.new(list(reversed(bot_verts))))
    return created_faces


def add_curved_trunk_segment(bm, start_pt, end_pt, r_start, r_end, segments=8):
    """Creates an organic lofted cylinder segment connecting start_pt to end_pt."""
    p0 = Vector(start_pt)
    p1 = Vector(end_pt)
    axis = (p1 - p0).normalized()
    if axis.length < 1e-4:
        axis = Vector((0, 0, 1))
    
    # Orthogonal basis
    up = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
    right = axis.cross(up).normalized()
    forward = right.cross(axis).normalized()

    v_bot = []
    v_top = []
    for i in range(segments):
        theta = (2.0 * math.pi * i) / segments
        cos_t, sin_t = math.cos(theta), math.sin(theta)
        radial = right * cos_t + forward * sin_t
        v_bot.append(bm.verts.new(p0 + radial * r_start))
        v_top.append(bm.verts.new(p1 + radial * r_end))

    bm.verts.ensure_lookup_table()
    faces = []
    for i in range(segments):
        i_next = (i + 1) % segments
        faces.append(bm.faces.new([v_bot[i], v_bot[i_next], v_top[i_next], v_top[i]]))
    return faces, v_bot, v_top


def fracture_mesh_z(bm, cuts=6, radius=1.0, rng=None, bias_horizontal=0.0):
    """Applies random planar bisect cuts in Z-up space to create sharp rock facets."""
    if rng is None:
        rng = random.Random(42)
    for _ in range(cuts):
        theta = rng.uniform(0, 2.0 * math.pi)
        phi = rng.uniform(-math.pi * 0.4, math.pi * 0.4)
        nx = math.cos(phi) * math.cos(theta)
        ny = math.cos(phi) * math.sin(theta)
        nz = math.sin(phi) * (1.0 - bias_horizontal)
        n = Vector((nx, ny, nz)).normalized()
        dist = radius * rng.uniform(0.35, 0.75)
        plane_co = n * dist
        res = bmesh.ops.bisect_plane(
            bm,
            geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
            plane_co=plane_co,
            plane_no=n,
            clear_outer=True,
            clear_inner=False
        )
        cut_edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        if cut_edges:
            bmesh.ops.holes_fill(bm, edges=cut_edges)


# ---------------------------------------------------------------------------
# 1. Authentic Organic Trees (Pine, Spruce, Oak, Birch, Snag, Sapling)
# ---------------------------------------------------------------------------

def build_organic_tree(name, seed=0):
    """Generates an upright, beautiful organic tree with genuine species architecture."""
    rng = random.Random(seed)
    bm = bmesh.new()

    within = seed % 20
    if within < 3:
        species = 0  # Layered Nordic Spruce
    elif within < 6:
        species = 1  # Highland Alpine Fir
    elif within < 10:
        species = 2  # Broadleaf Branching Oak
    elif within < 14:
        species = 3  # Slender Aspen / Birch
    elif within < 17:
        species = 4  # Weathered Lightning Snag
    else:
        species = 5  # Juvenile Sapling

    # Natural palettes
    bark_palettes = [
        (0.28, 0.20, 0.14),  # Spruce brown
        (0.24, 0.18, 0.12),  # Fir dark bark
        (0.32, 0.24, 0.16),  # Oak furrowed bark
        (0.72, 0.70, 0.65),  # Birch pale bark
        (0.42, 0.39, 0.35),  # Snag weathered silver
        (0.30, 0.22, 0.15)   # Sapling brown
    ]
    foliage_palettes = [
        (0.14, 0.28, 0.12),  # Spruce deep evergreen
        (0.12, 0.26, 0.14),  # Fir dark pine green
        (0.18, 0.36, 0.14),  # Oak lush leaf green
        (0.24, 0.40, 0.16),  # Birch vibrant lime-green
        (0.42, 0.39, 0.35),  # Snag (no leaves)
        (0.20, 0.38, 0.15)   # Sapling fresh green
    ]

    trunk_col = bark_palettes[species]
    canopy_col = foliage_palettes[species]

    if species == 0:  # Layered Nordic Spruce (Z-up)
        height = rng.uniform(4.0, 5.8)
        trunk_h = height * 0.25
        trunk_r = rng.uniform(0.14, 0.20)

        # Flared trunk with root buttresses at Z=0
        t_faces = add_cylinder_z(bm, (0, 0, trunk_h * 0.5), radius_bottom=trunk_r * 1.5,
                                 height=trunk_h, segments=7, radius_top=trunk_r * 0.8)
        for f in t_faces:
            f.material_index = 0

        # 4-6 tiered layered conifer boughs
        tiers = rng.randint(4, 6)
        canopy_h = height - trunk_h
        tier_step = canopy_h / float(tiers)
        for t in range(tiers):
            prog = float(t) / float(tiers - 1) if tiers > 1 else 0.0
            r_tier = rng.uniform(1.2, 1.8) * (1.0 - prog * 0.7)
            z_tier = trunk_h + t * tier_step * 0.8 + tier_step * 0.5
            # Conical bough skirt
            b_faces = add_cylinder_z(bm, (0, 0, z_tier), radius_bottom=r_tier,
                                     height=tier_step * 1.4, segments=9,
                                     radius_top=r_tier * 0.25 if t < tiers - 1 else 0.0)
            for f in b_faces:
                f.material_index = 1

    elif species == 1:  # Highland Alpine Fir (Z-up)
        height = rng.uniform(3.6, 5.0)
        trunk_h = height * 0.20
        trunk_r = rng.uniform(0.16, 0.22)
        t_faces = add_cylinder_z(bm, (0, 0, trunk_h * 0.5), radius_bottom=trunk_r * 1.4,
                                 height=trunk_h, segments=7, radius_top=trunk_r)
        for f in t_faces:
            f.material_index = 0

        # 3 steep dense conical tiers
        canopy_h = height - trunk_h
        for t in range(3):
            r_c = rng.uniform(1.4, 1.9) * (1.0 - t * 0.32)
            z_c = trunk_h + canopy_h * (0.2 + t * 0.32)
            c_faces = add_cylinder_z(bm, (0, 0, z_c), radius_bottom=r_c,
                                     height=canopy_h * 0.55, segments=8,
                                     radius_top=r_c * 0.3 if t < 2 else 0.0)
            for f in c_faces:
                f.material_index = 1

    elif species == 2:  # Broadleaf Branching Oak (Z-up)
        height = rng.uniform(3.8, 5.2)
        trunk_h = height * 0.45
        trunk_r = rng.uniform(0.20, 0.28)

        # Trunk base with flare
        t_faces = add_cylinder_z(bm, (0, 0, trunk_h * 0.5), radius_bottom=trunk_r * 1.6,
                                 height=trunk_h, segments=8, radius_top=trunk_r)
        for f in t_faces:
            f.material_index = 0

        # 3-4 organic twisting branch limbs
        n_branches = rng.randint(3, 4)
        for b in range(n_branches):
            b_ang = (2.0 * math.pi * b) / float(n_branches) + rng.uniform(-0.25, 0.25)
            spread = rng.uniform(0.8, 1.4)
            b_end = Vector((math.cos(b_ang) * spread, math.sin(b_ang) * spread, trunk_h + rng.uniform(0.4, 1.1)))
            b_faces, _, _ = add_curved_trunk_segment(bm, (0, 0, trunk_h * 0.85), b_end, trunk_r * 0.6, trunk_r * 0.35, segments=6)
            for f in b_faces:
                f.material_index = 0

            # Organic foliage cluster at branch end
            cluster_r = rng.uniform(0.9, 1.3)
            ret = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=cluster_r)
            for v in ret["verts"]:
                disp = organic_noise_3d(v.co.x, v.co.y, v.co.z, seed=seed + b * 7)
                v.co += v.co.normalized() * (disp * 0.25)
                v.co.z *= 0.8
                v.co += b_end
            for f in {f for v in ret["verts"] for f in v.link_faces}:
                f.material_index = 1

        # Central crown dome
        ret_c = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=rng.uniform(1.2, 1.6))
        for v in ret_c["verts"]:
            disp = organic_noise_3d(v.co.x, v.co.y, v.co.z, seed=seed + 99)
            v.co += v.co.normalized() * (disp * 0.28)
            v.co.z *= 0.85
            v.co += Vector((0, 0, trunk_h + 1.2))
        for f in {f for v in ret_c["verts"] for f in v.link_faces}:
            f.material_index = 1

    elif species == 3:  # Slender Aspen / Birch (Z-up)
        height = rng.uniform(4.2, 5.8)
        trunk_h = height * 0.60
        trunk_r = rng.uniform(0.10, 0.15)
        # Gently curved slender trunk
        mid_pt = Vector((rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), trunk_h * 0.5))
        top_pt = Vector((rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25), trunk_h))
        f1, _, _ = add_curved_trunk_segment(bm, (0, 0, 0), mid_pt, trunk_r * 1.3, trunk_r, segments=6)
        f2, _, _ = add_curved_trunk_segment(bm, mid_pt, top_pt, trunk_r, trunk_r * 0.7, segments=6)
        for f in f1 + f2:
            f.material_index = 0

        # 3 airy offset foliage clouds
        for p in range(3):
            p_ang = (2.0 * math.pi * p) / 3.0 + rng.uniform(-0.3, 0.3)
            p_r = rng.uniform(0.35, 0.7)
            pz = trunk_h + (p - 0.5) * 0.7
            ret = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=rng.uniform(0.75, 1.1))
            for v in ret["verts"]:
                disp = organic_noise_3d(v.co.x, v.co.y, v.co.z, seed=seed + p * 13)
                v.co += v.co.normalized() * (disp * 0.22)
                v.co.z *= 0.8
                v.co += Vector((math.cos(p_ang) * p_r, math.sin(p_ang) * p_r, pz))
            for f in {f for v in ret["verts"] for f in v.link_faces}:
                f.material_index = 1

    elif species == 4:  # Weathered Lightning Snag (Z-up)
        height = rng.uniform(3.2, 4.8)
        trunk_h = height
        trunk_r = rng.uniform(0.18, 0.26)
        t_faces = add_cylinder_z(bm, (0, 0, trunk_h * 0.5), radius_bottom=trunk_r * 1.5,
                                 height=trunk_h, segments=7, radius_top=trunk_r * 0.4)
        for f in t_faces:
            f.material_index = 0
        # Broken splinter points at top
        for sp in range(4):
            ang = (2.0 * math.pi * sp) / 4
            r_sp = trunk_r * 0.35
            add_cylinder_z(bm, (math.cos(ang) * r_sp, math.sin(ang) * r_sp, trunk_h + 0.25),
                           radius_bottom=0.04, height=0.5, segments=4, radius_top=0.0)

    else:  # Juvenile Sapling (Z-up)
        height = rng.uniform(1.6, 2.4)
        trunk_h = height * 0.35
        t_faces = add_cylinder_z(bm, (0, 0, trunk_h * 0.5), radius_bottom=0.06, height=trunk_h, segments=5)
        for f in t_faces:
            f.material_index = 0
        c_faces = add_cylinder_z(bm, (0, 0, trunk_h + (height - trunk_h) * 0.5),
                                 radius_bottom=0.55, height=height - trunk_h, segments=7, radius_top=0.0)
        for f in c_faces:
            f.material_index = 1

    # Rest ground at Z=0
    min_z = min(v.co.z for v in bm.verts)
    if min_z != 0.0:
        bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, -min_z))

    return finalize_mesh_dual(bm, name, mat0_color=trunk_col, mat1_color=canopy_col, smooth=True, auto_smooth_angle=40)


# ---------------------------------------------------------------------------
# 2. Organic Boulders, Rock Spires, Scree & Cliffs
# ---------------------------------------------------------------------------

def build_organic_boulder(name, radius=1.0, seed=0, style="weathered"):
    """Builds a rich, organic weathered boulder with realistic stone relief."""
    rng = random.Random(seed)
    bm = bmesh.new()

    # High-density icosphere base
    ret = bmesh.ops.create_icosphere(bm, subdivisions=3, radius=radius)
    verts = ret["verts"]

    # Natural anisotropic proportions
    if style == "slab":
        bmesh.ops.scale(bm, verts=verts, vec=(1.2, 0.9, 0.65))
        cuts, noise_scale = 5, 0.35
    elif style == "shelf":
        bmesh.ops.scale(bm, verts=verts, vec=(1.35, 1.1, 0.45))
        cuts, noise_scale = 4, 0.30
    else:  # weathered rounded boulder
        bmesh.ops.scale(bm, verts=verts, vec=(1.05, 0.95, 0.85))
        cuts, noise_scale = 4, 0.45

    # Multi-octave 3D organic displacement
    for v in bm.verts:
        p = v.co
        n = organic_noise_3d(p.x, p.y, p.z, seed=seed)
        v.co += v.co.normalized() * (n * noise_scale * radius)

    # Apply gentle natural fracture planes
    fracture_mesh_z(bm, cuts=cuts, radius=radius, rng=rng, bias_horizontal=0.2)

    # Rest firmly on ground at Z=0
    min_z = min(v.co.z for v in bm.verts)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, -min_z))

    col = (rng.uniform(0.38, 0.46), rng.uniform(0.37, 0.44), rng.uniform(0.35, 0.42))
    return finalize_mesh(bm, name, color=col, metallic=0.05, roughness=0.92, smooth=True, auto_smooth_angle=42)


def build_organic_rock_spire(name, seed=0):
    """Builds a tall organic rock monolith with natural horizontal strata."""
    rng = random.Random(seed)
    bm = bmesh.new()

    height = rng.uniform(3.5, 5.5)
    radius_base = rng.uniform(0.8, 1.3)

    # Multi-tier lofted pillar
    n_tiers = 6
    prev_verts = None
    all_faces = []
    for t in range(n_tiers + 1):
        z = (float(t) / n_tiers) * height
        prog = float(t) / n_tiers
        r = radius_base * (1.0 - prog * 0.55 + 0.15 * math.sin(prog * math.pi * 3.0))
        tier_verts = []
        segments = 10
        for i in range(segments):
            theta = (2.0 * math.pi * i) / segments
            cx = math.cos(theta) * r
            cy = math.sin(theta) * r
            # Organic displacement
            disp = organic_noise_3d(cx, cy, z, seed=seed) * 0.3
            tier_verts.append(bm.verts.new((cx * (1.0 + disp), cy * (1.0 + disp), z)))
        
        if prev_verts is not None:
            for i in range(segments):
                i_next = (i + 1) % segments
                all_faces.append(bm.faces.new([prev_verts[i], prev_verts[i_next], tier_verts[i_next], tier_verts[i]]))
        prev_verts = tier_verts

    # Top cap
    bm.faces.new(prev_verts)

    # Apply fracture chisel cuts
    fracture_mesh_z(bm, cuts=6, radius=radius_base * 1.5, rng=rng, bias_horizontal=0.1)

    min_z = min(v.co.z for v in bm.verts)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, -min_z))

    col = (0.42, 0.40, 0.37)
    return finalize_mesh(bm, name, color=col, metallic=0.06, roughness=0.90, smooth=True, auto_smooth_angle=38)


def build_organic_pebble_cluster(name, seed=0):
    """Builds an organic cluster of 8-14 rounded weathered river/talus pebbles."""
    rng = random.Random(seed)
    bm = bmesh.new()

    n_pebbles = rng.randint(8, 14)
    for i in range(n_pebbles):
        p_ang = rng.uniform(0, 2.0 * math.pi)
        p_dist = rng.uniform(0.1, 0.95)
        p_rad = rng.uniform(0.08, 0.24)
        px = math.cos(p_ang) * p_dist
        py = math.sin(p_ang) * p_dist

        ret = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=p_rad)
        p_verts = ret["verts"]
        # Organic scale & noise
        bmesh.ops.scale(bm, verts=p_verts, vec=(rng.uniform(0.8, 1.3), rng.uniform(0.8, 1.3), rng.uniform(0.5, 0.8)))
        for v in p_verts:
            n = organic_noise_3d(v.co.x, v.co.y, v.co.z, seed=seed + i * 5)
            v.co += v.co.normalized() * (n * 0.15 * p_rad)
            v.co += Vector((px, py, p_rad * 0.4))

    min_z = min(v.co.z for v in bm.verts)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, -min_z))

    col = (0.42, 0.40, 0.38)
    return finalize_mesh(bm, name, color=col, metallic=0.05, roughness=0.95, smooth=True, auto_smooth_angle=45)


def build_organic_cliff_face(name, seed=0, width=8.0, height=5.5, depth=2.8):
    """Builds a sheer rock cliff facade with realistic horizontal sedimentary strata."""
    rng = random.Random(seed)
    bm = bmesh.new()

    # Subdivided grid front face with horizontal bedding strata
    nx, nz = 12, 8
    grid_verts = []
    for iz in range(nz + 1):
        z = (float(iz) / nz) * height
        # Strata overhang rhythm
        strata_bulge = 0.4 * math.sin((z / height) * math.pi * 4.0)
        row = []
        for ix in range(nx + 1):
            x = (float(ix) / nx - 0.5) * width
            # Front face depth with multi-octave relief
            disp = organic_noise_3d(x, 0, z, seed=seed) * 0.6
            y = depth * 0.5 + strata_bulge + disp
            v = bm.verts.new((x, y, z))
            row.append(v)
        grid_verts.append(row)

    bm.verts.ensure_lookup_table()
    # Front quad faces
    for iz in range(nz):
        for ix in range(nx):
            v0 = grid_verts[iz][ix]
            v1 = grid_verts[iz][ix + 1]
            v2 = grid_verts[iz + 1][ix + 1]
            v3 = grid_verts[iz + 1][ix]
            bm.faces.new([v0, v1, v2, v3])

    # Rear flat backing vertices
    back_v0 = bm.verts.new((-width * 0.5, -depth * 0.5, 0))
    back_v1 = bm.verts.new((width * 0.5, -depth * 0.5, 0))
    back_v2 = bm.verts.new((width * 0.5, -depth * 0.5, height))
    back_v3 = bm.verts.new((-width * 0.5, -depth * 0.5, height))
    bm.faces.new([back_v0, back_v3, back_v2, back_v1])

    # Connect top, bottom, and side perimeter faces
    for ix in range(nx):
        bm.faces.new([grid_verts[0][ix + 1], grid_verts[0][ix], back_v0, back_v1])
        bm.faces.new([grid_verts[nz][ix], grid_verts[nz][ix + 1], back_v2, back_v3])

    # Fracture chisel cuts for sharp joint edges
    fracture_mesh_z(bm, cuts=6, radius=max(width, height) * 0.6, rng=rng, bias_horizontal=0.25)

    min_z = min(v.co.z for v in bm.verts)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, -min_z))

    col = (0.38, 0.36, 0.34)
    return finalize_mesh(bm, name, color=col, metallic=0.06, roughness=0.92, smooth=True, auto_smooth_angle=36)


def build_organic_cliff_corner(name, seed=0, size=6.0, height=5.0):
    """Builds a 90-degree salient cliff promontory rock bastion."""
    rng = random.Random(seed)
    bm = bmesh.new()

    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, verts=bm.verts, vec=(size, size, height))
    # Deform with organic 3D noise
    for v in bm.verts:
        n = organic_noise_3d(v.co.x, v.co.y, v.co.z, seed=seed)
        v.co += v.co.normalized() * (n * 0.45)

    fracture_mesh_z(bm, cuts=10, radius=size * 0.7, rng=rng, bias_horizontal=0.2)

    min_z = min(v.co.z for v in bm.verts)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, -min_z))

    col = (0.39, 0.37, 0.35)
    return finalize_mesh(bm, name, color=col, metallic=0.06, roughness=0.92, smooth=True, auto_smooth_angle=36)


def build_organic_cliff_strata(name, seed=0, length=10.0, height=1.4, depth=2.0):
    """Builds a low horizontal rock strata rib to dress hillsides and slopes."""
    rng = random.Random(seed)
    bm = bmesh.new()

    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, verts=bm.verts, vec=(length, depth, height))
    for v in bm.verts:
        n = organic_noise_3d(v.co.x, v.co.y, v.co.z, seed=seed)
        v.co.z += n * 0.25
        v.co.y += n * 0.35

    fracture_mesh_z(bm, cuts=6, radius=length * 0.5, rng=rng, bias_horizontal=0.4)

    min_z = min(v.co.z for v in bm.verts)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, -min_z))

    col = (0.40, 0.38, 0.36)
    return finalize_mesh(bm, name, color=col, metallic=0.05, roughness=0.94, smooth=True, auto_smooth_angle=38)


# ---------------------------------------------------------------------------
# 3. Grass Tufts, Shrubs & Reeds (Z-Up Orientation)
# ---------------------------------------------------------------------------

def build_organic_grass_tuft(name, seed=0, style="prairie"):
    """Builds curved multi-blade grass tufts in Blender Z-up space."""
    rng = random.Random(seed)
    bm = bmesh.new()

    count = 14 if style == "dense" else 10 if style == "fescue" else 12
    base_height = rng.uniform(0.55, 0.90) if style != "tall" else rng.uniform(0.95, 1.35)
    base_width = rng.uniform(0.045, 0.075)

    for i in range(count):
        angle = (2.0 * math.pi * i) / float(count) + rng.uniform(-0.25, 0.25)
        lean_dir = angle + rng.uniform(-0.2, 0.2)
        lean_mag = rng.uniform(0.25, 0.65)
        h = base_height * rng.uniform(0.75, 1.15)
        w = base_width * rng.uniform(0.8, 1.2)
        segments = 4

        spine = []
        r_off = rng.uniform(0.02, 0.08)
        start_x = math.cos(angle) * r_off
        start_y = math.sin(angle) * r_off

        for s in range(segments + 1):
            t = float(s) / segments
            arch = (t * t) * lean_mag * h
            pz = t * h * (1.0 - t * 0.15)
            px = start_x + math.cos(lean_dir) * arch
            py = start_y + math.sin(lean_dir) * arch
            spine.append(Vector((px, py, pz)))

        blade_verts = []
        perp_x = -math.sin(angle)
        perp_y = math.cos(angle)

        for s in range(segments + 1):
            t = float(s) / segments
            cur_w = w * (1.0 - t * 0.9)
            center = spine[s]
            v_l = bm.verts.new(center + Vector((perp_x * cur_w * 0.5, perp_y * cur_w * 0.5, 0.0)))
            v_r = bm.verts.new(center - Vector((perp_x * cur_w * 0.5, perp_y * cur_w * 0.5, 0.0)))
            blade_verts.append((v_l, v_r))

        bm.verts.ensure_lookup_table()
        for s in range(segments):
            v0_l, v0_r = blade_verts[s]
            v1_l, v1_r = blade_verts[s + 1]
            try:
                bm.faces.new([v0_l, v1_l, v1_r, v0_r])
            except ValueError:
                pass

    col = (0.22, 0.38, 0.15)
    return finalize_mesh(bm, name, color=col, metallic=0.0, roughness=0.9, smooth=True)


def build_organic_shrub(name, seed=0, style="dense"):
    """Builds an organic shrub with branching woody stems and foliage puffs in Z-up space."""
    rng = random.Random(seed)
    bm = bmesh.new()

    shrub_h = rng.uniform(0.7, 1.15)
    n_stems = rng.randint(3, 5)
    canopy_centers = []

    for i in range(n_stems):
        angle = (2.0 * math.pi * i) / float(n_stems) + rng.uniform(-0.3, 0.3)
        spread = rng.uniform(0.3, 0.6) * shrub_h
        branch_h = rng.uniform(0.45, 0.75) * shrub_h
        top_pos = (math.cos(angle) * spread, math.sin(angle) * spread, branch_h)
        canopy_centers.append(top_pos)
        faces = add_cylinder_z(bm, (top_pos[0] * 0.5, top_pos[1] * 0.5, top_pos[2] * 0.5),
                               radius_bottom=0.045, height=branch_h, segments=5, radius_top=0.025)
        for f in faces:
            f.material_index = 0

    canopy_centers.append((0.0, 0.0, shrub_h * 0.8))
    for center in canopy_centers:
        r = rng.uniform(0.28, 0.48)
        ret = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=r)
        for v in ret["verts"]:
            disp = organic_noise_3d(v.co.x, v.co.y, v.co.z, seed=seed)
            v.co += v.co.normalized() * (disp * 0.18)
            v.co.z *= 0.8
            v.co += Vector((center[0], center[1], center[2]))
        for f in {f for v in ret["verts"] for f in v.link_faces}:
            f.material_index = 1

    stem_col = (0.28, 0.20, 0.14)
    leaf_col = (0.18, 0.34, 0.14)
    return finalize_mesh_dual(bm, name, mat0_color=stem_col, mat1_color=leaf_col, smooth=True)


def build_organic_reeds(name, seed=0):
    """Builds wetland cattails & marsh reeds in Z-up space."""
    rng = random.Random(seed)
    bm = bmesh.new()

    n_reeds = rng.randint(8, 12)
    for i in range(n_reeds):
        angle = rng.uniform(0, 2.0 * math.pi)
        r = rng.uniform(0.05, 0.45)
        pos = (math.cos(angle) * r, math.sin(angle) * r, 0.0)
        h = rng.uniform(1.3, 2.1)

        stalk = add_cylinder_z(bm, (pos[0], pos[1], h * 0.5), radius_bottom=0.018, height=h, segments=5)
        for f in stalk:
            f.material_index = 0

        if i % 3 == 0:
            head_h = rng.uniform(0.22, 0.35)
            head_z = h * rng.uniform(0.72, 0.86)
            head = add_cylinder_z(bm, (pos[0], pos[1], head_z), radius_bottom=0.038, height=head_h, segments=6)
            for f in head:
                f.material_index = 1

    return finalize_mesh_dual(bm, name, mat0_color=(0.24, 0.38, 0.16), mat1_color=(0.28, 0.16, 0.10), smooth=True)


def build_organic_wildflower(name, seed=0, flower_color=(0.92, 0.78, 0.15)):
    """Builds a flowering meadow grass tuft with blossom heads in Z-up space."""
    rng = random.Random(seed)
    bm = bmesh.new()

    # Base foliage
    for i in range(8):
        angle = (2.0 * math.pi * i) / 8.0 + rng.uniform(-0.2, 0.2)
        h = rng.uniform(0.35, 0.65)
        faces = add_cylinder_z(bm, (math.cos(angle) * 0.08, math.sin(angle) * 0.08, h * 0.5),
                               radius_bottom=0.02, height=h, segments=4, radius_top=0.002)
        for f in faces:
            f.material_index = 0

    # Flower stems + blossom heads
    n_flowers = rng.randint(4, 7)
    for i in range(n_flowers):
        angle = (2.0 * math.pi * i) / float(n_flowers) + rng.uniform(-0.3, 0.3)
        r = rng.uniform(0.08, 0.25)
        fh = rng.uniform(0.5, 0.8)
        fpos = (math.cos(angle) * r, math.sin(angle) * r, fh)
        s_faces = add_cylinder_z(bm, (fpos[0], fpos[1], fh * 0.5), radius_bottom=0.01, height=fh, segments=4)
        for f in s_faces:
            f.material_index = 0
        b_faces = add_cylinder_z(bm, fpos, radius_bottom=0.065, height=0.025, segments=6)
        for f in b_faces:
            f.material_index = 1

    return finalize_mesh_dual(bm, name, mat0_color=(0.22, 0.38, 0.16), mat1_color=flower_color, smooth=True)


# ---------------------------------------------------------------------------
# Main Generation Runner
# ---------------------------------------------------------------------------

def generate_all_terrain_props():
    os.makedirs(TERRAIN_DIR, exist_ok=True)
    print("==========================================================")
    print("Generating Authentic Organic Terrain Assets -> %s" % TERRAIN_DIR)
    print("==========================================================")

    # 1. Grass Tufts (6 varieties)
    grass_styles = ["prairie", "dense", "fescue", "windswept", "tussock", "tall"]
    for i, style in enumerate(grass_styles):
        clear_scene()
        fn = "grass_tuft_%d.glb" % i
        obj = build_organic_grass_tuft("grass_tuft_%d" % i, seed=100 + i, style=style)
        export_glb(obj, os.path.join(TERRAIN_DIR, fn))

    # 2. Shrubs (4 varieties)
    shrub_styles = ["dense", "spreading", "round", "dry"]
    for i, style in enumerate(shrub_styles):
        clear_scene()
        fn = "shrub_%d.glb" % i
        obj = build_organic_shrub("shrub_%d" % i, seed=200 + i, style=style)
        export_glb(obj, os.path.join(TERRAIN_DIR, fn))

    # 3. Wetland Reeds (3 varieties)
    for i in range(3):
        clear_scene()
        fn = "reeds_%d.glb" % i
        obj = build_organic_reeds("reeds_%d" % i, seed=300 + i)
        export_glb(obj, os.path.join(TERRAIN_DIR, fn))

    # 4. Wildflower Tufts (3 varieties)
    flower_colors = [(0.92, 0.78, 0.15), (0.28, 0.45, 0.92), (0.92, 0.24, 0.18)]
    for i, col in enumerate(flower_colors):
        clear_scene()
        fn = "wildflower_tuft_%d.glb" % i
        obj = build_organic_wildflower("wildflower_tuft_%d" % i, seed=400 + i, flower_color=col)
        export_glb(obj, os.path.join(TERRAIN_DIR, fn))

    # 5. Ambient Trees (20 high-fidelity models)
    for i in range(20):
        clear_scene()
        fn = "ambient_tree_%d.glb" % i
        obj = build_organic_tree("ambient_tree_%d" % i, seed=600 + i)
        export_glb(obj, os.path.join(TERRAIN_DIR, fn))

    # 6. Organic Boulders (6 varieties: Weathered, Slab, Shelf)
    boulder_styles = ["weathered", "weathered", "slab", "slab", "shelf", "shelf"]
    for i, style in enumerate(boulder_styles):
        clear_scene()
        fn = "boulder_%d.glb" % i
        obj = build_organic_boulder("boulder_%d" % i, radius=1.0 + 0.35 * (i % 3), seed=700 + i, style=style)
        export_glb(obj, os.path.join(TERRAIN_DIR, fn))

    # 7. Rock Spires (4 varieties)
    for i in range(4):
        clear_scene()
        fn = "rock_spire_%d.glb" % i
        obj = build_organic_rock_spire("rock_spire_%d" % i, seed=800 + i)
        export_glb(obj, os.path.join(TERRAIN_DIR, fn))

    # 8. Scree & Pebble Clusters (4 varieties)
    for i in range(4):
        clear_scene()
        fn = "pebble_cluster_%d.glb" % i
        obj = build_organic_pebble_cluster("pebble_cluster_%d" % i, seed=900 + i)
        export_glb(obj, os.path.join(TERRAIN_DIR, fn))

    # 9. Cliff Facades & Escarpments (4 faces, 3 corners, 3 strata ribs)
    for i in range(4):
        clear_scene()
        fn = "cliff_face_%d.glb" % i
        obj = build_organic_cliff_face("cliff_face_%d" % i, seed=1000 + i, width=7.0 + i * 1.5, height=4.8 + i * 0.8)
        export_glb(obj, os.path.join(TERRAIN_DIR, fn))

    for i in range(3):
        clear_scene()
        fn = "cliff_corner_%d.glb" % i
        obj = build_organic_cliff_corner("cliff_corner_%d" % i, seed=1100 + i, size=5.5 + i * 1.0, height=5.0)
        export_glb(obj, os.path.join(TERRAIN_DIR, fn))

    for i in range(3):
        clear_scene()
        fn = "cliff_strata_%d.glb" % i
        obj = build_organic_cliff_strata("cliff_strata_%d" % i, seed=1200 + i, length=8.0 + i * 2.0)
        export_glb(obj, os.path.join(TERRAIN_DIR, fn))

    print("==========================================================")
    print("All Organic Terrain Assets Successfully Generated!")
    print("==========================================================")


if __name__ == "__main__":
    generate_all_terrain_props()
