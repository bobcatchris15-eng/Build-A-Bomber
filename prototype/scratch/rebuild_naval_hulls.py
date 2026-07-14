"""
Scratch: rebuild naval_hull/small_boat_hull/heavy_cruiser_hull.glb against
the updated build_ship_hull() (Geometric Polish Pass Tier 1 - real per-
station V-deadrise loft, sheer, topside flare, tiered bevel). Loads the
real build_meshes.py module's function defs (skipping its own top-level
autorun) and exports each with its exact catalog parameters, copied
verbatim from generate_hulls().

Run:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python scratch\\rebuild_naval_hulls.py
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
build_ship_hull = ns["build_ship_hull"]
export_and_cleanup = ns["export_and_cleanup"]
HULLS_DIR = ns["HULLS_DIR"]
_ship_hull_greebles = ns["_ship_hull_greebles"]
_small_boat_greebles = ns["_small_boat_greebles"]
_heavy_cruiser_greebles = ns["_heavy_cruiser_greebles"]

clear_scene()
export_and_cleanup(build_ship_hull("naval_hull", 3.5, 1.6, 9.0,
	bow_frac=0.35, deadrise=0.3, sheer=0.08, flare=0.0, bevel_pct=0.07,
	color=(0.35, 0.38, 0.4), greebles=_ship_hull_greebles), HULLS_DIR, "naval_hull")

export_and_cleanup(build_ship_hull("small_boat_hull", 2.0, 1.0, 5.0,
	bow_frac=0.5, deadrise=0.55, sheer=0.15, flare=0.0, bevel_pct=0.06, bevel_segments=1,
	color=(0.4, 0.42, 0.44), greebles=_small_boat_greebles), HULLS_DIR, "small_boat_hull")

export_and_cleanup(build_ship_hull("heavy_cruiser_hull", 4.4, 1.9, 10.5,
	bow_frac=0.28, deadrise=0.12, sheer=0.22, flare=0.35, bevel_pct=0.09, bevel_segments=3,
	color=(0.3, 0.32, 0.34), greebles=_heavy_cruiser_greebles), HULLS_DIR, "heavy_cruiser_hull")

print("=== naval/small_boat/heavy_cruiser hulls rebuilt (Tier 1 rollout) ===")
