"""
PR 1 follow-up: rename the hardcoded legacy hull id strings in the
.gd source files to the new family-slug names. Targeted: only
quoted-string occurrences (so comments and identifiers in code
that happen to contain "medium_hull" as part of a longer name
are not touched), and only for the legacy names that the new
catalogue has retired.

Mapping (the new family slug for each legacy name):
  medium_hull   -> block_main_meridian_a
  light_hull    -> block_scout_meridian_a
  heavy_hull    -> block_heavy_meridian_a
  scout_hull    -> wedge_scout_meridian_a
  transport_hull-> carrier_main_meridian_a
  assault_hull  -> plate_heavy_meridian_a
  open_transport_hull -> carrier_open_meridian_a
  heavy_transport_hull-> carrier_heavy_meridian_a

Files to sweep: every .gd under prototype/ that the prior grep
flagged. Also the .gd/.json under prototype/data/ and
prototype/tools/ that the same grep flagged.
"""
import os
import re

ROOT = r'E:\Kitbash-Command'

REPLACEMENTS = [
    # Longest first, so the more specific replacements land before
    # the substring matches they overlap.
    ('open_transport_hull', 'carrier_open_meridian_a'),
    ('heavy_transport_hull', 'carrier_heavy_meridian_a'),
    ('medium_hull', 'block_main_meridian_a'),
    ('light_hull', 'block_scout_meridian_a'),
    ('heavy_hull', 'block_heavy_meridian_a'),
    ('scout_hull', 'wedge_scout_meridian_a'),
    ('transport_hull', 'carrier_main_meridian_a'),
    ('assault_hull', 'plate_heavy_meridian_a'),
]


def sweep(path):
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()
    original = text
    n_replacements = 0
    # Only replace inside double-quoted strings, so we don't touch
    # comments or longer identifiers. A regex matching "<name>" in
    # any quoted context.
    for old, new in REPLACEMENTS:
        # Pattern: "old" with optional surrounding single quotes in
        # dicts (Godot uses "key" syntax in .tscn/.tres but the
        # .gd/.json code uses double quotes).
        pattern = re.compile(r'"%s"' % re.escape(old))
        text, n = pattern.subn('"%s"' % new, text)
        n_replacements += n
    if text != original:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(text)
        return n_replacements
    return 0


# Files to sweep (built from the prior grep, with the .gd sources
# only - .glb files have no source to change). Now a global sweep
# over all .gd / .json under prototype/ that match the patterns.
ROOT_PROTOTYPE = os.path.join(ROOT, 'prototype')

# Stat totals
n_files = 0
n_total = 0
for dirpath, dirnames, filenames in os.walk(ROOT_PROTOTYPE):
    # Skip .godot (Godot's cache) and parts/buildings (not hulls)
    rel = os.path.relpath(dirpath, ROOT)
    if '.godot' in rel or 'NEW_HULLS' in rel:
        continue
    for fname in filenames:
        if not (fname.endswith('.gd') or fname.endswith('.json') or fname.endswith('.tscn') or fname.endswith('.tres') or fname.endswith('.py')):
            continue
        full = os.path.join(dirpath, fname)
        n = sweep(full)
        if n > 0:
            n_files += 1
            n_total += n
            print('  %4d  %s' % (n, os.path.relpath(full, ROOT)))

print('=' * 60)
print('%d files, %d string replacements' % (n_files, n_total))
