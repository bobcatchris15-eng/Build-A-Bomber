"""
Scratch: export the new mount_strut_flat.glb (hover_engine's hull-mounting
pylon - a flattened version of the helicopter_rotors tapered strut, about
3x as wide as it is thick, per Chris's ask).
Loads the real build_meshes.py module's function defs (skipping its own
top-level autorun) and exports with its exact catalog parameters.

Run:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python scratch\\rebuild_mount_strut_flat.py
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
build_tapered_strut = ns["build_tapered_strut"]
export_and_cleanup = ns["export_and_cleanup"]
PARTS_DIR = ns["PARTS_DIR"]

clear_scene()
export_and_cleanup(build_tapered_strut("mount_strut_flat", depth_scale=1.0 / 3.0), PARTS_DIR, "mount_strut_flat")

print("=== mount_strut_flat exported (new part) ===")
