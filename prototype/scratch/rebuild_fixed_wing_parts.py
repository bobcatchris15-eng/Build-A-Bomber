"""
Scratch: export the new engine_core.glb (turbine core segment, stretched by
fixed_wing_engine's turbine_compression tweak) and mount_strut_aerofoil.glb
(aerofoil-cross-section mounting pylon) - Chris's fixed_wing_engine redesign.
Loads the real build_meshes.py module's function defs (skipping its own
top-level autorun) and exports with its exact catalog parameters.

Run:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python scratch\\rebuild_fixed_wing_parts.py
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
build_engine_core = ns["build_engine_core"]
build_aerofoil_strut = ns["build_aerofoil_strut"]
export_and_cleanup = ns["export_and_cleanup"]
PARTS_DIR = ns["PARTS_DIR"]

clear_scene()
export_and_cleanup(build_engine_core("engine_core"), PARTS_DIR, "engine_core")
export_and_cleanup(build_aerofoil_strut("mount_strut_aerofoil"), PARTS_DIR, "mount_strut_aerofoil")

print("=== fixed_wing_engine new parts exported (engine_core, mount_strut_aerofoil) ===")
