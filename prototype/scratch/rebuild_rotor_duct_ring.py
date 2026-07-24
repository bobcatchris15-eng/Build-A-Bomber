"""
Scratch: rebuild rotor_duct_ring.glb against the fixed build_rotor_duct_ring()
(was a solid capped drum via add_cyl_y - no hollow option - now a genuine
hollow tube via cap_ends=False, so the blades are actually visible spinning
inside the duct instead of hidden behind an opaque disc).
Loads the real build_meshes.py module's function defs (skipping its own
top-level autorun) and exports with its exact catalog parameters.

Run:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python scratch\\rebuild_rotor_duct_ring.py
"""
import os

SRC = os.path.join(os.path.dirname(__file__), "..", "tools", "blender", "build_meshes.py")
src_text = open(SRC, "r", encoding="utf-8").read()

marker = "clear_scene()\ngenerate_parts()"
idx = src_text.index(marker)
defs_only = src_text[:idx]

ns = {"__name__": "build_meshes_defs", "__file__": SRC}
exec(compile(defs_only, SRC, "exec"), ns)

clear_scene = ns["clear_scene"]
build_rotor_duct_ring = ns["build_rotor_duct_ring"]
export_and_cleanup = ns["export_and_cleanup"]
PARTS_DIR = ns["PARTS_DIR"]

clear_scene()
export_and_cleanup(build_rotor_duct_ring("rotor_duct_ring"), PARTS_DIR, "rotor_duct_ring")

print("=== rotor_duct_ring rebuilt (hollow tube fix) ===")
