"""
Interface props: 3D objects that appear inside the UI rather than on the field.

Run headlessly:
  "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background \\
      --python tools/blender/build_ui_props.py

WHY THIS IS A SEPARATE SCRIPT FROM build_meshes.py, and not a few more functions
inside it. Two reasons, and the second is the important one:

  1. Different job. build_meshes.py authors hulls and weapon parts against
     module_catalog.gd's size vectors. Nothing here is a game object - these are
     set dressing for menus.

  2. DIFFERENT BLENDER. build_meshes.py's header says to run it with the bundled
     "UPBGE-0.30-windows-x86_64\\blender.exe", and that directory does not exist
     in this checkout - the documented interpreter is gone, and UPBGE 0.30 is a
     Blender 2.9x-era API besides. What is actually installed is Blender 5.2 LTS.
     Re-running the hull pipeline on 5.2 risks silently regenerating every
     committed hull GLB differently, which is not a thing to do incidentally, so
     this script deliberately touches nothing that pipeline owns.

COORDINATE CONVENTION is inherited from build_meshes.py: author in GODOT space
(x, y_up, z_depth) and convert at the call site with GV()/GS(). Blender is Z-up
and the glTF exporter's Y-up conversion maps Godot_Y = Blender_Z.
"""

import bpy
import bmesh
import math
import os

OUT_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models", "ui"
)
OUT_DIR = os.path.normpath(OUT_DIR)
os.makedirs(OUT_DIR, exist_ok=True)


def GV(x, y, z):
    """Godot-space (x, y_up, z_depth) -> raw Blender-space tuple."""
    return (x, z, y)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.objects):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def new_mesh(name):
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj, bmesh.new()


def finish(obj, bm):
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.calc_loop_triangles()
    return obj


def export_glb(obj, filename):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(OUT_DIR, filename + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path,
        use_selection=True,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
    )
    print("Exported: " + path)
    return path


# ---------------------------------------------------------------------------
# THE TURNTABLE
# ---------------------------------------------------------------------------
# What the main menu currently puts the player's design on is a CylinderMesh with
# top_radius 4.8, bottom_radius 5.2 and a flat grey material - a truncated cone.
# It is the first three-dimensional thing anyone sees in the game and it reads as
# a placeholder, because it is one.
#
# This is the same silhouette as a real machined turntable: a chamfered plinth,
# a recessed shoulder, a raised deck, a bolt circle, and index graduations cut
# into the rim. Every one of those is a lathe or mill operation, which is what
# makes it read as MADE rather than as a primitive.
#
# It stays a cone in overall profile deliberately - the wider base is what stops
# a heavy model looking like it is about to tip off.

def build_turntable():
    obj, bm = new_mesh("turntable_base")

    SEG = 64          # smooth enough at menu scale without being wasteful
    R_BASE = 5.25
    R_SHOULDER = 5.00
    R_DECK = 4.75
    Y_BOTTOM = -0.32
    Y_CHAMFER = -0.24
    Y_SHOULDER = -0.08
    Y_DECK = 0.0

    def ring(radius, y):
        return [
            bm.verts.new(GV(math.cos(i / SEG * math.tau) * radius, y,
                            math.sin(i / SEG * math.tau) * radius))
            for i in range(SEG)
        ]

    # Profile rings, bottom to top. Four rings give three bands: the chamfer
    # under the base, the shoulder recess, and the deck face.
    r0 = ring(R_BASE - 0.18, Y_BOTTOM)   # underside, pulled in so the chamfer reads
    r1 = ring(R_BASE, Y_CHAMFER)         # widest point
    r2 = ring(R_SHOULDER, Y_SHOULDER)    # recessed shoulder
    r3 = ring(R_DECK, Y_DECK)            # deck edge

    for lower, upper in ((r0, r1), (r1, r2), (r2, r3)):
        for i in range(SEG):
            j = (i + 1) % SEG
            bm.faces.new((lower[i], lower[j], upper[j], upper[i]))

    # Deck face, as a fan to a centre vertex. A single n-gon of 64 verts is legal
    # but triangulates unpredictably and can produce a visible crease across the
    # middle of the deck under the menu's key light.
    centre = bm.verts.new(GV(0.0, Y_DECK, 0.0))
    for i in range(SEG):
        j = (i + 1) % SEG
        bm.faces.new((r3[i], r3[j], centre))

    # Underside, closed so the silhouette is solid from any menu camera angle.
    base_centre = bm.verts.new(GV(0.0, Y_BOTTOM, 0.0))
    for i in range(SEG):
        j = (i + 1) % SEG
        bm.faces.new((r0[j], r0[i], base_centre))

    # --- Index graduations ---------------------------------------------------
    # Shallow notches cut into the shoulder at 15 degree intervals, with every
    # fourth one deeper. This is the detail that says "this thing rotates and
    # someone reads an angle off it", which is exactly what the menu turntable
    # is doing.
    for k in range(24):
        ang = k / 24.0 * math.tau
        major = (k % 4) == 0
        depth = 0.10 if major else 0.055
        half = 0.022 if major else 0.014
        ca, sa = math.cos(ang), math.sin(ang)
        pa, pb = -sa * half, ca * half     # tangent offset
        inner = R_SHOULDER - depth
        quad = [
            bm.verts.new(GV(ca * R_SHOULDER + pa, Y_SHOULDER + 0.002, sa * R_SHOULDER + pb)),
            bm.verts.new(GV(ca * R_SHOULDER - pa, Y_SHOULDER + 0.002, sa * R_SHOULDER - pb)),
            bm.verts.new(GV(ca * inner - pa, Y_SHOULDER + 0.002, sa * inner - pb)),
            bm.verts.new(GV(ca * inner + pa, Y_SHOULDER + 0.002, sa * inner + pb)),
        ]
        bm.faces.new(quad)

    # --- Bolt circle ---------------------------------------------------------
    # Eight hex heads proud of the deck, inset from the edge. Proud rather than
    # countersunk because a recess needs a boolean and reads as nothing at menu
    # distance, while a raised head catches the key light and reads immediately.
    for k in range(8):
        ang = (k / 8.0) * math.tau + math.tau / 16.0
        bx = math.cos(ang) * (R_DECK - 0.42)
        bz = math.sin(ang) * (R_DECK - 0.42)
        head_r = 0.13
        top = []
        bot = []
        for h in range(6):
            ha = h / 6.0 * math.tau
            hx = bx + math.cos(ha) * head_r
            hz = bz + math.sin(ha) * head_r
            bot.append(bm.verts.new(GV(hx, Y_DECK, hz)))
            top.append(bm.verts.new(GV(hx, Y_DECK + 0.055, hz)))
        for h in range(6):
            i2 = (h + 1) % 6
            bm.faces.new((bot[h], bot[i2], top[i2], top[h]))
        bm.faces.new(tuple(top))

    bm.normal_update()
    finish(obj, bm)
    return obj


# ---------------------------------------------------------------------------
# THE SPRUE FRAME
# ---------------------------------------------------------------------------
# A runner with unclipped parts still attached. This is the L0 workbench layer in
# three dimensions - dressing for the Front Desk and the loading screen, sitting
# behind and beside the turntable.
#
# Deliberately GENERIC blanks rather than recognisable vehicle parts. A sprue
# carrying identifiable turret halves would raise the question of which unit they
# belong to; blanks read as "kit parts" without making a claim.

def build_sprue():
    obj, bm = new_mesh("sprue_frame")

    def box(cx, cy, cz, sx, sy, sz):
        verts = []
        for dx in (-1, 1):
            for dy in (-1, 1):
                for dz in (-1, 1):
                    verts.append(bm.verts.new(
                        GV(cx + dx * sx / 2, cy + dy * sy / 2, cz + dz * sz / 2)))
        # (-x-y-z, -x-y+z, -x+y-z, -x+y+z, +x-y-z, +x-y+z, +x+y-z, +x+y+z)
        v = verts
        for quad in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
                     (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
            bm.faces.new(tuple(v[i] for i in quad))

    W, D, T = 4.4, 3.0, 0.10
    RAIL = 0.16
    # Outer frame: four rails.
    box(0, 0, -D / 2, W, T, RAIL)
    box(0, 0, D / 2, W, T, RAIL)
    box(-W / 2, 0, 0, RAIL, T, D)
    box(W / 2, 0, 0, RAIL, T, D)
    # One cross rail, so the frame does not read as a picture frame.
    box(0, 0, 0, W, T, RAIL * 0.8)

    # Parts on the sprue, each joined by a thin GATE - the neck you cut. The gate
    # is the whole point of the object; without it these are just blocks near a
    # frame rather than parts attached to one.
    parts = [
        (-1.35, -0.95, 0.85, 0.62),
        (0.10, -0.95, 1.05, 0.42),
        (1.45, -0.95, 0.70, 0.70),
        (-1.10, 0.95, 0.75, 0.50),
        (1.05, 0.95, 0.95, 0.55),
    ]
    for px, pz, pw, pd in parts:
        box(px, 0, pz, pw, T * 1.6, pd)
        gate_z = pz + (0.5 if pz < 0 else -0.5) * (abs(pz) - abs(pz) * 0.45)
        box(px, 0, gate_z, 0.07, T * 0.7, abs(pz) * 0.5)

    bm.normal_update()
    finish(obj, bm)
    return obj


# ---------------------------------------------------------------------------
# CONTROL HARDWARE (UX_REDESIGN_PLAN.md Phase 0 asset register): real machined
# hardware for the controls that currently render as flat theme boxes -
# toggles, a rotary selector, a rocker, a knurled dial, a DZUS fastener and a
# latch. Chris: "do not fail to author meshes for toggles and switches and
# buttons in menus... especially in the Design Lab, I'd like a fully modern
# and fluid UI/UX."
#
# WHY GLBS AND NOT FLAT ICONS. Everything else genuinely mechanical in this
# game (the turntable, every weapon module, every hull) is a real mesh, not a
# drawn glyph - the interface hardware should not be the one place that
# breaks the rule. These import through mesh_asset_loader.gd exactly like a
# hull or a weapon part and are meant to sit as small 3D props beside a
# control (a SubViewport the same way the turntable works, or a baked icon
# rendered from one), not as a texture atlas.
#
# SCALE: authored around a 1.0-unit nominal footprint so one import scale
# setting works for all six, matching build_meshes.py's own convention for
# weapon parts.

def _cylinder(bm, cx, cy, cz, radius, height, segments=24, cap_top=True, cap_bottom=True):
    """A vertical (Godot Y-axis) cylinder centred at (cx,cy,cz), height along Y."""
    top = []
    bot = []
    for i in range(segments):
        ang = i / segments * math.tau
        x = cx + math.cos(ang) * radius
        z = cz + math.sin(ang) * radius
        bot.append(bm.verts.new(GV(x, cy - height / 2, z)))
        top.append(bm.verts.new(GV(x, cy + height / 2, z)))
    for i in range(segments):
        j = (i + 1) % segments
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    if cap_top:
        c = bm.verts.new(GV(cx, cy + height / 2, cz))
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((top[i], top[j], c))
    if cap_bottom:
        c = bm.verts.new(GV(cx, cy - height / 2, cz))
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((bot[j], bot[i], c))
    return top, bot


def _box(bm, cx, cy, cz, sx, sy, sz):
    verts = []
    for dx in (-1, 1):
        for dy in (-1, 1):
            for dz in (-1, 1):
                verts.append(bm.verts.new(
                    GV(cx + dx * sx / 2, cy + dy * sy / 2, cz + dz * sz / 2)))
    v = verts
    for quad in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
                 (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        bm.faces.new(tuple(v[i] for i in quad))


# --- Toggle switch -----------------------------------------------------------
# A bat-handle switch on a hex bezel nut, thrown up (ON reads as up, matching
# every real toggle this one visually quotes).

def build_toggle_switch():
    obj, bm = new_mesh("ui_toggle_switch")

    # Hex bezel nut, flush to the panel it mounts through.
    hex_r = 0.34
    for i in range(6):
        pass  # hex approximated by a 6-seg cylinder below, kept simple/cheap
    _cylinder(bm, 0, 0.0, 0, hex_r, 0.14, segments=6)

    # Threaded bushing the bat lever pivots from.
    _cylinder(bm, 0, 0.16, 0, 0.16, 0.18, segments=16)

    # The bat handle itself, thrown to ON (canted toward +Y/+Z).
    lever_len = 0.62
    lever_r = 0.075
    top = []
    bot = []
    segs = 12
    for i in range(segs):
        ang = i / segs * math.tau
        x = math.cos(ang) * lever_r
        z_local = math.sin(ang) * lever_r
        bot.append(bm.verts.new(GV(x, 0.24, z_local)))
        # Canted end point: up and slightly back, so the bat reads as thrown
        # rather than standing dead vertical.
        top.append(bm.verts.new(GV(x * 0.5, 0.24 + lever_len, z_local * 0.5 + lever_len * 0.35)))
    for i in range(segs):
        j = (i + 1) % segs
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    ball = bm.verts.new(GV(0, 0.24 + lever_len + 0.05, lever_len * 0.35))
    for i in range(segs):
        j = (i + 1) % segs
        bm.faces.new((top[i], top[j], ball))
    bottom_cap = bm.verts.new(GV(0, 0.24, 0))
    for i in range(segs):
        j = (i + 1) % segs
        bm.faces.new((bot[j], bot[i], bottom_cap))

    bm.normal_update()
    return finish(obj, bm)


# --- Rotary selector (8 detents) ---------------------------------------------
# A knurled drum with a pointer line and eight index ticks on the bezel - the
# view-mode / profile selector the plan calls for wherever a player picks one
# of a small fixed set of exclusive states.

def build_rotary_selector():
    obj, bm = new_mesh("ui_rotary_selector")

    bezel_r = 0.42
    _cylinder(bm, 0, 0.0, 0, bezel_r, 0.10, segments=32)

    # Eight detent ticks cut into the bezel rim, matching the eight stops.
    for k in range(8):
        ang = k / 8.0 * math.tau
        ca, sa = math.cos(ang), math.sin(ang)
        outer = bezel_r + 0.03
        inner = bezel_r - 0.06
        half = 0.012
        pa, pb = -sa * half, ca * half
        quad = [
            bm.verts.new(GV(ca * outer + pa, 0.051, sa * outer + pb)),
            bm.verts.new(GV(ca * outer - pa, 0.051, sa * outer - pb)),
            bm.verts.new(GV(ca * inner - pa, 0.051, sa * inner - pb)),
            bm.verts.new(GV(ca * inner + pa, 0.051, sa * inner + pb)),
        ]
        bm.faces.new(quad)

    # Knurled drum, raised above the bezel - vertical knurl ribs around the rim.
    drum_r = 0.30
    drum_h = 0.26
    ribs = 20
    top, bot = _cylinder(bm, 0, 0.10 + drum_h / 2, 0, drum_r, drum_h, segments=ribs,
                          cap_top=True, cap_bottom=False)
    for i in range(0, ribs, 2):
        j = (i + 1) % ribs
        # Push every other rib vertex pair slightly inward to fake knurl teeth.
        for v in (top[i], bot[i]):
            v.co.x *= 0.92
            v.co.z *= 0.92

    # Pointer line on the drum top, showing the current detent.
    tip = bm.verts.new(GV(0, 0.10 + drum_h + 0.001, drum_r * 0.85))
    base_l = bm.verts.new(GV(-0.02, 0.10 + drum_h + 0.001, drum_r * 0.2))
    base_r = bm.verts.new(GV(0.02, 0.10 + drum_h + 0.001, drum_r * 0.2))
    bm.faces.new((base_l, base_r, tip))

    bm.normal_update()
    return finish(obj, bm)


# --- Rocker switch -------------------------------------------------------------
# A wide two-position rocker (the shape everyone recognises from a wall
# switch), for on/off toggles that read as bigger commitments than the small
# bat toggle - e.g. a whole settings section's master enable.

def build_rocker_switch():
    obj, bm = new_mesh("ui_rocker_switch")

    frame_w, frame_d, frame_h = 0.9, 0.5, 0.10
    _box(bm, 0, 0.0, 0, frame_w, frame_h, frame_d)

    # The rocker paddle, tilted so one end (ON, +Z) sits proud and the other
    # (OFF, -Z) sits recessed - a rocker mid-throw, same idea as the toggle's
    # canted bat.
    paddle_w, paddle_d, paddle_t = frame_w * 0.82, frame_d * 0.86, 0.05
    tilt = 0.05
    y0 = frame_h / 2
    verts = []
    for dz, dy in ((-1, -tilt), (1, tilt)):
        for dx in (-1, 1):
            verts.append(bm.verts.new(GV(
                dx * paddle_w / 2,
                y0 + dy + paddle_t / 2,
                dz * paddle_d / 2)))
    for dz, dy in ((-1, -tilt), (1, tilt)):
        for dx in (-1, 1):
            verts.append(bm.verts.new(GV(
                dx * paddle_w / 2,
                y0 + dy - paddle_t / 2,
                dz * paddle_d / 2)))
    tbl, tbr, ttl, ttr = verts[0], verts[1], verts[2], verts[3]
    bbl, bbr, btl, btr = verts[4], verts[5], verts[6], verts[7]
    bm.faces.new((tbl, tbr, ttr, ttl))          # top face
    bm.faces.new((bbr, bbl, btl, btr))          # bottom face
    bm.faces.new((tbl, ttl, btl, bbl))          # -Z (OFF) end
    bm.faces.new((ttr, tbr, bbr, btr))          # +Z (ON) end
    bm.faces.new((tbl, bbl, bbr, tbr))          # -X side
    bm.faces.new((ttl, ttr, btr, btl))          # +X side

    bm.normal_update()
    return finish(obj, bm)


# --- Knurled dial (continuous, e.g. a volume slider's thumb) -----------------

def build_knurled_dial():
    obj, bm = new_mesh("ui_knurled_dial")

    r = 0.34
    h = 0.22
    ribs = 28
    top, bot = _cylinder(bm, 0, 0.0, 0, r, h, segments=ribs)
    for i in range(0, ribs, 2):
        for v in (top[i], bot[i]):
            v.co.x *= 0.90
            v.co.z *= 0.90

    # Fingertip dimple on top, so the dial reads as something you press your
    # thumb into rather than a plain puck.
    dimple = bm.verts.new(GV(0, h / 2 - 0.03, 0))
    ring = []
    for i in range(16):
        ang = i / 16.0 * math.tau
        ring.append(bm.verts.new(GV(math.cos(ang) * r * 0.55, h / 2, math.sin(ang) * r * 0.55)))
    for i in range(16):
        j = (i + 1) % 16
        bm.faces.new((ring[i], ring[j], dimple))

    bm.normal_update()
    return finish(obj, bm)


# --- DZUS fastener -------------------------------------------------------------
# The quarter-turn slotted stud that holds real equipment panels shut - a
# small detail that reads as "this chrome is a panel bolted to a chassis"
# wherever it sits at a panel corner.

def build_dzus_fastener():
    obj, bm = new_mesh("ui_dzus_fastener")

    head_r = 0.16
    _cylinder(bm, 0, 0.0, 0, head_r, 0.06, segments=20)

    # Slot cut across the head (a thin notch, not a real boolean - two ridges
    # either side of a gap reads as a slot at this scale).
    slot_w = 0.03
    slot_len = head_r * 1.6
    for side in (-1, 1):
        cx = side * (slot_w / 2 + 0.005)
        _box(bm, cx, 0.031, 0, slot_w, 0.01, slot_len)

    # Shaft below the panel line.
    _cylinder(bm, 0, -0.10, 0, 0.05, 0.14, segments=12)

    bm.normal_update()
    return finish(obj, bm)


# --- Latch (toolbox / dock-collapse handle) ----------------------------------
# A drawbolt latch: a swung bail over a strike plate. Doubles as the physical
# metaphor for a UIDock's collapse handle - "unlatching" a panel closed.

def build_latch():
    obj, bm = new_mesh("ui_latch")

    plate_w, plate_h, plate_t = 0.5, 0.34, 0.05
    _box(bm, 0, 0.0, -0.08, plate_w, plate_h, plate_t)

    # Two pivot lugs the bail hooks through.
    for side in (-1, 1):
        _cylinder(bm, side * plate_w * 0.32, plate_h * 0.28, -0.08 + plate_t / 2 + 0.03,
                  0.035, 0.10, segments=10)

    # The bail: a bent tube from the lugs down to a hook, swung CLOSED (over
    # the strike) rather than open, since a menu control defaults to its
    # resting state.
    bail_r = 0.02
    pts = [
        (-plate_w * 0.32, plate_h * 0.28, 0.02),
        (-plate_w * 0.30, -plate_h * 0.05, 0.16),
        (0.0, -plate_h * 0.30, 0.20),
        (plate_w * 0.30, -plate_h * 0.05, 0.16),
        (plate_w * 0.32, plate_h * 0.28, 0.02),
    ]
    rings = []
    segs = 8
    for (px, py, pz) in pts:
        ring = []
        for i in range(segs):
            ang = i / segs * math.tau
            ring.append(bm.verts.new(GV(px + math.cos(ang) * bail_r, py, pz + math.sin(ang) * bail_r)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((a[i], a[j], b[j], b[i]))

    bm.normal_update()
    return finish(obj, bm)


# --- Chunky push button (StampedButton's 3D face) -----------------------------
# The "worn toolbox and stamped enamelled label" the design lab and battle
# production HUD already carry, taken one step further: the button itself
# is a real piece of hardware, not a flat plate with a 2D label.
#
# SHAPE: a low-profile chunky cylinder with a slightly dished top, a small
# chamfer on the top edge, and a closed bottom. Real industrial push
# buttons (factory control panels, emergency stops, machine consoles) all
# read as this silhouette - "a thing that you press with your finger" -
# which is what makes the StampedButton family feel pressed even before the
# user has touched one.
#
# PHASE 3 PASS WILL ADD, on top of this procedural base:
#   * An HD albedo (manufacturer mark stamped into the dish, part number
#     stamp near the rim, a real chamfered screw at each cardinal point).
#   * A normal map encoding the same surface detail the albedo carries,
#     so the dish and the stamp read under raking light.
#   * Variant-specific tinting baked in: PRIMARY gets a green pinstripe
#     under the chamfer, DANGER gets a red one, etc.
# None of that needs a mesh change - this geometry is what the HD textures
# wrap around. Phase 3 is a paint job, not a rebuild.

def build_push_button():
    obj, bm = new_mesh("ui_push_button")

    # DIMENSIONS. A 1.0-unit footprint is the convention build_ui_props.py
    # already uses for the other six UI meshes (see the script's own header),
    # so a single import-scale setting works for all seven.
    RADIUS = 0.50
    HEIGHT = 0.20
    # How deep the top dish is. ~10% of the radius - "slightly" dished, as
    # the brief said. A deeper dish starts to look like a sink; shallower
    # looks like a moulded-paint dimple.
    DISH_DEPTH = 0.05
    # Dish profile exponent. pow(1-r, FALLOFF) where FALLOFF>1 = centre-most
    # of the dish is deeper, edges blend smoothly to the chamfer. 2.0 is the
    # canonical sphere-cap profile; higher values exaggerate the centre
    # depression, lower values flatten it.
    DISH_FALLOFF = 2.0
    # Top edge chamfer width. 0.03 is small enough to read as "machined
    # edge" rather than "tapered mushroom cap" but large enough that a
    # beveled highlight lands on it under the SubViewport's key light.
    CHAMFER = 0.03
    # Dish subdivision. Six rings is the right density for a 96x96-pixel
    # button - finer and the polygons are smaller than the rendered
    # texel size, coarser and the dish silhouettes into a faceted bowl.
    TOP_RINGS = 6
    # Radial subdivision. 48 is more than enough at this size and matches
    # the toggle/rocker meshes for visual consistency.
    SEG = 48

    def ring(radius, y):
        return [bm.verts.new(GV(math.cos(i / SEG * math.tau) * radius, y,
                                math.sin(i / SEG * math.tau) * radius))
                for i in range(SEG)]

    # --- Side wall: bottom (r0) up to the chamfer start (r1) ---
    r0 = ring(RADIUS, 0.0)
    r1 = ring(RADIUS, HEIGHT - CHAMFER)
    for i in range(SEG):
        j = (i + 1) % SEG
        bm.faces.new((r0[i], r0[j], r1[j], r1[i]))

    # --- Chamfer: a flat 45-degree strip at the top edge ---
    # r1 sits at the full cylinder radius; r2 sits at (RADIUS - CHAMFER),
    # a hair inset, so the strip slopes INWARD as it rises. This is the
    # canonical machined chamfer - a flat, sloped band rather than a
    # curved fillet - which is what catches the key light in a strip the
    # eye reads as "this edge was cut on a lathe".
    r2 = ring(RADIUS - CHAMFER, HEIGHT)
    for i in range(SEG):
        j = (i + 1) % SEG
        bm.faces.new((r1[i], r1[j], r2[j], r2[i]))

    # --- Dish: r2 (outer rim) down to a centre vertex ---
    # The dish is built as concentric rings. Each ring's Y is on the
    # sphere-cap profile pow(1-r_norm, DISH_FALLOFF) so the centre is the
    # deepest point and the rim blends smoothly to the chamfer.
    dish_outer = RADIUS - CHAMFER
    dish_rings = [r2]
    for i in range(1, TOP_RINGS):
        r_norm = float(i) / TOP_RINGS
        r = dish_outer * r_norm
        y = HEIGHT - DISH_DEPTH * pow(1.0 - r_norm, DISH_FALLOFF)
        dish_rings.append(ring(r, y))
    center = bm.verts.new(GV(0.0, HEIGHT - DISH_DEPTH, 0.0))

    # Connect the dish rings into a smooth fan.
    for i in range(len(dish_rings) - 1):
        lower = dish_rings[i]
        upper = dish_rings[i + 1]
        for j in range(SEG):
            k = (j + 1) % SEG
            bm.faces.new((lower[j], lower[k], upper[k], upper[j]))

    # Innermost ring to centre vertex.
    innermost = dish_rings[-1]
    for j in range(SEG):
        k = (j + 1) % SEG
        bm.faces.new((innermost[j], innermost[k], center))

    # --- Bottom: closed so the silhouette is solid from any menu angle ---
    # Winding reversed from the side wall so the normal points DOWN.
    bot_center = bm.verts.new(GV(0.0, 0.0, 0.0))
    for j in range(SEG):
        k = (j + 1) % SEG
        bm.faces.new((r0[k], r0[j], bot_center))

    bm.normal_update()
    return finish(obj, bm)


def main():
    clear_scene()
    export_glb(build_turntable(), "turntable_base")
    clear_scene()
    export_glb(build_sprue(), "sprue_frame")
    clear_scene()
    export_glb(build_toggle_switch(), "ui_toggle_switch")
    clear_scene()
    export_glb(build_rotary_selector(), "ui_rotary_selector")
    clear_scene()
    export_glb(build_rocker_switch(), "ui_rocker_switch")
    clear_scene()
    export_glb(build_knurled_dial(), "ui_knurled_dial")
    clear_scene()
    export_glb(build_dzus_fastener(), "ui_dzus_fastener")
    clear_scene()
    export_glb(build_latch(), "ui_latch")
    clear_scene()
    export_glb(build_push_button(), "ui_push_button")
    clear_scene()
    print("\nUI props written to %s" % OUT_DIR)


if __name__ == "__main__":
    main()
