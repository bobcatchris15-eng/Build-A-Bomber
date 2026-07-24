"""Throwaway probe: empirically determine which raw-Blender axis
add_cyl_axis(bm, center, radius, length, 'z') actually produces its long
dimension along, by building an asymmetric cone (tiny radius1, big radius2)
and printing the raw bmesh vertex bounding box after the function runs.
Run: UPBGE-0.30-windows-x86_64\\blender.exe --background --python scratch\\probe_add_cyl_axis.py
"""
import os
SRC = os.path.join(os.path.dirname(__file__), "..", "tools", "blender", "build_meshes.py")
src_text = open(SRC, "r", encoding="utf-8").read()
marker = "clear_scene()\ngenerate_parts()"
idx = src_text.index(marker)
defs_only = src_text[:idx]
ns = {"__name__": "build_meshes_defs", "__file__": SRC}
exec(compile(defs_only, SRC, "exec"), ns)

import bmesh
add_cyl_axis = ns["add_cyl_axis"]

for axis in ['x', 'z']:
    bm = bmesh.new()
    verts = add_cyl_axis(bm, (0, 0, 0), 0.05, 2.0, axis, segments=8, radius2=0.5)
    xs = [v.co.x for v in verts]
    ys = [v.co.y for v in verts]
    zs = [v.co.z for v in verts]
    print("godot_axis=%s -> raw Blender extents: X[%.3f,%.3f] Y[%.3f,%.3f] Z[%.3f,%.3f]" % (
        axis, min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))
    bm.free()
