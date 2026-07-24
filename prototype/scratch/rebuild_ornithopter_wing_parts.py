"""
Scratch: regenerate wing_membrane.glb, wing_rib.glb, and wing_shoulder.glb
for the dragonfly-style ornithopter_wing rebuild (Chris's ask, 2026-07-24 -
longer/narrower wings, then a lengthened gearbox + mirrored inner connector
panel in a follow-up pass the same day).

Run:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python scratch\\rebuild_ornithopter_wing_parts.py
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
build_wing_membrane = ns["build_wing_membrane"]
build_wing_rib = ns["build_wing_rib"]
build_wing_shoulder = ns["build_wing_shoulder"]
export_and_cleanup = ns["export_and_cleanup"]
PARTS_DIR = ns["PARTS_DIR"]

clear_scene()
export_and_cleanup(build_wing_membrane("wing_membrane"), PARTS_DIR, "wing_membrane")
export_and_cleanup(build_wing_rib("wing_rib"), PARTS_DIR, "wing_rib")
export_and_cleanup(build_wing_shoulder("wing_shoulder"), PARTS_DIR, "wing_shoulder")

print("=== ornithopter_wing parts regenerated (wing_membrane, wing_rib, wing_shoulder) ===")
