"""
Scratch: rebuild tread_plate.glb against the updated build_tread_plate()
(Geometric Polish Pass - tiered bevel on the base plate and link ridges).
Loads the real build_meshes.py module's function defs (skipping its own
top-level autorun) and exports with its exact catalog parameters.

Run:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python scratch\\rebuild_tread_plate.py
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
build_tread_plate = ns["build_tread_plate"]
export_and_cleanup = ns["export_and_cleanup"]
PARTS_DIR = ns["PARTS_DIR"]

clear_scene()
export_and_cleanup(build_tread_plate("tread_plate", color=(0.16, 0.16, 0.17)), PARTS_DIR, "tread_plate")

print("=== tread_plate rebuilt (Tier 1 rollout) ===")
