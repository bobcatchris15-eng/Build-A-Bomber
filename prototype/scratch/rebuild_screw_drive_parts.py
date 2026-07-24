"""
Scratch: regenerate screw_drum.glb (axis-swap fix - was oriented spanwise
instead of fore-aft), two new discrete depth variants for the new
"Helix Depth" tweak (screw_drum_shallow/screw_drum_deep - a single static
GLB can't be continuously re-deformed at runtime, so depth is a 3-way
variant pick instead of a continuous scale), and rg_screw_cradle.glb
(axis-swap fix, reused as the new "gearbox that projects out and down from
the fore and aft corners of the hull" - Chris's ask, 2026-07-24).

Run:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python scratch\\rebuild_screw_drive_parts.py
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
build_screw_drum = ns["build_screw_drum"]
build_rg_screw_cradle = ns["build_rg_screw_cradle"]
export_and_cleanup = ns["export_and_cleanup"]
PARTS_DIR = ns["PARTS_DIR"]

clear_scene()
export_and_cleanup(build_screw_drum("screw_drum"), PARTS_DIR, "screw_drum")
export_and_cleanup(build_screw_drum("screw_drum_shallow", fin_reach=0.09), PARTS_DIR, "screw_drum_shallow")
export_and_cleanup(build_screw_drum("screw_drum_deep", fin_reach=0.24), PARTS_DIR, "screw_drum_deep")
export_and_cleanup(build_rg_screw_cradle("screw_gearbox"), PARTS_DIR, "screw_gearbox")

print("=== screw_drive parts regenerated (screw_drum, screw_drum_shallow, screw_drum_deep, screw_gearbox) ===")
