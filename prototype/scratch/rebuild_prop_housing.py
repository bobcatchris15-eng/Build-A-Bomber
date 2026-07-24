"""
Scratch: regenerate prop_housing.glb after fixing the add_cyl_axis 'x'/'z'
axis-swap bug locally inside this builder (same fix already applied to
build_engine_nacelle/build_engine_core/build_exhaust_cone). Chris's report,
2026-07-24: the naval_propeller/buoyant_envelope housing cone faced
spanwise instead of backwards.

Run:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python scratch\\rebuild_prop_housing.py
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
build_prop_housing = ns["build_prop_housing"]
export_and_cleanup = ns["export_and_cleanup"]
PARTS_DIR = ns["PARTS_DIR"]

clear_scene()
export_and_cleanup(build_prop_housing("prop_housing"), PARTS_DIR, "prop_housing")

print("=== prop_housing regenerated ===")
