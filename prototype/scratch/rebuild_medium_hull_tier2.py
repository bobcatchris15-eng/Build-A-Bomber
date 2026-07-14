"""
Scratch: rebuild medium_hull.glb against the new waist-inset + deck-line
step (Geometric Polish Pass Tier 2), validating on medium_hull first per
the design doc's own sequencing. Loads the real build_meshes.py module's
function defs (skipping its own top-level autorun) and exports with the
exact catalog parameters, copied verbatim from generate_hulls().

Run:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python scratch\\rebuild_medium_hull_tier2.py
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
_medium_hull_greebles = ns["_medium_hull_greebles"]

clear_scene()
export_and_cleanup(build_wedge_hull("medium_hull", 4.0, 1.0, 6.0,
	nose_frac=0.25, spine_w=0.6, spine_h=1.15, rear_flare=1.0, front_flare=0.85,
	waist_inset=0.09, waist_height_frac=0.5, deck_line=0.5,
	color=(0.5, 0.5, 0.52), greebles=_medium_hull_greebles), HULLS_DIR, "medium_hull")

print("=== medium_hull.glb rebuilt (Tier 2: waist-inset + deck-line step) ===")
