"""
Dump all unique vertex positions in the GLB, grouped by primitive.
Verifies what the bake + glTF export actually produces per vertex.
"""
import json
import os
import struct
import sys


def read_glb_chunks(path):
    with open(path, 'rb') as f:
        data = f.read()
    assert data[:4] == b'glTF'
    json_len, _ = struct.unpack('<II', data[12:20])
    json_bytes = data[20:20 + json_len]
    json_chunk = json.loads(json_bytes.decode('utf-8'))
    return json_chunk, data


def main():
    argv = sys.argv[1:] if '--' not in sys.argv else sys.argv[sys.argv.index('--') + 1:]
    if len(argv) < 1:
        print('Usage: dump_vertices.py input.glb')
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
            bv = glb_json['bufferViews'][accessor['bufferView']]
            blob = bin_bytes[bv['byteOffset']:bv['byteOffset'] + bv['byteLength']]
            count = accessor['count']
            mat_idx = prim.get('material', 0)
            mat = glb_json.get('materials', [{}])[mat_idx] if mat_idx is not None else {}
            pbr = mat.get('pbrMetallicRoughness', {})
            color = pbr.get('baseColorFactor', [0, 0, 0, 1])
            print('  Prim %d (color=(%.2f, %.2f, %.2f)):' % (pi, color[0], color[1], color[2]))
            # Print first 8 unique vertex positions
            seen = set()
            printed = 0
            for i in range(count):
                v = struct.unpack('<fff', blob[i * 12:(i + 1) * 12])
                vt = (round(v[0], 3), round(v[1], 3), round(v[2], 3))
                if vt in seen:
                    continue
                seen.add(vt)
                if printed < 8:
                    print('    v%d: (%.3f, %.3f, %.3f)' % (i, v[0], v[1], v[2]))
                    printed += 1
            if printed < count:
                print('    ... (%d unique total)' % len(seen))


if __name__ == '__main__':
    main()
