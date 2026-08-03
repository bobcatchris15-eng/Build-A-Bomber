"""Rebuilds ONLY the autocannon's four .glb parts.

build_roster_expansion.py's own main() rebuilds every weapon in the roster
expansion (MK19, recoilless, coil gun, napalm mortar, mine layer, ballista,
smoke discharger, anti-materiel rifle...). Re-exporting all of those to change
one gun would rewrite a dozen unrelated .glb files - each one a binary blob in
git whose diff nobody can review - so this driver imports that module and calls
the single builder.

Run:
  ./UPBGE-0.30-windows-x86_64/blender.exe --background --factory-startup \
      --python tools/blender/rebuild_autocannon.py
"""

import os
import sys
import importlib.util

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Imported by path rather than by name: Blender runs this file as __main__ with
# its own sys.path, and tools/blender is not a package.
spec = importlib.util.spec_from_file_location(
    "build_roster_expansion", os.path.join(SCRIPT_DIR, "build_roster_expansion.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

mod.clear_scene()
mod.build_autocannon()
print("[rebuild_autocannon] done")
