"""
Kitbash Command - Utility Module Mesh Builder (Rework Pass)
Run headlessly with UPBGE:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python tools\\blender\\build_utility_modules.py

Produces refined multi-part GLBs for three support modules:
  - Sensor Suite (Radar Mast):   sensor_suite_mount / sensor_suite_mast / sensor_suite_dish
  - Resource Harvester:          resource_harvester_mount / resource_harvester_arm / resource_harvester_drill
  - Repair Array:                repair_array_mount / repair_array_arm / repair_array_welder
  - Drone Carrier (unchanged):   drone_carrier_mount / drone_carrier_housing / drone_carrier_drone

COORDINATE CONVENTION  (same as build_meshes.py):
  Blender is authored Z-up. The glTF exporter's Y-up conversion maps:
    Godot_X = Blender_X,  Godot_Y = Blender_Z,  Godot_Z = Blender_Y
  GV(x, y, z) -> raw Blender (x, z, y)   [point positions]
  GS(sx, sy, sz) -> raw Blender (sx, sz, sy) [sizes/scales]
  So all authoring code is written in Godot X/Y/Z semantics.

ANIMATION CONTRACTS (must NOT be broken - game code depends on these):
  sensor_suite_dish.glb  - origin at Godot (0,0,0), dish faces +Z (Blender +Y).
                           auto_weapon.gd gets node "sensor_suite_dish" and calls rotate_y each frame.
  resource_harvester_drill.glb - origin at tip pivot. visual_builder places it at the boom end.
  repair_array_arm / repair_array_welder - visual_builder positions & rotates each radially at runtime.

ART RULES (VISUAL_ART_DIRECTION.md):
  - No crew-served fittings: no grips, triggers, handwheels, eyepieces, seats.
  - Optics: boxed camera housings with a lens disc on the outside face, or LIDAR drums.
  - Remote hardware vocabulary: servo cans, cable glands, solenoid conduits, heat fins.
  - Mount origins sit at deck level (Godot Y=0, raw Blender Z=0).
  - Bevels keyed to part size - use smaller bevels on instanced/repeated geometry.
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


# ---------------------------------------------------------------------------
# Coordinate helpers (Godot-space -> raw Blender-space)
# ---------------------------------------------------------------------------

def GV(x, y, z):
    """Godot (x, y_up, z_depth) -> raw Blender (x, z, y)."""
    return (x, z, y)


def GS(sx, sy, sz):
    """Godot (width, height, depth) -> raw Blender scale (width, depth, height)."""
    return (sx, sz, sy)


# ---------------------------------------------------------------------------
# Scene helpers
# ---------------------------------------------------------------------------

def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        if block.users == 0:
            bpy.data.meshes.remove(block)
    for block in list(bpy.data.materials):
        if block.users == 0:
            bpy.data.materials.remove(block)


# ---------------------------------------------------------------------------
# Primitive builders  (all take raw Blender coordinates for pos/size)
# ---------------------------------------------------------------------------

def _cone(bm, pos, r1, r2, depth, segments, rot=None):
    res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                                radius1=r1, radius2=r2, depth=depth)
    loc = mathutils.Vector(pos)
    for v in res['verts']:
        v.co = (rot @ v.co if rot else v.co) + loc


def add_cyl_z(bm, pos, radius, height, segments=16):
    """Vertical cylinder (Blender Z / Godot Y up)."""
    _cone(bm, pos, radius, radius, height, segments)


def add_cone_z(bm, pos, r_bot, r_top, height, segments=16):
    """Frustum/cone along Blender Z."""
    _cone(bm, pos, r_top, r_bot, height, segments)


def add_cyl_y(bm, pos, radius, height, segments=16):
    """Horizontal cylinder along Blender Y (Godot -Z / forward)."""
    rot = mathutils.Matrix.Rotation(math.radians(90), 4, 'X')
    _cone(bm, pos, radius, radius, height, segments, rot)


def add_cyl_x(bm, pos, radius, height, segments=16):
    """Horizontal cylinder along Blender X."""
    rot = mathutils.Matrix.Rotation(math.radians(90), 4, 'Y')
    _cone(bm, pos, radius, radius, height, segments, rot)


def add_box(bm, pos, size, bevel=0.0, bevel_segments=2, rot_z=0.0):
    """Box centred at pos with given size. rot_z rotates around Blender Z."""
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


def add_tube_between(bm, p0, p1, radius, segments=8):
    """Tube spanning two Blender-space points."""
    a = mathutils.Vector(p0)
    b = mathutils.Vector(p1)
    d = b - a
    length = d.length
    if length < 1e-5:
        return
    res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                                radius1=radius, radius2=radius, depth=length)
    rot = mathutils.Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    mid = (a + b) / 2.0
    for v in res['verts']:
        v.co = (rot @ v.co) + mid


def bolt_ring_z(bm, z, radius, count=8, bolt_r=0.007, bolt_h=0.012):
    """Ring of cylindrical bolt heads around a Z-axis circle."""
    for i in range(count):
        a = (i / count) * math.tau
        add_cyl_z(bm, (math.cos(a) * radius, math.sin(a) * radius, z), bolt_r, bolt_h, segments=6)


# ---------------------------------------------------------------------------
# Export helper
# ---------------------------------------------------------------------------

def export_bmesh(bm, object_name, filename,
                 color=(0.24, 0.26, 0.28), metallic=0.70, roughness=0.32):
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


# ---------------------------------------------------------------------------
# SENSOR SUITE (RADAR MAST)
# ---------------------------------------------------------------------------
# Three separate GLBs:
#   sensor_suite_mount.glb  — static deck pedestal, bolt ring, cable conduit trunks
#   sensor_suite_mast.glb   — lattice truss mast (static, Y-scaled by mast_height tweak)
#   sensor_suite_dish.glb   — rotating phased-array/parabolic head + yoke pivot
#                             Origin at (0,0,0) in its own space = the rotation axis
#                             auto_weapon.gd calls rotate_y() on the node named "sensor_suite_dish"

def build_sensor_suite_mount():
    """
    Octagonal deck pedestal with weld collar, cable conduit trunks and bolt ring.
    Sits flush at Godot Y=0 / Blender Z=0.  Top face is at Blender Z=0.12.
    """
    bm = bmesh.new()

    # Main octagonal base plate
    add_cyl_z(bm, (0, 0, 0.04), 0.26, 0.08, segments=8)
    # Bevelled top collar
    add_cone_z(bm, (0, 0, 0.10), 0.17, 0.13, 0.04, segments=16)
    # Mast socket tube sticking up
    add_cyl_z(bm, (0, 0, 0.13), 0.055, 0.06, segments=12)

    # Bolt ring around base
    bolt_ring_z(bm, 0.09, 0.20, count=8)

    # Four cable conduit trunks at 45-degree offsets
    for i in range(4):
        a = math.radians(45 + i * 90)
        cx = math.cos(a) * 0.19
        cy = math.sin(a) * 0.19
        add_box(bm, (cx, cy, 0.06), (0.03, 0.05, 0.07), bevel=0.004)

    # Servo drive housing on one side (art rule: remote operation hardware)
    add_box(bm, (0.0, -0.21, 0.07), (0.07, 0.06, 0.06), bevel=0.006)
    # Cable gland stub on servo housing
    add_cyl_y(bm, (0.0, -0.25, 0.07), 0.012, 0.03, segments=8)

    export_bmesh(bm, "sensor_suite_mount", "sensor_suite_mount.glb",
                 color=(0.18, 0.20, 0.24), metallic=0.72, roughness=0.38)


def build_sensor_suite_mast():
    """
    Lattice truss mast column.  Total height in Blender Z = 1.0 unit.
    visual_builder.gd scales this Vector3(1.0, mast_height, 1.0) so cross-truss
    ring heights are evenly distributed and stretch correctly.
    Origin at base (Blender Z=0), top at Blender Z=1.0.
    """
    bm = bmesh.new()

    mast_h = 1.0

    # Central spine column — slightly tapered (wider at base)
    add_cone_z(bm, (0, 0, mast_h * 0.5), 0.038, 0.028, mast_h, segments=12)

    # Four corner truss legs, angled inward as they rise (braced lattice look)
    for angle in (0, 90, 180, 270):
        rad = math.radians(angle + 22.5)
        base_r = 0.095
        top_r = 0.035
        bx0 = math.cos(rad) * base_r
        by0 = math.sin(rad) * base_r
        bx1 = math.cos(rad) * top_r
        by1 = math.sin(rad) * top_r
        add_tube_between(bm, (bx0, by0, 0.0), (bx1, by1, mast_h), radius=0.012, segments=8)

    # Diagonal cross-braces between legs (two X patterns at 1/3 and 2/3 height)
    for frac in (0.28, 0.62):
        zh = mast_h * frac
        for ia, ib in ((0, 2), (1, 3)):
            a0 = math.radians(ia * 90 + 22.5)
            a1 = math.radians(ib * 90 + 22.5)
            fr = 0.095 - (0.095 - 0.035) * frac   # interpolate radius at height
            p0 = (math.cos(a0) * fr, math.sin(a0) * fr, zh)
            p1 = (math.cos(a1) * fr, math.sin(a1) * fr, zh)
            add_tube_between(bm, p0, p1, radius=0.008, segments=6)

    # Three ring collars at 25%, 55%, 80% height
    for frac in (0.25, 0.55, 0.80):
        zh = mast_h * frac
        # Collar ring
        r_at = 0.095 - (0.095 - 0.035) * frac
        add_cyl_z(bm, (0, 0, zh), r_at + 0.015, 0.018, segments=12)

    # Equipment pod at 70% height: small junction box on one face
    pod_h = mast_h * 0.70
    r_pod = 0.095 - (0.095 - 0.035) * 0.70
    add_box(bm, (r_pod + 0.025, 0.0, pod_h), (0.04, 0.055, 0.04), bevel=0.005)
    # Tiny cable stub running to spine
    add_cyl_x(bm, (r_pod * 0.5, 0.0, pod_h), 0.008, r_pod * 0.8, segments=6)

    export_bmesh(bm, "sensor_suite_mast", "sensor_suite_mast.glb",
                 color=(0.22, 0.25, 0.28), metallic=0.68, roughness=0.40)


def build_sensor_suite_dish():
    """
    Rotating phased-array / parabolic dish head.
    Sits on a U-shaped elevation yoke so it can visually tilt.
    Origin at (0,0,0) = the mast-top rotation axis (Blender Z=0).
    auto_weapon.gd spins the MeshInstance3D named "sensor_suite_dish" around Y each frame.

    Geometry extends mostly in +Z (Blender) = Godot -Z (forward) so the dish face
    points 'outward' from the mast, and Y (Blender) / Godot_X is the horizontal pan axis.
    The dish bowl opening faces Blender +Y (Godot -Z / forward).
    """
    bm = bmesh.new()

    # --- Elevation yoke (U-frame that the dish rocks in) ---
    # Yoke base / rotation collar
    add_cyl_z(bm, (0, 0, 0.04), 0.065, 0.08, segments=14)
    # Left yoke arm
    add_box(bm, (-0.16, 0.0, 0.14), (0.025, 0.025, 0.16), bevel=0.005)
    # Right yoke arm
    add_box(bm, (0.16, 0.0, 0.14), (0.025, 0.025, 0.16), bevel=0.005)
    # Cross-piece joining tops of arms
    add_box(bm, (0.0, 0.0, 0.225), (0.345, 0.025, 0.025), bevel=0.004)
    # Pivot axle pins at each arm tip
    add_cyl_x(bm, (-0.16, 0.0, 0.225), 0.018, 0.04, segments=10)
    add_cyl_x(bm, (0.16, 0.0, 0.225), 0.018, 0.04, segments=10)

    # Servo drive on left arm (elevation actuator)
    add_box(bm, (-0.20, 0.0, 0.17), (0.045, 0.04, 0.052), bevel=0.005)
    add_cyl_y(bm, (-0.20, -0.04, 0.17), 0.010, 0.03, segments=6)   # cable gland

    # --- Dish back-plate / spine ---
    # Back centre rib
    add_box(bm, (0.0, -0.075, 0.225), (0.025, 0.10, 0.20), bevel=0.005)
    # Feed arm tube from centre
    add_cyl_y(bm, (0.0, 0.04, 0.225), 0.012, 0.22, segments=8)

    # --- Phased-array panel (rectangular grid face) ---
    # Main panel body
    add_box(bm, (0.0, 0.0, 0.225), (0.42, 0.015, 0.32), bevel=0.008)
    # Panel frame lip
    add_box(bm, (0.0, -0.016, 0.225), (0.45, 0.012, 0.35), bevel=0.006)
    # Radiating element rows (5×3 grid of small rectangular emitters)
    for col in range(5):
        for row in range(3):
            ex = (col - 2) * 0.074
            ez = (row - 1) * 0.088 + 0.225
            add_box(bm, (ex, 0.012, ez), (0.052, 0.012, 0.064), bevel=0.003)

    # --- Feed horn assembly at front centre ---
    # Main horn cylinder
    add_cyl_y(bm, (0.0, 0.115, 0.225), 0.026, 0.08, segments=14)
    # Horn cap / lens disc (represents the active receive element)
    add_cyl_y(bm, (0.0, 0.165, 0.225), 0.032, 0.012, segments=14)
    # Secondary LIDAR drum beside horn (art rule: camera/sensor, not eyepiece)
    add_cyl_z(bm, (0.07, 0.10, 0.235), 0.022, 0.042, segments=14)
    add_cyl_z(bm, (0.07, 0.10, 0.258), 0.024, 0.008, segments=14)  # lens cap ring

    export_bmesh(bm, "sensor_suite_dish", "sensor_suite_dish.glb",
                 color=(0.82, 0.85, 0.88), metallic=0.55, roughness=0.28)


# ---------------------------------------------------------------------------
# RESOURCE HARVESTER
# ---------------------------------------------------------------------------
# Three separate GLBs:
#   resource_harvester_mount.glb — heavy rotary turntable + upright pivot frame
#   resource_harvester_arm.glb   — articulated boom arm with hydraulic cylinder detail
#   resource_harvester_drill.glb — rotary auger/drill head (animated spin by visual_builder)
#
# visual_builder.gd assembles them:
#   mount at (0,0,0), arm at (0,0,0) scaled by ext_size on Z,
#   drill at (0, 0, -0.28*ext_size)

def build_resource_harvester_mount():
    """
    Heavy-duty turntable mount with upright bearing posts and hydraulic manifold.
    All geometry in raw Blender coords (no GV needed since this file's helpers are raw).
    """
    bm = bmesh.new()

    # Base turntable disc — thick, industrial
    add_cyl_z(bm, (0, 0, 0.05), 0.32, 0.10, segments=24)
    # Outer race ring
    add_cyl_z(bm, (0, 0, 0.11), 0.35, 0.018, segments=24)
    bolt_ring_z(bm, 0.115, 0.30, count=12, bolt_r=0.009, bolt_h=0.015)

    # Central slew bearing column
    add_cyl_z(bm, (0, 0, 0.12), 0.09, 0.06, segments=16)

    # Two upright bearing posts (left/right of arm)
    for sx in (-0.14, 0.14):
        add_box(bm, (sx, 0.0, 0.22), (0.055, 0.065, 0.24), bevel=0.008)
        # Pivot pin
        add_cyl_x(bm, (sx, 0.0, 0.345), 0.022, 0.075, segments=10)

    # Cross-beam connecting posts
    add_box(bm, (0.0, 0.0, 0.345), (0.30, 0.055, 0.04), bevel=0.006)

    # Hydraulic manifold block (art rule: servo/hydraulic hardware, not hand cranks)
    add_box(bm, (0.0, -0.18, 0.15), (0.08, 0.07, 0.08), bevel=0.008)
    # Hydraulic line ports (two small cylinder stubs)
    for px in (-0.025, 0.025):
        add_cyl_z(bm, (px, -0.22, 0.15), 0.010, 0.04, segments=8)

    # Two cable conduit runs from base to bearing posts
    for sx in (-0.14, 0.14):
        add_tube_between(bm, (sx * 0.6, -0.12, 0.10), (sx, -0.08, 0.30), radius=0.010, segments=6)

    export_bmesh(bm, "resource_harvester_mount", "resource_harvester_mount.glb",
                 color=(0.20, 0.22, 0.20), metallic=0.65, roughness=0.45)


def build_resource_harvester_arm():
    """
    Articulated extractor boom arm.
    Origin at the pivot pin (Blender Z=0.345 in mount space becomes the joint).
    The arm extends in Blender +Y (Godot -Z) direction.
    visual_builder scales Z (Godot Z / Blender Y) by ext_size tweak.
    """
    bm = bmesh.new()

    # Main structural box boom
    add_box(bm, (0, 0.28, 0.0), (0.10, 0.52, 0.08), bevel=0.010)
    # Underside flange stiffeners
    add_box(bm, (-0.03, 0.28, -0.052), (0.012, 0.48, 0.012), bevel=0.003)
    add_box(bm, (0.03, 0.28, -0.052), (0.012, 0.48, 0.012), bevel=0.003)

    # Elbow joint (mid-arm knuckle)
    add_cyl_x(bm, (0, 0.52, 0.0), 0.045, 0.12, segments=14)

    # Lower forearm box section
    add_box(bm, (0, 0.72, -0.015), (0.085, 0.36, 0.065), bevel=0.008)

    # Hydraulic cylinder (main lift ram)
    add_cyl_y(bm, (0, 0.18, 0.06), 0.022, 0.28, segments=12)   # outer cylinder
    add_cyl_y(bm, (0, 0.42, 0.06), 0.016, 0.20, segments=10)   # piston rod
    # Ram mount clevis at each end
    add_box(bm, (0, 0.06, 0.06), (0.04, 0.03, 0.035), bevel=0.004)
    add_box(bm, (0, 0.62, 0.06), (0.04, 0.03, 0.035), bevel=0.004)

    # Wrist joint at forearm tip
    add_cyl_x(bm, (0, 0.90, -0.015), 0.038, 0.11, segments=12)
    # Wrist servo actuator housing (art rule: remote operation)
    add_box(bm, (0.08, 0.90, -0.015), (0.04, 0.055, 0.04), bevel=0.005)

    # Cable runs along the boom top chord
    add_tube_between(bm, (0.0, 0.0, 0.045), (0.0, 0.88, 0.045), radius=0.008, segments=6)
    # Cable clamp clips every ~0.15 units
    for t in (0.15, 0.30, 0.45, 0.60, 0.75):
        add_box(bm, (0.0, t, 0.058), (0.024, 0.018, 0.012), bevel=0.002, bevel_segments=1)

    export_bmesh(bm, "resource_harvester_arm", "resource_harvester_arm.glb",
                 color=(0.72, 0.48, 0.12), metallic=0.60, roughness=0.42)


def build_resource_harvester_drill():
    """
    Rotary auger / drill head.
    Origin at the spin axis centre, top face at Blender Z=0 (attaches to arm wrist).
    Drill body extends in Blender -Z (downward / Godot -Y), which is the boring direction.
    auto_weapon.gd / battle code expected to spin this part.
    Auger flights are baked in as static twisted fins for a readable 'drill' silhouette.
    """
    bm = bmesh.new()

    # Drive hub / gearbox at top (connects to wrist)
    add_cyl_z(bm, (0, 0, -0.04), 0.078, 0.08, segments=16)
    # Gearbox housing detail
    add_box(bm, (0.06, 0.0, -0.05), (0.04, 0.06, 0.06), bevel=0.005)
    # Bolt ring on gearbox flange
    bolt_ring_z(bm, -0.005, 0.068, count=8, bolt_r=0.007, bolt_h=0.010)

    # Main drill shank — tapers from hub to tip
    add_cone_z(bm, (0, 0, -0.19), 0.048, 0.035, 0.22, segments=16)

    # Pilot point (carbide tip)
    add_cone_z(bm, (0, 0, -0.325), 0.020, 0.004, 0.045, segments=10)

    # Three carbide cutter blades (auger flights) at 120-degree spacing
    # These are elongated angled boxes — twisted appearance comes from progressive Z position
    for i in range(3):
        angle = math.radians(i * 120)
        # Each flight sweeps from near hub to near tip across ~0.22 units of Z
        for seg in range(5):
            frac = seg / 4.0
            t_angle = angle + frac * math.radians(120)  # one full twist over the flight
            r = 0.042 - frac * 0.012      # taper in radius
            bz = -0.08 - frac * 0.19
            fx = math.cos(t_angle) * (r + 0.052)
            fy = math.sin(t_angle) * (r + 0.052)
            # Blade segment box — angled by rotation
            add_box(bm, (fx, fy, bz),
                    (0.045, 0.010, 0.038),
                    bevel=0.003, bevel_segments=1,
                    rot_z=t_angle + math.pi * 0.5)

    export_bmesh(bm, "resource_harvester_drill", "resource_harvester_drill.glb",
                 color=(0.30, 0.32, 0.35), metallic=0.78, roughness=0.30)


# ---------------------------------------------------------------------------
# REPAIR ARRAY
# ---------------------------------------------------------------------------
# Three separate GLBs:
#   repair_array_mount.glb   — octagonal pedestal with central energy coupling
#   repair_array_arm.glb     — telescoping shoulder post + elbow arm segment
#   repair_array_welder.glb  — torch nozzle + camera head + arc electrode tip
#
# visual_builder.gd spawns welder_count (1-4) arms in a radial ring at r=0.12,
# each arm.rotation.y = -angle, and welder placed at the same radial offset.

def build_repair_array_mount():
    """
    Octagonal deck pedestal with central energy coupling dome and power conduit trunks.
    """
    bm = bmesh.new()

    # Main octagonal base plate
    add_cyl_z(bm, (0, 0, 0.04), 0.28, 0.08, segments=8)
    # Top octagonal step
    add_cyl_z(bm, (0, 0, 0.10), 0.20, 0.04, segments=8)
    # Central energy coupling dome
    add_cone_z(bm, (0, 0, 0.14), 0.12, 0.08, 0.06, segments=16)
    add_cyl_z(bm, (0, 0, 0.17), 0.055, 0.03, segments=14)

    # Bolt ring on base
    bolt_ring_z(bm, 0.085, 0.22, count=8, bolt_r=0.008, bolt_h=0.014)

    # Four power conduit trunks at cardinal points
    for i in range(4):
        a = math.radians(i * 90)
        cx = math.cos(a) * 0.20
        cy = math.sin(a) * 0.20
        # Conduit block
        add_box(bm, (cx, cy, 0.07), (0.04, 0.05, 0.08), bevel=0.005)
        # Round conduit stub leading outward
        add_tube_between(bm, (cx, cy, 0.07),
                         (math.cos(a) * 0.27, math.sin(a) * 0.27, 0.07),
                         radius=0.012, segments=6)

    # Holographic emitter ring (small cylinders evenly spaced on outer step)
    for i in range(8):
        a = math.radians(i * 45 + 22.5)
        add_cyl_z(bm, (math.cos(a) * 0.17, math.sin(a) * 0.17, 0.125), 0.012, 0.018, segments=8)

    export_bmesh(bm, "repair_array_mount", "repair_array_mount.glb",
                 color=(0.18, 0.20, 0.26), metallic=0.72, roughness=0.36)


def build_repair_array_arm():
    """
    Telescoping shoulder post with articulated elbow and forearm.
    Origin at base (Blender Z=0) — the arm foot sits on the mount.
    The arm extends upward and outward, with the welder tip at the top.
    visual_builder.gd positions this at (ax, 0, az) and rotates by -angle.
    """
    bm = bmesh.new()

    # Shoulder post (vertical column rising from mount surface)
    add_cone_z(bm, (0, 0, 0.12), 0.030, 0.022, 0.24, segments=12)

    # Shoulder joint knuckle at top of post
    add_cyl_y(bm, (0, 0, 0.245), 0.030, 0.06, segments=12)
    # Servo actuator for shoulder joint
    add_box(bm, (0.04, 0, 0.245), (0.038, 0.038, 0.045), bevel=0.005)

    # Upper arm box section (from shoulder joint extending forward/outward)
    add_box(bm, (0, 0.14, 0.245), (0.040, 0.28, 0.038), bevel=0.007)
    # Upper arm stiffener rib on top
    add_box(bm, (0, 0.14, 0.268), (0.014, 0.27, 0.010), bevel=0.002, bevel_segments=1)

    # Elbow joint at forearm
    add_cyl_y(bm, (0, 0.28, 0.245), 0.025, 0.055, segments=12)

    # Forearm — shorter, angled slightly downward (arm reaches forward to target)
    add_box(bm, (0, 0.38, 0.228), (0.032, 0.18, 0.030), bevel=0.005)

    # Wrist joint at forearm tip
    add_cyl_y(bm, (0, 0.47, 0.228), 0.022, 0.048, segments=10)

    # Cable conduit running from shoulder to wrist (outer arc of arm)
    add_tube_between(bm, (0.024, 0.0, 0.245), (0.024, 0.46, 0.228), radius=0.007, segments=6)

    # Power pack / capacitor housing on upper arm
    add_box(bm, (0, 0.16, 0.270), (0.024, 0.075, 0.020), bevel=0.003, bevel_segments=1)

    export_bmesh(bm, "repair_array_arm", "repair_array_arm.glb",
                 color=(0.22, 0.25, 0.30), metallic=0.68, roughness=0.38)


def build_repair_array_welder():
    """
    Multi-sensor torch head: targeting camera, plasma nozzle, arc electrode.
    Origin corresponds to the wrist joint (Blender at Z=0.228 in arm space),
    but in this GLB the origin is at (0,0,0) and geometry hangs from there.
    visual_builder.gd places it at (ax, 0, az) with rotation.y = -angle,
    matching the arm's own position — so this should visually be the torch head
    sitting at the arm tip.

    Art rules:
      - Boxed camera housing with lens disc on outside face
      - No human grip or eyepiece
      - Plasma nozzle + electrode = the working end
    """
    bm = bmesh.new()

    # Tool head base block (attaches to wrist)
    add_box(bm, (0, 0, 0.0), (0.055, 0.055, 0.055), bevel=0.007)

    # Camera/targeting head on top (art: boxed EO sensor, lens on front face)
    add_box(bm, (0, 0.04, 0.028), (0.045, 0.042, 0.040), bevel=0.005)
    # Lens disc protruding from front face
    add_cyl_y(bm, (0, 0.068, 0.028), 0.014, 0.012, segments=14)
    # Sunshade above lens
    add_box(bm, (0, 0.058, 0.040), (0.050, 0.022, 0.008), bevel=0.002, bevel_segments=1)
    # LIDAR side puck
    add_cyl_z(bm, (0.030, 0.036, 0.038), 0.011, 0.018, segments=10)

    # Junction box / power coupler on rear
    add_box(bm, (0, -0.040, 0.0), (0.042, 0.038, 0.040), bevel=0.004)
    # Conduit stubs (two)
    add_cyl_y(bm, (0.010, -0.062, 0.010), 0.008, 0.02, segments=6)
    add_cyl_y(bm, (-0.010, -0.062, -0.005), 0.008, 0.02, segments=6)

    # Plasma nozzle / torch barrel (extends forward in Blender +Y)
    add_cone_z(bm, (0, 0.06, -0.025), 0.022, 0.015, 0.065, segments=14)  # nozzle taper
    add_cyl_z(bm, (0, 0.06, -0.065), 0.015, 0.030, segments=12)          # electrode barrel

    # Arc electrode tip — a pointed cone, the actual arc emitter
    add_cone_z(bm, (0, 0.06, -0.094), 0.012, 0.003, 0.022, segments=10)

    # Heat dissipation fins on nozzle sides (small flat fins)
    for i in range(3):
        fz = -0.025 - i * 0.015
        add_box(bm, (0.025, 0.06, fz), (0.020, 0.008, 0.010), bevel=0.002, bevel_segments=1)
        add_box(bm, (-0.025, 0.06, fz), (0.020, 0.008, 0.010), bevel=0.002, bevel_segments=1)

    export_bmesh(bm, "repair_array_welder", "repair_array_welder.glb",
                 color=(0.18, 0.20, 0.24), metallic=0.72, roughness=0.28)


# ---------------------------------------------------------------------------
# DRONE CARRIER  (geometry unchanged from original, just preserved here)
# ---------------------------------------------------------------------------

def build_drone_carrier_parts():
    clear_scene()
    bm1 = bmesh.new()
    add_box(bm1, (0, 0, 0.03), (0.50, 0.80, 0.06), bevel=0.015)
    add_box(bm1, (-0.12, 0.0, 0.07), (0.04, 0.76, 0.03), bevel=0.005)
    add_box(bm1, (0.12, 0.0, 0.07), (0.04, 0.76, 0.03), bevel=0.005)
    export_bmesh(bm1, "drone_carrier_mount", "drone_carrier_mount.glb",
                 color=(0.20, 0.22, 0.26))

    bm2 = bmesh.new()
    add_box(bm2, (0, 0.15, 0.16), (0.46, 0.44, 0.22), bevel=0.02)
    add_box(bm2, (0, -0.06, 0.16), (0.42, 0.04, 0.18), bevel=0.01)
    export_bmesh(bm2, "drone_carrier_housing", "drone_carrier_housing.glb",
                 color=(0.28, 0.30, 0.34))

    bm3 = bmesh.new()
    add_box(bm3, (0, 0, 0), (0.06, 0.18, 0.04), bevel=0.008)
    add_box(bm3, (0, 0, 0.01), (0.24, 0.05, 0.015), bevel=0.003)
    add_box(bm3, (0, 0.08, 0.02), (0.02, 0.04, 0.03), bevel=0.002)
    export_bmesh(bm3, "drone_carrier_drone", "drone_carrier_drone.glb",
                 color=(0.85, 0.85, 0.88))


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def build_utility_parts():
    print("=== Building Sensor Suite (Radar Mast) ===")
    clear_scene()
    build_sensor_suite_mount()
    clear_scene()
    build_sensor_suite_mast()
    clear_scene()
    build_sensor_suite_dish()

    print("=== Building Resource Harvester ===")
    clear_scene()
    build_resource_harvester_mount()
    clear_scene()
    build_resource_harvester_arm()
    clear_scene()
    build_resource_harvester_drill()

    print("=== Building Repair Array ===")
    clear_scene()
    build_repair_array_mount()
    clear_scene()
    build_repair_array_arm()
    clear_scene()
    build_repair_array_welder()

    print("=== Building Drone Carrier (unchanged) ===")
    build_drone_carrier_parts()

    print("=== All utility modules exported successfully ===")


if __name__ == "__main__":
    build_utility_parts()
