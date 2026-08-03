"""
Procedural material plates for the interface theme.

WHAT THIS PRODUCES, and why there are two kinds of output:

  assets/textures/ui/plate_<material>_<state>.png   96x96, 12px 9-slice margin
      Small repeated widgets - buttons, tabs, fields, list rows. These go into
      StyleBoxTexture, which is a thing a Theme resource can CARRY, so the
      whole game repaints from one theme rebuild with no call-site edits. That
      is the entire reason this pipeline exists.

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
    bakelite    buttons, tabs, toggles, radial ring
    canvas      drawer and flyout backing, tooltips
    carbon      primary action only - sparing
    fiberglass  hazard placards, alert states

Colours are the ui_tokens.gd palette. They are duplicated here as literals
because this is a build-time Python script that cannot import GDScript - if
the tokens move, these move with them. That coupling is stated rather than
hidden; TOKEN_REFERENCE below names the constant each one mirrors.

Run:  python tools/generate_ui_plates.py
Then: Godot_v4.3-stable_win64_console.exe --headless --editor --import
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

    base = np.array([0.150, 0.148, 0.132])
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


def mat_bakelite(h, w, rng):
    """Dark phenolic resin. Near-black brown, faint marbled swirl, semi-gloss."""
    yy, xx = _coords(h, w)
    # Marbling: a low-frequency field used to DISTORT a second one, which is
    # what gives phenolic its characteristic smeared-swirl look. A single
    # noise octave reads as dirt instead.
    warp = fbm(h, w, octaves=3, base=3, rng=rng)
    # The carrier frequency must be a WHOLE number of cycles across the
    # texture or the swirl does not wrap. The first version used
    # `xx / w * 6.0`, which is 6 radians end to end - not 6 cycles - so the
    # left and right edges landed on unrelated phases and every bakelite
    # button carried a visible vertical seam. `warp` is itself seamless, so
    # distorting a periodic carrier with it stays periodic.
    swirl_src = np.sin(2.0 * np.pi * 3.0 * xx / w + warp * 7.0) * 0.5 + 0.5
    speck = fbm(h, w, octaves=2, base=40, rng=rng)

    base = np.array([0.085, 0.073, 0.066])
    lum = 1.0 + (swirl_src - 0.5) * 0.20 + (speck - 0.5) * 0.06
    rgb = base[None, None, :] * lum[:, :, None]
    # Warm the lighter marbling toward brown rather than grey - phenolic goes
    # amber where it is thin, never neutral.
    rgb[:, :, 0] *= 1.0 + (swirl_src - 0.5) * 0.10
    gloss = np.full((h, w), 0.62)
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

    base = np.array([0.072, 0.072, 0.078])
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


MATERIALS = {
    "powdercoat": mat_powdercoat,
    "steel": mat_steel,
    "bakelite": mat_bakelite,
    "canvas": mat_canvas,
    "carbon": mat_carbon,
    "fiberglass": mat_fiberglass,
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
STATES = {
    "normal":   (1.00, +1.0, 1.00),
    "hover":    (1.18, +1.0, 1.15),
    "pressed":  (0.82, -1.0, 0.90),
    "disabled": (0.68, +1.0, 0.35),
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


def build_plate(material, state, rng):
    fn = MATERIALS[material]
    rgb, gloss = fn(PLATE, PLATE, rng)
    brightness, direction, strength = STATES[state]
    rgb = rgb * brightness
    rgb = _apply_bevel(rgb, gloss, direction, strength)
    return np.clip(rgb, 0.0, 1.0)


def build_field(material, rng):
    fn = MATERIALS[material]
    rgb, _gloss = fn(FIELD, FIELD, rng)
    return np.clip(rgb, 0.0, 1.0)


def save(arr, path):
    img = Image.fromarray((arr * 255.0 + 0.5).astype(np.uint8), mode="RGB")
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
            arr = build_plate(material, state, rng)
            save(arr, OUT / f"plate_{material}_{state}.png")
        rng = np.random.default_rng(_seed(material) + 7)
        save(build_field(material, rng), OUT / f"field_{material}.png")
        print(f"  {material}: 4 plates + 1 field")

    total = len(MATERIALS) * (len(STATES) + 1)
    print(f"\n{total} texture(s) written.")


if __name__ == "__main__":
    main()
