# build_vehicle_hulls.py - the vehicle hull catalogue: 8 manufacturers,
# ~80 hulls. One bmesh per hull. Structural features (cabs, sponsons, casemates,
# wheel arches, outriggers) are part of the cross-section evolution that gets
# lofted through, not bolted-on chamfered boxes glued to the main body.
#
# Run:
#   cd prototype
#   & "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" --background \
#       --python tools/blender/build_vehicle_hulls.py
#   ./Godot_v4.7.1-stable_win64_console.exe --headless --editor --import
#
# Options after a `--` separator:
#   --only <id>[,<id>...]   build a subset (fast iteration)
#   --out <dir>             override the output directory
#   --list                  print the lineup and exit without touching Blender
#
# DESIGN CONTRACT
# ---------------
# Manufacturer owns the BODY STRUCTURE (which cross-section, which bulges,
# which tiers). Class owns the PROPORTIONS and the large role element. Variant
# owns one further structural change. No hull carries surface detail - no
# rivets, no panel lines, no bolt rings. Every silhouette difference is
# load-bearing geometry you could read as a black shape at 40 metres.
#
# SINGLE-MESH BUILDS
# ------------------
# Every body function builds ONE bmesh and exports it as one GLB. Structural
# features are integrated by:
#   - For bulges in the main body (wheel arches, cab roofs, sponson
#     shoulders): the cross-section has a fixed number of "stations" around
#     its perimeter and those stations move (up/down/in/out) as z progresses
#     so the feature grows out of the main body. loft_evolution() handles this.
#   - For tiered features (casemate on plinth, bulwark on deck): a SECOND
#     add_solid() in the same bmesh, placed so the tier's bottom face shares
#     a face with the body. Still one mesh, just with the tier as its own
#     loft. add_chamfered_box() / add_wedge() are the tiered helpers.
#
# The eight houses:
#
#   halvorsen  Boat hulls dragged ashore. Hard-chine section: wide flat deck,
#              near-vertical topsides, a hard horizontal chine crease, steep
#              deadrise panels down to a narrow flat keel. Raked stem, high
#              freeboard, continuous raised bulwark rim around the deck.
#
#   kestrel    Aircraft fuselages with the wings sawn off. Faceted eight-sided
#              tube with a flat cargo floor, stepped-down tail boom, vertical
#              fin, angular canopy riding high at the nose, thick wing-root
#              stubs where the spar used to pass through.
#
#   brenntal   Mobile bunkers. Stacked orthogonal blocks with no taper at all:
#              wide low plinth, narrower casemate offset rearward, one
#              enormous frontal glacis plate, full-length sponson shoulders.
#
#   tallow     Open spaceframes. There is barely a body - a chassis rail, four
#              corner posts, a cab jammed against the front bumper, and the
#              rear two-thirds left as open flatbed framed by rails and thick
#              transverse beams.
#
#   orrin      Symmetric salvage. The main mass is a sheared wedge centered on
#              the longitudinal axis (no port/starboard lean), with a centred
#              dorsal spine and a rear cap block. No strut, no outrigger -
#              any asymmetry lives in the cross-section's top/bottom split,
#              not left/right, so locomotion mounts have a clean AABB to work
#              against.
#
#   rackham    Industrial crawler. Stout muscular body, exposed boiler barrel
#              running the length as a top ridge, deep forward radiator grille
#              that grows out of the cross-section at the nose, full-length
#              side rails at deck level, no curves anywhere.
#
#   calder     Fast-attack wedge. Low-slung, narrow at the nose and full-width
#              at the tail. Cross-section widens and shortens as z moves aft
#              so the silhouette tapers forward, and big side sponsons bulge
#              out of the mid-z range. Rear wing element on top.
#
#   pillar     Modular boxy. The body is a stack of chamfered rectangular
#              "cells" (one cell = 1.0 hull-height cubed), visibly stacked in
#              cross-section. Transport variants are a 2x2 cell wall with an
#              open flat well between them; combat variants are solid stacks.

import json
import math
import os
import sys

import bpy
import bmesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hull_forge as HF  # noqa: E402


HULLS_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "assets", "models", "hulls",
)


# ---------------------------------------------------------------------------
# Manufacturers
# ---------------------------------------------------------------------------

MANUFACTURERS = {
    "halvorsen": {
        "display": "Halvorsen Yard",
        "color": (0.376, 0.435, 0.415, 1.0),
    },
    "kestrel": {
        "display": "Kestrel Aeroworks",
        "color": (0.717, 0.729, 0.749, 1.0),
    },
    "brenntal": {
        "display": "Brenntal Schwerbau",
        "color": (0.298, 0.302, 0.322, 1.0),
    },
    "tallow": {
        "display": "Tallow & Vance",
        "color": (0.616, 0.482, 0.204, 1.0),
    },
    "orrin": {
        "display": "Orrin Collective",
        "color": (0.451, 0.341, 0.259, 1.0),
    },
    "rackham": {
        "display": "Rackham Forge",
        # A sooty iron grey with a warm tint - "industrial forge".
        "color": (0.340, 0.330, 0.310, 1.0),
    },
    "calder": {
        "display": "Calder Mobility",
        # A bright racing red - "fast attack".
        "color": (0.660, 0.190, 0.155, 1.0),
    },
    "pillar": {
        "display": "Pillar Ironworks",
        # A pale steel blue - "modular container".
        "color": (0.420, 0.490, 0.560, 1.0),
    },
}

CLASSES = ["scout", "light", "medium", "heavy", "transport", "oddball"]


# ---------------------------------------------------------------------------
# Bodies - one per manufacturer. Every body function is ONE add_solid() call
# (or loft_evolution() sampling one section function). The cross-section at
# every z is a single closed polygon, and the structural features (cabs,
# casemates, sponsons, outriggers, wheel arches) are part of the cross-
# section's evolution as z progresses, not bolted-on chamfered boxes.
#
# Discipline that makes the single-mesh work:
#   1. The cross-section has a FIXED number of vertices at every z (so the
#      loft between sections is well-defined). Features that are only present
#      in a z range have their vertices positioned at the "inactive" location
#      outside the range, and at the "active" location inside, with smooth
#      transitions in between.
#   2. The bottom of the cross-section is always at y = -h/2 (the hull's
#      underside). Locomotion mounts at the underside therefore work on every
#      hull uniformly, regardless of body shape.
#   3. The front of the hull rises up out of the flat underside as a sloped
#      face (a glacis), not as a dropping keel. Nose drops are small, kept
#      under 0.3*h, so a Halvorsen or Brenntal bow never reaches below the
#      underside plane.
#   4. Non-convex cross-sections (e.g. the Brenntal T-shape with plinth
#      shoulders + narrower casemate on top) are supported. hull_forge's
#      add_solid() now triangulates quads that fail to create, so a T-shape
#      with a real shoulder produces a closed, single-mesh surface.
#
# Role elements (masts, fins, ridges) stay as separate add_chamfered_box() /
# add_ridge() in the same bmesh - they are small thin features on top of
# the body, and treating them as part of the cross-section would force the
# outline to carry a tall vertical spike for a small mast, distorting the
# rest of the silhouette.
# ---------------------------------------------------------------------------

# --- HALVORSEN YARD ---------------------------------------------------------

def _halvorsen_section(z, hw, hl, w, h, l, chine, keel, deck_cut, rim_h,
                       bow_drop):
    """Cross-section for Halvorsen at a given z.

    A chine outline is the base, sized to fit the hull's height fraction at
    this z. The keel is always at y = -h/2 (flat underside, no rake), the
    deck is at y = -h/2 + h_frac*h, the chine is in between. The bulwark rim
    is integrated as a small upward bulge of the deck top edges in the
    mid-z range.

    h_frac(z) is the body's vertical fill at this z. At the very bow it is
    small (the bow rises out of the flat underside as a sloped face, not a
    dropping keel), at the middle it is full, at the stern it dips slightly.
    The cross-section outline has constant point count (10 vertices for the
    chine_outline + 2 deck-top points that the rim lives on).
    """
    # Height fraction along z. Front rises out of the flat underside as a
    # sloped face (no nose drop), middle is full, stern dips a little.
    if z <= -hl:
        h_frac = 0.30
    elif z <= -hl + l * 0.18:
        t = (z - (-hl)) / (l * 0.18)
        h_frac = 0.30 + (1.00 - 0.30) * t
    elif z <= hl - l * 0.16:
        h_frac = 1.00
    else:
        t = (z - (hl - l * 0.16)) / (l * 0.16)
        h_frac = 1.00 - 0.15 * t

    # Width fraction - hull narrows at the bow and stern slightly
    if z <= -hl:
        w_frac = 0.70
    elif z <= -hl + l * 0.18:
        t = (z - (-hl)) / (l * 0.18)
        w_frac = 0.70 + 0.30 * t
    elif z <= hl - l * 0.16:
        w_frac = 1.00
    else:
        w_frac = 0.95

    h_active = h * h_frac
    # Centre the chine outline so the keel is at -h/2 (flat underside) and
    # the deck is at -h/2 + h_active.
    cy = h_active / 2.0 - h / 2.0

    base = HF.chine_outline(
        w_deck=w * w_frac, w_keel=w * w_frac * keel,
        h=h_active, chine_frac=chine, cy=cy, deck_cut=deck_cut,
    )
    if rim_h <= 1e-6:
        return base
    # Lift the top deck-edge points to form the bulwark rim. chine_outline's
    # top is a pair of deck-edge points; raise them by rim_h and chamfer the
    # rim corners to match the deck chamfer. Outside the rim's z range the
    # lift is zero, so the deck is flat.
    deck_top_y = -h / 2.0 + h_active - deck_cut
    lifted = []
    for (x, y) in base:
        if y > deck_top_y - deck_cut * 0.6:
            lifted.append((x, y + rim_h))
        else:
            lifted.append((x, y))
    return lifted


def body_halvorsen(bm, w, h, l, opt):
    """Hard-chine boat section, flat keel, integrated bulwark rim.

    ONE loft. The cross-section's keel is always at y = -h/2, the deck is
    at -h/2 + h_frac(z)*h. The bow rises out of the flat underside as a
    sloped face (no nose drop), the middle is full height, the stern dips
    slightly. The bulwark rim is part of the cross-section, not bolted on.
    """
    hl = l / 2.0
    chine = opt.get("chine_frac", 0.42)
    keel = opt.get("keel_frac", 0.34)
    deck_cut = w * 0.055
    rim_h = h * opt.get("bulwark_h", 0.17) if opt.get("bulwark", True) else 0.0
    bow_drop = opt.get("bow_drop", 0.0)  # kept for backward compat, ignored

    def sec(z):
        return _halvorsen_section(
            z, w / 2.0, hl, w, h, l, chine, keel, deck_cut, rim_h, bow_drop,
        )

    HF.loft_evolution(bm, -hl, hl, sec, n_sections=8, cap_chamfer=min(w, h) * 0.10)


# --- KESTREL AEROWORKS ------------------------------------------------------

def _kestrel_section(z, hw, hl, w, h, l, fuse_w, cut, boom_frac, boom_z,
                     stub_w, stub_z, stub_l, wing_root_h, canopy_h,
                     spine_h, spine_zw):
    """Cross-section for Kestrel at a given z.

    A flat-floor octagon is the base, sized to fit the hull's fraction at
    this z. Wing-root stubs are integrated as side bulges in the cross-
    section in the mid-z range (the fuselage is inset to leave room for
    them, then widens back out). The canopy is a centered top peak in
    the nose region. The optional dorsal spine is a wider, lower top
    ridge in the mid-z range (vertex 4 and 6 also rise, so the top is
    a flat ridge from v4 to v6). The tail boom is a stepped narrowing
    at the rear.

    Outline vertices, clockwise from bottom-left, when the tail boom is
    narrow:
      0: bottom-left, at the flat floor y
      1: bottom-right, at the flat floor y
      2: right side lower
      3: right side upper
      4: right stub top / right spine side
      5: top center (canopy or spine peak)
      6: left stub top / left spine side
      7: left side upper
      8: left side lower

    The bottom edge (vertices 0-1) is always at y = -h/2 (flat floor).
    The top edge rises and falls as the canopy/spine grows and shrinks.
    """
    # Width and height of the fuselage, with stepped tail boom
    if z <= -hl:
        fw = 0.46
        fh = 0.50
    elif z <= -hl + l * 0.14:
        t = (z - (-hl)) / (l * 0.14)
        fw = 0.46 + (0.80 - 0.46) * t
        fh = 0.50 + (0.84 - 0.50) * t
    elif z <= -hl + l * 0.34:
        t = (z - (-hl + l * 0.14)) / (l * 0.20)
        fw = 0.80 + (1.00 - 0.80) * t
        fh = 0.84 + (1.00 - 0.84) * t
    elif z <= hl * boom_z - l * 0.06:
        fw = 1.00
        fh = 1.00
    elif z <= hl * boom_z:
        # Hard step - fuselage narrows in one jump at the empennage joint.
        t = (z - (hl * boom_z - l * 0.06)) / (l * 0.06)
        fw = 1.00 + (boom_frac - 1.00) * t
        fh = 1.00 + (boom_frac + 0.06 - 1.00) * t
    else:
        fw = boom_frac
        fh = boom_frac + 0.06

    # Inset fuselage width to make room for wing-root stub bulges in the
    # stub region. Outside the stub region, full width.
    in_stub = abs(z - stub_z) < stub_l / 2.0
    if in_stub:
        # Stub region: full width (stub bulges are outboard of fuse)
        full_w = w * fw
    else:
        # Outside stub region: inset by 2*stub_w on the sides
        full_w = w * fw - 2.0 * stub_w
    full_h = h * fh

    # Canopy bulge: a centered top peak in the canopy z range.
    in_canopy = z <= -hl + l * 0.30
    canopy_top = canopy_h if in_canopy else 0.0

    # Dorsal spine: a wider, lower top ridge in the mid-z range. The
    # spine widens the top (vertices 4 and 6 also rise to the same height
    # as vertex 5), so the silhouette has a flat ridge from v4 to v6
    # rather than a single peak at v5.
    in_spine = abs(z) < spine_zw
    spine_top = spine_h if in_spine else 0.0

    top_bulge = max(canopy_top, spine_top)
    top_widen = spine_top > 0.0 and canopy_top <= 0.0

    return _flat_floor_with_top_bulge(
        full_w, full_h, cut, top_bulge, top_widen,
    )


def _flat_floor_with_top_bulge(w, h, cut, top_bulge, widen=False):
    """Flat-floor octagon outline with an optional centered top bulge.

    9 vertices always. The bottom is at y = -h/2 (flat floor). When
    top_bulge = 0, the top is a flat octagon. When top_bulge > 0, the
    top center (vertex 5) rises by top_bulge. When widen is also True,
    the top sides (vertices 4 and 6) rise to the same height as vertex 5,
    forming a flat ridge from v4 to v6 (the dorsal-spine look). When
    widen is False, only v5 rises (the canopy look - a single peak).
    """
    hw, hh = w / 2.0, h / 2.0
    c = min(cut, hw * 0.7, hh * 0.7)
    floor_y = -hh
    side_top_y = hh - c
    if top_bulge > 1e-6:
        if widen:
            bulged_top_y = hh + top_bulge - c
            center_y = hh + top_bulge
        else:
            bulged_top_y = side_top_y
            center_y = side_top_y + top_bulge
    else:
        bulged_top_y = side_top_y
        center_y = side_top_y
    floor_half = hw - c * 0.35
    return [
        (-floor_half, floor_y),       # 0: bottom-left
        (floor_half, floor_y),        # 1: bottom-right
        (hw, floor_y + c * 0.8),      # 2: right side lower
        (hw, side_top_y),             # 3: right side upper
        (hw - c, bulged_top_y),       # 4: right stub top / bulge right
        (0, center_y),                # 5: top center (raised by bulge)
        (-hw + c, bulged_top_y),      # 6: left stub top / bulge left
        (-hw, side_top_y),            # 7: left side upper
        (-hw, floor_y + c * 0.8),     # 8: left side lower
    ]


def body_kestrel(bm, w, h, l, opt):
    """Faceted eight-sided fuselage, stepped tail boom, integrated wing
    stubs and canopy/spine bulge, flat floor.

    ONE loft. The cross-section is a flat-floor octagon with optional
    side bulges for wing-root stubs and a centered top bulge for the
    canopy or dorsal spine. The fuselage narrows at the tail boom in a
    hard step.
    """
    hl = l / 2.0
    boom_frac = opt.get("boom_frac", 0.52)
    boom_z = opt.get("boom_z", 0.30)
    stub_frac = opt.get("stub_w", 0.15)
    stub_w = w * stub_frac
    stub_l = l * opt.get("stub_l", 0.24)
    stub_z = hl * opt.get("stub_z", -0.10)
    wing_root_h = h * 0.34
    cut = min(w, h) * opt.get("facet_cut", 0.26)
    fuse_w = w * (1.0 - 2.0 * stub_frac * 0.88)
    canopy_h = h * 0.30 if opt.get("canopies", (-0.52,)) else 0.0
    spine_h = h * opt.get("spine_h", 0.0)
    spine_zw = l * opt.get("spine_zw", 0.0)

    def sec(z):
        return _kestrel_section(
            z, w / 2.0, hl, w, h, l, fuse_w, cut, boom_frac, boom_z,
            stub_w, stub_z, stub_l, wing_root_h, canopy_h,
            spine_h, spine_zw,
        )

    HF.loft_evolution(bm, -hl, hl, sec, n_sections=8, cap_chamfer=cut * 0.7)

    # Tail fin - small thin element on top, still a tiered add_solid in the
    # same bmesh (the fin is too thin to fit in the cross-section without
    # distorting the fuselage).
    if opt.get("fin", True):
        fin_h = h * opt.get("fin_h", 0.42)
        HF.add_solid(
            bm,
            [(hl - l * 0.30, HF.trap_outline(w * 0.14, w * 0.07, fin_h,
                                            cy=fin_h / 2.0 - h * 0.04,
                                            cx=0.0)),
             (hl - l * 0.02, HF.trap_outline(w * 0.11, w * 0.05, fin_h * 0.8,
                                             cy=fin_h * 0.4 - h * 0.04,
                                             cx=0.0))],
            cap_chamfer=w * 0.035,
        )


# --- BRENNTAL SCHWERBAU -----------------------------------------------------

def _brenntal_section(z, hl, w, h, l, plinth_w, casemate_w, casemate_h, cut,
                     glacis_z_frac, casemate_z_frac, casemate_l_frac,
                     tiers, top_cap_h, top_cap_l, top_cap_w):
    """Cross-section for Brenntal at a given z.

    The cross-section is a NON-CONVEX T-shape with the wider plinth at the
    bottom and a narrower casemate on top. The casemate grows out of the
    plinth as the cross-section evolves: outside the casemate z range, the
    casemate vertices collapse to the plinth top, so the cross-section
    becomes a simple wide-topped shape. Inside the range, the casemate
    vertices rise to the casemate top, creating the T-shape with real
    plinth shoulders.

    The bottom of the cross-section is at y = -h/2 (flat underside, no
    drop). The bow rises out of the flat underside as a sloped face.
    """
    # Height fraction along z. Bow rises as a glacis, full at the casemate,
    # medium at the rear.
    if z <= -hl:
        h_frac = 0.20  # bow is short, sloped face
    elif z <= -hl + l * glacis_z_frac:
        t = (z - (-hl)) / max(l * glacis_z_frac, 1e-6)
        h_frac = 0.20 + 0.80 * t  # ramps from 0.20 to 1.00
    elif z <= hl - l * casemate_l_frac:
        h_frac = 1.00
    else:
        t = (z - (hl - l * casemate_l_frac)) / max(l * casemate_l_frac, 1e-6)
        h_frac = 1.00 - 0.35 * t  # back end dips to 0.65

    # Width fraction. Bow is slightly narrower.
    if z <= -hl:
        w_frac = 0.94
    elif z <= -hl + l * glacis_z_frac:
        t = (z - (-hl)) / max(l * glacis_z_frac, 1e-6)
        w_frac = 0.94 + 0.06 * t
    else:
        w_frac = 1.00

    # Casemate present factor. Inside the casemate z range (centered at
    # casemate_z_frac of the length, total length casemate_l_frac of the
    # length), the casemate vertices are at casemate top. Outside, they
    # collapse to the plinth top.
    cas_center = -hl + l * casemate_z_frac
    cas_active = 1.0 if abs(z - cas_center) < l * casemate_l_frac / 2.0 else 0.0

    # Plinth top y, casemate top y. Bottom is always at -h/2 (flat).
    plinth_top_y = -h / 2.0 + h * h_frac
    casemate_top_y = plinth_top_y + h * 0.30 * cas_active  # casemate is 30% of h tall
    if top_cap_h > 0.0:
        # Top cap (a tier) - a small box on top of the casemate. Same range
        # as the casemate.
        cap_present = abs(z - cas_center) < l * (top_cap_l * 0.5) and cas_active > 0.0
        if cap_present:
            cap_top_y = casemate_top_y + h * top_cap_h
        else:
            cap_top_y = casemate_top_y
    else:
        cap_top_y = casemate_top_y

    plinth_w_at = w * w_frac
    cas_w_at = plinth_w_at * casemate_w
    cap_w_at = cas_w_at * top_cap_w if top_cap_h > 0.0 else cas_w_at

    # 11-vertex T-shape cross-section. The casemate vertices collapse to
    # the plinth top when cas_active = 0, so the cross-section becomes a
    # flat-topped shape. When cas_active = 1, the casemate is a real
    # bulge on top of the plinth.
    c = cut
    return [
        (-plinth_w_at / 2.0 + c, -h / 2.0),                # 0: bottom-left
        (plinth_w_at / 2.0 - c, -h / 2.0),                 # 1: bottom-right
        (plinth_w_at / 2.0, -h / 2.0 + c),                 # 2: right lower
        (plinth_w_at / 2.0, plinth_top_y - c),              # 3: right shoulder
        (cas_w_at / 2.0, plinth_top_y),                     # 4: right notch
        (cas_w_at / 2.0, casemate_top_y - c * cas_active),  # 5: right casemate side
        (cap_w_at / 2.0, cap_top_y),                        # 6: right cap side (or casemate top)
        (-cap_w_at / 2.0, cap_top_y),                       # 7: left cap side (mirror)
        (-cas_w_at / 2.0, casemate_top_y - c * cas_active), # 8: left casemate side
        (-cas_w_at / 2.0, plinth_top_y),                    # 9: left notch
        (-plinth_w_at / 2.0, plinth_top_y - c),             # 10: left shoulder
        (-plinth_w_at / 2.0, -h / 2.0 + c),                 # 11: left lower
    ]


def body_brenntal(bm, w, h, l, opt):
    """Wide low plinth + narrower casemate on top + frontal glacis, all in
    ONE lofted solid.

    The cross-section is a T-shape with the wider plinth at the bottom
    (full width) and a narrower casemate on top, integrated into the
    outline. The casemate grows out of the cross-section as z enters the
    casemate region. The bottom of the cross-section is always at y=-h/2
    (flat underside, no drop). The bow rises out of the flat underside
    as a sloped face.
    """
    hl = l / 2.0
    casemate_w = opt.get("casemate_w", 0.78)
    casemate_h = opt.get("casemate_h", 0.30)
    glacis_z_frac = opt.get("glacis_z", 0.24)
    casemate_z_frac = opt.get("casemate_z_frac", 0.55)
    casemate_l_frac = opt.get("casemate_l", 0.60)
    tiers = opt.get("tiers", 1)
    cut = min(w, h) * 0.10
    top_cap_h = opt.get("top_cap_h", 0.0)
    top_cap_l = opt.get("top_cap_l", 0.40)
    top_cap_w = opt.get("top_cap_w", 0.62)

    def sec(z):
        return _brenntal_section(
            z, hl, w, h, l, 1.0, casemate_w, casemate_h, cut,
            glacis_z_frac, casemate_z_frac, casemate_l_frac, tiers,
            top_cap_h, top_cap_l, top_cap_w,
        )

    HF.loft_evolution(bm, -hl, hl, sec, n_sections=8, cap_chamfer=cut)


# --- TALLOW & VANCE ---------------------------------------------------------

def _tallow_section(z, hl, l, w, h, frame_w, cab_l_frac, cab_h_frac, cab_w_frac,
                    cab_rake, cut):
    """Cross-section for Tallow at a given z.

    Closed-body truck. The cross-section is an octagon whose height varies
    along z: low chassis at the rear (the flatbed), tall cab at the front
    (with a sloped/raked top to read as a windshield). The bottom is
    always at y = -h/2 (flat underside).

    The cab has a raked top: at the very front of the cab z range, the
    cross-section's top is at the cab front height; at the rear of the cab
    z range, the cross-section's top is at the cab back height (taller
    than the front - the cab roof is taller than the windshield). After
    the cab z range, the cross-section's top drops to the flatbed height.
    """
    cab_z_start = -hl
    cab_z_end = -hl + l * cab_l_frac
    flatbed_z_start = cab_z_end

    if z <= cab_z_start:
        # Pre-cab: chassis height (low)
        h_frac = 0.40
    elif z <= cab_z_start + l * 0.04:
        # Glacis front: ramps up from chassis to cab front
        t = (z - cab_z_start) / (l * 0.04)
        h_frac = 0.40 + (cab_h_frac * cab_rake - 0.40) * t
    elif z <= cab_z_end:
        # Cab: tall, with raked top
        t = (z - cab_z_start) / max(l * cab_l_frac, 1e-6)
        h_front = cab_h_frac * cab_rake
        h_back = cab_h_frac
        h_frac = h_front + (h_back - h_front) * t
    elif z <= flatbed_z_start + l * 0.04:
        # Drop from cab back to flatbed
        t = (z - flatbed_z_start) / (l * 0.04)
        h_frac = cab_h_frac + (0.40 - cab_h_frac) * t
    else:
        # Flatbed: low chassis height
        h_frac = 0.40

    full_w = frame_w
    full_h = h * h_frac
    cy = full_h / 2.0 - h / 2.0
    return HF.oct_outline(full_w, full_h, cut, cut, cy=cy)


def body_tallow(bm, w, h, l, opt):
    """Closed-body truck. Cab at the front, flatbed at the rear.

    ONE loft. The cross-section's height varies along z: low chassis at
    the flatbed, tall cab with a raked top (windshield shorter than
    roof) at the front, sloped transition between them. Bottom always at
    y = -h/2 (flat underside).

    The "open spaceframe" character of the old Tallow is gone - the new
    Tallow is a single closed body. The cab + flatbed vocabulary is kept.
    """
    hl = l / 2.0
    frame_w = w * opt.get("frame_w", 0.90)
    cab_l_frac = opt.get("cab_l", 0.26)
    cab_h_frac = opt.get("cab_h", 0.72)
    cab_w_frac = opt.get("cab_w", 0.94)
    cab_rake = opt.get("cab_rake", 0.66)
    cut = min(w, h) * 0.09

    def sec(z):
        return _tallow_section(
            z, hl, l, w, h, frame_w, cab_l_frac, cab_h_frac, cab_w_frac,
            cab_rake, cut,
        )

    HF.loft_evolution(bm, -hl, hl, sec, n_sections=8, cap_chamfer=cut)


# --- ORRIN COLLECTIVE (symmetric, tumblehome) -------------------------------

def body_orrin(bm, w, h, l, opt):
    """Symmetric salvage with TUMBLEHOME cross-section.

    BILATERALLY symmetric. ONE loft. The cross-section is a trapezoid
    (naval-architecture tumblehome): wider at the bottom (full w), narrower
    at the top (w * tumblehome_frac, default 0.80). The bottom is always
    at y = -h/2 (flat underside, no drop). The bow rises out of the flat
    underside as a sloped face.

    Optional centered dorsal spine or tall mast is integrated as a 4-vertex
    mesa peak in its z range, so the peak is a cross-section bulge (not a
    separate add_chamfered_box bolted on top). Spine and mast are mutually
    exclusive - one peak per hull. The peak vertices are kept in the
    outline at every z, collapsed to a flat segment on the deck when not
    active, so the cross-section point count is constant for the loft.
    """
    hl = l / 2.0
    mass_w = w * opt.get("mass_w", 0.85)
    cut = min(w, h) * 0.09
    tumblehome_frac = opt.get("tumblehome_frac", 0.80)

    # Peak: a spine (wide + low) or a mast (narrow + tall). Mutually
    # exclusive - one peak per hull.
    spine_h_frac = opt.get("spine_h", 0.0)
    spine_w_frac = opt.get("spine_w", 0.0)
    spine_zc = hl * opt.get("spine_zc", 0.0)
    spine_zw = l * opt.get("spine_zw", 0.20)

    mast_h_frac = opt.get("mast_h", 0.0)
    mast_w_frac = opt.get("mast_w", 0.0)
    mast_zc = hl * opt.get("mast_zc", 0.10)
    mast_zw = l * opt.get("mast_zw", 0.05)

    if spine_h_frac > 0.0 and spine_w_frac > 0.0:
        peak_h = h * spine_h_frac
        peak_w = w * spine_w_frac
        peak_zc = spine_zc
        peak_zw = spine_zw
    elif mast_h_frac > 0.0 and mast_w_frac > 0.0:
        peak_h = h * mast_h_frac
        peak_w = w * mast_w_frac
        peak_zc = mast_zc
        peak_zw = mast_zw
    else:
        peak_h = 0.0
        peak_w = 0.0
        peak_zc = 0.0
        peak_zw = 0.0

    def sec(z):
        # Width and height fractions along z. Slight vertical squish at
        # the bow and stern.
        if z <= -hl:
            fw, fh = 0.52, 0.58
        elif z <= -hl + l * 0.24:
            t = (z - (-hl)) / (l * 0.24)
            fw = 0.52 + 0.48 * t
            fh = 0.58 + 0.42 * t
        elif z <= hl * 0.74:
            fw, fh = 1.00, 1.00
        else:
            t = (z - hl * 0.74) / (hl * 0.26)
            fw = 1.00 - 0.18 * t
            fh = 1.00 - 0.18 * t

        full_w = mass_w * fw
        full_h = h * fh
        top_w = full_w * tumblehome_frac
        deck_y = -h / 2.0 + full_h

        t_peak = HF.smooth_transition(z, peak_zc, peak_zw) if peak_h > 0 else 0.0

        return _tumblehome_with_peak(
            full_w, full_h, top_w, deck_y, cut, peak_w, peak_h, t_peak,
        )

    HF.loft_evolution(bm, -hl, hl, sec, n_sections=10, cap_chamfer=cut)


def _tumblehome_with_peak(full_w, full_h, top_w, deck_y, cut, peak_w,
                            peak_h, t_peak):
    """Tumblehome trapezoid cross-section with optional centered peak.

    12 vertices ALWAYS (constant count for the loft). The bottom is at
    y = -h/2 with full width; the top is at deck_y with top_w (narrower
    than the bottom for tumblehome). When t_peak = 0, the 4 center
    vertices form a flat segment along the deck top, so the cross-section
    has no peak. When t_peak = 1, the 4 center vertices form a centered
    mesa bump (peak base on the deck, peak top at deck_y + peak_h).

    The smooth_transition() interpolation makes the peak grow smoothly
    out of the flat deck as z enters the peak region, and recede back to
    the flat deck as z leaves it.
    """
    hw = full_w / 2.0
    tw = top_w / 2.0
    floor_y = deck_y - full_h  # = -h/2 (the flat underside)
    ceiling_y = deck_y
    c = cut

    if peak_w > 0.0 and peak_h > 0.0:
        pw = peak_w / 2.0
        peak_y = ceiling_y + peak_h

        # Flat positions (t_peak = 0): the 4 peak vertices form a flat
        # segment along the deck top, between (tw - c) and (-tw + c).
        # Spacing them prevents degenerate faces in the loft.
        flat_outer_x = tw - c * 0.7
        flat_inner_x = c * 0.4

        # Active positions (t_peak = 1): the 4 peak vertices form a
        # centered mesa bump with base at pw and top at peak_y.
        v5_x = (1.0 - t_peak) * flat_outer_x + t_peak * pw
        v6_x = (1.0 - t_peak) * flat_inner_x + t_peak * pw
        v7_x = (1.0 - t_peak) * (-flat_inner_x) + t_peak * (-pw)
        v8_x = (1.0 - t_peak) * (-flat_outer_x) + t_peak * (-pw)
        v5_y = ceiling_y
        v6_y = (1.0 - t_peak) * ceiling_y + t_peak * peak_y
        v7_y = (1.0 - t_peak) * ceiling_y + t_peak * peak_y
        v8_y = ceiling_y
    else:
        # No peak possible - place the 4 vertices on the deck top.
        v5_x, v5_y = tw - c * 0.7, ceiling_y
        v6_x, v6_y = c * 0.4, ceiling_y
        v7_x, v7_y = -c * 0.4, ceiling_y
        v8_x, v8_y = -tw + c * 0.7, ceiling_y

    return [
        (-hw + c, floor_y),       # 0: bottom-left
        (hw - c, floor_y),        # 1: bottom-right
        (hw, floor_y + c),        # 2: right lower side
        (tw, ceiling_y),          # 3: right tumblehome top
        (tw - c, ceiling_y),      # 4: right deck top (chamfered)
        (v5_x, v5_y),             # 5: right peak base / flat
        (v6_x, v6_y),             # 6: right peak top / flat
        (v7_x, v7_y),             # 7: left peak top / flat
        (v8_x, v8_y),             # 8: left peak base / flat
        (-tw + c, ceiling_y),     # 9: left deck top (chamfered)
        (-tw, ceiling_y),         # 10: left tumblehome top
        (-hw, floor_y + c),       # 11: left lower side
    ]


# --- RACKHAM FORGE ----------------------------------------------------------

def _rackham_section(z, hl, l, w, h, cut, mast_w, mast_h, mast_zc, mast_zw):
    """Cross-section for Rackham at a given z.

    ONE loft. The cross-section is a chassis rectangle (octagon) at the
    bottom, with a centered boiler barrel bulge on top in the mid-z
    range, a taller radiator bulge in the front, and a smokestack bulge
    in the mid-rear. All bulges are part of the cross-section.

    The optional centered mast is a tall thin vertical structure in the
    mast z range - integrated as a 4-vertex mesa peak in the cross-
    section, not bolted on. The mast sits on top of whatever is at the
    chassis top in that z range (chassis alone, boiler, or smokestack).

    12 vertices always. When the mast is not active, its 4 vertices
    form a flat segment along the bulged top, so the cross-section has
    no peak. When the mast is active, the 4 vertices form a centered
    mesa bump (base on the bulged top, peak at bulged_top + mast_h).
    """
    # Chassis height (constant)
    chassis_h = 0.46
    chassis_top_y = -h / 2.0 + h * chassis_h
    chassis_w_at_z = w * (0.92 if z > -hl + l * 0.14 else 0.88 + 0.04 * max(0, (z - (-hl)) / (l * 0.14)))

    # Bulge heights: boiler in mid-z, radiator in front, smokestack mid-rear
    in_boiler = abs(z) < l * 0.32
    in_radiator = -hl <= z <= -hl + l * 0.20
    in_stack = abs(z - hl * 0.20) < l * 0.10

    boiler_top = h * 0.30 if in_boiler else 0.0
    rad_top = h * 0.40 if in_radiator else 0.0
    stack_top = h * 0.18 if in_stack else 0.0
    top_bulge = max(boiler_top, rad_top, stack_top)

    chassis_top_chamfered = chassis_top_y
    full_top_y = chassis_top_y + top_bulge

    # Mast peak - a 4-vertex mesa on top of the bulged top, active in
    # the mast z range. smooth_transition gives a soft ramp.
    t_mast = HF.smooth_transition(z, mast_zc, mast_zw) if mast_h > 0 else 0.0

    c = cut
    if mast_w > 0.0 and mast_h > 0.0:
        mw = mast_w / 2.0
        mast_peak_y = full_top_y + mast_h
        # Flat positions (t_mast = 0): 4 vertices on a flat segment along
        # the bulged top, ordered RIGHT-TO-LEFT (decreasing x) so each
        # face's bmesh normal points UP (+Y) and the glTF export flips
        # it to the convention (top faces DOWN, -Y).
        flat_outer_x = chassis_w_at_z * 0.30
        flat_inner_x = chassis_w_at_z * 0.08
        v5_x = (1.0 - t_mast) * flat_outer_x + t_mast * mw
        v6_x = (1.0 - t_mast) * flat_inner_x + t_mast * mw
        v7_x = (1.0 - t_mast) * (-flat_inner_x) + t_mast * (-mw)
        v8_x = (1.0 - t_mast) * (-flat_outer_x) + t_mast * (-mw)
        v5_y = full_top_y
        v6_y = (1.0 - t_mast) * full_top_y + t_mast * mast_peak_y
        v7_y = (1.0 - t_mast) * full_top_y + t_mast * mast_peak_y
        v8_y = full_top_y
    else:
        v5_x, v5_y = chassis_w_at_z * 0.30, full_top_y
        v6_x, v6_y = chassis_w_at_z * 0.08, full_top_y
        v7_x, v7_y = -chassis_w_at_z * 0.08, full_top_y
        v8_x, v8_y = -chassis_w_at_z * 0.30, full_top_y

    return [
        (-chassis_w_at_z / 2.0 + c, -h / 2.0),                # 0: bottom-left
        (chassis_w_at_z / 2.0 - c, -h / 2.0),                 # 1: bottom-right
        (chassis_w_at_z / 2.0, -h / 2.0 + c),                 # 2: right lower
        (chassis_w_at_z / 2.0, chassis_top_chamfered - c),    # 3: right chassis top
        (chassis_w_at_z / 2.0 - c, full_top_y),               # 4: right top (bulged)
        (v5_x, v5_y),                                         # 5: right mast base / flat
        (v6_x, v6_y),                                         # 6: right mast top / flat
        (v7_x, v7_y),                                         # 7: left mast top / flat
        (v8_x, v8_y),                                         # 8: left mast base / flat
        (-chassis_w_at_z / 2.0 + c, full_top_y),              # 9: left top (bulged)
        (-chassis_w_at_z / 2.0, chassis_top_chamfered - c),   # 10: left chassis top
        (-chassis_w_at_z / 2.0, -h / 2.0 + c),                # 11: left lower
    ]


def body_rackham(bm, w, h, l, opt):
    """Industrial crawler. ONE loft with integrated boiler, radiator,
    smokestack, and optional centered mast as cross-section bulges.
    Flat underside, no drop.
    """
    hl = l / 2.0
    cut = min(w, h) * 0.09
    mast_w = w * opt.get("mast_w", 0.0)
    mast_h = h * opt.get("mast_h", 0.0)
    mast_zc = hl * opt.get("mast_zc", 0.0)
    mast_zw = l * opt.get("mast_zw", 0.05)

    def sec(z):
        return _rackham_section(z, hl, l, w, h, cut, mast_w, mast_h,
                                mast_zc, mast_zw)

    HF.loft_evolution(bm, -hl, hl, sec, n_sections=8, cap_chamfer=cut)


# --- CALDER MOBILITY --------------------------------------------------------

def _calder_section(z, hw, hl, l, w, h, body_w_min_frac, body_h_min_frac,
                    body_h_max_frac, cut, sponson_w, sponson_zc, sponson_zw):
    """Cross-section for Calder at a given z.

    Body is an octagon whose width and height grow linearly with z. Outside
    sponson_zw of sponson_zc, the body is inset (2*sponson_w narrower) so
    the sponson bulge can grow back out to full w inside the sponson region.
    The sponson is therefore a bulge in the body, not an add-on.
    """
    if z <= -hl:
        fw, fh = 0.55, 0.65
    elif z >= hl:
        fw, fh = 1.00, 1.00
    else:
        t = (z - (-hl)) / (2.0 * hl)
        fw = body_w_min_frac + (1.0 - body_w_min_frac) * t
        fh = body_h_min_frac + (body_h_max_frac - body_h_min_frac) * t

    sponson_active = abs(z - sponson_zc) < sponson_zw
    body_w_at = w if sponson_active else w - 2.0 * sponson_w
    full_w = body_w_at * fw
    return HF.oct_outline(full_w, h * fh, cut, cut,
                          cy=-h * 0.05 * (1.0 - fh))


def _calder_section(z, hl, l, w, h, body_w_min_frac, body_h_min_frac,
                    body_h_max_frac, cut, sponson_w, sponson_zc, sponson_zw,
                    wing_h_frac, barbette_w, barbette_h, barbette_zc,
                    barbette_zw):
    """Cross-section for Calder at a given z.

    The body width and height grow linearly with z. The body is inset
    by 2*sponson_w outside the sponson z range and full-width inside,
    so the sponsons are a width bulge in the mid-z. The rear wing
    is a top bulge in the rear. The optional centered barbette is a
    mesa bump on top of the chassis (or on top of the wing if both
    are active at this z) in the barbette z range - integrated as a
    4-vertex peak in the cross-section, not bolted on.

    12 vertices always. When the barbette is not active, its 4 vertices
    form a flat segment along the bulged top, so the cross-section has
    no peak. When the barbette is active, the 4 vertices form a centered
    mesa bump (base on the bulged top, peak at bulged_top + barbette_h).
    """
    if z <= -hl:
        fw, fh = 0.55, 0.65
    elif z >= hl:
        fw, fh = 1.00, 1.00
    else:
        t = (z - (-hl)) / (2.0 * hl)
        fw = body_w_min_frac + (1.0 - body_w_min_frac) * t
        fh = body_h_min_frac + (body_h_max_frac - body_h_min_frac) * t

    in_sponson = abs(z - sponson_zc) < sponson_zw
    body_w_at = w if in_sponson else w - 2.0 * sponson_w
    full_w = body_w_at * fw
    full_h = h * fh
    # Top: in the rear, add the wing as a centered top bulge.
    in_wing = z > hl * 0.55
    wing_top = wing_h_frac if in_wing else 0.0
    top_y = -h / 2.0 + full_h
    bulged_top_y = top_y + wing_top

    # Barbette peak - a 4-vertex mesa on top of the bulged top, active
    # in the barbette z range. smooth_transition gives a soft ramp.
    t_barbette = HF.smooth_transition(z, barbette_zc, barbette_zw) if barbette_h > 0 else 0.0

    c = cut
    if barbette_w > 0.0 and barbette_h > 0.0:
        bw = barbette_w / 2.0
        barbette_peak_y = bulged_top_y + barbette_h
        # Flat positions (t_barbette = 0): 4 vertices on a flat segment
        # along the bulged top, ordered RIGHT-TO-LEFT (decreasing x) so
        # each face's bmesh normal points UP (+Y) and the glTF export
        # flips it to the convention (top faces DOWN, -Y). The flat
        # positions are well inside the chamfered top corners (v4, v9)
        # so the interpolation to the active barbette base (bw) is a
        # smooth inward slide rather than a crossover.
        flat_outer_x = full_w * 0.30
        flat_inner_x = full_w * 0.08
        v5_x = (1.0 - t_barbette) * flat_outer_x + t_barbette * bw
        v6_x = (1.0 - t_barbette) * flat_inner_x + t_barbette * bw
        v7_x = (1.0 - t_barbette) * (-flat_inner_x) + t_barbette * (-bw)
        v8_x = (1.0 - t_barbette) * (-flat_outer_x) + t_barbette * (-bw)
        v5_y = bulged_top_y
        v6_y = (1.0 - t_barbette) * bulged_top_y + t_barbette * barbette_peak_y
        v7_y = (1.0 - t_barbette) * bulged_top_y + t_barbette * barbette_peak_y
        v8_y = bulged_top_y
    else:
        v5_x, v5_y = full_w * 0.30, bulged_top_y
        v6_x, v6_y = full_w * 0.08, bulged_top_y
        v7_x, v7_y = -full_w * 0.08, bulged_top_y
        v8_x, v8_y = -full_w * 0.30, bulged_top_y

    return [
        (-full_w / 2.0 + c, -h / 2.0),                 # 0: bottom-left
        (full_w / 2.0 - c, -h / 2.0),                  # 1: bottom-right
        (full_w / 2.0, -h / 2.0 + c),                  # 2: right lower
        (full_w / 2.0, top_y - c),                      # 3: right top (chamfered)
        (full_w / 2.0 - c, bulged_top_y),               # 4: right top (bulged)
        (v5_x, v5_y),                                  # 5: right barbette base / flat
        (v6_x, v6_y),                                  # 6: right barbette top / flat
        (v7_x, v7_y),                                  # 7: left barbette top / flat
        (v8_x, v8_y),                                  # 8: left barbette base / flat
        (-full_w / 2.0 + c, bulged_top_y),              # 9: left top (bulged)
        (-full_w / 2.0, top_y - c),                     # 10: left top (chamfered)
        (-full_w / 2.0, -h / 2.0 + c),                  # 11: left lower
    ]


def body_calder(bm, w, h, l, opt):
    """Fast-attack wedge. ONE loft with integrated sponson bulges,
    rear wing, and optional centered barbette mesa. Flat underside,
    no drop. Body narrows at the nose.
    """
    hl = l / 2.0
    body_w_min_frac = opt.get("body_w_min", 0.55)
    body_h_min_frac = opt.get("body_h_min", 0.45)
    body_h_max_frac = opt.get("body_h_max", 0.78)
    cut = min(w, h) * 0.10
    sponson_w = w * opt.get("sponson_w", 0.18)
    sponson_zc = hl * opt.get("sponson_zc", 0.05)
    sponson_zw = l * opt.get("sponson_zw", 0.35)
    wing_h_frac = h * 0.06 if opt.get("wing", True) else 0.0
    barbette_w = w * opt.get("barbette_w", 0.0)
    barbette_h = h * opt.get("barbette_h", 0.0)
    barbette_zc = hl * opt.get("barbette_zc", 0.0)
    barbette_zw = l * opt.get("barbette_zw", 0.05)

    def sec(z):
        return _calder_section(
            z, hl, l, w, h, body_w_min_frac, body_h_min_frac, body_h_max_frac,
            cut, sponson_w, sponson_zc, sponson_zw, wing_h_frac,
            barbette_w, barbette_h, barbette_zc, barbette_zw,
        )

    HF.loft_evolution(bm, -hl, hl, sec, n_sections=8, cap_chamfer=cut)


# --- PILLAR IRONWORKS -------------------------------------------------------

def _pillar_section(z, hl, l, w, h, transport_well, cut, barbette_w,
                     barbette_h, barbette_zc, barbette_zw):
    """Cross-section for Pillar at a given z.

    ONE loft. Combat variants are a single tall box (the modular cell
    stack reads as chamfered ridges in the silhouette). Transport
    variants are a U-shape (two side walls + a floor) - the cavity
    is part of the cross-section.

    Cell-stack look: the cross-section has step bulges on the sides
    that grow out and back in, like a stack of cells. Implemented as
    a periodic width modulation.

    The optional centered barbette (combat mode only) is a 4-vertex
    mesa peak on top of the box, integrated as a cross-section bulge.
    12 vertices for combat (8 base + 4 barbette). Transport mode is
    unchanged (U-shape, no barbette).
    """
    # Width modulation: stacked cells, each cell is l * 0.18 long
    cell_w_mod = 1.00 if (int((z + hl) / (l * 0.10)) % 2 == 0) else 0.96

    if transport_well:
        # U-shape: two side walls + a thin floor at the underside
        wall_w = w * 0.30
        well_w = w - 2.0 * wall_w
        floor_thick = h * 0.10
        # The cross-section is a U with the floor at the bottom and walls
        # going up. The underside (floor bottom) is at -h/2, the wall tops
        # are at +h/2 - floor_thick.
        wall_top_y = -h / 2.0 + h - floor_thick
        floor_top_y = -h / 2.0 + floor_thick
        return [
            (-w / 2.0 + cut, -h / 2.0),                                # 0: floor BL
            (w / 2.0 - cut, -h / 2.0),                                 # 1: floor BR
            (w / 2.0, -h / 2.0 + cut),                                 # 2: floor right
            (w / 2.0, wall_top_y),                                     # 3: wall right top
            (w / 2.0 - wall_w, wall_top_y - cut),                      # 4: well right
            (w / 2.0 - wall_w, floor_top_y),                          # 5: well floor right
            (-w / 2.0 + wall_w, floor_top_y),                         # 6: well floor left
            (-w / 2.0 + wall_w, wall_top_y - cut),                     # 7: well left
            (-w / 2.0, wall_top_y),                                    # 8: wall left top
            (-w / 2.0, -h / 2.0 + cut),                                # 9: floor left
        ]
    else:
        # Solid box with cell-stack ridges, 12 vertices (8 base +
        # 4 barbette). The barbette is centered on top.
        full_w = w * cell_w_mod
        full_h = h
        top_y = full_h / 2.0  # = h/2 since full_h = h
        c = cut

        # Barbette peak - 4-vertex mesa on top of the box, active in
        # the barbette z range.
        t_barbette = HF.smooth_transition(z, barbette_zc, barbette_zw) if barbette_h > 0 else 0.0

        if barbette_w > 0.0 and barbette_h > 0.0:
            bw = barbette_w / 2.0
            barbette_peak_y = top_y + barbette_h
            # Flat positions (t_barbette = 0): 4 vertices on a flat
            # segment along the top, ordered RIGHT-TO-LEFT (decreasing
            # x) so each face's bmesh normal points UP (+Y) and the
            # glTF export flips it to the convention (top faces DOWN,
            # -Y). Positions are well inside the chamfered top corners
            # (v4, v9) so the interpolation to the active barbette base
            # (bw) is a smooth inward slide.
            flat_outer_x = full_w * 0.30
            flat_inner_x = full_w * 0.08
            v5_x = (1.0 - t_barbette) * flat_outer_x + t_barbette * bw
            v6_x = (1.0 - t_barbette) * flat_inner_x + t_barbette * bw
            v7_x = (1.0 - t_barbette) * (-flat_inner_x) + t_barbette * (-bw)
            v8_x = (1.0 - t_barbette) * (-flat_outer_x) + t_barbette * (-bw)
            v5_y = top_y
            v6_y = (1.0 - t_barbette) * top_y + t_barbette * barbette_peak_y
            v7_y = (1.0 - t_barbette) * top_y + t_barbette * barbette_peak_y
            v8_y = top_y
        else:
            v5_x, v5_y = full_w * 0.30, top_y
            v6_x, v6_y = full_w * 0.08, top_y
            v7_x, v7_y = -full_w * 0.08, top_y
            v8_x, v8_y = -full_w * 0.30, top_y

        return [
            (-full_w / 2.0 + c, -h / 2.0),                # 0: bottom-left
            (full_w / 2.0 - c, -h / 2.0),                 # 1: bottom-right
            (full_w / 2.0, -h / 2.0 + c),                 # 2: right lower
            (full_w / 2.0, top_y - c),                     # 3: right top (chamfered)
            (full_w / 2.0 - c, top_y),                     # 4: right top (flat)
            (v5_x, v5_y),                                 # 5: right barbette base / flat
            (v6_x, v6_y),                                 # 6: right barbette top / flat
            (v7_x, v7_y),                                 # 7: left barbette top / flat
            (v8_x, v8_y),                                 # 8: left barbette base / flat
            (-full_w / 2.0 + c, top_y),                    # 9: left top (flat)
            (-full_w / 2.0, top_y - c),                    # 10: left top (chamfered)
            (-full_w / 2.0, -h / 2.0 + c),                 # 11: left lower
        ]


def body_pillar(bm, w, h, l, opt):
    """Modular boxy. ONE loft, flat underside, no drop.

    Combat variants are a single tall box (12-vertex cross-section with
    optional centered barbette mesa, the cell-stack reads as chamfered
    ridges in the silhouette). Transport variants are a U-shape (two
    side walls + a floor), with the cavity as part of the cross-section.
    """
    hl = l / 2.0
    cut = min(w, h) * 0.12
    transport_well = opt.get("transport_well", False)
    barbette_w = w * opt.get("barbette_w", 0.0)
    barbette_h = h * opt.get("barbette_h", 0.0)
    barbette_zc = hl * opt.get("barbette_zc", 0.0)
    barbette_zw = l * opt.get("barbette_zw", 0.05)

    def sec(z):
        return _pillar_section(z, hl, l, w, h, transport_well, cut,
                                barbette_w, barbette_h, barbette_zc,
                                barbette_zw)

    HF.loft_evolution(bm, -hl, hl, sec, n_sections=8, cap_chamfer=cut)


BODIES = {
    "halvorsen": body_halvorsen,
    "kestrel": body_kestrel,
    "brenntal": body_brenntal,
    "tallow": body_tallow,
    "orrin": body_orrin,
    "rackham": body_rackham,
    "calder": body_calder,
    "pillar": body_pillar,
}


# ---------------------------------------------------------------------------
# Role elements - the large greebles that read a class on top of a
# manufacturer body. These are tiered structures: an add_chamfered_box()
# or add_wedge() in the same bmesh, with the bottom face sitting on the
# body's top or flank. They are separate lofts in one mesh.
# ---------------------------------------------------------------------------

def _local_top_at_z(bm, godot_z: float, tolerance: float = 0.5) -> float:
    """Y coordinate of the highest TOP-facing facet near the given Godot-Z.

    Elements that sit on the body deck (bolster / gantry / second_deck / flatbed
    / trunk / barbette / well / bridge / mast / spine) used to be placed at
    `hh + ...` (top of the body's bounding box). That worked for hulls with a
    uniform top (block, slab) but on a tallow - which has a tall cab at the
    nose and a low flatbed at the rear - it put the rear elements high in the
    air. The screenshot in the floating-parts bug report showed exactly that:
    the bolster posts floating 0.9 units above the flatbed.

    The body's true top is whatever face is currently facing up. The face's
    centroid Z is the height in Godot, and Blender Y maps to Godot -Z (see
    mark_frontal_armour's coordinate note at line ~441), so we convert the
    Godot-Z to a Blender-Y target and pick the highest up-facing face near it.
    Fallback to 0.0 if no top face is in range - the element ends up exactly
    where the old code put it, so the behaviour is never worse than before.

    bmesh face.normal is unreliable on freshly created faces (the bmesh.ops
    call may not have computed the winding yet), so we derive the normal
    manually from two edge vectors and take the +Z component.
    """
    target_blender_y = -godot_z
    best: float = -1e9
    for f in bm.faces:
        verts = f.verts
        if len(verts) < 3:
            continue
        v0 = verts[0].co
        v1 = verts[1].co
        v2 = verts[2].co
        e1 = v1 - v0
        e2 = v2 - v0
        n = e1.cross(e2)
        if n.length < 1e-6:
            continue
        nz = n.z / n.length
        if nz < 0.5:
            continue
        c = f.calc_center_median()
        if abs(c.y - target_blender_y) > tolerance:
            continue
        if c.z > best:
            best = c.z
    return best if best > -1e8 else 0.0


def el_mast(bm, w, h, l, p):
    """Tall square-section sensor mast. The scout tell.

    Base anchored to the body's local top at the mast z, not the bbox top.
    See _local_top_at_z() - same rationale as el_bolster. The -h*0.04
    inset on the old code was a poor attempt at "slightly below the
    bbox top"; with the real top in hand it just disappears.
    """
    hl = l / 2.0
    mh = h * p.get("mh", 1.05)
    base = w * p.get("base", 0.15)
    z = hl * p.get("z", 0.10)
    x = w * p.get("x", 0.0)
    local_top = _local_top_at_z(bm, z)
    base_y = local_top
    HF.add_solid(bm, [
        (z - base / 2.0, HF.oct_outline(base, mh, base * 0.26, mh * 0.05,
                                        cy=base_y + mh / 2.0, cx=x)),
        (z + base / 2.0, HF.oct_outline(base * 0.9, mh, base * 0.26, mh * 0.05,
                                        cy=base_y + mh / 2.0, cx=x)),
    ], cap_chamfer=base * 0.22)
    HF.add_chamfered_box(bm, (x, base_y + mh * 0.86, z),
                         (w * p.get("vane", 0.46), h * 0.07, base * 0.7),
                         cut=h * 0.02)


def el_barbette(bm, w, h, l, p):
    """Low octagonal-PLAN turret plinth. The medium/heavy gun-platform tell.

    Base anchored to the body's local top at the barbette z. See
    _local_top_at_z() - same rationale as el_bolster.
    """
    hl = l / 2.0
    r = w * p.get("r", 0.34)
    bh = h * p.get("bh", 0.22)
    z = hl * p.get("z", 0.0)
    base_y = _local_top_at_z(bm, z)
    cy = base_y + bh / 2.0
    wide = HF.oct_outline(r * 2.0, bh, r * 0.30, bh * 0.28, cy=cy)
    narrow = HF.oct_outline(r * 1.46, bh * 0.92, r * 0.24, bh * 0.26, cy=cy)
    HF.add_solid(bm, [
        (z - r * 0.98, narrow),
        (z - r * 0.44, wide),
        (z + r * 0.44, wide),
        (z + r * 0.98, narrow),
    ], cap_chamfer=bh * 0.22)


def el_bridge(bm, w, h, l, p):
    """Stepped superstructure stack. The command-variant tell.

    First step base anchored to the body's local top at the bridge z. See
    _local_top_at_z() - same rationale as el_bolster.
    """
    hl = l / 2.0
    steps = p.get("steps", 3)
    z = hl * p.get("z", 0.10)
    total = h * p.get("total", 0.95)
    w0 = w * p.get("w", 0.62)
    l0 = l * p.get("l", 0.30)
    y = _local_top_at_z(bm, z)
    for i in range(steps):
        f = 1.0 - i * (0.62 / max(1, steps))
        sh = total / steps
        HF.add_chamfered_box(bm, (w * p.get("x", 0.0), y + sh / 2.0, z),
                             (w0 * f, sh, l0 * f), cut=min(w0 * f, sh) * 0.16)
        y += sh


def el_spine(bm, w, h, l, p):
    """Full-length dorsal ridge.

    Base anchored to the body's local top at the spine's mid z, not the
    bbox top. See _local_top_at_z() - same rationale as el_bolster. The
    spine runs the length of the hull, so the local top can vary along
    its z range; we use the spine's mid-z as a representative sample.
    """
    hl = l / 2.0
    z0 = hl * p.get("z0", -0.72)
    z1 = hl * p.get("z1", 0.86)
    mid_z = (z0 + z1) / 2.0
    base_y = _local_top_at_z(bm, mid_z)
    sh = h * p.get("sh", 0.30)
    HF.add_ridge(bm, z0, z1,
                 base_y, base_y + sh + h * 0.02,
                 w * p.get("w_bot", 0.24), w * p.get("w_top", 0.10),
                 cx=w * p.get("x", 0.0), cut=w * 0.035)


def el_flatbed(bm, w, h, l, p):
    """Open cargo deck with low perimeter rails. The transport tell.

    Deck base anchored to the body's local top across the deck's z range.
    See _local_top_at_z() - same rationale as el_bolster. Use the lowest
    local top so the deck doesn't clip through the hull.
    """
    hl = l / 2.0
    z0 = hl * p.get("z0", -0.10)
    z1 = hl * p.get("z1", 0.94)
    bw = w * p.get("w", 0.86)
    mid_z = (z0 + z1) / 2.0
    base_y = _local_top_at_z(bm, mid_z)
    deck_y = base_y + h * 0.02
    HF.add_chamfered_box(bm, (0.0, deck_y, mid_z),
                         (bw, h * p.get("deck_h", 0.20), z1 - z0), cut=h * 0.04)
    rail_h = h * p.get("rail_h", 0.30)
    for xs in (-1, 1):
        HF.add_chamfered_box(
            bm, (xs * (bw / 2.0 - w * 0.03), deck_y + rail_h / 2.0, mid_z),
            (w * 0.06, rail_h, z1 - z0), cut=w * 0.015)
    HF.add_chamfered_box(bm, (0.0, deck_y + rail_h / 2.0, z1 - w * 0.03),
                         (bw, rail_h, w * 0.06), cut=w * 0.015)


def el_trunk(bm, w, h, l, p):
    """Raised full-length trunk deck - the tanker/bulk-carrier read.

    Base anchored to the body's local top at the trunk's mid z. See
    _local_top_at_z() - same rationale as el_bolster.
    """
    hl = l / 2.0
    th = h * p.get("th", 0.42)
    z0 = hl * p.get("z0", -0.62)
    z1 = hl * p.get("z1", 0.90)
    tw = w * p.get("w", 0.66)
    mid_z = (z0 + z1) / 2.0
    base_y = _local_top_at_z(bm, mid_z)
    outline = HF.oct_outline(tw, th, tw * 0.22, th * 0.30,
                             cy=base_y + th / 2.0)
    HF.add_solid(bm, [(z0, outline), (z1, outline)], cap_chamfer=th * 0.24)


def el_well(bm, w, h, l, p):
    """Open cargo well: two tall side walls and a rear gate, nothing between.

    Wall bases anchored to the body's local top across the well's z range.
    See _local_top_at_z() - same rationale as el_bolster.
    """
    hl = l / 2.0
    z0 = hl * p.get("z0", -0.20)
    z1 = hl * p.get("z1", 0.94)
    ww = w * p.get("w", 0.88)
    wall_h = h * p.get("wall_h", 0.52)
    t = w * 0.09
    base_y = _local_top_at_z(bm, (z0 + z1) / 2.0)
    for xs in (-1, 1):
        HF.add_chamfered_box(
            bm, (xs * (ww / 2.0 - t / 2.0), base_y + wall_h / 2.0,
                 (z0 + z1) / 2.0),
            (t, wall_h, z1 - z0), cut=t * 0.26)
    HF.add_chamfered_box(bm, (0.0, base_y + wall_h / 2.0, z1 - t / 2.0),
                         (ww, wall_h, t), cut=t * 0.26)
    HF.add_chamfered_box(bm, (0.0, base_y + wall_h * 0.30, z0 + t / 2.0),
                         (ww * 0.9, wall_h * 0.7, t), cut=t * 0.26)


def el_ramp(bm, w, h, l, p):
    """Enormous raked bow gate - the landing-craft read."""
    hh, hl = h / 2.0, l / 2.0
    z_foot = -hl * p.get("z_foot", 0.99)
    z_head = -hl * p.get("z_head", 0.52)
    y_foot = -hh * p.get("y_foot", 0.62)
    y_head = hh + h * p.get("rise", 0.26)
    gw = w * p.get("w", 0.80)
    th = h * p.get("th", 0.16)
    HF.add_solid(bm, [
        (z_foot, HF.oct_outline(gw, th, gw * 0.10, th * 0.30, cy=y_foot)),
        (z_head, HF.oct_outline(gw * 0.96, th, gw * 0.10, th * 0.30, cy=y_head)),
    ], cap_chamfer=th * 0.30)


def el_glacis(bm, w, h, l, p):
    """A second, steeper armour plate stacked over the front. Heavy-class."""
    hh, hl = h / 2.0, l / 2.0
    HF.add_wedge(bm, (0.0, hh * p.get("y", 0.10), -hl * p.get("z", 0.58)),
                 (w * p.get("w", 0.94), h * p.get("hh", 0.46), l * p.get("len", 0.34)),
                 front_h_frac=p.get("front", 0.28), cut=min(w, h) * 0.08)


def el_ballast(bm, w, h, l, p):
    """Big solid rear counterweight block. Prime-mover / wrecker read."""
    hh, hl = h / 2.0, l / 2.0
    HF.add_chamfered_box(
        bm, (w * p.get("x", 0.0), hh * p.get("y", 0.32), hl * p.get("z", 0.72)),
        (w * p.get("w", 0.70), h * p.get("h", 0.54), l * p.get("len", 0.24)),
        cut=min(w, h) * 0.09)


def el_gantry(bm, w, h, l, p):
    """Portal-frame arch straddling the deck. Two legs and a beam.

    Leg base anchored to the body's local top at the gantry z, not the
    bounding-box top. See _local_top_at_z() - same rationale as el_bolster.
    """
    hw, hl = w / 2.0, l / 2.0
    gh = h * p.get("gh", 0.86)
    t = w * p.get("t", 0.11)
    z = hl * p.get("z", 0.24)
    beam_h = h * p.get("beam_h", 0.13)
    local_top = _local_top_at_z(bm, z)
    leg_center_y = local_top + gh / 2.0
    beam_center_y = local_top + gh - beam_h / 2.0
    for xs in (-1, 1):
        HF.add_chamfered_box(bm, (xs * (hw - t * 0.8), leg_center_y, z),
                             (t, gh, t * 1.2), cut=t * 0.24)
    HF.add_chamfered_box(bm, (0.0, beam_center_y, z),
                         (w * 0.96, beam_h, t * 1.2), cut=min(beam_h, t) * 0.24)


def el_bolster(bm, w, h, l, p):
    """Tall transverse bolsters - the log/pipe hauler read.

    The post base is now anchored to the body's actual top at the bolster's
    z position, not the bounding-box top. Old code used `hh + bh / 2.0`
    which is `h/2 + bh/2` - the top of the hull's bbox, which on a tallow
    hull is the cab roof. The bolster at z = -0.06 and z = 0.60 is in the
    flatbed area, where the body is much lower, so the old code put the
    whole structure 0.9 units in the air. See _local_top_at_z().
    """
    hl = l / 2.0
    bh = h * p.get("bh", 0.62)
    for zf in p.get("z", (-0.12, 0.66)):
        z_actual = hl * zf
        local_top = _local_top_at_z(bm, z_actual)
        # Post center: bottom at local_top, so the post sits on the body.
        post_y = local_top + bh / 2.0
        # Beam center: same Y as the post center - the beam is a cross-brace
        # in the middle of the post pair, like a sawhorse rail. Old code
        # shared this Y with the post (and the bug was that Y was bbox-top,
        # not flatbed-top).
        beam_y = post_y
        HF.add_chamfered_box(bm, (0.0, beam_y, z_actual),
                             (w * 0.90, bh * 0.24, l * 0.05), cut=h * 0.03)
        for xs in (-1, 1):
            HF.add_chamfered_box(
                bm, (xs * (w * 0.44), post_y, z_actual),
                (w * 0.07, bh, l * 0.05), cut=w * 0.018)


def el_second_deck(bm, w, h, l, p):
    """A whole second open deck on posts above the first.

    Post bases anchored to the body's local top across the deck's z range,
    not the bounding-box top. See _local_top_at_z() - same rationale as
    el_bolster. We sample the local top at each post's z so the deck sits
    flat even when the hull under it is not.
    """
    hl = l / 2.0
    lift = h * p.get("lift", 0.62)
    z0 = hl * p.get("z0", -0.30)
    z1 = hl * p.get("z1", 0.92)
    dw = w * 0.88
    sample_zs = [z0 + l * 0.04, (z0 + z1) / 2.0, z1 - l * 0.04]
    # Use the LOWEST local top across the deck's z range so every post sits
    # on the body. If we used the highest, the posts on the lower side of
    # the deck would float again.
    base_y = min(_local_top_at_z(bm, z) for z in sample_zs)
    for xs in (-1, 1):
        for zf in sample_zs:
            HF.add_chamfered_box(bm, (xs * (dw / 2.0 - w * 0.05),
                                      base_y + lift / 2.0, zf),
                                 (w * 0.08, lift, w * 0.08), cut=w * 0.02)
    HF.add_chamfered_box(bm, (0.0, base_y + lift + h * 0.05, (z0 + z1) / 2.0),
                         (dw, h * 0.11, z1 - z0),
                         cut=h * 0.026)


ELEMENTS = {
    "mast": el_mast,
    "barbette": el_barbette,
    "bridge": el_bridge,
    "spine": el_spine,
    "flatbed": el_flatbed,
    "trunk": el_trunk,
    "well": el_well,
    "ramp": el_ramp,
    "glacis": el_glacis,
    "ballast": el_ballast,
    "gantry": el_gantry,
    "bolster": el_bolster,
    "second_deck": el_second_deck,
}


# ---------------------------------------------------------------------------
# The lineup. 80 hulls. Deliberately unbalanced across manufacturers, per the
# brief: Brenntal and Halvorsen carry the heavy end, Tallow owns transports at
# every size, Kestrel skews small and fast, Orrin is symmetric salvage, Rackham
# is industrial mid, Calder is fast-attack light, Pillar is modular boxy.
#
# size is the Godot-space envelope (width, height, length) and it is EXACT:
# autofit() solves for the working size whose natural AABB lands here, and
# HF.normalize() finishes the job, so the shipped .glb measures exactly this.
# ---------------------------------------------------------------------------

HEIGHT_BOOST = 1.38


def H(hid, mfr, cls, name, size, elements=(), body=None, domain="Ground"):
    return {
        "id": hid, "mfr": mfr, "cls": cls, "name": name,
        "size": (size[0], round(size[1] * HEIGHT_BOOST, 3), size[2]),
        "elements": list(elements), "body": dict(body or {}), "domain": domain,
    }


LINEUP = [
    # -- HALVORSEN YARD (13): boats ashore -------------------------------
    H("halvorsen_scout_a", "halvorsen", "scout", "Halvorsen Picket Launch",
      (2.4, 1.15, 3.9), [("mast", {"mh": 0.62, "z": 0.20})],
      {"bulwark_h": 0.20}),
    H("halvorsen_light_a", "halvorsen", "light", "Halvorsen Gunboat",
      (2.8, 1.15, 4.8), [("barbette", {"z": -0.30, "r": 0.30, "bh": 0.20})]),
    H("halvorsen_light_b", "halvorsen", "light", "Halvorsen Patrol Skiff",
      (2.9, 1.05, 5.1), [("spine", {"sh": 0.20, "z0": -0.10})],
      {"chine_frac": 0.30, "keel_frac": 0.52}, domain="Naval"),
    H("halvorsen_medium_a", "halvorsen", "medium", "Halvorsen Monitor",
      (3.8, 1.35, 5.7), [("barbette", {"z": -0.14, "r": 0.36, "bh": 0.22})]),
    H("halvorsen_medium_b", "halvorsen", "medium", "Halvorsen Cutter",
      (3.3, 1.55, 6.3), [("bridge", {"steps": 2, "z": 0.34, "w": 0.56,
                                     "total": 0.62})]),
    H("halvorsen_heavy_a", "halvorsen", "heavy", "Halvorsen Armoured Monitor",
      (4.5, 1.75, 7.3), [("barbette", {"z": -0.44, "r": 0.34, "bh": 0.22}),
                         ("barbette", {"z": 0.46, "r": 0.30, "bh": 0.20})]),
    H("halvorsen_heavy_b", "halvorsen", "heavy", "Halvorsen Bridge Ship",
      (4.3, 2.10, 7.5), [("bridge", {"steps": 3, "z": 0.06, "total": 0.80})]),
    H("halvorsen_heavy_c", "halvorsen", "heavy", "Halvorsen Dreadnought Hull",
      (5.1, 1.70, 8.1), [("barbette", {"z": -0.20, "r": 0.30, "bh": 0.20})],
      {"bulwark_h": 0.13}),
    H("halvorsen_transport_a", "halvorsen", "transport", "Halvorsen Landing Barge",
      (4.1, 1.45, 7.7), [("ramp", {}), ("well", {"z0": -0.22, "wall_h": 0.40})],
      {"bulwark": False}),
    H("halvorsen_transport_b", "halvorsen", "transport", "Halvorsen Lighter",
      (3.9, 1.25, 8.3), [("flatbed", {"z0": -0.34, "rail_h": 0.22})],
      {"bulwark": False}, domain="Naval"),
    H("halvorsen_transport_c", "halvorsen", "transport", "Halvorsen Trunk Tanker",
      (3.9, 1.65, 8.5), [("trunk", {"th": 0.38, "z0": -0.56})],
      {"bulwark_h": 0.12}),
    H("halvorsen_oddball_a", "halvorsen", "oddball", "Halvorsen Catamaran",
      (5.3, 1.50, 7.1), [("mast", {"mh": 0.48})],
      {"bulwark": False}, domain="Naval"),
    H("halvorsen_oddball_b", "halvorsen", "oddball", "Halvorsen Cradle Crawler",
      (4.1, 1.60, 6.3), [], {"bulwark": False,
                             "chine_frac": 0.60, "keel_frac": 0.10}),

    # -- KESTREL AEROWORKS (12): fuselages, wings sawn off ---------------
    H("kestrel_scout_a", "kestrel", "scout", "Kestrel Recon Fuselage",
      (2.5, 1.15, 4.1), [], {"boom_frac": 0.48, "fin_h": 0.46}),
    H("kestrel_scout_b", "kestrel", "scout", "Kestrel Pathfinder",
      (2.3, 0.95, 4.9), [], {"boom_frac": 0.40, "boom_z": 0.00,
                             "stub_w": 0.11, "fin_h": 0.52}),
    H("kestrel_scout_c", "kestrel", "scout", "Kestrel Drone Tender",
      (2.7, 1.05, 4.3), [],
      {"canopies": (), "boom_frac": 0.52, "fin_h": 0.38,
       "spine_h": 0.20, "spine_zw": 0.20}),
    H("kestrel_light_a", "kestrel", "light", "Kestrel Strafer",
      (3.2, 1.05, 5.3), [], {"stub_w": 0.22, "stub_l": 0.30, "fin_h": 0.34}),
    H("kestrel_light_b", "kestrel", "light", "Kestrel Interceptor",
      (2.9, 1.00, 5.9), [], {"boom_frac": 0.44, "boom_z": 0.0,
                             "stub_w": 0.13, "fin_h": 0.40}),
    H("kestrel_light_c", "kestrel", "light", "Kestrel Tandem Trainer",
      (2.8, 1.25, 5.5), [], {"canopies": (-0.56, -0.10), "boom_frac": 0.50,
                             "fin_h": 0.36}),
    H("kestrel_medium_a", "kestrel", "medium", "Kestrel Gunship",
      (3.6, 1.50, 6.1), [],
      {"facet_cut": 0.22, "stub_w": 0.14, "fin_h": 0.34}),
    H("kestrel_medium_b", "kestrel", "medium", "Kestrel Bay Bomber",
      (3.5, 1.60, 6.5), [("trunk", {"th": 0.26, "w": 0.54, "z0": -0.40,
                                    "z1": 0.30})],
      {"boom_frac": 0.54, "fin_h": 0.36}),
    H("kestrel_heavy_a", "kestrel", "heavy", "Kestrel Heavy Lifter",
      (4.5, 1.95, 7.7), [],
      {"facet_cut": 0.20, "stub_w": 0.12, "stub_z": -0.44,
       "boom_frac": 0.60, "fin_h": 0.40}),
    H("kestrel_transport_a", "kestrel", "transport", "Kestrel Freighter",
      (3.8, 1.70, 8.7), [("well", {"z0": 0.28, "wall_h": 0.30, "w": 0.72})],
      {"boom_frac": 0.66, "boom_z": 0.52, "canopies": (-0.60,),
       "stub_w": 0.12, "fin_h": 0.38}),
    H("kestrel_oddball_a", "kestrel", "oddball", "Kestrel Twin Boom",
      (4.4, 1.62, 6.9), [],
      {"boom_frac": 0.46, "boom_z": -0.10, "fin": False, "stub_w": 0.20}),
    H("kestrel_oddball_b", "kestrel", "oddball", "Kestrel Flying Boat",
      (4.2, 1.65, 7.1), [],
      {"boom_frac": 0.56, "stub_w": 0.11, "fin_h": 0.40}, domain="Naval"),

    # -- BRENNTAL SCHWERBAU (13): mobile bunkers ------------------------
    H("brenntal_scout_a", "brenntal", "scout", "Brenntal Recon Casemate",
      (2.7, 1.10, 4.0), [], {"plinth_h": 0.58, "casemate_l": 0.46,
                             "glacis_z": 0.30}),
    H("brenntal_light_a", "brenntal", "light", "Brenntal Casemate Gun",
      (3.2, 1.05, 5.1), [], {"plinth_h": 0.72, "casemate_l": 0.40,
                             "casemate_w": 0.62, "glacis_z": 0.34}),
    H("brenntal_medium_a", "brenntal", "medium", "Brenntal Casemate Medium",
      (3.6, 1.40, 5.9), [], {"glacis_z": 0.26}),
    H("brenntal_medium_b", "brenntal", "medium", "Brenntal Turret Plinth",
      (3.8, 1.50, 6.1), [("barbette", {"z": 0.04, "r": 0.34, "bh": 0.22})],
      {"plinth_h": 0.62, "casemate_l": 0.44, "casemate_w": 0.64}),
    H("brenntal_medium_c", "brenntal", "medium", "Brenntal Command Stack",
      (3.7, 1.85, 6.0), [], {"tiers": 3, "plinth_h": 0.38,
                             "casemate_l": 0.52}),
    H("brenntal_heavy_a", "brenntal", "heavy", "Brenntal Breakthrough",
      (4.7, 1.90, 7.5), [("glacis", {})],
      {"glacis_z": 0.22}),
    H("brenntal_heavy_b", "brenntal", "heavy", "Brenntal Siege Casemate",
      (4.9, 2.20, 7.7), [], {"plinth_h": 0.30, "casemate_l": 0.86,
                             "casemate_w": 0.92, "casemate_z": 0.04}),
    H("brenntal_heavy_c", "brenntal", "heavy", "Brenntal Assault Gun",
      (4.5, 1.65, 7.9), [], {"plinth_h": 0.86, "casemate_l": 0.34,
                             "casemate_w": 0.54, "glacis_z": 0.46}),
    H("brenntal_heavy_d", "brenntal", "heavy", "Brenntal Fortress",
      (5.1, 2.05, 8.3), [],
      {"plinth_h": 0.50, "casemate_w": 0.66, "sponsons": False}),
    H("brenntal_transport_a", "brenntal", "transport", "Brenntal Armoured Carrier",
      (4.1, 1.60, 7.7), [], {"plinth_h": 0.62, "casemate_l": 0.88,
                             "casemate_w": 0.90, "casemate_z": 0.06}),
    H("brenntal_transport_b", "brenntal", "transport", "Brenntal Heavy Hauler",
      (4.3, 1.70, 8.5), [("well", {"z0": 0.06, "wall_h": 0.36, "w": 0.80})],
      {"plinth_h": 0.60, "casemate_l": 0.34, "casemate_z": -0.52}),
    H("brenntal_oddball_a", "brenntal", "oddball", "Brenntal Tandem Casemate",
      (4.3, 1.75, 7.9), [],
      {"casemate_l": 0.30, "casemate_z": -0.44, "glacis_z": 0.22}),
    H("brenntal_oddball_b", "brenntal", "oddball", "Brenntal Watch Stack",
      (3.3, 2.70, 5.1), [], {"tiers": 3, "plinth_h": 0.26,
                             "casemate_l": 0.40, "casemate_w": 0.58}),

    # -- TALLOW & VANCE (12): open spaceframes --------------------------
    H("tallow_scout_a", "tallow", "scout", "Tallow Runabout",
      (2.4, 1.05, 3.9), [], {"cab_l": 0.34, "beams": 2, "post_h": 0.26}),
    H("tallow_light_a", "tallow", "light", "Tallow Pickup",
      (2.8, 1.15, 4.9), [], {"cab_l": 0.30, "beams": 2}),
    H("tallow_light_b", "tallow", "light", "Tallow Gun Truck",
      (3.0, 1.25, 5.1), [("barbette", {"z": 0.34, "r": 0.28, "bh": 0.24})],
      {"cab_l": 0.26, "beams": 2, "rail_h": 0.14}),
    H("tallow_medium_a", "tallow", "medium", "Tallow Flatbed",
      (3.4, 1.25, 6.3), [], {"beams": 3}),
    H("tallow_medium_b", "tallow", "medium", "Tallow Stake Bed",
      (3.5, 1.60, 6.5), [("bolster", {"bh": 0.46, "z": (-0.06, 0.60)})],
      {"beams": 3, "rail_h": 0.34}),
    H("tallow_heavy_a", "tallow", "heavy", "Tallow Lowboy",
      (4.3, 1.40, 8.1), [], {"deck_h": 0.38, "deck_lift": 0.02, "beams": 4,
                             "cab_h": 0.90, "post_h": 0.30}),
    H("tallow_heavy_b", "tallow", "heavy", "Tallow Prime Mover",
      (4.1, 1.85, 7.1), [("ballast", {"z": 0.74, "h": 0.62, "w": 0.74})],
      {"cab_l": 0.38, "cab_h": 0.90, "beams": 2}),
    H("tallow_transport_a", "tallow", "transport", "Tallow Container Carrier",
      (3.9, 1.35, 8.9), [("flatbed", {"z0": -0.34, "z1": 0.96,
                                      "deck_h": 0.30, "rail_h": 0.22})],
      {"beams": 4, "cab_l": 0.22}),
    H("tallow_transport_b", "tallow", "transport", "Tallow Tanker Frame",
      (3.7, 1.75, 8.5), [("trunk", {"th": 0.40, "w": 0.62, "z0": -0.30})],
      {"beams": 4, "cab_l": 0.24}),
    H("tallow_transport_c", "tallow", "transport", "Tallow Bolster Hauler",
      (3.8, 1.80, 9.1), [("bolster", {"bh": 0.52, "z": (-0.10, 0.34, 0.78)})],
      {"beams": 4, "cab_l": 0.22, "rail_h": 0.12}),
    H("tallow_transport_d", "tallow", "transport", "Tallow Double Deck",
      (3.9, 2.10, 8.7), [("second_deck", {"lift": 0.46, "z0": -0.26})],
      {"beams": 3, "cab_l": 0.24}),
    H("tallow_oddball_a", "tallow", "oddball", "Tallow Gantry Rig",
      (4.1, 2.45, 7.5), [("gantry", {"gh": 0.62, "z": 0.30})],
      {"beams": 3, "cab_l": 0.22}),

    # -- ORRIN COLLECTIVE (8): symmetric salvage -----------------------
    H("orrin_scout_a", "orrin", "scout", "Orrin Skulker",
      (2.6, 1.10, 4.1), [],
      {"mass_w": 0.58, "spine_h": 0.20, "spine_w": 0.36,
       "spine_zc": 0.0, "spine_zw": 0.30}),
    H("orrin_scout_b", "orrin", "scout", "Orrin Spotter",
      (2.8, 1.40, 4.3), [],
      {"mass_w": 0.60, "mast_h": 0.52, "mast_w": 0.10,
       "mast_zc": 0.10, "mast_zw": 0.05}),
    H("orrin_light_a", "orrin", "light", "Orrin Raider",
      (3.3, 1.15, 5.3), [],
      {"mass_w": 0.56, "tumblehome_frac": 0.78}),
    H("orrin_medium_a", "orrin", "medium", "Orrin Bodge Tank",
      (3.7, 1.55, 6.1), [],
      {"mass_w": 0.62, "tumblehome_frac": 0.76,
       "spine_h": 0.16, "spine_w": 0.30,
       "spine_zc": 0.0, "spine_zw": 0.30}),
    H("orrin_heavy_a", "orrin", "heavy", "Orrin Wrecker",
      (4.9, 1.95, 7.7), [],
      {"mass_w": 0.58, "tumblehome_frac": 0.74,
       "spine_h": 0.18, "spine_w": 0.34,
       "spine_zc": 0.0, "spine_zw": 0.28}),
    H("orrin_transport_a", "orrin", "transport", "Orrin Scav Hauler",
      (4.3, 1.50, 8.1), [("flatbed", {"z0": -0.06, "w": 0.58})],
      {"mass_w": 0.60, "tumblehome_frac": 0.82}),
    H("orrin_oddball_a", "orrin", "oddball", "Orrin Crab",
      (5.1, 1.65, 6.3), [],
      {"mass_w": 0.44, "tumblehome_frac": 0.72,
       "spine_h": 0.24, "spine_w": 0.40,
       "spine_zc": 0.0, "spine_zw": 0.30}),
    H("orrin_oddball_b", "orrin", "oddball", "Orrin Twin Spine",
      (3.9, 1.85, 6.7), [],
      {"mass_w": 0.64, "tumblehome_frac": 0.78,
       "spine_h": 0.28, "spine_w": 0.36,
       "spine_zc": 0.0, "spine_zw": 0.32}),

    # -- RACKHAM FORGE (8): industrial crawler -------------------------
    H("rackham_scout_a", "rackham", "scout", "Rackham Prospector",
      (2.6, 1.30, 4.0), [],
      {"mast_h": 0.50, "mast_w": 0.10,
       "mast_zc": 0.20, "mast_zw": 0.05}),
    H("rackham_light_a", "rackham", "light", "Rackham Yard Truck",
      (3.0, 1.10, 4.9), [], {"boiler_l": 0.66, "boiler_h": 0.26,
                             "stack_h": 0.18}),
    H("rackham_light_b", "rackham", "light", "Rackham Boiler Carriage",
      (3.2, 1.20, 5.1), [], {"boiler_l": 0.74, "boiler_w": 0.54,
                             "boiler_h": 0.32}),
    H("rackham_medium_a", "rackham", "medium", "Rackham Forge Crawler",
      (3.7, 1.30, 6.1), [], {"boiler_l": 0.70, "boiler_w": 0.50,
                             "boiler_h": 0.30}),
    H("rackham_medium_b", "rackham", "medium", "Rackham Steam Lorry",
      (3.5, 1.45, 6.3), [("barbette", {"z": 0.30, "r": 0.30, "bh": 0.18})],
      {"boiler_l": 0.62, "boiler_w": 0.46, "boiler_h": 0.26}),
    H("rackham_heavy_a", "rackham", "heavy", "Rackham Iron Hulk",
      (4.5, 1.65, 7.5), [], {"boiler_l": 0.72, "boiler_w": 0.54,
                             "boiler_h": 0.30, "body_h": 0.58}),
    H("rackham_heavy_b", "rackham", "heavy", "Rackham Siege Engine",
      (4.7, 1.85, 7.7), [("barbette", {"z": 0.0, "r": 0.34, "bh": 0.20})],
      {"boiler_l": 0.66, "boiler_w": 0.50, "boiler_h": 0.28,
       "body_h": 0.60, "radiator": False}),
    H("rackham_transport_a", "rackham", "transport", "Rackham Coal Hauler",
      (3.9, 1.50, 8.5), [("flatbed", {"z0": -0.20, "z1": 0.96,
                                      "deck_h": 0.18, "rail_h": 0.26})],
      {"boiler_l": 0.46, "boiler_w": 0.40, "boiler_h": 0.24,
       "body_h": 0.66, "stack": False}),

    # -- CALDER MOBILITY (8): fast-attack wedge -----------------------
    H("calder_scout_a", "calder", "scout", "Calder Spotter",
      (2.4, 1.00, 4.1), [], {"body_w_min": 0.45, "body_h_min": 0.40,
                             "body_h_max": 0.72, "sponson_w": 0.14,
                             "sponson_zc": 0.10, "sponson_zw": 0.30}),
    H("calder_scout_b", "calder", "scout", "Calder Pathrunner",
      (2.2, 0.95, 4.3), [("mast", {"mh": 0.40, "z": 0.20, "vane": 0.36})],
      {"body_w_min": 0.40, "body_h_min": 0.42, "body_h_max": 0.66,
       "sponson_w": 0.10, "sponson_zc": 0.05, "sponson_zw": 0.28}),
    H("calder_light_a", "calder", "light", "Calder Striker",
      (2.9, 1.00, 5.0), [], {"body_w_min": 0.50, "body_h_min": 0.42,
                             "body_h_max": 0.74, "sponson_w": 0.18,
                             "sponson_zc": 0.05, "sponson_zw": 0.32}),
    H("calder_light_b", "calder", "light", "Calder Interceptor",
      (3.0, 1.10, 5.3), [], {"body_w_min": 0.52, "body_h_min": 0.46,
                             "body_h_max": 0.78, "sponson_w": 0.20,
                             "sponson_zc": 0.10, "sponson_zw": 0.30}),
    H("calder_light_c", "calder", "light", "Calder Skirmisher",
      (2.8, 1.20, 5.5), [],
      {"body_w_min": 0.50, "body_h_min": 0.44, "body_h_max": 0.76,
       "sponson_w": 0.18, "sponson_zc": 0.10, "sponson_zw": 0.32,
       "barbette_w": 0.36, "barbette_h": 0.16,
       "barbette_zc": 0.50, "barbette_zw": 0.05}),
    H("calder_medium_a", "calder", "medium", "Calder Racer",
      (3.4, 1.20, 5.9), [], {"body_w_min": 0.50, "body_h_min": 0.42,
                             "body_h_max": 0.78, "sponson_w": 0.22,
                             "sponson_zc": 0.05, "sponson_zw": 0.36,
                             "wing_w": 1.20}),
    H("calder_medium_b", "calder", "medium", "Calder Assault Car",
      (3.6, 1.35, 6.1), [],
      {"body_w_min": 0.52, "body_h_min": 0.44, "body_h_max": 0.80,
       "sponson_w": 0.22, "sponson_zc": 0.05, "sponson_zw": 0.38,
       "wing_w": 1.10,
       "barbette_w": 0.40, "barbette_h": 0.20,
       "barbette_zc": 0.30, "barbette_zw": 0.06}),
    H("calder_heavy_a", "calder", "heavy", "Calder Command Car",
      (4.0, 1.55, 6.9), [],
      {"body_w_min": 0.56, "body_h_min": 0.48, "body_h_max": 0.82,
       "sponson_w": 0.22, "sponson_zc": 0.05, "sponson_zw": 0.40,
       "wing_w": 1.20,
       "barbette_w": 0.42, "barbette_h": 0.22,
       "barbette_zc": 0.20, "barbette_zw": 0.06}),

    # -- PILLAR IRONWORKS (7): modular boxy ---------------------------
    H("pillar_medium_a", "pillar", "medium", "Pillar Cell Block",
      (3.6, 1.60, 6.0), [], {}),
    H("pillar_medium_b", "pillar", "medium", "Pillar Twin Stack",
      (3.8, 1.80, 6.3), [("barbette", {"z": 0.30, "r": 0.30, "bh": 0.20})], {}),
    H("pillar_heavy_a", "pillar", "heavy", "Pillar Slab",
      (4.5, 1.90, 7.5), [], {}),
    H("pillar_heavy_b", "pillar", "heavy", "Pillar Battlement",
      (4.7, 2.10, 7.7), [],
      {"barbette_w": 0.42, "barbette_h": 0.20,
       "barbette_zc": 0.20, "barbette_zw": 0.06}),
    H("pillar_transport_a", "pillar", "transport", "Pillar Container Carrier",
      (3.9, 1.50, 8.5), [("flatbed", {"z0": -0.20, "z1": 0.96,
                                      "deck_h": 0.18, "rail_h": 0.30})],
      {"transport_well": True}),
    H("pillar_transport_b", "pillar", "transport", "Pillar Heavy Hauler",
      (4.1, 1.70, 9.1), [("trunk", {"th": 0.34, "w": 0.58, "z0": -0.50})],
      {"transport_well": True}),
    H("pillar_transport_c", "pillar", "transport", "Pillar Twin Well",
      (4.3, 1.80, 8.9), [], {"transport_well": True}),
]


# ---------------------------------------------------------------------------
# Blender plumbing. Deliberately local rather than imported from
# build_meshes.py: that module's hull path is the one with the reflected axis
# helper, and this catalogue must not be able to pick it up by accident.
# ---------------------------------------------------------------------------

def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        if block.users == 0:
            bpy.data.meshes.remove(block)
    for block in list(bpy.data.materials):
        if block.users == 0:
            bpy.data.materials.remove(block)


def new_material(name, color, metallic, roughness):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (
            color[0], color[1], color[2], 1.0)
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = metallic
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = roughness
    return mat


def finalize_dual(obj, name, color):
    """Two material slots: 0 = structural, 1 = armour.

    hull_material_builder.gd's apply_hull_materials() overrides surface 0 with
    the structural material and surfaces 1+ with the armour material, so the
    slot ORDER here is load-bearing even though these colours never reach the
    game. Two genuinely distinct materials are also what makes Blender's glTF
    exporter emit two primitives.
    """
    obj.name = name
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    bpy.ops.object.shade_flat()
    obj.data.materials.append(
        new_material(name + "_structural_mat", color, 0.15, 0.82))
    obj.data.materials.append(
        new_material(name + "_armor_mat",
                     tuple(min(1.0, c * 1.14) for c in color[:3]), 0.75, 0.40))


def export_glb(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=path,
        use_selection=True,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
    )


def write_sidecar(out_dir, spec, size, color):
    """Sidecar schema per scripts/hull_loader.gd's REQUIRED_FIELDS + optionals."""
    sx, sy, sz = size
    volume = sx * (sy / HEIGHT_BOOST) * sz
    data = {
        "name": spec["name"],
        "hp": round(100.0 + volume * 20.0, 1),
        "weight": round(50.0 + volume * 15.0, 1),
        "metal": 20 + int(volume * 5.0),
        "crystal": 5 + int(volume * 1.0),
        "size": [round(sx, 3), round(sy, 3), round(sz, 3)],
        "color": [round(color[0], 3), round(color[1], 3), round(color[2], 3), 1.0],
        "domain": spec["domain"],
        "base_energy": round(30.0 + volume * 1.5, 1),
        "base_power": round(2.0 + volume * 0.12, 2),
        "base_vision": 20.0,
        "is_foundation": False,
        "category": "hull",
        "visual_yaw_offset_deg": 0.0,
        "visual_pitch_offset_deg": 0.0,
        "visual_roll_offset_deg": 0.0,
        "manufacturer": MANUFACTURERS[spec["mfr"]]["display"],
        "hull_class": spec["cls"].capitalize(),
    }
    with open(os.path.join(out_dir, spec["id"] + ".json"), "w") as f:
        json.dump(data, f, indent=2)
    return data


AUTOFIT_PASSES = 2


def build_geometry(spec, w, h, l):
    """Body + role elements into a fresh bmesh, at the given working size."""
    bm = bmesh.new()
    BODIES[spec["mfr"]](bm, w, h, l, spec["body"])
    for kind, params in spec["elements"]:
        ELEMENTS[kind](bm, w, h, l, params)
    return bm


def autofit(spec):
    """Solve for the working size whose natural AABB lands on the envelope."""
    target = spec["size"]
    work = list(target)
    natural = None
    for _ in range(AUTOFIT_PASSES):
        bm = build_geometry(spec, *work)
        _lo, natural = HF.measure(bm)
        bm.free()
        for i in range(3):
            if natural[i] > 1e-9:
                work[i] *= target[i] / natural[i]
    return tuple(work), natural


def build_one(spec, out_dir):
    w, h, l = spec["size"]
    work, _natural = autofit(spec)
    bm = build_geometry(spec, *work)

    factors = HF.normalize(bm, (w, h, l))
    HF.finish(bm)
    armour_faces = HF.mark_frontal_armour(bm, l / 2.0, front_frac=0.32)
    lo, size = HF.measure(bm)

    mesh = bpy.data.meshes.new(spec["id"] + "_mesh")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    obj = bpy.data.objects.new(spec["id"], mesh)
    bpy.context.collection.objects.link(obj)

    color = MANUFACTURERS[spec["mfr"]]["color"]
    finalize_dual(obj, spec["id"], color)
    export_glb(obj, os.path.join(out_dir, spec["id"] + ".glb"))
    sidecar = write_sidecar(out_dir, spec, size, color)

    mesh_data = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh_data and mesh_data.users == 0:
        bpy.data.meshes.remove(mesh_data)

    print("HULL %-24s aabb=(%.2f, %.2f, %.2f) min=(%.2f, %.2f, %.2f) "
          "fit=(%.3f, %.3f, %.3f) armour=%d hp=%.0f" % (
              spec["id"], size[0], size[1], size[2], lo[0], lo[1], lo[2],
              factors[0], factors[1], factors[2], armour_faces, sidecar["hp"]))
    return size


def parse_args():
    argv = sys.argv
    args = argv[argv.index("--") + 1:] if "--" in argv else []
    only, out_dir, do_list = None, HULLS_DIR, False
    i = 0
    while i < len(args):
        if args[i] == "--only" and i + 1 < len(args):
            only = set(args[i + 1].split(","))
            i += 2
        elif args[i] == "--out" and i + 1 < len(args):
            out_dir = args[i + 1]
            i += 2
        elif args[i] == "--list":
            do_list = True
            i += 1
        else:
            i += 1
    return only, out_dir, do_list


def validate_lineup():
    ids = [s["id"] for s in LINEUP]
    dupes = {i for i in ids if ids.count(i) > 1}
    if dupes:
        raise AssertionError("duplicate hull ids: %s" % sorted(dupes))
    for s in LINEUP:
        if s["mfr"] not in MANUFACTURERS:
            raise AssertionError("%s: unknown manufacturer %s" % (s["id"], s["mfr"]))
        if s["cls"] not in CLASSES:
            raise AssertionError("%s: unknown class %s" % (s["id"], s["cls"]))
        if not s["id"].replace("_", "").isalnum() or s["id"] != s["id"].lower():
            raise AssertionError(
                "%s: HullLoader requires lowercase snake_case [a-z0-9_]+" % s["id"])
        for kind, _p in s["elements"]:
            if kind not in ELEMENTS:
                raise AssertionError("%s: unknown element %s" % (s["id"], kind))
    missing = set(CLASSES) - {s["cls"] for s in LINEUP}
    if missing:
        raise AssertionError("classes with no hull: %s" % sorted(missing))


def main():
    HF.selftest_axis_determinant()
    validate_lineup()
    only, out_dir, do_list = parse_args()

    if do_list:
        for m in MANUFACTURERS:
            rows = [s for s in LINEUP if s["mfr"] == m]
            print("%-11s %2d  %s" % (
                m, len(rows),
                " ".join("%s:%d" % (c, len([r for r in rows if r["cls"] == c]))
                         for c in CLASSES
                         if any(r["cls"] == c for r in rows))))
        print("TOTAL %d hulls" % len(LINEUP))
        return

    os.makedirs(out_dir, exist_ok=True)
    specs = [s for s in LINEUP if only is None or s["id"] in only]
    print("Building %d hull(s) into %s" % (len(specs), out_dir))
    for spec in specs:
        clear_scene()
        build_one(spec, out_dir)
    print("DONE %d hull(s)" % len(specs))


main()
