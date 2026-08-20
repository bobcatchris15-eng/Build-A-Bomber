"""
Procedural material plates for the interface theme.

WHAT THIS PRODUCES, and why there are two kinds of output:

  assets/textures/ui/plate_<material>_<state>.png   128x128 RGBA
      A 96x96 opaque body inside a 16px transparent pad that carries the baked
      elevation shadow, so the 9-slice margin Godot must not stretch is
      MARGIN + PAD = 28px. Small repeated widgets - buttons, tabs, fields, list
      rows. These go into StyleBoxTexture, which is a thing a Theme resource can
      CARRY, so the whole game repaints from one theme rebuild with no call-site
      edits. That is the entire reason this pipeline exists.

      See the BAKED ELEVATION SHADOWS block below for why the shadow is in the
      PNG at all, and for the expand_margin_* setting in build_ui_theme.gd that
      this pad depends on.

  assets/textures/ui/field_<material>.png           512x512, seamless
      Large continuous surfaces - dock bodies, backdrops, the radial bezel -
      where a tiled 96px plate would show its repeat. Sampled by
      shaders/ui_material.gdshader at a FIXED PIXEL SCALE.

THE 9-SLICE TRAP, which is the one thing here that looks fine in a unit test
and wrong on screen: Godot stretches a StyleBoxTexture's centre region to fill
the control. So the centre must be flat and tileable, and every bevel, edge
highlight and outline must live ENTIRELY within the 12px margin. Bake a
top-edge highlight that bleeds into the centre and a wide button smears it
across its whole face. _apply_bevel() enforces this by only touching pixels
within MARGIN of an edge.

TILING: value noise here wraps (the control grid's last row/column is the
first), so both plate centres and fields are seamless. The non-wrapping
_value_noise in generate_effect_textures.py is fine for one-shot sprites and
would put a visible seam through every panel in the game.

MATERIAL VOCABULARY - see the plan and VISUAL_ART_DIRECTION.md. Six surfaces,
each assigned a job:
    powdercoat  panel and dock bodies, HUD chrome
    steel       frames, rails, splitters, toolbars
    moulded     buttons, tabs, toggles, radial ring
    canvas      drawer and flyout backing, tooltips
    carbon      primary action only - sparing
    fiberglass  hazard placards, alert states

NOTE ON THE NAME: "moulded" replaced "bakelite" in Phase 4. The surface was
dark marbled phenolic at first; it is now matte finely-stippled injection-
moulded ABS / powdercoated aluminium (see mat_moulded). The old key stuck
around through the original material pass because it appeared in 24 committed
PNG filenames, build_ui_theme.gd, ui_theme.gd's MATERIALS/MATERIAL_DEFAULTS
and the style guide - so the rename is its own commit rather than a side
effect of an appearance change.

Colours are the ui_tokens.gd palette. They are duplicated here as literals
because this is a build-time Python script that cannot import GDScript - if
the tokens move, these move with them. That coupling is stated rather than
hidden; TOKEN_REFERENCE below names the constant each one mirrors.

Run:  python tools/generate_ui_plates.py
Then: Godot_v4.7.1-stable_win64_console.exe --headless --editor --import
Then: Godot_v4.7.1-stable_win64_console.exe --headless --script tools/build_ui_theme.gd --quit-after 2
"""

import zlib

import numpy as np
from PIL import Image
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "assets" / "textures" / "ui"
OUT.mkdir(parents=True, exist_ok=True)

PLATE = 96
# How much of the plate Godot must not stretch (the 9-slice frame).
MARGIN = 12
# How far the bevel LIGHTING reaches in from the edge. Deliberately much
# smaller than MARGIN - see _apply_bevel() for why these are not the same
# number.
BEVEL_PX = 3.5
FIELD = 512

# ---------------------------------------------------------------------------
# BAKED ELEVATION SHADOWS
# ---------------------------------------------------------------------------
# WHY THE SHADOW IS BAKED INTO THE PNG rather than set on the stylebox:
# StyleBoxFlat has shadow_size/shadow_offset/shadow_color, but every panel
# variation in the theme is a StyleBoxTexture (see build_ui_theme.gd's
# _plate()), and StyleBoxTexture has NO shadow properties at all. Stacking a
# second shadow-only box behind it is not available either - Godot draws exactly
# one stylebox per control state, which build_ui_theme.gd already documents as
# the reason signal colours became material modulation instead of borders. So
# for a plate-backed surface the only place a shadow can live is the texture.
#
# THE TRANSPARENT PAD, and why the plate grew from 96 to 128: a stylebox is
# drawn inside the control's rect, so a shadow baked flush against the plate's
# edge would have nowhere to fall. The body stays 96x96 and gains a PAD ring of
# initially-transparent pixels around it for the shadow to occupy.
#
# THE PIECE THAT MUST NOT BE FORGOTTEN: build_ui_theme.gd has to set
# expand_margin_* = PAD alongside texture_margin_* = MARGIN + PAD. expand_margin
# lets the box draw OUTSIDE the control rect, which is what keeps the panel's
# content box and layout position exactly where they were. Without it every
# panel in the game visually shrinks by PAD on all four sides and every
# alignment in every screen shifts.
PAD = 16

# tier -> (blur radius px, downward offset px, peak alpha)
#
# Mirrors ui_tokens.gd's ELEVATION_* / SHADOW_OFFSET_* constants, under the same
# stated-not-hidden duplication rule as the colour literals above. "modal" is
# absent deliberately: no plate-backed variation is modal (dialogs use
# CardPanel), and a 24px spread would not fit inside PAD.
SHADOW_TIERS = {
    "flush": (0.0, 0.0, 0.00),
    "raised": (3.0, 1.0, 0.35),
    "floating": (8.0, 3.0, 0.45),
}

# (material, state) -> tier. This table is the load-bearing coupling to
# build_ui_theme.gd's variation assignments, so it is worth stating why it can
# be keyed this coarsely: every variation sharing a (material, state) also
# shares an elevation tier. powdercoat/normal backs Panel, CardPanel and
# DockPanel - all raised. canvas/normal backs FlyoutPanel and CalloutPanel -
# both floating. If a future variation needs a different tier from another
# variation on the same plate, this table stops being sufficient and the plate
# filenames have to carry the tier too.
#
# Every `pressed` state is flush by definition: a control that reads as pushed
# IN must not simultaneously cast a shadow claiming it stands proud. Same for
# `disabled`, which is meant to recede. `moulded` is the button material and
# stays raised-only - buttons sit in dense rows (the parts bin, the build bar),
# and a floating-strength shadow on each one turns a toolbar into mud.
SHADOW_ASSIGNMENT = {
    ("powdercoat", "normal"): "raised",
    ("powdercoat", "hover"): "raised",
    ("steel", "normal"): "raised",
    ("steel", "hover"): "raised",
    ("canvas", "normal"): "floating",
    ("canvas", "hover"): "floating",
    ("moulded", "normal"): "raised",
    ("moulded", "hover"): "raised",
    ("carbon", "normal"): "raised",
    ("carbon", "hover"): "raised",
    ("fiberglass", "normal"): "raised",
    ("fiberglass", "hover"): "raised",
    # The dock shell is a physical box sitting on the screen, not a control
    # resting on a panel, so it casts the heaviest tier available.
    ("toolbox", "normal"): "floating",
    ("toolbox", "hover"): "floating",
    # Bakelite desk surface - raised like powdercoat panels.
    ("bakelite", "normal"): "raised",
    ("bakelite", "hover"): "raised",
}

# Warm near-black, matching ui_tokens.gd SHADOW_COLOR. A neutral or cool shadow
# on this warm palette reads as grime rather than as absence of light.
SHADOW_RGB = (0.035, 0.032, 0.026)

# Fixed seed: these are committed artifacts, so a rerun must not silently
# produce a different-looking interface.
RNG = np.random.default_rng(20260802)

# Mirrors ui_tokens.gd. (constant name -> linear 0..1 RGB)
TOKEN_REFERENCE = {
    "BASE_900": (0.075, 0.074, 0.068),
    "BASE_800": (0.108, 0.106, 0.098),
    "BASE_700": (0.145, 0.142, 0.131),
    "BASE_600": (0.196, 0.190, 0.174),
    "BASE_500": (0.290, 0.281, 0.257),
    "BASE_400": (0.404, 0.392, 0.360),
}


# ---------------------------------------------------------------------------
# Noise
# ---------------------------------------------------------------------------

def _tileable_value_noise(h, w, res_y, res_x, rng):
    """
    One octave of value noise that wraps at both edges.

    The wrap is the whole point: the control grid is generated at
    (res_y, res_x) and then its first row/column is COPIED to the far edge, so
    interpolation across the boundary lands back on the same values. Without
    this every panel in the game carries a visible seam where the texture
    repeats.
    """
    grid = rng.random((res_y + 1, res_x + 1))
    grid[-1, :] = grid[0, :]
    grid[:, -1] = grid[:, 0]

    ys = np.linspace(0, res_y, h, endpoint=False)
    xs = np.linspace(0, res_x, w, endpoint=False)
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    fy = ys - y0
    fx = xs - x0
    # Smoothstep easing, so stacked octaves don't show the control lattice.
    fy = (fy * fy * (3 - 2 * fy))[:, None]
    fx = (fx * fx * (3 - 2 * fx))[None, :]

    v00 = grid[np.ix_(y0, x0)]
    v01 = grid[np.ix_(y0, x0 + 1)]
    v10 = grid[np.ix_(y0 + 1, x0)]
    v11 = grid[np.ix_(y0 + 1, x0 + 1)]
    top = v00 * (1 - fx) + v01 * fx
    bot = v10 * (1 - fx) + v11 * fx
    return top * (1 - fy) + bot * fy


def fbm(h, w, octaves=5, base=4, rng=None, aniso=1.0):
    """
    Seamless fractal noise, normalised to 0..1.

    `aniso` > 1 uses proportionally fewer control points HORIZONTALLY, which
    stretches features along X into horizontal streaks - brushed-metal grain.

    The direction is worth stating because it is easy to get backwards and the
    first version of this did: fewer control points along an axis means
    features are LONGER along that axis. Brush grain on a panel runs across it
    horizontally, so it is res_x that has to shrink, not res_y. The earlier
    version divided res_y and produced vertical striations that read as a
    corrugated shutter rather than as a brushed finish.
    """
    rng = rng or RNG
    total = np.zeros((h, w))
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        f = base * 2 ** o
        rx = max(1, int(round(f / aniso)))
        total += amp * _tileable_value_noise(h, w, f, rx, rng)
        norm += amp
        amp *= 0.5
    out = total / norm
    return (out - out.min()) / (np.ptp(out) + 1e-9)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0 + 1e-9), 0, 1)
    return t * t * (3 - 2 * t)


def _coords(h, w):
    """Pixel coordinate grids."""
    yy, xx = np.mgrid[0:h, 0:w]
    return yy.astype(float), xx.astype(float)


# ---------------------------------------------------------------------------
# Materials
#
# Each returns (rgb, gloss) where rgb is HxWx3 in 0..1 and gloss is HxW in
# 0..1. Gloss only modulates how hard the bevel highlight reads - it is not a
# real specular term, and pretending otherwise in a 2D UI is how panels end up
# looking like plastic toys.
# ---------------------------------------------------------------------------

def mat_powdercoat(h, w, rng):
    """Olive-grey enamel over steel. Matte, fine orange-peel stipple."""
    # Orange peel: high-frequency, low-amplitude, ISOTROPIC. The dimpling is
    # the signature of powder that flowed before it cured, and it is what
    # separates this from flat paint.
    peel = fbm(h, w, octaves=3, base=24, rng=rng)
    # Brush grain of the substrate telegraphing faintly through the coat.
    grain = fbm(h, w, octaves=3, base=8, rng=rng, aniso=14.0)
    # Broad unevenness in coat thickness.
    roll = fbm(h, w, octaves=2, base=2, rng=rng)

    # BASE_800, the palette's "panel body". Was 0.150/0.148/0.132 (luminance
    # 0.147, i.e. BASE_700) which is the RAISED CONTROL value - so panels and
    # buttons were competing for the same tier. Dropping panels to BASE_800
    # while moulded rises to BASE_700 is what opens the gap that lets a button
    # read as sitting on a panel rather than in it. Still comfortably above the
    # backdrop, which lands near 0.084 (steel field x apply_backdrop's 0.42
    # brightness), so the floor/surface/control stack stays strictly ascending.
    base = np.array([0.112, 0.110, 0.098])
    lum = 1.0 + (peel - 0.5) * 0.14 + (grain - 0.5) * 0.05 + (roll - 0.5) * 0.10
    rgb = base[None, None, :] * lum[:, :, None]
    gloss = np.full((h, w), 0.22) + (peel - 0.5) * 0.10
    return rgb, gloss


def mat_steel(h, w, rng):
    """Brushed mill-finish steel. Strong directional grain."""
    # aniso 40 is extreme on purpose: brushed metal is nearly pure streak, and
    # anything less reads as "noisy grey" rather than as a grain direction.
    grain = fbm(h, w, octaves=5, base=6, rng=rng, aniso=40.0)
    fine = fbm(h, w, octaves=2, base=64, rng=rng, aniso=30.0)
    roll = fbm(h, w, octaves=2, base=3, rng=rng)

    base = np.array([0.205, 0.200, 0.188])
    lum = 1.0 + (grain - 0.5) * 0.34 + (fine - 0.5) * 0.10 + (roll - 0.5) * 0.08
    rgb = base[None, None, :] * lum[:, :, None]
    gloss = np.full((h, w), 0.55) + (grain - 0.5) * 0.25
    return rgb, gloss


def mat_moulded(h, w, rng):
    """
    Injection-moulded ABS / powdercoated aluminium. Matte, finely stippled.

    WAS dark marbled phenolic - a low-frequency swirl at semi-gloss. The swirl
    was the problem: at button size a 3-cycle marble reads as a smear or a stain
    rather than as a surface finish, and it fought every label sitting on it. A
    moulded control's finish is uniform by construction, so the character has to
    come from a FINE even stipple, not from large-scale figure.

    HOW THIS STAYS DISTINCT FROM mat_powdercoat, which is also matte and also
    stippled: powdercoat is a sprayed coating over brushed metal, so it carries
    an anisotropic substrate grain and a broad thickness roll - the coat is
    visibly uneven. This is a moulded polymer, which is dimensionally even by
    nature: no directional grain and no broad undulation at all, just a dense
    isotropic bead-blast stipple at roughly twice the frequency. Side by side the
    panel looks sprayed and the button looks moulded, which is the correct
    relationship - a faceplate fitted into a coated chassis.
    """
    # Bead-blasted mould finish. Deliberately much higher frequency than
    # powdercoat's orange peel (base 48 vs 24) and lower amplitude: the flecks
    # should be at the threshold of resolution so they read as tooth rather than
    # as noise. Isotropic - a mould cavity has no grain direction.
    stipple = fbm(h, w, octaves=4, base=48, rng=rng)
    # A second, finer pass. Two scales of fleck is what keeps the stipple from
    # looking like a regular screen pattern once the plate is tiled.
    micro = fbm(h, w, octaves=2, base=96, rng=rng)

    # BASE_700, the token palette's "raised control body". This was 0.085/0.073/
    # 0.066 - luminance 0.075, which is exactly BASE_900, the value reserved for
    # the DEEPEST RECESS and the modal scrim. Buttons were therefore rendered
    # darker than the powdercoat panels they sit on, and a control darker than
    # its own container cannot read as raised however good its bevel is. It also
    # flattened every state: at base 0.075 the x1.18 hover reached 0.089, an
    # absolute delta of 0.014, which is invisible. The luminance stack now
    # ascends the way the palette intends - backdrop, then panel, then control.
    #
    # Named "moulded" rather than the historical "bakelite" because the surface
    # is no longer dark marbled phenolic. See the material vocabulary comment
    # at the top of this file.
    #
    # Neutral warm grey, NOT the old brown. Phenolic goes amber where it is thin;
    # ABS and powdercoated aluminium do not go anywhere - they are one colour all
    # the way through, so the red-channel warming the old version applied to its
    # marbling is gone with the marbling.
    base = np.array([0.152, 0.144, 0.134])
    lum = 1.0 + (stipple - 0.5) * 0.085 + (micro - 0.5) * 0.045
    rgb = base[None, None, :] * lum[:, :, None]
    # Matte. 0.30 against powdercoat's 0.22 - a moulded polymer has slightly more
    # sheen than cured powder, but nowhere near the old 0.62 semi-gloss, which is
    # what made these read as shiny toy plastic. Gloss only modulates how hard
    # the bevel highlight reads (see the section header above), so dropping it
    # this far is what actually turns the edge from a glint into a chamfer.
    gloss = np.full((h, w), 0.30) + (stipple - 0.5) * 0.08
    return rgb, gloss


def mat_bakelite(h, w, rng):
    """
    Warm bakelite/phenolic plastic. The commander's desk surface.

    Dark marbled phenolic with fine isotropic stipple. Unlike the moulded
    polymer (mat_moulded), bakelite has visible depth - a subtle low-frequency
    marble/swirl from the resin flow during curing, plus a fine bead-blast
    texture. It is warmer (amber-biased) than the neutral greys of steel and
    powdercoat, and reads as an aged, authoritative surface.
    """
    # Low-frequency marble/swirl from resin flow - the signature of phenolic.
    marble = fbm(h, w, octaves=3, base=4, rng=rng)
    # Fine isotropic stipple - bead blasted finish.
    stipple = fbm(h, w, octaves=4, base=48, rng=rng)
    micro = fbm(h, w, octaves=2, base=96, rng=rng)

    # Warm dark amber-brown base. BASE_800 warmed toward amber.
    base = np.array([0.125, 0.105, 0.075])
    lum = 1.0 + (marble - 0.5) * 0.18 + (stipple - 0.5) * 0.085 + (micro - 0.5) * 0.045
    rgb = base[None, None, :] * lum[:, :, None]
    # Slight sheen - cured phenolic has a subtle gloss.
    gloss = np.full((h, w), 0.35) + (stipple - 0.5) * 0.10
    return rgb, gloss


def mat_canvas(h, w, rng):
    """Cotton duck. Visible warp/weft weave, matte."""
    yy, xx = _coords(h, w)
    # Weave period must DIVIDE the texture size or the plate will not tile.
    # 6px at both 96 and 512 satisfies that (96/6=16, 512/6 is not integer) -
    # so derive the period from the size instead of hardcoding it.
    period = 6 if w % 6 == 0 else 8
    warp = (np.sin(xx / period * np.pi * 2.0) * 0.5 + 0.5) ** 1.6
    weft = (np.sin(yy / period * np.pi * 2.0) * 0.5 + 0.5) ** 1.6
    # Alternating over/under: which thread is on top flips every half period.
    over = ((np.floor(xx / period) + np.floor(yy / period)) % 2).astype(float)
    weave = warp * over + weft * (1.0 - over)

    slub = fbm(h, w, octaves=3, base=10, rng=rng)   # thread thickness variation
    dirt = fbm(h, w, octaves=3, base=4, rng=rng)

    base = np.array([0.128, 0.121, 0.103])
    lum = 0.86 + weave * 0.26 + (slub - 0.5) * 0.12 + (dirt - 0.5) * 0.10
    rgb = base[None, None, :] * lum[:, :, None]
    gloss = np.full((h, w), 0.08)
    return rgb, gloss


def mat_carbon(h, w, rng):
    """2x2 twill carbon fibre. Tight, regular, dark."""
    yy, xx = _coords(h, w)
    period = 8 if w % 8 == 0 else 6
    half = period / 2.0
    # 2x2 twill: blocks alternate weave direction on a checker of half-period
    # cells, and within a block the tow runs diagonally.
    cell_x = np.floor(xx / half)
    cell_y = np.floor(yy / half)
    diag = ((cell_x + cell_y) % 2).astype(float)
    tow_a = np.sin((xx + yy) / period * np.pi * 2.0) * 0.5 + 0.5
    tow_b = np.sin((xx - yy) / period * np.pi * 2.0) * 0.5 + 0.5
    weave = tow_a * diag + tow_b * (1.0 - diag)
    # Individual filaments within each tow.
    filament = fbm(h, w, octaves=2, base=48, rng=rng, aniso=8.0)

    # Lifted from 0.072 (BASE_900) to BASE_800. Carbon backs PrimaryButton, and
    # once moulded rose to BASE_700 a BASE_900 carbon made the PRIMARY action
    # the darkest control on the screen - it receded behind every ordinary
    # button, which is precisely backwards. It still reads as the dark premium
    # material (it stays the darkest of the control materials, below moulded),
    # and _plate_tinted's green cast lands it around panel luminance rather than
    # below it. Cool-biased blue channel kept: carbon weave is never warm.
    base = np.array([0.104, 0.104, 0.112])
    lum = 0.80 + weave * 0.55 + (filament - 0.5) * 0.10
    rgb = base[None, None, :] * lum[:, :, None]
    gloss = np.full((h, w), 0.72) + weave * 0.20
    return rgb, gloss


def mat_fiberglass(h, w, rng):
    """Translucent resin over chopped glass mat. Milky, slightly warm."""
    # Chopped strand mat: long thin strands at random angles. Approximated by
    # summing a few strongly anisotropic noise fields at different rotations,
    # which is cheap and reads correctly at this scale.
    strands = np.zeros((h, w))
    for _ in range(3):
        strands += fbm(h, w, octaves=3, base=8, rng=rng, aniso=18.0)
    strands /= 3.0
    # Resin pooling - the milky variation that sits ON TOP of the mat.
    resin = fbm(h, w, octaves=3, base=3, rng=rng)

    base = np.array([0.178, 0.170, 0.152])
    lum = 0.90 + (strands - 0.5) * 0.30 + (resin - 0.5) * 0.16
    rgb = base[None, None, :] * lum[:, :, None]
    # Warm it - GRP is never neutral grey, it yellows.
    rgb[:, :, 0] *= 1.06
    rgb[:, :, 1] *= 1.01
    gloss = np.full((h, w), 0.40) + (resin - 0.5) * 0.15
    return rgb, gloss


def mat_toolbox(h, w, rng):
    """
    Faded oxide-red enamel over steel, chipped and scratched back to bare metal.

    The Design Lab's parts dock, and nothing else. It is the one surface in the
    game that is supposed to read as a specific OBJECT - a beaten mechanic's
    toolbox the player keeps their parts in - rather than as neutral chrome, so
    it is the one material allowed to carry a hue of its own.

    WHY THE RED IS THIS DULL. UI_STYLE_GUIDE.md:15 reserves red for damage and
    destructive actions, and the dock is a large surface that must not read as
    an alert. The separation is carried by VALUE and SATURATION, not by hue:
    SIGNAL_ALERT is (0.784, 0.267, 0.196), this enamel sits at roughly a third
    of that luminance and well under its saturation, which is the difference
    between "aged brick" and "warning lamp". Anything brighter here and a real
    alert has nothing left to be.

    WHY THE CHIPS ARE HARD-EDGED. Paint is either on the steel or off it. The
    existing wear_amount in ui_material.gdshader is a luminance scuff - it
    brightens the coat but never breaks it - which is convincing for rubbed
    powdercoat and completely unconvincing for a chipped toolbox, because a chip
    is a DIFFERENT MATERIAL showing through with a crisp boundary. That is why
    this is a material rather than a wear setting: the bare-steel layer has to
    exist underneath before anything can be chipped off to reveal it.
    """
    # ---- The steel underneath -------------------------------------------
    # Duller and darker than mat_steel: this is the inside of a chip, not a
    # brushed face. It has oxidised slightly and it never gets polished.
    under_grain = fbm(h, w, octaves=4, base=8, rng=rng, aniso=22.0)
    under = np.array([0.225, 0.212, 0.196])[None, None, :] * (
        1.0 + (under_grain - 0.5) * 0.30
    )[:, :, None]

    # ---- The enamel ------------------------------------------------------
    # Brush-applied, so it carries broad thickness variation rather than the
    # isotropic orange-peel dimple of a powder coat.
    lay = fbm(h, w, octaves=3, base=6, rng=rng, aniso=9.0)
    roll = fbm(h, w, octaves=2, base=2, rng=rng)
    chalk = fbm(h, w, octaves=3, base=20, rng=rng)

    enamel_base = np.array([0.300, 0.145, 0.115])
    lum = 1.0 + (lay - 0.5) * 0.16 + (roll - 0.5) * 0.14 + (chalk - 0.5) * 0.07
    enamel = enamel_base[None, None, :] * lum[:, :, None]
    # Sun-bleached coats lose their red before they lose their darkness, so the
    # thinnest, most exposed enamel desaturates toward the substrate rather than
    # simply getting lighter.
    bleach = smoothstep(0.55, 1.0, roll)[:, :, None]
    enamel = enamel * (1.0 - bleach * 0.30) + enamel.mean(
        axis=2, keepdims=True
    ) * bleach * 0.30

    # ---- Chips -----------------------------------------------------------
    # Two frequencies multiplied: a broad "this corner of the box gets knocked"
    # zone, times the individual chip shapes. Without the zone term the chips
    # scatter evenly and read as noise or as a disease; real wear is clustered.
    #
    # BOTH FREQUENCIES MATTER AND THE FIRST PASS GOT THEM WRONG. At base 14 the
    # chip shapes were the same scale as the wear zones, so the two multiplied
    # into continent-sized blobs that read as camouflage. Chips have to be an
    # order of magnitude smaller than the zone that clusters them - base 3 for
    # "which end of the box gets knocked", base 30 for the chips themselves.
    zone = fbm(h, w, octaves=2, base=3, rng=rng)
    chips = fbm(h, w, octaves=4, base=30, rng=rng)
    # The zone gates the chips rather than merely scaling them: raised to a
    # power it is near zero across most of the panel, so paint survives
    # everywhere except the few places that actually take knocks.
    chip_field = chips * (0.25 + smoothstep(0.40, 0.95, zone) * 1.15)
    # A DELIBERATELY NARROW smoothstep band. This is the crisp paint boundary -
    # widen it and the chips turn into soft blotches that read as staining.
    chip_mask = smoothstep(0.615, 0.645, chip_field)
    # The lip of a chip: paint that has lifted but not yet flaked, slightly
    # darker than the coat because it is shadowed and dirt has crept under it.
    lip_mask = smoothstep(0.585, 0.615, chip_field) * (1.0 - chip_mask)

    # ---- Scratches -------------------------------------------------------
    # Long, thin, and shallow - these cut the gloss and skim the metal, they do
    # not remove the coat the way a chip does. Two passes at different angles so
    # the surface does not read as combed in one direction.
    #
    # THRESHOLDED HIGH AND NARROW. At 0.78 these came through as broad bands
    # spanning the full width, which read as scanlines across the panel rather
    # than as scratches on it. A scratch is a rare, thin, incidental mark: only
    # the very top of the noise range should survive, and the anisotropy has to
    # stay off the extreme end or every mark runs edge to edge.
    # THINNESS COMES FROM `base`, LENGTH COMES FROM `aniso`, and they have to be
    # pushed together. `base` is the cell count down Y, so it alone sets how
    # thin a mark can be; `aniso` divides the cell count across X, so it alone
    # sets how far one runs. Moderate values of either give the fat lozenges
    # this produced twice - once as multi-octave smears, once as single-octave
    # blobs. A scratch is ~1px of Y over most of a panel of X, which means a
    # high base AND a high aniso, single octave so nothing broad rides beneath.
    scr_a = fbm(h, w, octaves=1, base=110, rng=rng, aniso=36.0)
    scr_b = fbm(h, w, octaves=1, base=150, rng=rng, aniso=52.0)
    scratch = np.maximum(
        smoothstep(0.90, 0.94, scr_a), smoothstep(0.91, 0.95, scr_b) * 0.7
    )
    # A scratch never shows on a surface that has already lost its paint.
    scratch = scratch * (1.0 - chip_mask)

    # ---- Composite -------------------------------------------------------
    rgb = enamel * (1.0 - lip_mask[:, :, None] * 0.35)
    rgb = rgb * (1.0 - chip_mask[:, :, None]) + under * chip_mask[:, :, None]
    # Scratched enamel shows a bright metal skim, brighter than bare chip steel
    # because it is freshly abraded rather than dulled.
    rgb = rgb + (scratch * 0.10)[:, :, None]

    # Bare steel is glossier than a chalky aged coat, which is what makes the
    # bevel catch differently across a chip edge and sells the depth.
    gloss = np.full((h, w), 0.26) + chip_mask * 0.34 + scratch * 0.20
    return rgb, gloss


MATERIALS = {
    "powdercoat": mat_powdercoat,
    "steel": mat_steel,
    "moulded": mat_moulded,
    "canvas": mat_canvas,
    "carbon": mat_carbon,
    "fiberglass": mat_fiberglass,
    "toolbox": mat_toolbox,
    "bakelite": mat_bakelite,
}


# ---------------------------------------------------------------------------
# Plate assembly
# ---------------------------------------------------------------------------

# state -> (overall brightness, bevel direction, bevel strength)
#
# `bevel` +1 lights the TOP edge (a raised control) and -1 lights the BOTTOM
# (a depressed one). Flipping the light direction rather than merely darkening
# the fill is what makes a pressed control read as physically pushed in - it
# is the same cue build_ui_theme.gd already gets from swapping border widths,
# and the two reinforce each other.
# Gaps widened from 1.18/0.82 to 1.28/0.74. The old spread was chosen when
# moulded (then called bakelite) sat at luminance 0.075, where even a large
# multiplier moved the absolute value almost not at all; now that controls
# start at BASE_700 the multiplier translates into a delta the eye actually
# resolves (~0.041 up on hover, ~0.038 down on press, against ~0.014 before).
#
# Bevel strength rises with the state too, not just brightness. A hover that
# only brightens reads as a lighting change on a flat card; a hover that also
# sharpens the chamfer reads as the control physically catching more light.
STATES = {
    "normal":   (1.00, +1.0, 1.00),
    "hover":    (1.28, +1.0, 1.30),
    "pressed":  (0.74, -1.0, 1.10),
    "disabled": (0.62, +1.0, 0.30),
}


def _apply_bevel(rgb, gloss, direction, strength):
    """
    Lights the margin ring only. The centre is left untouched so it stays flat
    and tileable when Godot stretches it - see the 9-slice trap in the module
    docstring.
    """
    h, w = gloss.shape
    yy, xx = _coords(h, w)
    d_top = yy
    d_bottom = h - 1 - yy
    d_left = xx
    d_right = w - 1 - xx
    d_edge = np.minimum(np.minimum(d_top, d_bottom), np.minimum(d_left, d_right))

    # Falls from 1 at the outermost pixel to 0 at BEVEL_PX, so it is exactly
    # zero everywhere the centre region will be sampled.
    #
    # BEVEL_PX, NOT MARGIN. These are two different things and conflating them
    # was the first version's mistake: MARGIN (12px) is how much of the plate
    # Godot must not stretch, while the bevel is how far the LIGHT falls, and
    # a light ramp that fills the whole 12px margin produces a fat soft pillow
    # that reads as a glossy web button from 2005. ui_tokens.gd asks for
    # "a barely-broken edge" on stamped and machined panels - so the bevel is
    # tight and hard, and the rest of the margin is simply flat material that
    # happens not to be stretched.
    ramp = 1.0 - smoothstep(0.0, float(BEVEL_PX), d_edge)
    # Bias toward the hard end: a linear-ish ramp still reads as a gradient,
    # whereas squaring the falloff concentrates the contrast at the very edge
    # where a machined chamfer actually catches light.
    ramp = ramp ** 1.8

    # Which edge each margin pixel belongs to decides its sign. Top and left
    # catch light; bottom and right fall away. Left/right are weaker because a
    # panel lit from above has far less side contrast than top/bottom.
    is_top = (d_top <= d_bottom) & (d_top <= d_left) & (d_top <= d_right)
    is_bottom = (d_bottom < d_top) & (d_bottom <= d_left) & (d_bottom <= d_right)
    is_left = (d_left < d_top) & (d_left < d_bottom) & (d_left <= d_right)

    sign = np.where(is_top, 1.0,
           np.where(is_bottom, -1.0,
           np.where(is_left, 0.45, -0.45)))

    amount = ramp * sign * direction * strength * (0.30 + gloss * 0.55)
    out = rgb * (1.0 + amount[:, :, None])

    # A hard 1px outline at the very edge. Without it the bevel fades into
    # whatever is behind the control and adjacent widgets bleed together.
    edge = (d_edge < 1.0)
    out[edge] *= 0.42
    return out


def _box_blur(a, radius):
    """
    Separable box blur, run three times to approximate a Gaussian.

    Hand-rolled because scipy is not a dependency of this pipeline and pulling
    one in for a single blur would make a committed-artifact script harder to
    reproduce. Three box passes is the standard cheap Gaussian approximation and
    is indistinguishable from one at these radii.
    """
    r = int(round(radius))
    if r < 1:
        return a
    k = 2 * r + 1
    out = a
    for _ in range(3):
        # Pad with zeros: outside the plate there is no shadow to smear inward,
        # and edge-replicate padding would drag the shadow out to the border and
        # square off the corners.
        p = np.pad(out, ((r, r), (0, 0)), mode="constant")
        c = np.cumsum(p, axis=0)
        c = np.pad(c, ((1, 0), (0, 0)), mode="constant")
        out = (c[k:, :] - c[:-k, :]) / k
        p = np.pad(out, ((0, 0), (r, r)), mode="constant")
        c = np.cumsum(p, axis=1)
        c = np.pad(c, ((0, 0), (1, 0)), mode="constant")
        out = (c[:, k:] - c[:, :-k]) / k
    return out


def _shadow_alpha(tier):
    """
    The shadow's alpha channel over the full padded canvas.

    The caster is the plate body: a hard PLATE-sized rectangle inset by PAD,
    pushed down by the tier's offset, then blurred. Returns zeros for a flush
    tier so callers do not have to branch.
    """
    size = PLATE + 2 * PAD
    blur, offset, peak = SHADOW_TIERS[tier]
    if peak <= 0.0:
        return np.zeros((size, size), dtype=np.float64)

    caster = np.zeros((size, size), dtype=np.float64)
    top = PAD + int(round(offset))
    caster[top:top + PLATE, PAD:PAD + PLATE] = 1.0

    a = _box_blur(caster, blur)
    # Normalise before scaling: three box passes lose a little peak amplitude at
    # the centre, so scaling the raw result would make larger blurs quietly
    # fainter than their configured alpha rather than merely softer.
    m = a.max()
    if m > 0.0:
        a = a / m
    return np.clip(a * peak, 0.0, 1.0)


def build_plate(material, state, rng):
    """
    Returns (rgb, alpha) over the padded canvas.

    The opaque 96x96 body sits centred in a PAD ring that carries only the
    baked shadow. Material generation and bevelling still run at exactly PLATE
    resolution - the pad is composited around the result rather than being fed
    through the material functions, so the noise stays tileable and the bevel
    still lands on the body's real edge instead of PAD pixels away from it.
    """
    fn = MATERIALS[material]
    rgb, gloss = fn(PLATE, PLATE, rng)
    brightness, direction, strength = STATES[state]
    rgb = rgb * brightness
    rgb = _apply_bevel(rgb, gloss, direction, strength)
    body = np.clip(rgb, 0.0, 1.0)

    size = PLATE + 2 * PAD
    tier = SHADOW_ASSIGNMENT.get((material, state), "flush")
    alpha = _shadow_alpha(tier)

    out_rgb = np.empty((size, size, 3), dtype=np.float64)
    out_rgb[:, :] = SHADOW_RGB
    out_rgb[PAD:PAD + PLATE, PAD:PAD + PLATE] = body

    # The body is fully opaque regardless of what the shadow ramp says under it.
    alpha[PAD:PAD + PLATE, PAD:PAD + PLATE] = 1.0
    return out_rgb, alpha


def build_field(material, rng):
    fn = MATERIALS[material]
    rgb, _gloss = fn(FIELD, FIELD, rng)
    return np.clip(rgb, 0.0, 1.0)


def save(arr, path, alpha=None):
    """
    Writes RGB, or RGBA when an alpha channel is supplied.

    Plates are RGBA now because the baked elevation shadow needs the pad ring to
    be transparent; fields stay RGB, since they are sampled as opaque surface
    texture by ui_material.gdshader and an alpha channel there would only cost
    memory.
    """
    rgb = (arr * 255.0 + 0.5).astype(np.uint8)
    if alpha is None:
        img = Image.fromarray(rgb, mode="RGB")
    else:
        a = (alpha * 255.0 + 0.5).astype(np.uint8)
        img = Image.fromarray(np.dstack([rgb, a]), mode="RGBA")
    img.save(path)


def _seed(name):
    """
    Stable per-material seed.

    NOT hash() - Python randomises string hashing per process unless
    PYTHONHASHSEED is set, so hash("steel") differs between runs and every
    rerun of this script would produce a subtly different interface. These
    PNGs are committed artifacts; a rebuild has to be a no-op in the diff.
    """
    return zlib.crc32(name.encode("utf-8"))


def main():
    print(f"Writing UI material plates -> {OUT}")
    for material in MATERIALS:
        # The RNG is re-seeded identically for every state, so all four states
        # of a material share the SAME underlying surface and differ only by
        # lighting. Without that a button visibly changes its grain on hover,
        # which reads as a texture pop rather than as a light change.
        for state in STATES:
            rng = np.random.default_rng(_seed(material))
            arr, alpha = build_plate(material, state, rng)
            save(arr, OUT / f"plate_{material}_{state}.png", alpha)
        rng = np.random.default_rng(_seed(material) + 7)
        save(build_field(material, rng), OUT / f"field_{material}.png")
        print(f"  {material}: 4 plates + 1 field")

    total = len(MATERIALS) * (len(STATES) + 1)
    print(f"\n{total} texture(s) written.")


if __name__ == "__main__":
    main()
