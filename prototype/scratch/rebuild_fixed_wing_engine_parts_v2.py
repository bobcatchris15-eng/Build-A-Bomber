"""
Scratch: regenerate engine_nacelle.glb, engine_core.glb, engine_fan.glb,
exhaust_cone.glb after fixing the add_cyl_axis 'x'/'z' axis-swap bug
locally inside these four builders (see build_engine_core's comment in
build_meshes.py). mount_strut_aerofoil is untouched (built along Y via a
manual profile sweep, not add_cyl_axis) so it's not regenerated here.

Run:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python scratch\\rebuild_fixed_wing_engine_parts_v2.py
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
build_engine_nacelle = ns["build_engine_nacelle"]
build_engine_core = ns["build_engine_core"]
build_engine_fan = ns["build_engine_fan"]
build_exhaust_cone = ns["build_exhaust_cone"]
export_and_cleanup = ns["export_and_cleanup"]
PARTS_DIR = ns["PARTS_DIR"]

clear_scene()
export_and_cleanup(build_engine_nacelle("engine_nacelle"), PARTS_DIR, "engine_nacelle")
export_and_cleanup(build_engine_core("engine_core"), PARTS_DIR, "engine_core")
export_and_cleanup(build_engine_fan("engine_fan"), PARTS_DIR, "engine_fan")
export_and_cleanup(build_exhaust_cone("exhaust_cone"), PARTS_DIR, "exhaust_cone")

print("=== fixed_wing_engine parts regenerated (nacelle, core, fan, exhaust_cone) ===")
