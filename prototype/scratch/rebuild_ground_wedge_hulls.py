"""
Scratch: rebuild light_hull/heavy_hull/interceptor_hull/assault_hull.glb
against the per-archetype-tuned build_wedge_hull() (Geometric Polish Pass
Tier 1, rolled out beyond medium_hull's validation pass). Loads the real
build_meshes.py module's function defs (skipping its own top-level autorun)
and exports each hull with its exact catalog parameters, copied verbatim
from generate_hulls().

Run:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python scratch\\rebuild_ground_wedge_hulls.py
"""
import os

SRC = os.path.join(os.path.dirname(__file__), "..", "tools", "blender", "build_meshes.py")
src_text = open(SRC, "r", encoding="utf-8").read()

marker = "clear_scene()\ngenerate_parts()\ngenerate_hulls()"
idx = src_text.index(marker)
defs_only = src_text[:idx]

ns = {"__name__": "build_meshes_defs"}
exec(compile(defs_only, SRC, "exec"), ns)

clear_scene = ns["clear_scene"]
build_wedge_hull = ns["build_wedge_hull"]
export_and_cleanup = ns["export_and_cleanup"]
HULLS_DIR = ns["HULLS_DIR"]
_light_hull_greebles = ns["_light_hull_greebles"]
_heavy_hull_greebles = ns["_heavy_hull_greebles"]
_interceptor_hull_greebles = ns["_interceptor_hull_greebles"]
_assault_hull_greebles = ns["_assault_hull_greebles"]

clear_scene()
export_and_cleanup(build_wedge_hull("light_hull", 3.0, 1.0, 4.0,
	nose_frac=0.6, spine_w=0.35, spine_h=1.08, rear_flare=0.85, front_flare=0.55,
	nose_region=0.28, bevel_pct=0.06,
	color=(0.72, 0.73, 0.75), greebles=_light_hull_greebles), HULLS_DIR, "light_hull")

export_and_cleanup(build_wedge_hull("heavy_hull", 6.0, 1.5, 8.0,
	nose_frac=0.08, spine_w=0.75, spine_h=1.2, rear_flare=1.0, front_flare=1.0,
	nose_region=0.5, bevel_pct=0.09, bevel_segments=3,
	color=(0.32, 0.32, 0.34), greebles=_heavy_hull_greebles), HULLS_DIR, "heavy_hull")

export_and_cleanup(build_wedge_hull("interceptor_hull", 2.4, 0.8, 3.2,
	nose_frac=0.95, spine_w=0.22, spine_h=1.05, rear_flare=0.75, front_flare=0.3,
	nose_region=0.22, height_taper=0.45, bevel_pct=0.05, bevel_segments=1,
	color=(0.55, 0.65, 0.78), greebles=_interceptor_hull_greebles), HULLS_DIR, "interceptor_hull")

export_and_cleanup(build_wedge_hull("assault_hull", 5.0, 1.3, 7.0,
	nose_frac=0.4, spine_w=0.7, spine_h=1.22, rear_flare=1.0, front_flare=0.9,
	bevel_pct=0.085, bevel_segments=3,
	color=(0.4, 0.32, 0.28), greebles=_assault_hull_greebles), HULLS_DIR, "assault_hull")

print("=== light/heavy/interceptor/assault hulls rebuilt (Tier 1 rollout) ===")
