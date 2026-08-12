"""Stage the PR 2 changes selectively. Use a Python loop instead of
trying to drive git from PowerShell syntax (which gets messy)."""
import os
import subprocess

ROOT = r'E:\Kitbash-Command'

def run(*args, check=True):
    result = subprocess.run(['git', '-C', ROOT] + list(args), capture_output=True, text=True)
    if check and result.returncode != 0:
        print('FAILED:', args, '\n', result.stderr)
    return result

# 1. The script
run('add', 'prototype/tools/blender/build_meshes.py')

# 2. The 54 new hulls (each is a triple: glb + glb.import + json)
for family in ('block', 'wedge', 'plate', 'pod', 'carrier', 'skiff'):
    for tonnage in ('scout', 'main', 'heavy'):
        for manufacturer in ('meridian', 'osterholm', 'tidemark'):
            stem = '%s_%s_%s' % (family, tonnage, manufacturer)
            for ext in ('.glb', '.glb.import', '.json'):
                path = 'prototype/assets/models/hulls/%s%s' % (stem, ext)
                full = os.path.join(ROOT, path)
                if os.path.exists(full):
                    run('add', path)

# 3. Remove the PR 1 placeholder
for ext in ('.json', '.res'):
    path = 'prototype/assets/models/hulls/block_main_meridian_a%s' % ext
    full = os.path.join(ROOT, path)
    if os.path.exists(full):
        run('rm', path)

# 4. The housekeeping scripts
run('add', 'scratch/probe_axes/pr2_remove_orphan_greebles_post.py',
          'scratch/probe_axes/pr2_remove_placeholder.py')

# Status
print()
print('--- Staged ---')
result = run('status', '--short', check=False)
print(result.stdout)
