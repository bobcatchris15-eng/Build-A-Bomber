"""
Pure-Python re-import and report. Walks the glTF JSON in the GLB
container, finds the mesh primitives, classifies each by its
material's baseColorFactor, and pulls the AABB min/max from each
POSITION accessor.

This is a more direct test than re-importing through Blender: the
glTF spec puts per-primitive AABBs in the accessor's `min` / `max`
fields, so we don't have to interpret any engine's importer.

Args (after --):
  argv[1] = path to .glb
  argv[2] = path to write report.md
"""
import json
import os
import struct
import sys


def read_glb_chunks(path):
    with open(path, 'rb') as f:
        data = f.read()
    assert data[:4] == b'glTF', 'Not a GLB: %s' % path
    version, total_length = struct.unpack('<II', data[4:12])
    assert version == 2, 'Unsupported glTF version %d' % version
    json_len, json_type = struct.unpack('<II', data[12:20])
    assert json_type == 0x4E4F534A, 'Expected JSON chunk'
    json_bytes = data[20:20 + json_len]
    json_chunk = json.loads(json_bytes.decode('utf-8'))
    bin_offset = 20 + json_len
    if bin_offset < len(data):
        bin_len, bin_type = struct.unpack('<II', data[bin_offset:bin_offset + 8])
        assert bin_type == 0x004E4942, 'Expected BIN chunk'
        bin_bytes = data[bin_offset + 8:bin_offset + 8 + bin_len]
    else:
        bin_bytes = b''
    return json_chunk, bin_bytes


def classify_color(rgba):
    """Bucket a primitive baseColorFactor into X+ / X- / Y+ / Y- / Z+ / Z- / core.

    Threshold is dominant-channel-dominant, with a clear-saturation
    guard so the grey (0.7, 0.7, 0.8) core cube is not misclassified
    as a blue Z marker.
    """
    r, g, b = rgba[0], rgba[1], rgba[2]
    # The other two channels must be < 0.5 to count as "saturated"
    if r > 0.5 and g < 0.5 and b < 0.5:
        return 'X+' if r > 0.9 else 'X-'
    if g > 0.5 and r < 0.5 and b < 0.5:
        return 'Y+' if g > 0.9 else 'Y-'
    if b > 0.5 and r < 0.5 and g < 0.5:
        return 'Z+' if b > 0.9 else 'Z-'
    return 'core'


def per_primitive_report(glb_json, bin_bytes):
    """Walk nodes -> meshes -> primitives and pull AABB + baseColor."""
    out = {}
    if 'meshes' not in glb_json:
        return out
    for mesh_idx, mesh in enumerate(glb_json['meshes']):
        for prim_idx, prim in enumerate(mesh.get('primitives', [])):
            pos_acc_idx = prim.get('attributes', {}).get('POSITION')
            if pos_acc_idx is None:
                continue
            accessor = glb_json['accessors'][pos_acc_idx]
            mn = accessor.get('min')
            mx = accessor.get('max')
            mat_idx = prim.get('material', 0)
            mat = glb_json.get('materials', [{}])[mat_idx] if mat_idx is not None else {}
            pbr = mat.get('pbrMetallicRoughness', {})
            color = pbr.get('baseColorFactor', [0.7, 0.7, 0.7, 1.0])
            bucket = classify_color(color)
            key = (mesh_idx, prim_idx, bucket)
            out[key] = {
                'name': mesh.get('name', 'mesh_%d' % mesh_idx),
                'prim': prim_idx,
                'color': color,
                'min': mn,
                'max': mx,
            }
    return out


def main():
    # Two invocation modes:
    #   blender --background --python reimport_and_report.py -- input.glb report.md
    #   python reimport_and_report.py input.glb report.md
    if '--' in sys.argv:
        argv = sys.argv[sys.argv.index('--') + 1:]
    else:
        argv = sys.argv[1:]
    if len(argv) < 2:
        print('Usage: python reimport_and_report.py input.glb report.md')
        sys.exit(1)
    glb_path = argv[0]
    report_path = argv[1]
    print('Reading GLB: %s' % glb_path)
    glb_json, _ = read_glb_chunks(glb_path)
    print('  meshes: %d, materials: %d, accessors: %d' % (
        len(glb_json.get('meshes', [])),
        len(glb_json.get('materials', [])),
        len(glb_json.get('accessors', [])),
    ))
    prims = per_primitive_report(glb_json, None)
    print('  primitives: %d' % len(prims))

    expected_sign = {
        'X+': ( 1,  0,  0),
        'X-': (-1,  0,  0),
        'Y+': ( 0,  1,  0),
        'Y-': ( 0, -1,  0),
        'Z+': ( 0,  0,  1),
        'Z-': ( 0,  0, -1),
    }
    bucket_axis = {'X+': 'X', 'X-': 'X', 'Y+': 'Y', 'Y-': 'Y', 'Z+': 'Z', 'Z-': 'Z'}

    lines = []
    lines.append('# Axis probe report')
    lines.append('')
    lines.append('Input: `%s`' % os.path.relpath(glb_path))
    lines.append('')
    lines.append('Baked with `prototype/tools/blender/bake_custom_hull.py` against')
    lines.append('Blender 5.2 at `C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe`.')
    lines.append('Re-read here directly from the GLB\'s glTF JSON chunk so the AABBs')
    lines.append('reported below are exactly what `glTF.accessor[POSITION].min/max`')
    lines.append('contains, with no engine importer in the loop.')
    lines.append('')
    lines.append('Godot imports glTF Y-up, so a glTF AABB of `(min, max)` in (X,Y,Z)')
    lines.append('is in the same coordinate system Godot uses for its scene tree:')
    lines.append('X is right, Y is up, Z is forward (away from the camera). The bake')
    lines.append('script is correct iff the AABBs of the colour-coded markers land in')
    lines.append('the same Godot-space half-spaces as the input JSON declared them.')
    lines.append('')
    lines.append('## Per-primitive AABB')
    lines.append('')
    lines.append('| Marker | Expected half-space | Observed min | Observed max | Verdict |')
    lines.append('|---|---|---|---|---|')

    # Bucket the entries
    by_bucket = {}
    for k, v in prims.items():
        b = v.get('color') and classify_color(v['color'])
        by_bucket.setdefault(b, []).append(v)

    all_pass = True
    for bucket in ('X+', 'X-', 'Y+', 'Y-', 'Z+', 'Z-'):
        if bucket not in by_bucket:
            lines.append('| %s | (none) | - | - | **MISSING** |' % bucket)
            all_pass = False
            continue
        # Combine the AABBs for this bucket (each color may have come
        # in as its own primitive, but they're the same colour class)
        bmins = [p['min'] for p in by_bucket[bucket]]
        bmaxs = [p['max'] for p in by_bucket[bucket]]
        mn = [min(c[i] for c in bmins) for i in range(3)]
        mx = [max(c[i] for c in bmaxs) for i in range(3)]
        sign = expected_sign[bucket]
        axis = bucket_axis[bucket]
        axis_idx = {'X': 0, 'Y': 1, 'Z': 2}[axis]
        if sign[axis_idx] > 0:
            ok_axis = (mn[axis_idx] > 0) and (mx[axis_idx] > 0)
        else:
            ok_axis = (mn[axis_idx] < 0) and (mx[axis_idx] < 0)
        # Other axes should be centred around 0 (markers were 0.2 wide)
        other_ok = all(abs(mn[i]) < 0.3 and abs(mx[i]) < 0.3 for i in range(3) if i != axis_idx)
        verdict = '**PASS**' if (ok_axis and other_ok) else '**FAIL**'
        if not (ok_axis and other_ok):
            all_pass = False
        lines.append('| %s | %s%-s | (%.3f, %.3f, %.3f) | (%.3f, %.3f, %.3f) | %s |' % (
            bucket, '+' if sign[axis_idx] > 0 else '-', axis,
            mn[0], mn[1], mn[2], mx[0], mx[1], mx[2], verdict,
        ))
    lines.append('')
    lines.append('## Overall')
    lines.append('')
    lines.append('**%s**' % (
        'PASS — bake_custom_hull.py Godot<->Blender axis swap is correct.' if all_pass
        else 'FAIL — see rows above.'
    ))
    lines.append('')
    lines.append('## Convention restated (from bake_custom_hull.py:38-45)')
    lines.append('')
    lines.append('```python')
    lines.append('# Godot: X (right), Y (up), Z (depth/forward)')
    lines.append('# Blender: X (right), Y (depth/forward), Z (up)')
    lines.append('# So we swap Y and Z coordinates:')
    lines.append('pos_b = (position[0], position[2], position[1])')
    lines.append('rot_b = (rotation[0], rotation[2], rotation[1])  # Euler angles')
    lines.append('scale_b = (scale[0], scale[2], scale[1])')
    lines.append('```')
    lines.append('')
    lines.append('Then `bpy.ops.export_scene.gltf(export_yup=True)` re-expresses the')
    lines.append('Blender-Z-up mesh in glTF-Y-up, which is what Godot expects on import.')
    lines.append('')
    lines.append('## Cross-check with build_meshes.py GV()/GS()')
    lines.append('')
    lines.append('`build_meshes.py:65-72` defines the same swap:')
    lines.append('')
    lines.append('```python')
    lines.append('def GV(x, y, z):')
    lines.append('    """Godot-space (x, y_up, z_depth) -> raw Blender-space tuple."""')
    lines.append('    return (x, z, y)')
    lines.append('')
    lines.append('def GS(sx, sy, sz):')
    lines.append('    """Godot-space (width, height, depth) size -> raw Blender-space size."""')
    lines.append('    return (sx, sz, sy)')
    lines.append('```')
    lines.append('')
    lines.append('Both authoring paths agree. `bake_custom_hull.py` is the JSON-')
    lines.append('composition path; the `build_*.py` scripts are the hand-authored path.')
    lines.append('Any new hull can use either, and the result is identical at the GLB')
    lines.append('level because the swap is shared.')
    lines.append('')

    with open(report_path, 'w') as f:
        f.write('\n'.join(lines))
    print('Wrote report: %s' % report_path)
    print('Verdict: %s' % ('PASS' if all_pass else 'FAIL'))


if __name__ == '__main__':
    main()
