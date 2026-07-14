"""
Scratch: rebuild pillbox_foundation/tower_foundation/fortress_wall_foundation
against the updated build_bunker_hull/build_tower_hull/build_wall_hull
(Geometric Polish Pass Tier 1 - tiered bevel, tower base skirt, wall bevel
with end-cap preservation for tiling). Loads the real build_meshes.py
module's function defs (skipping its own top-level autorun) and exports
each with its exact catalog parameters, copied verbatim from generate_hulls().

Run:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python scratch\\rebuild_static_foundations.py
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
build_bunker_hull = ns["build_bunker_hull"]
build_tower_hull = ns["build_tower_hull"]
build_wall_hull = ns["build_wall_hull"]
export_and_cleanup = ns["export_and_cleanup"]
HULLS_DIR = ns["HULLS_DIR"]
_pillbox_greebles = ns["_pillbox_greebles"]
_tower_greebles = ns["_tower_greebles"]
_wall_greebles = ns["_wall_greebles"]

clear_scene()
export_and_cleanup(build_bunker_hull("pillbox_foundation", 3.0, 1.2, 3.0,
	sides=8, taper=0.7, color=(0.45, 0.45, 0.4), greebles=_pillbox_greebles), HULLS_DIR, "pillbox_foundation")

export_and_cleanup(build_tower_hull("tower_foundation", 3.0, 4.0, 3.0,
	tiers=3, color=(0.5, 0.48, 0.44), greebles=_tower_greebles), HULLS_DIR, "tower_foundation")

export_and_cleanup(build_wall_hull("fortress_wall_foundation", 6.0, 2.2, 1.3,
	merlons=5, color=(0.42, 0.4, 0.36), greebles=_wall_greebles), HULLS_DIR, "fortress_wall_foundation")

print("=== pillbox/tower/fortress_wall foundations rebuilt (Tier 1 rollout) ===")
