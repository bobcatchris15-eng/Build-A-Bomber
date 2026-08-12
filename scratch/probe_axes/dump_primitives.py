"""
Dump every primitive in the GLB with its base color and AABB.
Used to figure out the actual Godot->glTF transformation matrix
the bake pipeline is applying, so we can fix the swap precisely.
"""
import json
import os
import struct
import sys


def read_glb_chunks(path):
    with open(path, 'rb') as f:
        data = f.read()
    assert data[:4] == b'glTF'
    json_len, json_type = struct.unpack('<II', data[12:20])
    json_bytes = data[20:20 + json_len]
    json_chunk = json.loads(json_bytes.decode('utf-8'))
    return json_chunk, data


def main():
    argv = sys.argv[1:] if '--' not in sys.argv else sys.argv[sys.argv.index('--') + 1:]
    if len(argv) < 1:
        print('Usage: dump_primitives.py input.glb')
        sys.exit(1)
    glb_path = argv[0]
    glb_json, raw = read_glb_chunks(glb_path)
    bin_offset = 20 + struct.unpack('<I', raw[12:16])[0]
    bin_len = struct.unpack('<I', raw[bin_offset:bin_offset + 4])[0]
    bin_bytes = raw[bin_offset + 8:bin_offset + 8 + bin_len]

    for mi, mesh in enumerate(glb_json.get('meshes', [])):
        print('=== Mesh %d: %s ===' % (mi, mesh.get('name', '?')))
        for pi, prim in enumerate(mesh.get('primitives', [])):
            pos_acc_idx = prim['attributes']['POSITION']
            accessor = glb_json['accessors'][pos_acc_idx]
            mn = accessor.get('min')
            mx = accessor.get('max')
            mat_idx = prim.get('material', 0)
            mat = glb_json.get('materials', [{}])[mat_idx] if mat_idx is not None else {}
            pbr = mat.get('pbrMetallicRoughness', {})
            color = pbr.get('baseColorFactor', [0.7, 0.7, 0.7, 1.0])
            name = mat.get('name', 'mat_%d' % mat_idx)
            print('  Prim %d (mat=%d "%s", color=(%.2f, %.2f, %.2f, %.2f))' % (
                pi, mat_idx, name, color[0], color[1], color[2], color[3]
            ))
            print('    AABB min=(%.3f, %.3f, %.3f) max=(%.3f, %.3f, %.3f) centroid=(%.3f, %.3f, %.3f)' % (
                mn[0], mn[1], mn[2], mx[0], mx[1], mx[2],
                (mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2, (mn[2] + mx[2]) / 2
            ))


if __name__ == '__main__':
    main()
