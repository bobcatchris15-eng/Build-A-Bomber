"""
Scratch: rebuild the first-wave module parts (Geometric Polish Pass, module
detail vocabulary from Section 3) - barrels (stepped-diameter loft), wheel
hub (rim groove + lug bolts + stronger outer bevel), leg segments (joint
housing collar), and assault_hull (armor-plate rivets + tiered bevel on the
applique plates). Loads the real build_meshes.py module's function defs
(skipping its own top-level autorun) and exports each with its exact
catalog parameters, copied verbatim from generate_parts()/generate_hulls().

Run:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python scratch\\rebuild_module_parts_wave1.py
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
build_barrel = ns["build_barrel"]
build_wheel = ns["build_wheel"]
build_leg_segment = ns["build_leg_segment"]
build_wedge_hull = ns["build_wedge_hull"]
export_and_cleanup = ns["export_and_cleanup"]
PARTS_DIR = ns["PARTS_DIR"]
HULLS_DIR = ns["HULLS_DIR"]
_assault_hull_greebles = ns["_assault_hull_greebles"]

clear_scene()
export_and_cleanup(build_barrel("barrel_thin", length=1.0, radius=0.06, muzzle_radius=0.05), PARTS_DIR, "barrel_thin")
export_and_cleanup(build_barrel("barrel_standard", length=1.0, radius=0.1, muzzle_radius=0.09), PARTS_DIR, "barrel_standard")
export_and_cleanup(build_barrel("barrel_heavy", length=1.0, radius=0.16, muzzle_radius=0.22, fins=3), PARTS_DIR, "barrel_heavy")
export_and_cleanup(build_barrel("barrel_taper_wide", length=1.0, radius=0.08, muzzle_radius=0.1), PARTS_DIR, "barrel_taper_wide")

export_and_cleanup(build_wheel("wheel_hub", color=(0.08, 0.08, 0.08)), PARTS_DIR, "wheel_hub")

export_and_cleanup(build_leg_segment("leg_thigh", length=0.55, radius_top=0.13, radius_bottom=0.09, color=(0.3, 0.3, 0.32)), PARTS_DIR, "leg_thigh")
export_and_cleanup(build_leg_segment("leg_shin", length=0.5, radius_top=0.09, radius_bottom=0.06, color=(0.16, 0.16, 0.17)), PARTS_DIR, "leg_shin")

export_and_cleanup(build_wedge_hull("assault_hull", 5.0, 1.3, 7.0,
	nose_frac=0.4, spine_w=0.7, spine_h=1.22, rear_flare=1.0, front_flare=0.9,
	bevel_pct=0.085, bevel_segments=3,
	color=(0.4, 0.32, 0.28), greebles=_assault_hull_greebles), HULLS_DIR, "assault_hull")

print("=== module parts wave 1 rebuilt (barrels/wheel/legs/assault armor plates) ===")
