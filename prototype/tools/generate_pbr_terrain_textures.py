"""
Procedural Seamless PBR Terrain Texture Plate Generator.
Generates albedo, normal (Sobel/central-difference with periodic wrapping),
and roughness (with packed height in green channel) maps for:
- Missing variants: ice (v1-v3), blue_water (v1-v3), shallow_water (v1-v3)
- New surface types: dirt, steppe_grass, dry_grass, mud, cobble, scree, volcanic
- Shared detail_normal.png
"""
import os
import math
import numpy as np
from PIL import Image

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TEXTURES_DIR = os.path.join(PROJECT_ROOT, "assets", "textures", "terrain")
TEX_SIZE = 512


def periodic_noise_2d(size, period=8, seed=0):
    """Generate seamless periodic value noise using cubic hermite interpolation."""
    rng = np.random.default_rng(seed)
    lattice = rng.random((period, period))
    
    # Grid of coordinates
    x = np.linspace(0, period, size, endpoint=False)
    y = np.linspace(0, period, size, endpoint=False)
    gx, gy = np.meshgrid(x, y)
    
    x0 = np.floor(gx).astype(int) % period
    y0 = np.floor(gy).astype(int) % period
    x1 = (x0 + 1) % period
    y1 = (y0 + 1) % period
    
    fx = gx - np.floor(gx)
    fy = gy - np.floor(gy)
    
    # Quintic Hermite
    ux = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0)
    uy = fy * fy * fy * (fy * (fy * 6.0 - 15.0) + 10.0)
    
    v00 = lattice[y0, x0]
    v10 = lattice[y0, x1]
    v01 = lattice[y1, x0]
    v11 = lattice[y1, x1]
    
    top = v00 * (1.0 - ux) + v10 * ux
    bottom = v01 * (1.0 - ux) + v11 * ux
    return top * (1.0 - uy) + bottom * uy


def periodic_fbm(size, base_period=4, octaves=4, persistence=0.5, seed=0):
    """Multi-octave seamless fBM noise."""
    res = np.zeros((size, size))
    amp = 1.0
    total_amp = 0.0
    period = base_period
    for oct_idx in range(octaves):
        res += periodic_noise_2d(size, period=period, seed=seed + oct_idx * 137) * amp
        total_amp += amp
        amp *= persistence
        period *= 2
    return res / total_amp


def height_to_normal_map(height, strength=2.5):
    """Compute seamless normal map via central differences with periodic wrap."""
    h_px = np.roll(height, -1, axis=1)
    h_mx = np.roll(height, 1, axis=1)
    h_py = np.roll(height, -1, axis=0)
    h_my = np.roll(height, 1, axis=0)
    
    dx = (h_px - h_mx) * strength
    dy = (h_py - h_my) * strength
    dz = np.ones_like(dx)
    
    norm = np.sqrt(dx * dx + dy * dy + dz * dz)
    nx = -dx / norm
    ny = -dy / norm
    nz = dz / norm
    
    # Map from [-1, 1] to [0, 255]
    r = ((nx * 0.5 + 0.5) * 255.0).astype(np.uint8)
    g = ((ny * 0.5 + 0.5) * 255.0).astype(np.uint8)
    b = ((nz * 0.5 + 0.5) * 255.0).astype(np.uint8)
    
    return np.stack([r, g, b], axis=-1)


def generate_texture_plate(name, base_color, color_jitter, base_roughness, roughness_jitter, height_strength, seed=0):
    """Generate and save albedo, normal, and roughness maps."""
    h = periodic_fbm(TEX_SIZE, base_period=8, octaves=4, seed=seed)
    detail_h = periodic_fbm(TEX_SIZE, base_period=32, octaves=3, seed=seed + 99)
    combined_h = h * 0.75 + detail_h * 0.25

    # Albedo
    r0, g0, b0 = base_color
    albedo = np.zeros((TEX_SIZE, TEX_SIZE, 3), dtype=np.float32)
    for c_idx, val in enumerate([r0, g0, b0]):
        jitter = (h - 0.5) * color_jitter[c_idx] + (detail_h - 0.5) * (color_jitter[c_idx] * 0.5)
        albedo[:, :, c_idx] = np.clip(val + jitter, 0.0, 1.0)
    albedo_img = (albedo * 255.0).astype(np.uint8)

    # Normal
    normal_img = height_to_normal_map(combined_h, strength=height_strength)

    # Roughness + packed Height in green channel for height-aware displacement
    rough = np.clip(base_roughness + (detail_h - 0.5) * roughness_jitter, 0.0, 1.0)
    r_chan = (rough * 255.0).astype(np.uint8)
    g_chan = (combined_h * 255.0).astype(np.uint8)  # packed displacement
    b_chan = np.zeros_like(r_chan)
    rough_img = np.stack([r_chan, g_chan, b_chan], axis=-1)

    alb_path = os.path.join(TEXTURES_DIR, f"{name}_albedo.png")
    nrm_path = os.path.join(TEXTURES_DIR, f"{name}_normal.png")
    rgh_path = os.path.join(TEXTURES_DIR, f"{name}_roughness.png")

    Image.fromarray(albedo_img, "RGB").save(alb_path)
    Image.fromarray(normal_img, "RGB").save(nrm_path)
    Image.fromarray(rough_img, "RGB").save(rgh_path)
    print(f"Generated {name} plate set -> {alb_path}")


def main():
    os.makedirs(TEXTURES_DIR, exist_ok=True)
    
    # 1. Missing variants for ice
    ice_colors = [
        (0.72, 0.82, 0.88),
        (0.68, 0.79, 0.86),
        (0.76, 0.85, 0.91)
    ]
    for v_idx, col in enumerate(ice_colors):
        generate_texture_plate(f"ice_v{v_idx+1}", col, (0.08, 0.06, 0.08), 0.25, 0.15, 1.8, seed=100+v_idx)

    # 2. Missing variants for blue_water & shallow_water
    water_colors = [
        (0.18, 0.26, 0.32),
        (0.15, 0.23, 0.29),
        (0.20, 0.29, 0.35)
    ]
    for v_idx, col in enumerate(water_colors):
        generate_texture_plate(f"blue_water_v{v_idx+1}", col, (0.04, 0.05, 0.06), 0.10, 0.05, 1.2, seed=200+v_idx)

    shallow_colors = [
        (0.32, 0.42, 0.44),
        (0.28, 0.39, 0.41),
        (0.36, 0.46, 0.48)
    ]
    for v_idx, col in enumerate(shallow_colors):
        generate_texture_plate(f"shallow_water_v{v_idx+1}", col, (0.05, 0.06, 0.06), 0.15, 0.08, 1.0, seed=250+v_idx)

    # 3. New surface types
    # Dirt / Ploughed
    dirt_colors = [(0.32, 0.25, 0.18), (0.29, 0.22, 0.15), (0.35, 0.27, 0.20)]
    for v_idx, col in enumerate(dirt_colors):
        generate_texture_plate(f"dirt_v{v_idx+1}", col, (0.08, 0.06, 0.05), 0.92, 0.08, 2.5, seed=300+v_idx)
    generate_texture_plate("dirt", dirt_colors[0], (0.08, 0.06, 0.05), 0.92, 0.08, 2.5, seed=300)

    # Steppe grass / Dry grass
    steppe_colors = [(0.42, 0.44, 0.26), (0.45, 0.47, 0.28), (0.39, 0.41, 0.24)]
    for v_idx, col in enumerate(steppe_colors):
        generate_texture_plate(f"steppe_grass_v{v_idx+1}", col, (0.06, 0.06, 0.05), 0.88, 0.08, 2.0, seed=350+v_idx)
    generate_texture_plate("steppe_grass", steppe_colors[0], (0.06, 0.06, 0.05), 0.88, 0.08, 2.0, seed=350)

    dry_colors = [(0.52, 0.48, 0.32), (0.55, 0.50, 0.34), (0.48, 0.44, 0.30)]
    for v_idx, col in enumerate(dry_colors):
        generate_texture_plate(f"dry_grass_v{v_idx+1}", col, (0.07, 0.07, 0.05), 0.90, 0.06, 2.0, seed=400+v_idx)
    generate_texture_plate("dry_grass", dry_colors[0], (0.07, 0.07, 0.05), 0.90, 0.06, 2.0, seed=400)

    # Mud (Dark, saturated, glossy per §4)
    mud_colors = [(0.18, 0.13, 0.09), (0.16, 0.11, 0.08), (0.20, 0.15, 0.11)]
    for v_idx, col in enumerate(mud_colors):
        generate_texture_plate(f"mud_v{v_idx+1}", col, (0.05, 0.04, 0.04), 0.25, 0.12, 2.2, seed=450+v_idx)
    generate_texture_plate("mud", mud_colors[0], (0.05, 0.04, 0.04), 0.25, 0.12, 2.2, seed=450)

    # Cobble / Paved
    cobble_colors = [(0.38, 0.36, 0.34), (0.35, 0.33, 0.31), (0.41, 0.39, 0.37)]
    for v_idx, col in enumerate(cobble_colors):
        generate_texture_plate(f"cobble_v{v_idx+1}", col, (0.06, 0.06, 0.06), 0.80, 0.10, 3.2, seed=500+v_idx)
    generate_texture_plate("cobble", cobble_colors[0], (0.06, 0.06, 0.06), 0.80, 0.10, 3.2, seed=500)

    # Scree (High-contrast stone fragments)
    scree_colors = [(0.44, 0.42, 0.38), (0.40, 0.38, 0.35), (0.47, 0.45, 0.41)]
    for v_idx, col in enumerate(scree_colors):
        generate_texture_plate(f"scree_v{v_idx+1}", col, (0.08, 0.08, 0.08), 0.94, 0.05, 3.5, seed=550+v_idx)
    generate_texture_plate("scree", scree_colors[0], (0.08, 0.08, 0.08), 0.94, 0.05, 3.5, seed=550)

    # Volcanic (Dark basalt & ash)
    volcanic_colors = [(0.14, 0.14, 0.15), (0.12, 0.12, 0.13), (0.17, 0.16, 0.18)]
    for v_idx, col in enumerate(volcanic_colors):
        generate_texture_plate(f"volcanic_v{v_idx+1}", col, (0.05, 0.04, 0.05), 0.88, 0.08, 3.0, seed=600+v_idx)
    generate_texture_plate("volcanic", volcanic_colors[0], (0.05, 0.04, 0.05), 0.88, 0.08, 3.0, seed=600)
    
    # Shared detail micro-normal
    detail_h = periodic_fbm(TEX_SIZE, base_period=64, octaves=3, seed=999)
    detail_nrm = height_to_normal_map(detail_h, strength=1.5)
    detail_path = os.path.join(TEXTURES_DIR, "detail_normal.png")
    Image.fromarray(detail_nrm, "RGB").save(detail_path)
    print(f"Generated shared detail normal -> {detail_path}")


if __name__ == "__main__":
    main()
