"""
Scratch: rebuild ONLY medium_hull.glb against the updated build_wedge_hull()
(tiered bevel + non-linear taper, Geometric Polish Pass Tier 1). The shared
function change in tools/blender/build_meshes.py affects all 5 wedge-based
hulls (light/medium/heavy/interceptor/assault), but the design doc calls for
validating against medium_hull first before rebuilding the rest - so this
loads the real build_meshes.py module (functions only, skipping its own
top-level autorun) and exports just medium_hull with its exact catalog
parameters, copied verbatim from generate_hulls().

Run:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python scratch\\rebuild_medium_hull_only.py
"""
import os

SRC = os.path.join(os.path.dirname(__file__), "..", "tools", "blender", "build_meshes.py")
src_text = open(SRC, "r", encoding="utf-8").read()

# Strip the module's own top-level autorun (last 5 lines: clear_scene(),
# generate_parts(), generate_hulls(), print(...)) so importing it here
# doesn't rebuild the entire parts+hull library.
marker = "clear_scene()\ngenerate_parts()\ngenerate_hulls()"
idx = src_text.index(marker)
defs_only = src_text[:idx]

ns = {"__name__": "build_meshes_defs"}
exec(compile(defs_only, SRC, "exec"), ns)

clear_scene = ns["clear_scene"]
build_wedge_hull = ns["build_wedge_hull"]
export_and_cleanup = ns["export_and_cleanup"]
_medium_hull_greebles = ns["_medium_hull_greebles"]
HULLS_DIR = ns["HULLS_DIR"]

clear_scene()
export_and_cleanup(build_wedge_hull("medium_hull", 4.0, 1.0, 6.0,
	nose_frac=0.25, spine_w=0.6, spine_h=1.15, rear_flare=1.0, front_flare=0.85,
	color=(0.5, 0.5, 0.52), greebles=_medium_hull_greebles), HULLS_DIR, "medium_hull")

print("=== medium_hull.glb rebuilt (Tier 1: tiered bevel + non-linear taper) ===")
