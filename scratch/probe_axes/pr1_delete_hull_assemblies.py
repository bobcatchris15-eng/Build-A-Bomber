"""
PR 1 follow-up: delete the obsolete CSG-recipe files in
prototype/data/hull_assemblies/. These were the SDF-mesh-bake
recipes for the legacy hulls (medium_hull, scout_hull, etc.) plus
a handful of vestigial prototype entries (the_cube, airship_hull,
etc.) that never made it to production. The new hulls use
bake_custom_hull.py (primitive composition) or hand-authored
build_*.py, not the SDF mesh baker, so these recipes are dead.

Files to delete (all 15 in prototype/data/hull_assemblies/):
  airship_hull.json
  assault_hull.json
  cabover_truck_hull.json
  dreadnought_wedge_hull.json
  heavy_hull.json
  landing_craft_hull.json
  light_hull.json
  locomotive_hull.json
  medium_hull.json
  pressure_hull.json
  roadster_hull.json
  rotor_fuselage_hull.json
  scout_hull.json
  transport_hull.json
  water_tower_hull.json
"""
import os
import shutil

ROOT = r'E:\Kitbash-Command'
ASSEMBLY_DIR = os.path.join(ROOT, 'prototype', 'data', 'hull_assemblies')
TRASH = os.path.join(os.path.expanduser('~'), '.mavis', 'trash', 'pr1_delete_hull_assemblies')

os.makedirs(TRASH, exist_ok=True)

moved = []
for fname in os.listdir(ASSEMBLY_DIR):
    p = os.path.join(ASSEMBLY_DIR, fname)
    if not os.path.isfile(p):
        continue
    target = os.path.join(TRASH, fname)
    n = 1
    while os.path.exists(target):
        target = os.path.join(TRASH, '%s.%d' % (fname, n))
        n += 1
    shutil.move(p, target)
    moved.append((p, target))

print('Moved %d files to %s:' % (len(moved), TRASH))
for src, dst in moved:
    print('  %s -> %s' % (os.path.basename(src), os.path.basename(dst)))

# Also remove the now-empty directory
try:
    os.rmdir(ASSEMBLY_DIR)
    print('Removed empty directory: %s' % ASSEMBLY_DIR)
except OSError as e:
    print('Directory not empty or other error: %s' % e)
