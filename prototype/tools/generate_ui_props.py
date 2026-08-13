"""
Procedural per-prop textures for 3D UI controls (Phase 2 of Tactile Interface Programme).

Generates deterministic, seed-stable 256x256 texture sets per prop:
  assets/textures/ui/props/<prop_id>_albedo.png   (RGBA)
  assets/textures/ui/props/<prop_id>_orm.png      (RGB: R=AO, G=Roughness, B=Metallic)
  assets/textures/ui/props/<prop_id>_height.png   (RGB: POM heightfield)

Determinism rule: seed is derived strictly from zlib.crc32(prop_id.encode("utf-8")),
never Python's hash(). Rerunning this generator produces byte-identical results.
"""

import math
from pathlib import Path
import zlib
import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "assets" / "textures" / "ui" / "props"
OUT.mkdir(parents=True, exist_ok=True)

SIZE = 256

# Base hardware luminance reference (~0.154 for control bodies, sitting above panels at ~0.08-0.12)
BASE_GUNMETAL = np.array([0.42, 0.43, 0.45], dtype=np.float32)
METAL_WEAR = np.array([0.72, 0.74, 0.76], dtype=np.float32)
GRIME_TINT = np.array([0.18, 0.16, 0.14], dtype=np.float32)
STAMP_ENAMEL = np.array([0.88, 0.85, 0.78], dtype=np.float32)


def _tileable_value_noise(h, w, res_y, res_x, rng):
    grid = rng.random((res_y + 1, res_x + 1))
    grid[-1, :] = grid[0, :]
    grid[:, -1] = grid[:, 0]

    ys = np.linspace(0, res_y, h, endpoint=False)
    xs = np.linspace(0, res_x, w, endpoint=False)
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    fy = ys - y0
    fx = xs - x0
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
    total = np.zeros((h, w), dtype=np.float32)
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        f = base * 2**o
        rx = max(1, int(round(f / aniso)))
        total += amp * _tileable_value_noise(h, w, f, rx, rng).astype(np.float32)
        norm += amp
        amp *= 0.5
    out = total / norm
    return (out - out.min()) / (np.ptp(out) + 1e-9)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0 + 1e-9), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _coords(h, w):
    yy, xx = np.mgrid[0:h, 0:w]
    return yy.astype(np.float32), xx.astype(np.float32)


def generate_prop_textures(prop_id: str):
    seed = zlib.crc32(prop_id.encode("utf-8"))
    rng = np.random.default_rng(seed)

    h, w = SIZE, SIZE
    yy, xx = _coords(h, w)
    cx, cy = (w - 1) * 0.5, (h - 1) * 0.5
    nx = (xx - cx) / (w * 0.5)
    ny = (yy - cy) / (h * 0.5)
    r = np.sqrt(nx * nx + ny * ny)
    theta = np.arctan2(ny, nx)

    # Base noise layers
    fine_noise = fbm(h, w, octaves=5, base=16, rng=rng)
    macro_noise = fbm(h, w, octaves=4, base=4, rng=rng)
    swirl_angle = rng.uniform(0.0, math.tau)

    # Height map (0.0 to 1.0)
    height = np.full((h, w), 0.5, dtype=np.float32)
    # Ambient Occlusion (0.0 dark to 1.0 unoccluded)
    ao = np.ones((h, w), dtype=np.float32)
    # Roughness (0.03 floor to 1.0)
    roughness = np.full((h, w), 0.42, dtype=np.float32)
    # Metallic (0.0 to 1.0)
    metallic = np.full((h, w), 0.55, dtype=np.float32)
    # Albedo (RGB linear float 0..1)
    albedo = np.tile(BASE_GUNMETAL, (h, w, 1))

    # Prop-specific procedural masks and geometric details
    if prop_id in ("push_button", "rotary", "knurled_dial", "dzus_fastener"):
        # Circular lathe machining swirl
        swirl = np.sin((r * 28.0 + theta * 2.0 + swirl_angle) * math.pi) * 0.5 + 0.5
        roughness += (swirl * 0.12 - 0.06) + (fine_noise * 0.14 - 0.07)

        # Chamfer and rim contouring
        rim_mask = smoothstep(0.82, 0.96, r) * (1.0 - smoothstep(0.96, 1.02, r))
        center_dish = smoothstep(0.85, 0.0, r)

        # Dish depression in heightmap
        height = 0.5 + center_dish * 0.35 - rim_mask * 0.15

        # Edge scuffs & wear on rim
        edge_wear = smoothstep(0.88, 0.98, r) * smoothstep(0.45, 0.85, macro_noise)
        albedo = albedo * (1.0 - edge_wear[:, :, None]) + METAL_WEAR * edge_wear[:, :, None]
        roughness = np.clip(roughness - edge_wear * 0.18, 0.04, 0.95)

        # Grime in outer crevice
        outer_crevice = smoothstep(0.92, 1.0, r)
        ao = np.clip(1.0 - outer_crevice * 0.55 - (1.0 - macro_noise) * 0.2, 0.15, 1.0)
        albedo = albedo * (1.0 - outer_crevice[:, :, None] * 0.3) + GRIME_TINT * (outer_crevice[:, :, None] * 0.3)

        if prop_id == "dzus_fastener":
            # Quarter-turn screwdriver slot across the center
            slot_w = np.abs(nx * math.cos(swirl_angle) + ny * math.sin(swirl_angle))
            slot_len = np.abs(-nx * math.sin(swirl_angle) + ny * math.cos(swirl_angle))
            slot_mask = (1.0 - smoothstep(0.06, 0.12, slot_w)) * (1.0 - smoothstep(0.65, 0.75, slot_len))
            height -= slot_mask * 0.4
            ao = np.clip(ao - slot_mask * 0.75, 0.05, 1.0)
            roughness = np.clip(roughness + slot_mask * 0.25, 0.04, 0.95)
            metallic = np.full((h, w), 0.85, dtype=np.float32)

        elif prop_id == "knurled_dial":
            # Radial knurling pattern around rim
            knurl_teeth = 36
            knurl = np.sin(theta * knurl_teeth) * np.cos(theta * knurl_teeth * 0.5)
            knurl_band = smoothstep(0.65, 0.82, r) * (1.0 - smoothstep(0.92, 0.98, r))
            knurl_pattern = knurl_band * (knurl * 0.5 + 0.5)
            height += knurl_pattern * 0.25
            ao = np.clip(ao - knurl_pattern * 0.35, 0.1, 1.0)
            roughness = np.clip(roughness + knurl_pattern * 0.15, 0.04, 0.95)
            metallic = np.full((h, w), 0.75, dtype=np.float32)

        elif prop_id == "rotary":
            # Index pointer notch at top / angle
            pointer_ang = np.abs(theta - (-math.pi * 0.5))
            pointer_mask = (1.0 - smoothstep(0.04, 0.10, pointer_ang)) * smoothstep(0.35, 0.85, r)
            height += pointer_mask * 0.2
            albedo = albedo * (1.0 - pointer_mask[:, :, None]) + STAMP_ENAMEL * pointer_mask[:, :, None]
            roughness = np.clip(roughness - pointer_mask * 0.2, 0.04, 0.95)

    else:
        # Linear grain for rectangular/linear controls (toggle, rocker, latch)
        grain_aniso = fbm(h, w, octaves=5, base=8, rng=rng, aniso=3.5)
        roughness = np.clip(0.38 + grain_aniso * 0.22, 0.04, 0.92)

        # Border bevel / corner wear
        box_dist = np.maximum(np.abs(nx), np.abs(ny))
        edge_band = smoothstep(0.78, 0.95, box_dist)
        height = 0.5 + (1.0 - box_dist) * 0.3

        edge_wear = edge_band * smoothstep(0.4, 0.8, macro_noise)
        albedo = albedo * (1.0 - edge_wear[:, :, None]) + METAL_WEAR * edge_wear[:, :, None]

        outer_crevice = smoothstep(0.88, 0.98, box_dist)
        ao = np.clip(1.0 - outer_crevice * 0.5 - (1.0 - macro_noise) * 0.2, 0.15, 1.0)

        if prop_id == "toggle":
            metallic = np.full((h, w), 0.80, dtype=np.float32)
        elif prop_id == "rocker":
            metallic = np.full((h, w), 0.40, dtype=np.float32)
            # Center pivot ridge
            pivot_line = 1.0 - smoothstep(0.0, 0.15, np.abs(ny))
            height += pivot_line * 0.25
        elif prop_id == "latch":
            metallic = np.full((h, w), 0.70, dtype=np.float32)

    # Global roughness floor to avoid GGX specular singularity
    roughness = np.clip(roughness, 0.04, 0.96)
    ao = np.clip(ao, 0.05, 1.0)
    metallic = np.clip(metallic, 0.0, 1.0)
    height = np.clip(height, 0.0, 1.0)

    # Save Albedo (RGBA, 8-bit)
    albedo_u8 = (np.clip(albedo, 0.0, 1.0) * 255.0).astype(np.uint8)
    alpha_channel = np.full((h, w, 1), 255, dtype=np.uint8)
    albedo_rgba = np.concatenate([albedo_u8, alpha_channel], axis=2)
    Image.fromarray(albedo_rgba, mode="RGBA").save(OUT / f"{prop_id}_albedo.png")

    # Save ORM (RGB: R=Occlusion, G=Roughness, B=Metallic)
    orm_r = (ao * 255.0).astype(np.uint8)
    orm_g = (roughness * 255.0).astype(np.uint8)
    orm_b = (metallic * 255.0).astype(np.uint8)
    orm_rgb = np.stack([orm_r, orm_g, orm_b], axis=2)
    Image.fromarray(orm_rgb, mode="RGB").save(OUT / f"{prop_id}_orm.png")

    # Save Height (Grayscale / RGB)
    height_u8 = (height * 255.0).astype(np.uint8)
    height_rgb = np.stack([height_u8, height_u8, height_u8], axis=2)
    Image.fromarray(height_rgb, mode="RGB").save(OUT / f"{prop_id}_height.png")

    print(f"  [prop] {prop_id:<16} -> albedo, orm, height generated (seed={seed})")


def main():
    props = [
        "push_button",
        "toggle",
        "rotary",
        "rocker",
        "knurled_dial",
        "dzus_fastener",
        "latch",
    ]
    print(f"Generating procedural UI prop textures into {OUT}...")
    for p in props:
        generate_prop_textures(p)
    print(f"All {len(props)} prop texture sets generated successfully.")


if __name__ == "__main__":
    main()
