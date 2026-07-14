"""
Scratch: rebuild the second-wave module parts - turret bodies
(build_cylinder_part/build_box_part now get a real tier-1 bevel instead of
none or a fixed magic number) and mounting hardware (build_pintle_mount now
uses the tiered tier-3 "lightest touch" bevel instead of a fixed 0.006).
Loads the real build_meshes.py module's function defs (skipping its own
top-level autorun) and exports each with its exact catalog parameters,
copied verbatim from generate_parts().

Run:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python scratch\\rebuild_module_parts_wave2.py
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
build_cylinder_part = ns["build_cylinder_part"]
build_box_part = ns["build_box_part"]
build_pintle_mount = ns["build_pintle_mount"]
export_and_cleanup = ns["export_and_cleanup"]
PARTS_DIR = ns["PARTS_DIR"]

clear_scene()
export_and_cleanup(build_cylinder_part("turret_base_round", radius=0.4, height=0.35, color=(0.32, 0.32, 0.35)), PARTS_DIR, "turret_base_round")
export_and_cleanup(build_box_part("turret_base_box", size=(1.0, 0.5, 0.7), color=(0.32, 0.32, 0.35)), PARTS_DIR, "turret_base_box")
export_and_cleanup(build_cylinder_part("ammo_drum", radius=0.5, height=0.4, color=(0.22, 0.24, 0.2)), PARTS_DIR, "ammo_drum")
export_and_cleanup(build_cylinder_part("canister_small", radius=0.4, height=1.0, color=(0.5, 0.15, 0.12)), PARTS_DIR, "canister_small")
export_and_cleanup(build_cylinder_part("fuel_tank", radius=0.5, height=1.0, color=(0.4, 0.1, 0.1)), PARTS_DIR, "fuel_tank")
export_and_cleanup(build_pintle_mount("pintle_mount", color=(0.18, 0.18, 0.2)), PARTS_DIR, "pintle_mount")
export_and_cleanup(build_cylinder_part("muzzle_brake", radius=0.5, height=0.5, segments=10, color=(0.15, 0.15, 0.16)), PARTS_DIR, "muzzle_brake")

print("=== module parts wave 2 rebuilt (turret bodies + mounting hardware) ===")
