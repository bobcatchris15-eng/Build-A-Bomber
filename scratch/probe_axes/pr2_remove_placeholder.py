"""Remove the PR 1 placeholder block_main_meridian_a.{json,res}.

The new catalogue uses block_main_meridian (no suffix = default variant
a per HULL_REFRESH_PLAN §3.3) so the placeholder is no longer needed.
Trashed to ~/.mavis/trash/pr2_remove_placeholder/ for recoverability.
"""
import os
import shutil

HULLS = r'E:\Kitbash-Command\prototype\assets\models\hulls'
TRASH = os.path.join(os.path.expanduser('~'), '.mavis', 'trash', 'pr2_remove_placeholder')
os.makedirs(TRASH, exist_ok=True)

moved = []
for fname in ('block_main_meridian_a.json', 'block_main_meridian_a.res'):
    p = os.path.join(HULLS, fname)
    if os.path.exists(p):
        shutil.move(p, os.path.join(TRASH, fname))
        moved.append(p)

print('Moved %d files:' % len(moved))
for p in moved:
    print('  %s -> %s' % (p, os.path.join(TRASH, os.path.basename(p))))
