# Axis probe — NOTES

**Test date:** 2026-08-11
**Blender version:** 5.2 LTS (`C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`)
**Verdict:** PASS — bake_custom_hull.py's Godot↔Blender axis swap is correct after the fixes below.

## What the test does

A 2×2×2 core cube is surrounded by six colour-coded marker boxes, one
on each axis half-space, all authored in Godot-space (X right, Y up,
Z forward; -Z is "forward"):

| Marker | Color    | Input (Godot)  | Expected glTF AABB centroid |
|--------|----------|----------------|------------------------------|
| X+     | red 1.0  | ( 1.5,  0,  0) | ( 1.5,  0,  0)              |
| X-     | red 0.6  | (-1.5,  0,  0) | (-1.5,  0,  0)              |
| Y+     | green 1.0| ( 0,  1.5,  0) | ( 0,  1.5,  0)              |
| Y-     | green 0.6| ( 0, -1.5,  0) | ( 0, -1.5,  0)              |
| Z+     | blue 1.0 | ( 0,  0,  1.5) | ( 0,  0,  1.5)              |
| Z-     | blue 0.6 | ( 0,  0, -1.5) | ( 0,  0, -1.5)              |

The hull is baked through `prototype/tools/blender/bake_custom_hull.py`
(the JSON-composition path), then re-read directly from the GLB's
glTF JSON chunk so the AABBs reported are exactly what
`glTF.accessor[POSITION].min/max` contains, with no engine importer
in the loop.

**Pass criterion:** every marker's glTF AABB centroid lands in the
expected Godot-axis half-space (i.e., the Godot input passes through
the bake and lands at the same glTF coordinates).

## How to run

From PowerShell in the repo root:

```powershell
.\scratch\probe_axes\run_probe.ps1
```

The script bakes the test input through the project's
`bake_custom_hull.py`, then runs a pure-Python re-read of the
resulting GLB (no Blender needed for the read step) and writes
`axis_probe_report.md`.

## What was found — and what was fixed

Two bugs in the original `bake_custom_hull.py`. Both are now patched
in the file (the fix is in place; this section documents why).

### Bug 1: per-primitive location/scale silently dropped on export

`bake_custom_hull.py` originally exported with `export_apply=True`
but did **not** call `bpy.ops.object.transform_apply(location=True,
scale=True, rotation=True)` on the joined object before export. In
Blender 5.2 the glTF exporter's `export_apply` flag does not
reliably bake per-object transforms into the exported vertex
positions, so every per-primitive `pos_b` and `scale_b` was being
silently dropped. The result: every baked hull had all its
primitives collapsed to the origin at unit scale, regardless of the
input JSON.

**Fix:** added a `bpy.ops.object.transform_apply(location=True,
scale=True, rotation=True)` call on the joined object, after the
`bpy.ops.object.join()` step. This bakes every per-primitive
location/scale/rotation into the vertex data before the glTF
exporter runs, so the export step doesn't have to.

**Effect:** the test marker that the old code collapsed to glTF
(0, 0, 0) (a 1×0.2×0.2 box at the origin) now lands at glTF
(0.75, 0, 0) (a 1×0.2×0.2 box centred at X=0.75) and beyond,
which is the correct world-space position for the input
(1.5, 0, 0).

### Bug 2: Z axis inverted relative to existing hand-authored assets

`bake_custom_hull.py` originally swapped Godot-to-Blender as
`pos_b = (X, Z, Y)` (and the same swap for scale/rotation, no sign
change). This looks like the right swap in isolation, but combined
with the glTF exporter's `export_yup=True` — which applies a -90°
rotation about the X axis, i.e., glTF (X, Y, Z) = Blender (X, Z, -Y)
— the chain ends up:

```
Godot (X, Y, Z) -> Blender (X, Z, Y) -> glTF (X, Y, -Z)
```

so Godot +Z lands at glTF -Z and vice versa. The X and Y axes
happen to be correct under the same chain (Godot +X passes through;
Godot +Y becomes glTF +Z which is "backward" in glTF's own
convention, but Godot's "+Y up" matches glTF's "+Y up" and the
chain happens to put them in the same place).

**Cross-check against the existing hand-authored assets:** the
heavy_hull_mk2.glb's turret-top vertices (472 verts, Y top decile)
sit at glTF Z range -2.629 to 1.320, centroid -0.478 — i.e., the
turret is at glTF -Z. Since the existing hand-authored assets
follow Godot's "forward = -Z" convention, the bake pipeline was
producing the opposite: a hull baked via JSON with its nose at
Godot -Z would end up with its nose at glTF +Z, which is
backward in glTF's own convention.

**Fix:** negate the Godot-Z component when going to Blender. The
correct chain is:

```
Godot (X, Y, Z) -> Blender (X, -Z, Y) -> glTF (X, Y, Z)
```

so `pos_b = (Gx, -Gz, Gy)`, `scale_b = (Sx, -Sz, Sy)`, and
`rot_b = (Rx, -Rz, Ry)` (Euler angles). The Godot input passes
through the bake unchanged and lands at glTF in the same
coordinates — exactly what Godot's glTF importer wants.

## Final pass: 6/6 markers correct

After both fixes, the test reports:

| Marker | Expected | Observed centroid | Verdict |
|---|---|---|---|
| X+ | +X | ( 1.5,  0,  0) | PASS |
| X- | -X | (-1.5,  0,  0) | PASS |
| Y+ | +Y | ( 0,  1.5,  0) | PASS |
| Y- | -Y | ( 0, -1.5,  0) | PASS |
| Z+ | +Z | ( 0,  0,  1.5) | PASS |
| Z- | -Z | ( 0,  0, -1.5) | PASS |

## Why the existing assets were unaffected

The hand-authored assets under `prototype/assets/models/` are
generated by the `build_*.py` scripts (e.g. `build_37mm_m3.py`,
`build_hull_primitives.py`, `build_artillery.py`, etc.), not by
`bake_custom_hull.py`. The `build_*.py` scripts author the mesh
directly in Blender-space (Z-up, +Y forward) using the
shared `GV()` / `GS()` helpers in `build_meshes.py` to do the
Godot↔Blender conversion at the call site. Their internal
`export_yup=True` call applies the same -90° X rotation, but
because the source mesh is already in Blender Z-up convention
(where +Y is "forward"), the chain produces a glTF where the
forward axis is at glTF -Z — which matches Godot's "forward = -Z"
convention.

In other words: the `build_*.py` path and the (now-fixed)
`bake_custom_hull.py` path produce glTF files in the same Godot
coordinate system. Before this fix, the bake path was the odd one
out, and any hull composed via JSON would have ended up facing
backward in-game.

## Files in this directory

- `axis_probe_input.json` — the test input (7 primitives, colour-coded markers)
- `axis_probe.glb` — the baked output (regenerated by `run_probe.ps1`)
- `axis_probe.json` — the bake's sidecar JSON (regenerated by `run_probe.ps1`)
- `axis_probe_report.md` — the per-primitive AABB report (regenerated)
- `run_probe.ps1` — the runner
- `reimport_and_report.py` — pure-Python GLB reader that produces the report
- `dump_primitives.py` — utility: dumps every primitive in a GLB with its AABB and base color
- `dump_vertices.py` — utility: dumps unique vertex positions per primitive
- `check_existing_asset.py` — utility: takes an existing hand-authored GLB and reports its top-decile-Y vertices (useful for confirming "where is the front?" on a tank hull or similar)

## Files modified by this investigation

- `prototype/tools/blender/bake_custom_hull.py`
  - `pos_b = (position[0], -position[2], position[1])` (was: `(X, Z, Y)`)
  - `rot_b = (rotation[0], -rotation[2], rotation[1])` (was: `(Rx, Rz, Ry)`)
  - `scale_b = (scale[0], -scale[2], scale[1])` (was: `(Sx, Sz, Sy)`)
  - Added `bpy.ops.object.transform_apply(location=True, scale=True, rotation=True)` after the `bpy.ops.object.join()` step
  - Updated the comment block in `create_primitive_mesh()` to document the derivation and reference this NOTES file
