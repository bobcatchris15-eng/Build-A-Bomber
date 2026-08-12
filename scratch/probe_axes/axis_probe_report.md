# Axis probe report

Input: `scratch\probe_axes\axis_probe.glb`

Baked with `prototype/tools/blender/bake_custom_hull.py` against
Blender 5.2 at `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`.
Re-read here directly from the GLB's glTF JSON chunk so the AABBs
reported below are exactly what `glTF.accessor[POSITION].min/max`
contains, with no engine importer in the loop.

Godot imports glTF Y-up, so a glTF AABB of `(min, max)` in (X,Y,Z)
is in the same coordinate system Godot uses for its scene tree:
X is right, Y is up, Z is forward (away from the camera). The bake
script is correct iff the AABBs of the colour-coded markers land in
the same Godot-space half-spaces as the input JSON declared them.

## Per-primitive AABB

| Marker | Expected half-space | Observed min | Observed max | Verdict |
|---|---|---|---|---|
| X+ | +X | (0.500, -0.200, -0.200) | (2.500, 0.200, 0.200) | **PASS** |
| X- | -X | (-2.500, -0.200, -0.200) | (-0.500, 0.200, 0.200) | **PASS** |
| Y+ | +Y | (-0.200, 0.500, -0.200) | (0.200, 2.500, 0.200) | **PASS** |
| Y- | -Y | (-0.200, -2.500, -0.200) | (0.200, -0.500, 0.200) | **PASS** |
| Z+ | +Z | (-0.200, -0.200, 0.500) | (0.200, 0.200, 2.500) | **PASS** |
| Z- | -Z | (-0.200, -0.200, -2.500) | (0.200, 0.200, -0.500) | **PASS** |

## Overall

**PASS — bake_custom_hull.py Godot<->Blender axis swap is correct.**

## Convention restated (from bake_custom_hull.py:38-45)

```python
# Godot: X (right), Y (up), Z (depth/forward)
# Blender: X (right), Y (depth/forward), Z (up)
# So we swap Y and Z coordinates:
pos_b = (position[0], position[2], position[1])
rot_b = (rotation[0], rotation[2], rotation[1])  # Euler angles
scale_b = (scale[0], scale[2], scale[1])
```

Then `bpy.ops.export_scene.gltf(export_yup=True)` re-expresses the
Blender-Z-up mesh in glTF-Y-up, which is what Godot expects on import.

## Cross-check with build_meshes.py GV()/GS()

`build_meshes.py:65-72` defines the same swap:

```python
def GV(x, y, z):
    """Godot-space (x, y_up, z_depth) -> raw Blender-space tuple."""
    return (x, z, y)

def GS(sx, sy, sz):
    """Godot-space (width, height, depth) size -> raw Blender-space size."""
    return (sx, sz, sy)
```

Both authoring paths agree. `bake_custom_hull.py` is the JSON-
composition path; the `build_*.py` scripts are the hand-authored path.
Any new hull can use either, and the result is identical at the GLB
level because the swap is shared.
