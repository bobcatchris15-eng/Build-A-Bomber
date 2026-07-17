"""
Scratch: rebuild ONE named hull.glb against the current build_meshes.py,
without touching the rest of the parts+hull library (keeps each hull's
commit scoped to just that hull, avoiding incidental re-export diffs on
unrelated assets). Loads the real build_meshes.py module (functions only,
skipping its own top-level autorun) and re-executes just the one
export_and_cleanup(...) call for the requested hull, copied verbatim out
of generate_hulls().

Run:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python scratch\\rebuild_single_hull.py -- <hull_name>
"""
import os
import sys

HULL_NAME = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assault_hull"

SRC = os.path.join(os.path.dirname(__file__), "..", "tools", "blender", "build_meshes.py")
src_text = open(SRC, "r", encoding="utf-8").read()

marker = "clear_scene()\ngenerate_parts()\ngenerate_hulls()"
idx = src_text.index(marker)
defs_only = src_text[:idx]

ns = {"__name__": "build_meshes_defs"}
exec(compile(defs_only, SRC, "exec"), ns)

clear_scene = ns["clear_scene"]
export_and_cleanup = ns["export_and_cleanup"]
HULLS_DIR = ns["HULLS_DIR"]

# Extract generate_hulls()'s body text so we can find and run only the one
# export_and_cleanup(...) call matching HULL_NAME, exactly as authored -
# avoids hand-duplicating each hull's parameter list into this script.
gh_start = src_text.index("def generate_hulls():")
gh_body = src_text[gh_start:idx]
calls = gh_body.split("export_and_cleanup(")[1:]
target_call = None
for call in calls:
	if call.lstrip().startswith(f'build_wedge_hull("{HULL_NAME}"') or \
	   call.lstrip().startswith(f'build_afv_hull("{HULL_NAME}"') or \
	   call.lstrip().startswith(f'build_ship_hull("{HULL_NAME}"') or \
	   call.lstrip().startswith(f'build_bunker_hull("{HULL_NAME}"') or \
	   call.lstrip().startswith(f'build_tower_hull("{HULL_NAME}"') or \
	   call.lstrip().startswith(f'build_wall_hull("{HULL_NAME}"') or \
	   call.lstrip().startswith(f'build_sponson_hull("{HULL_NAME}"') or \
	   call.lstrip().startswith(f'build_fuselage_hull("{HULL_NAME}"') or \
	   call.lstrip().startswith(f'build_airship_hull("{HULL_NAME}"') or \
	   call.lstrip().startswith(f'build_flying_wing_hull("{HULL_NAME}"'):
		target_call = call
		break

if target_call is None:
	raise SystemExit(f"Could not find export_and_cleanup(...) call for hull '{HULL_NAME}' in generate_hulls()")

# Find the matching close paren for this call (balance parens across the
# call's own text) so we grab exactly one full call, not the rest of the file.
depth = 1
end = 0
for i, ch in enumerate(target_call):
	if ch == '(':
		depth += 1
	elif ch == ')':
		depth -= 1
		if depth == 0:
			end = i
			break
call_src = "export_and_cleanup(" + target_call[:end + 1]

clear_scene()
exec(compile(call_src, SRC, "exec"), ns)

print(f"=== {HULL_NAME}.glb rebuilt ===")
