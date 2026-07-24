"""
Scratch: rebuild leg_thigh/leg_shin (new longitudinal ridges) and export the
new leg_joint part (bulky faceted hip/ankle joint housing) - Chris's "cooler"
legs pass. Loads the real build_meshes.py module's function defs (skipping
its own top-level autorun) and exports with its exact catalog parameters.

Run:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python scratch\\rebuild_leg_parts.py
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
build_leg_segment = ns["build_leg_segment"]
build_leg_joint = ns["build_leg_joint"]
export_and_cleanup = ns["export_and_cleanup"]
PARTS_DIR = ns["PARTS_DIR"]

clear_scene()
export_and_cleanup(build_leg_segment("leg_thigh", length=0.55, radius_top=0.13, radius_bottom=0.09, color=(0.3, 0.3, 0.32)), PARTS_DIR, "leg_thigh")
export_and_cleanup(build_leg_segment("leg_shin", length=0.5, radius_top=0.09, radius_bottom=0.06, color=(0.16, 0.16, 0.17)), PARTS_DIR, "leg_shin")
export_and_cleanup(build_leg_joint("leg_joint"), PARTS_DIR, "leg_joint")

print("=== leg parts rebuilt (ridges + new faceted joint) ===")
