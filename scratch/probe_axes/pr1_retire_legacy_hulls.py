"""
PR 1 retirement: delete the existing legacy + modern + WIP hull
artifacts from disk. Does NOT touch the 3 foundations
(pillbox / tower / fortress_wall) - those are renamed, not
deleted, in PR 6.

What this deletes:
  - prototype/assets/models/hulls/<legacy_name>.{glb,import,json}
  - prototype/assets/models/hulls/<modern_name>.{glb,import,json}
  - prototype/assets/models/hulls/<orphan_name>.{glb,import,json,res}
  - the abstract "the_*" hulls (no .glb, but .json + maybe .res)
  - prototype/assets/models/hulls/<orphan_name>.res with no .glb
  - NEW_HULLS/hull_*.glb (8 WIP files at the repo root)
  - the renamed .res files that reference the deleted hulls

What this RENAMES (to keep the test suite loadable):
  - medium_hull.{glb,import,json} -> block_main_meridian_a.{glb,import,json}
    (placeholder; PR 2 will re-author this as a real Block family
    hull. Keeping the .glb means tests that load the mesh by name
    can resolve at least one entry; until PR 2 ships, this is the
    same geometry as the legacy medium_hull, just under a new name.)

What this keeps:
  - pillbox_foundation.{glb,import,json}
  - tower_foundation.{glb,import,json}
  - fortress_wall_foundation.{glb,import,json}
    These are renamed in PR 6; for PR 1 we just leave them alone.

Operates via the user-trash directory (recoverable, not hard-delete).
"""
import os
import shutil

ROOT = r'E:\Kitbash-Command'
TRASH = os.path.join(os.path.expanduser('~'), '.mavis', 'trash', 'pr1_retire_legacy_hulls')
HULLS = os.path.join(ROOT, 'prototype', 'assets', 'models', 'hulls')
NEW_HULLS = os.path.join(ROOT, 'NEW_HULLS')

os.makedirs(TRASH, exist_ok=True)


def trashed(path):
    """Move a single file to the trash, return the new path."""
    name = os.path.basename(path)
    target = os.path.join(TRASH, name)
    # Disambiguate if the trash already has a file with this name
    n = 1
    while os.path.exists(target):
        target = os.path.join(TRASH, '%s.%d' % (name, n))
        n += 1
    shutil.move(path, target)
    return target


# --- Hulls to delete ----------------------------------------------------

# Legacy tier 1/2 (military-typology names). Both the base name and any
# _mk2 / _mod_4a* / _heavy / _light variants. medium_hull is special
# (renamed below).
LEGACY = [
    'scout_hull',
    'scout_hull_mk2',
    'scout_hull_mod_4a2',
    'light_hull',
    'light_hull_mk2',
    'light_hull_mod_4a3',
    # 'medium_hull',  # renamed below, not deleted
    'medium_hull_mk2',
    'medium_hull_mod_4a4',
    'heavy_hull',
    'heavy_hull_mk2',
    'heavy_hull_mod_4a5',
    'transport_hull',
    'transport_hull_mk2',
    'transport_hull_mod_4a6',
    'heavy_transport_hull_mod_4a7',
    'open_transport_hull_mod_4a8',
    'assault_hull',
    'assault_hull_mod_4a9',
]

# Modern tier 3 (abstract names). All base + light/heavy/broad/flatbed
# variants.
MODERN = [
    'capsule_hull', 'capsule_hull_light', 'capsule_hull_heavy',
    'carapace_hull', 'carapace_hull_light', 'carapace_hull_heavy',
    'catamaran_hull', 'catamaran_hull_light', 'catamaran_hull_heavy',
    'crawler_hull', 'crawler_hull_light', 'crawler_hull_heavy',
    'delta_plate_hull', 'delta_plate_hull_light', 'delta_plate_hull_heavy',
    'flatbed_hull', 'flatbed_hull_light', 'flatbed_hull_heavy',
    'gantry_hull', 'gantry_hull_light', 'gantry_hull_flatbed',
    'hex_pod_hull', 'hex_pod_hull_light', 'hex_pod_hull_heavy',
    'octaplate_hull', 'octaplate_hull_light', 'octaplate_hull_broad',
    'spire_hull', 'spire_hull_light', 'spire_hull_heavy',
    'tandem_hull', 'tandem_hull_light', 'tandem_hull_heavy',
    'tank_drum_hull', 'tank_drum_hull_light', 'tank_drum_hull_heavy',
]

# Orphans: have .json and/or .res but no .glb. These are vestigial
# prototype entries that pre-date the current .glb roster.
ORPHANS = [
    'airship_hull',
    'cabover_truck_hull',
    'dreadnought_wedge_hull',
    'landing_craft_hull',
    'locomotive_hull',
    'pressure_hull',
    'roadster_hull',
    'rotor_fuselage_hull',
    'water_tower_hull',
    'the_cube', 'the_orb', 'the_rod', 'the_slab',
]

# Foundations: KEEP - they are renamed in PR 6, not deleted in PR 1.
# KEEP = ['pillbox_foundation', 'tower_foundation', 'fortress_wall_foundation']

# The 8 WIP files at repo root. These were never in the catalogue;
# they were Chris's in-progress hand-author attempts that informed
# the refresh plan. Move them to trash.
WIP = [
    'hull_01_scout',
    'hull_02_light_tank',
    'hull_03_medium_tank',
    'hull_04_heavy_tank',
    'hull_05_medium_transport',
    'hull_06_heavy_transport',
    'hull_07_open_topped_transport',
    'hull_08_assault_vehicle',
]

# medium_hull is renamed in place to the new default hull. The medium
# hull's existing .glb is the most-tested in the catalogue and serves
# as a placeholder for the new block_main_meridian_a until PR 2 ships
# the real Block family hull. After the rename, PR 2's author can
# re-author the file under the same name.
RENAME_MEDIUM = ('medium_hull', 'block_main_meridian_a')


def file_variants(stem):
    """All the file extensions a hull entry might have."""
    return [
        '%s.glb' % stem,
        '%s.glb.import' % stem,
        '%s.json' % stem,
        '%s.res' % stem,
    ]


# --- Run ----------------------------------------------------------------

actions = []


def delete_hull(stem, label):
    for fname in file_variants(stem):
        p = os.path.join(HULLS, fname)
        if os.path.exists(p):
            t = trashed(p)
            actions.append(('DELETE', p, t))
        else:
            actions.append(('SKIP (not present)', p, None))


def rename_hull(old_stem, new_stem):
    for fname in file_variants(old_stem):
        p = os.path.join(HULLS, fname)
        new_name = fname.replace(old_stem, new_stem, 1)
        np = os.path.join(HULLS, new_name)
        if os.path.exists(p):
            if os.path.exists(np):
                # New name already has a file - trash the old one instead
                # (we don't want to clobber a new file in case PR 1 is
                # re-run after a partial).
                t = trashed(p)
                actions.append(('RENAME-COLLISION', p, t))
            else:
                shutil.move(p, np)
                actions.append(('RENAME', p, np))
        else:
            actions.append(('SKIP (not present)', p, None))


for stem in LEGACY:
    delete_hull(stem, 'legacy')
for stem in MODERN:
    delete_hull(stem, 'modern')
for stem in ORPHANS:
    delete_hull(stem, 'orphan')
for stem in WIP:
    p = os.path.join(NEW_HULLS, '%s.glb' % stem)
    if os.path.exists(p):
        t = trashed(p)
        actions.append(('DELETE', p, t))
    else:
        actions.append(('SKIP (not present)', p, None))
rename_hull(*RENAME_MEDIUM)


# Report
print('=' * 78)
print('PR 1 retirement: %d actions' % len(actions))
print('=' * 78)
by_kind = {}
for kind, _, _ in actions:
    by_kind[kind] = by_kind.get(kind, 0) + 1
for kind, n in sorted(by_kind.items()):
    print('  %-22s %d' % (kind, n))
print('Trash dir: %s' % TRASH)
print('=' * 78)
for kind, src, dst in actions:
    if kind == 'SKIP (not present)':
        continue
    if dst is None:
        print('  %-22s %s' % (kind, src))
    else:
        print('  %-22s %s -> %s' % (kind, src, dst))
