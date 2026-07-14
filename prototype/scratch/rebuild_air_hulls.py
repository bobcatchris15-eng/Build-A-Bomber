"""
Scratch: rebuild flying_wing_hull/fuselage_hull/airship_hull.glb against
the updated build_flying_wing_hull/build_fuselage_hull/build_airship_hull
(Geometric Polish Pass Tier 1 - tiered bevel; fuselage's nose/body/tail
cone segments are now welded into one continuous mesh so the bevel has a
real seam to smooth; airship's gondola/fin bevels now use the R-keyed
tiered system instead of magic numbers, envelope topology itself deferred
to Tier 3 per the design doc). Loads the real build_meshes.py module's
function defs (skipping its own top-level autorun) and exports each with
its exact catalog parameters, copied verbatim from generate_hulls().

Run:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python scratch\\rebuild_air_hulls.py
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
build_flying_wing_hull = ns["build_flying_wing_hull"]
build_fuselage_hull = ns["build_fuselage_hull"]
build_airship_hull = ns["build_airship_hull"]
export_and_cleanup = ns["export_and_cleanup"]
HULLS_DIR = ns["HULLS_DIR"]
_flying_wing_hull_greebles = ns["_flying_wing_hull_greebles"]
_fuselage_hull_greebles = ns["_fuselage_hull_greebles"]
_airship_hull_greebles = ns["_airship_hull_greebles"]

clear_scene()
export_and_cleanup(build_flying_wing_hull("flying_wing_hull", 5.0, 0.7, 3.6,
	sweep=0.55, color=(0.5, 0.52, 0.56), greebles=_flying_wing_hull_greebles), HULLS_DIR, "flying_wing_hull")

export_and_cleanup(build_fuselage_hull("fuselage_hull", 4.2, 1.2, 6.2,
	color=(0.6, 0.6, 0.62), greebles=_fuselage_hull_greebles), HULLS_DIR, "fuselage_hull")

export_and_cleanup(build_airship_hull("airship_hull", 4.0, 3.0, 9.5,
	tail_taper=0.4, color=(0.72, 0.7, 0.6), greebles=_airship_hull_greebles), HULLS_DIR, "airship_hull")

print("=== flying_wing/fuselage/airship hulls rebuilt (Tier 1 rollout) ===")
