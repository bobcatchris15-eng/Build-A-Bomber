"""Remove the orphan _manufacturer_greebles_post function from build_meshes.py.

We use the closure-based greeble dispatcher (passed as the `greebles`
parameter of build_*.hull), so the post-build variant was a dead end.
"""
import os

PATH = r'E:\Kitbash-Command\prototype\tools\blender\build_meshes.py'

with open(PATH, 'r', encoding='utf-8') as f:
    text = f.read()

start_marker = '\n\n# Manufacturer greebles are applied to a built object\'s mesh, not'
end_marker = 'pass\n'

start = text.find(start_marker)
if start < 0:
    print('start marker not found, exiting')
    raise SystemExit(1)
end = text.find(end_marker, start)
if end < 0:
    print('end marker not found, exiting')
    raise SystemExit(1)
end += len(end_marker)

new_text = text[:start] + text[end:]
with open(PATH, 'w', encoding='utf-8') as f:
    f.write(new_text)
print('Removed %d chars (orphaned _manufacturer_greebles_post)' % (end - start))
