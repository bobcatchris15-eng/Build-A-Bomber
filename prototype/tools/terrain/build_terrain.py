"""
RTS_CORE_ROADMAP.md B4: the Python terrain authoring/generation pipeline
(runtime stays GDScript - terrain_height_at() is queried every physics tick
by every unit, which rules out a Python round-trip). Mirrors
tools/blender/build_meshes.py's role for hull/part meshes: a committed,
regenerable artifact pair per map, not hand-authored pixels.

Input: a map JSON's "terrain" block - {height_scale, features: [...]}.
Each feature is a high-level, diffable, seeded primitive (hill/basin/
plateau/ridge/ravine/escarpment/cliff), not raw pixels - see FEATURE
TYPES below for the exact param shape of each.

Output: <map_id>_height.png (RGBA8, 16-bit height packed into the R+G
channels - Godot's Image.load_from_file() doesn't reliably preserve a
true 16-bit-grayscale PNG, verified empirically) and <map_id>_surface.png
(8-bit indexed - see SURFACE_PALETTE) written next to the source map
JSON. Committed to git like any other regenerable asset (.glb, faction
textures).

Deterministic: every feature is fully described by its own JSON params
(no external RNG state), and pixel (px, pz) maps to world (px - half,
pz - half) via a fixed 1 pixel/world-unit grid - same inputs always
produce byte-identical PNGs (verified by regenerating and diffing).

Usage: python tools/terrain/build_terrain.py <map_json_path> [--resolution N]
"""
import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image

# Pixel (px, pz) -> world (px - HALF, pz - HALF). 1 pixel per world unit
# keeps the mapping exact at every integer world coordinate, which is what
# lets the bilinear-sample-matches-source-at-pixel-centers test hold
# without any resampling ambiguity.
PIXELS_PER_UNIT = 1.0

# 16-bit heightmap encoding: normalized = clamp(raw_height_world / height_scale, -1, 1),
# pixel16 = round((normalized + 1.0) * 32767.5). Godot's Image.load_from_file()
# does NOT preserve genuine 16-bit-grayscale PNGs (verified empirically -
# it silently collapses to 8-bit and every pixel saturates to 1.0), so the
# 16-bit value is split across the R+G channels of an ordinary RGBA8 PNG
# instead (high byte in R, low byte in G) - the standard workaround for
# engines/loaders without reliable 16-bit PNG support. Runtime
# (terrain_builder.gd) must decode with the exact inverse - see its
# _decode_heightmap_pixel().
HEIGHT_PIXEL_MAX = 65535

# Surface palette (RTS_CORE_ROADMAP.md B7 will wire the gameplay/visual
# side of this - B4 just needs the raster to exist). Index 0 is "no
# surface_zone" (plain ground), matching get_surface_type_at()'s existing
# "" empty-string default.
SURFACE_PALETTE = ["", "marsh", "rocky", "snow_mud", "sand"]


def _smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _point_to_segment_dist_and_t(px, pz, x0, z0, x1, z1):
    """Vectorized point-to-segment distance, plus the projected t in [0,1]
    along the segment (used by escarpment to find the perpendicular signed
    distance to the INFINITE line, not just the nearest point)."""
    dx, dz = x1 - x0, z1 - z0
    seg_len2 = dx * dx + dz * dz
    if seg_len2 <= 1e-9:
        t = np.zeros_like(px)
    else:
        t = ((px - x0) * dx + (pz - z0) * dz) / seg_len2
        t = np.clip(t, 0.0, 1.0)
    cx, cz = x0 + t * dx, z0 + t * dz
    dist = np.sqrt((px - cx) ** 2 + (pz - cz) ** 2)
    return dist, t


def _signed_dist_to_line(px, pz, x0, z0, x1, z1):
    """Signed perpendicular distance to the INFINITE line through
    (x0,z0)->(x1,z1) - positive on the "left" side of that direction,
    negative on the "right" (2D cross product sign convention)."""
    dx, dz = x1 - x0, z1 - z0
    length = math.hypot(dx, dz)
    if length <= 1e-9:
        return np.zeros_like(px)
    nx, nz = -dz / length, dx / length  # left-hand normal
    return (px - x0) * nx + (pz - z0) * nz


def _hill(px, pz, center, radius, height, falloff):
    dist = np.sqrt((px - center[0]) ** 2 + (pz - center[1]) ** 2)
    t = np.zeros_like(dist)
    if falloff > 0.0:
        t = _smoothstep((dist - radius) / falloff)
    else:
        t = np.where(dist > radius, 1.0, 0.0)
    return height * (1.0 - t)


def _basin(px, pz, center, radius, depth, falloff):
    return -_hill(px, pz, center, radius, depth, falloff)


def _plateau(px, pz, center, half_extents, height, falloff):
    dx = np.abs(px - center[0]) - half_extents[0]
    dz = np.abs(pz - center[1]) - half_extents[1]
    # Distance outside a rect (0 if inside on that axis), Euclidean-ish
    # combine for the rounded falloff ring - same "outside distance"
    # convention _rect_from()/is_position_blocked() already use elsewhere.
    outside = np.sqrt(np.clip(dx, 0, None) ** 2 + np.clip(dz, 0, None) ** 2)
    t = np.zeros_like(outside)
    if falloff > 0.0:
        t = _smoothstep(outside / falloff)
    else:
        t = np.where(outside > 0.0, 1.0, 0.0)
    return height * (1.0 - t)


def _ridge(px, pz, start, end, width, height, falloff):
    dist, _ = _point_to_segment_dist_and_t(px, pz, start[0], start[1], end[0], end[1])
    half_w = width / 2.0
    t = np.zeros_like(dist)
    if falloff > 0.0:
        t = _smoothstep((dist - half_w) / falloff)
    else:
        t = np.where(dist > half_w, 1.0, 0.0)
    return height * (1.0 - t)


def _ravine(px, pz, start, end, width, depth, falloff):
    return -_ridge(px, pz, start, end, width, depth, falloff)


def _escarpment(px, pz, start, end, height, falloff, side):
    signed = _signed_dist_to_line(px, pz, start[0], start[1], end[0], end[1])
    if side == "right":
        signed = -signed
    if falloff <= 0.0:
        falloff = 0.01  # cliff: near-zero transition, avoid div-by-zero
    t = _smoothstep(signed / falloff)  # 0 on the low side -> 1 on the high side
    return height * t


def _cliff(px, pz, start, end, height, side):
    # A cliff IS an escarpment with a forced near-zero transition - the
    # "hard vertical step" version, not a separate formula.
    return _escarpment(px, pz, start, end, height, 0.01, side)


FEATURE_BUILDERS = {
    "hill": lambda px, pz, f: _hill(px, pz, f["center"], f["radius"], f["height"], f.get("falloff", 10.0)),
    "basin": lambda px, pz, f: _basin(px, pz, f["center"], f["radius"], f["depth"], f.get("falloff", 10.0)),
    "plateau": lambda px, pz, f: _plateau(px, pz, f["center"], f["half_extents"], f["height"], f.get("falloff", 10.0)),
    "ridge": lambda px, pz, f: _ridge(px, pz, f["start"], f["end"], f["width"], f["height"], f.get("falloff", 10.0)),
    "ravine": lambda px, pz, f: _ravine(px, pz, f["start"], f["end"], f["width"], f["depth"], f.get("falloff", 10.0)),
    "escarpment": lambda px, pz, f: _escarpment(px, pz, f["start"], f["end"], f["height"], f.get("falloff", 6.0), f.get("side", "left")),
    "cliff": lambda px, pz, f: _cliff(px, pz, f["start"], f["end"], f["height"], f.get("side", "left")),
}


def build_heightfield(half_extents, features, resolution=None):
    """Returns (heightfield: np.ndarray[H,W] float32 world-unit heights, dim: int)."""
    dim = resolution or (int(round(half_extents * 2 * PIXELS_PER_UNIT)) + 1)
    coords = np.linspace(-half_extents, half_extents, dim, dtype=np.float64)
    px, pz = np.meshgrid(coords, coords)  # px varies along columns (x), pz along rows (z)

    height = np.zeros_like(px)
    for f in features:
        builder = FEATURE_BUILDERS.get(f.get("type"))
        if builder is None:
            raise ValueError(f"Unknown terrain feature type: {f.get('type')!r}")
        height += builder(px, pz, f)
    return height.astype(np.float32), dim


def encode_heightmap(height, height_scale):
    """Returns an (H, W, 4) uint8 RGBA array - R=high byte, G=low byte of
    the 16-bit pixel value, B=0, A=255 (opaque; some loaders drop fully-
    transparent pixel color data)."""
    normalized = np.clip(height / height_scale, -1.0, 1.0)
    pixel16 = np.round((normalized + 1.0) * (HEIGHT_PIXEL_MAX / 2.0)).astype(np.uint32)
    rgba = np.zeros(pixel16.shape + (4,), dtype=np.uint8)
    rgba[..., 0] = (pixel16 >> 8) & 0xFF  # R = high byte
    rgba[..., 1] = pixel16 & 0xFF          # G = low byte
    rgba[..., 2] = 0
    rgba[..., 3] = 255
    return rgba


def build_surfacemap(half_extents, surface_zones, resolution):
    dim = resolution
    coords = np.linspace(-half_extents, half_extents, dim, dtype=np.float64)
    px, pz = np.meshgrid(coords, coords)
    indices = np.zeros_like(px, dtype=np.uint8)
    # First-listed zone wins on overlap - matches get_surface_type_at()'s
    # existing "resolve to whichever is listed first" rule, so migrating a
    # map from rect surface_zones to this raster is behavior-preserving.
    for z in reversed(surface_zones):
        cx, cz = z["center"][0], z["center"][1]
        hx, hz = z["half_extents"][0], z["half_extents"][1]
        mask = (np.abs(px - cx) <= hx) & (np.abs(pz - cz) <= hz)
        try:
            idx = SURFACE_PALETTE.index(z.get("surface_type", ""))
        except ValueError:
            raise ValueError(f"Unknown surface_type {z.get('surface_type')!r}, not in SURFACE_PALETTE")
        indices[mask] = idx
    return indices


def generate(map_json_path, resolution=None):
    with open(map_json_path, "r") as f:
        map_def = json.load(f)

    terrain = map_def.get("terrain")
    if not terrain or not terrain.get("features"):
        print(f"'{map_json_path}' has no terrain.features - nothing to generate.")
        return

    half_extents = float(map_def["map_half_extents"])
    height_scale = float(terrain.get("height_scale", 20.0))
    features = terrain["features"]

    height, dim = build_heightfield(half_extents, features, resolution)
    pixels = encode_heightmap(height, height_scale)

    map_id = os.path.splitext(os.path.basename(map_json_path))[0]
    out_dir = os.path.dirname(map_json_path)
    height_path = os.path.join(out_dir, f"{map_id}_height.png")
    surface_path = os.path.join(out_dir, f"{map_id}_surface.png")

    Image.fromarray(pixels, mode="RGBA").save(height_path)
    print(f"Wrote {height_path} ({dim}x{dim})")

    surface_zones = map_def.get("surface_zones", [])
    indices = build_surfacemap(half_extents, surface_zones, dim)
    # "P" mode with an explicit palette so the file is a real indexed PNG,
    # not just a grayscale image that happens to hold small integers.
    surf_img = Image.fromarray(indices, mode="P")
    palette = []
    for i in range(256):
        palette.extend([i, i, i])  # runtime never reads pixel COLOR, only the index - grayscale ramp is just so it's inspectable in an image viewer
    surf_img.putpalette(palette)
    surf_img.save(surface_path)
    print(f"Wrote {surface_path} ({dim}x{dim})")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("map_json_path")
    parser.add_argument("--resolution", type=int, default=None)
    args = parser.parse_args()
    generate(args.map_json_path, args.resolution)
