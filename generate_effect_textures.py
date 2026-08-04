"""
Procedural texture generator for combat VFX (flames, smoke, scorch decals).

Deliberately NOT using an image-generation API, the way the project's original
terrain-texture generator did: these are small, high-contrast, alpha-keyed
sprites where exact control over the alpha falloff matters far more than
photographic detail. A generated "photo of fire" comes back with baked-in black
background and soft JPEG edges, which is exactly wrong for an additive
billboard. Procedural fbm gives a clean premultiplied-safe alpha and costs
nothing to re-tune. Terrain has since moved the same way - see
prototype/tools/generate_terrain_textures.gd, which bakes its maps procedurally
in-engine.

Outputs (prototype/assets/textures/effects/):
  flame_flipbook.png   4x4 sheet, 512px  - additive fire, plays once per particle
  smoke_flipbook.png   4x4 sheet, 512px  - white/alpha smoke, tinted in-material
  scorch_{0,1,2}_*.png 512px             - burn mark albedo/normal/orm variants
  scorch_emission.png  512px             - ember hotspots, emission channel
  crater_{0,1}_*.png   512px             - crater albedo/normal/orm variants

Run: python generate_effect_textures.py
"""

import numpy as np
from PIL import Image
from pathlib import Path

OUT = Path(__file__).parent / "prototype" / "assets" / "textures" / "effects"
OUT.mkdir(parents=True, exist_ok=True)

RNG = np.random.default_rng(20260731)


def _value_noise(h, w, res, rng):
    """One octave of smoothly-interpolated value noise at `res` control points."""
    gy, gx = res
    grid = rng.random((gy + 1, gx + 1))
    # Bilinear upsample with a smoothstep easing so octaves stack without
    # visible grid creases.
    ys = np.linspace(0, gy, h, endpoint=False)
    xs = np.linspace(0, gx, w, endpoint=False)
    y0, x0 = np.floor(ys).astype(int), np.floor(xs).astype(int)
    fy, fx = ys - y0, xs - x0
    fy = (fy * fy * (3 - 2 * fy))[:, None]
    fx = (fx * fx * (3 - 2 * fx))[None, :]
    v00 = grid[np.ix_(y0, x0)]
    v01 = grid[np.ix_(y0, x0 + 1)]
    v10 = grid[np.ix_(y0 + 1, x0)]
    v11 = grid[np.ix_(y0 + 1, x0 + 1)]
    top = v00 * (1 - fx) + v01 * fx
    bot = v10 * (1 - fx) + v11 * fx
    return top * (1 - fy) + bot * fy


def fbm(h, w, octaves=5, base=3, rng=None, stretch_y=1.0):
    """
    Fractal sum of value noise, normalised to 0..1.

    stretch_y > 1 uses proportionally FEWER control points vertically, which
    elongates features into vertical streaks. That is what makes fire read as
    licking tongues instead of round blobs - isotropic noise on a flame sprite
    always looks like clouds.
    """
    rng = rng or RNG
    total = np.zeros((h, w))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        f = base * 2 ** o
        res = (max(1, int(f / stretch_y)), f)
        total += amp * _value_noise(h, w, res, rng)
        norm += amp
        amp *= 0.5
    out = total / norm
    # np.ptp(arr), not arr.ptp() - the method was removed in NumPy 2.
    return (out - out.min()) / (np.ptp(out) + 1e-9)


def radial(h, w, cx=0.5, cy=0.5, rx=0.5, ry=0.5):
    """Normalised elliptical distance field, 0 at centre and 1 at the edge."""
    yy, xx = np.mgrid[0:h, 0:w]
    nx = (xx / w - cx) / rx
    ny = (yy / h - cy) / ry
    return np.sqrt(nx ** 2 + ny ** 2)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0 + 1e-9), 0, 1)
    return t * t * (3 - 2 * t)


def flame_frame(size, t, rng):
    """
    One flipbook cell of fire at normalised life t (0=ignition, 1=burnt out).

    The plume narrows and rises as it ages while the turbulence scrolls
    upward, so a particle playing the sheet over its lifetime reads as one
    continuous flame rather than 16 unrelated puffs.
    """
    # A soft turbulent PUFF, deliberately not a flame silhouette.
    #
    # An earlier version drew a proper teardrop flame with ragged tongues. It
    # looked correct in isolation and was wrong in use: a particle system
    # emits dozens of these at once, so a strongly flame-shaped sprite reads
    # as a crowd of little candles instead of one jet. In a particle system
    # the AGGREGATE makes the shape, and the individual sprite has to be
    # nondescript enough to blend with its neighbours. Hence: round-ish, soft
    # edged, hot in the middle, with enough turbulence to break up the
    # overlap so the jet doesn't look like a tube of airbrush.
    grow = 0.30 + 0.13 * t
    d = radial(size, size, cx=0.5, cy=0.52 - 0.06 * t, rx=grow, ry=grow * 1.12)
    body = 1.0 - smoothstep(0.15, 1.0, d)

    turb = fbm(size, size, octaves=5, base=4, rng=rng, stretch_y=2.0)
    turb = np.roll(turb, -int(t * size * 0.35), axis=0)

    # Mild erosion only - a WIDE smoothstep keeps the edges feathered so
    # overlapping particles merge instead of showing their outlines.
    field = body * (0.62 + 0.70 * turb)
    thr = 0.16 + 0.34 * t

    # Low peak alpha ON PURPOSE. These draw with additive blending, where
    # brightness accumulates wherever particles overlap - so each sprite has
    # to be dim enough that a stack of them reaches white, rather than each
    # one already being white on its own. At full alpha the jet rendered as a
    # crowd of blown-out white discs with no colour left in it.
    #
    # A GAMMA FALLOFF, not a smoothstep band. Any threshold - however wide -
    # ends the sprite at a definite radius, and because the coolest (reddest)
    # colour sits at exactly that radius, every particle drew a visible red
    # RIM and the jet read as a pile of discs. Raising a linear ramp to a
    # power instead gives a long asymptotic tail that reaches zero softly, so
    # neighbouring particles dissolve into each other.
    alpha = np.clip((field - thr) / (1.0 - thr + 1e-6), 0, 1) ** 2.1
    alpha *= (1.0 - smoothstep(0.72, 1.0, t)) * 0.55

    # Heat: mostly orange, with yellow only near the middle and white
    # essentially never - additive overlap supplies the white core for free.
    heat = np.clip((field - thr) / 0.48, 0, 1) * (1.0 - 0.50 * t)
    rgb = np.zeros((size, size, 3))
    rgb[..., 0] = np.clip(0.75 + heat * 1.2, 0, 1)     # always red-hot at minimum
    rgb[..., 1] = np.clip((heat - 0.30) * 1.15, 0, 1)  # -> orange -> yellow
    rgb[..., 2] = np.clip((heat - 0.88) * 1.6, 0, 1)   # a hint of white, no more
    return rgb, np.clip(alpha, 0, 1)


def smoke_frame(size, t, rng):
    """One flipbook cell of smoke: expands, drifts up, thins out."""
    rise = 0.20 * t
    grow = 0.26 + 0.20 * t
    d = radial(size, size, cx=0.5, cy=0.55 - rise, rx=grow, ry=grow)
    body = 1.0 - smoothstep(0.30, 1.0, d)

    turb = fbm(size, size, octaves=6, base=3, rng=rng, stretch_y=1.4)
    turb = np.roll(turb, -int(t * size * 0.25), axis=0)
    # Same erosion approach as the flame, but with a softer threshold ramp -
    # smoke should stay billowy where fire is ragged.
    # Wide threshold ramp, same reason as the flame: these overlap heavily in
    # a puff and hard edges would show every individual billboard as a
    # distinct grey ball (which is exactly what the first in-engine capture
    # showed).
    field = body * (0.40 + 1.05 * turb)
    thr = 0.24 + 0.40 * t
    dens = smoothstep(thr, thr + 0.52, field) * 0.85

    # White; the material tints it (grey exhaust vs. black oil smoke) so one
    # sheet serves every smoke colour in the game.
    value = 0.72 + 0.28 * turb
    rgb = np.dstack([value, value, value])
    return rgb, np.clip(dens, 0, 1)


def build_flipbook(name, frame_fn, cells=4, cell_px=128):
    size = cells * cell_px
    sheet = np.zeros((size, size, 4))
    rng = np.random.default_rng(7)
    n = cells * cells
    for i in range(n):
        t = i / (n - 1)
        rgb, a = frame_fn(cell_px, t, rng)
        r, c = divmod(i, cells)
        sheet[r * cell_px:(r + 1) * cell_px, c * cell_px:(c + 1) * cell_px, :3] = rgb
        sheet[r * cell_px:(r + 1) * cell_px, c * cell_px:(c + 1) * cell_px, 3] = a
    img = Image.fromarray((np.clip(sheet, 0, 1) * 255).astype(np.uint8), "RGBA")
    img.save(OUT / name)
    print(f"  {name}  {size}x{size}  ({cells}x{cells} frames)")


def build_scorch_emission(size=512):
    """
    Ember hotspots for a fresh burn, as an emission mask.

    A fresh napalm pool can glow and then be faded to a cold scorch by
    animating emission_energy alone - one decal, two lifetimes, no second
    texture swap. The albedo half of that pair used to be written here as
    scorch_decal.png; build_scorch_variants() below supersedes it with three
    albedo/normal/orm sets, which is what vfx_effects.gd actually loads.
    """
    rng = np.random.default_rng(11)
    warp = fbm(size, size, octaves=5, base=3, rng=rng)
    d = radial(size, size, rx=0.46, ry=0.46)
    # Perturb the distance field so the edge is ragged, not a circle.
    d = d + (warp - 0.5) * 0.42
    mask = 1.0 - smoothstep(0.55, 1.0, d)

    # Embers: sparse hot cells inside the burn, gated by the same mask.
    ember = fbm(size, size, octaves=4, base=10, rng=np.random.default_rng(13))
    hot = smoothstep(0.62, 0.92, ember) * mask
    em = np.dstack([hot, hot * 0.42, hot * 0.06, np.clip(hot * 1.4, 0, 1)])
    Image.fromarray((np.clip(em, 0, 1) * 255).astype(np.uint8), "RGBA") \
        .save(OUT / "scorch_emission.png")
    print(f"  scorch_emission.png  {size}x{size}")


def normal_from_height(height, strength=2.5):
    """
    Sobel-style normal map from a height field.

    Decals take a texture_normal, and it is the single biggest quality jump
    available to them: with only an albedo a scorch is a flat sticker, and no
    amount of better painting fixes that because it never reacts to the
    scene's light. With a normal, a crater rim catches the sun and the mark
    reads as displaced ground.
    """
    gy, gx = np.gradient(height.astype(np.float64))
    nx = -gx * strength
    ny = -gy * strength
    nz = np.ones_like(height)
    ln = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    # Godot expects tangent-space normals in the usual 0.5-centred encoding.
    return np.dstack([(nx / ln) * 0.5 + 0.5, (ny / ln) * 0.5 + 0.5, (nz / ln) * 0.5 + 0.5])


def build_orm(occlusion, roughness, metallic=None):
    """
    ORM packing Godot's texture_orm expects: R=occlusion, G=roughness,
    B=metallic. Lets a fresh burn read WET (low roughness, so it catches a
    specular highlight) while old ash is bone dry - the same shape telling
    you how recent the damage is, without a second albedo.
    """
    if metallic is None:
        metallic = np.zeros_like(occlusion)
    return np.dstack([occlusion, roughness, metallic])


def _save_rgb(arr, name):
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGB").save(OUT / name)
    print(f"  {name}  {arr.shape[1]}x{arr.shape[0]}")


def _save_rgba(rgb, alpha, name):
    Image.fromarray((np.clip(np.dstack([rgb, alpha]), 0, 1) * 255).astype(np.uint8), "RGBA").save(OUT / name)
    print(f"  {name}  {rgb.shape[1]}x{rgb.shape[0]}")


def build_scorch_variants(size=512, count=3):
    """
    Several scorch marks rather than one.

    A single silhouette stamped repeatedly is instantly readable as a repeat
    at RTS zoom, where the camera holds a dozen burn marks at once - the same
    reasoning terrain_builder.gd already applies to its ground tiles.
    """
    for v in range(count):
        rng = np.random.default_rng(400 + v)
        warp = fbm(size, size, octaves=5, base=3, rng=rng)
        d = radial(size, size, rx=0.44 + 0.03 * v, ry=0.46 - 0.02 * v)
        d = d + (warp - 0.5) * (0.38 + 0.08 * v)
        mask = 1.0 - smoothstep(0.55, 1.0, d)

        grit = fbm(size, size, octaves=6, base=6, rng=np.random.default_rng(500 + v))
        char = 0.04 + 0.10 * grit
        rgb = np.dstack([char * 1.25, char * 1.05, char * 0.9])
        alpha = np.clip(mask * (0.55 + 0.55 * grit), 0, 1)
        _save_rgba(rgb, alpha, f"scorch_{v}_albedo.png")

        # Burnt ground is slightly sunken and crusty, not flat.
        height = -0.25 * mask + 0.14 * grit * mask
        _save_rgb(normal_from_height(height, strength=3.0), f"scorch_{v}_normal.png")
        # Char is matte and dark-occluded; the crusty grit is a touch glossier.
        occl = 1.0 - 0.45 * mask
        rough = np.clip(0.95 - 0.25 * grit * mask, 0, 1)
        _save_rgb(build_orm(occl, rough), f"scorch_{v}_orm.png")


def build_craters(size=512, count=2):
    """
    Impact craters: a real bowl with a raised, ejecta-streaked rim.

    Distinct from a scorch, and worth its own texture rather than a recoloured
    one: a burn is a surface stain with no relief, a crater is displaced
    earth. The difference lives almost entirely in the normal map, which is
    why this only became worth authoring once decals carried one.
    """
    for v in range(count):
        rng = np.random.default_rng(700 + v)
        warp = fbm(size, size, octaves=5, base=4, rng=rng)
        d = radial(size, size, rx=0.40, ry=0.40)
        d = d + (warp - 0.5) * 0.22          # irregular, not a perfect circle

        bowl = 1.0 - smoothstep(0.0, 1.0, d)  # 1 at centre
        rim = np.exp(-((d - 0.78) ** 2) / 0.012)   # ring of piled-up spoil
        mask = 1.0 - smoothstep(0.85, 1.30, d)

        # Ejecta rays streaking outward past the rim.
        ang = np.arctan2(*np.mgrid[0:size, 0:size][::-1] - size / 2.0)
        rays = (0.5 + 0.5 * np.sin(ang * (7 + 3 * v))) * smoothstep(0.7, 1.25, d) * (1.0 - smoothstep(1.0, 1.5, d))
        grit = fbm(size, size, octaves=6, base=7, rng=np.random.default_rng(800 + v))

        height = -0.85 * bowl + 0.45 * rim + 0.10 * grit * mask + 0.12 * rays
        _save_rgb(normal_from_height(height, strength=4.5), f"crater_{v}_normal.png")

        # Dark shadowed pit, dusty pale rim and rays.
        dark = 0.05 + 0.09 * grit
        pale = 0.34 + 0.20 * grit
        blend = np.clip(rim * 1.4 + rays * 0.9, 0, 1)
        base = dark * (1 - blend) + pale * blend
        rgb = np.dstack([base * 1.12, base * 1.02, base * 0.92])
        alpha = np.clip(mask * (0.75 + 0.35 * grit), 0, 1)
        _save_rgba(rgb, alpha, f"crater_{v}_albedo.png")

        occl = np.clip(1.0 - 0.75 * bowl, 0, 1)   # the pit self-shadows
        rough = np.clip(0.92 - 0.15 * blend, 0, 1)
        _save_rgb(build_orm(occl, rough), f"crater_{v}_orm.png")


if __name__ == "__main__":
    print(f"Writing effect textures to {OUT}")
    build_flipbook("flame_flipbook.png", flame_frame)
    build_flipbook("smoke_flipbook.png", smoke_frame)
    build_scorch_emission()
    build_scorch_variants()
    build_craters()
    print("Done.")
