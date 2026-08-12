"""
Cross-check: read an existing hand-authored hull GLB and find the
asymmetric feature's "front" direction. For a tank, the turret is
the natural front marker - it sits at the highest Y AND at one
end of the Z extent. We find the Y-top decile of vertices and
report where they sit on the Z axis.

If the existing assets are authored in Godot's standard
"forward = -Z" convention, the turret-top vertices should be at
negative Z. If they're at positive Z, then Godot's actual
convention is "forward = +Z" (or the asset is rotated to make it
so), and my axis probe test labels were wrong.

Args (after --):
  argv[1] = path to .glb
"""
import json
import os
import struct
import sys


def read_glb_chunks(path):
    with open(path, 'rb') as f:
        data = f.read()
    assert data[:4] == b'glTF', 'Not a GLB: %s' % path
    json_len, json_type = struct.unpack('<II', data[12:20])
    json_bytes = data[20:20 + json_len]
    json_chunk = json.loads(json_bytes.decode('utf-8'))
    return json_chunk, data


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    if len(argv) < 1:
        print('Usage: check_existing_asset.py input.glb')
        sys.exit(1)
    glb_path = argv[0]
    glb_json, raw = read_glb_chunks(glb_path)
    bin_offset = 20 + struct.unpack('<I', raw[12:16])[0]
    bin_len = struct.unpack('<I', raw[bin_offset:bin_offset + 4])[0]
    bin_bytes = raw[bin_offset + 8:bin_offset + 8 + bin_len]

    # Walk every primitive, collect all POSITION vertices
    all_x, all_y, all_z = [], [], []
    for mesh in glb_json.get('meshes', []):
        for prim in mesh.get('primitives', []):
            pos_acc_idx = prim['attributes']['POSITION']
            accessor = glb_json['accessors'][pos_acc_idx]
            bv = glb_json['bufferViews'][accessor['bufferView']]
            blob = bin_bytes[bv['byteOffset']:bv['byteOffset'] + bv['byteLength']]
            count = accessor['count']
            comp_type = accessor['componentType']  # 5126 = FLOAT
            type_str = accessor['type']  # 'VEC3'
            if comp_type != 5126 or type_str != 'VEC3':
                continue
            stride = 12
            for i in range(count):
                x, y, z = struct.unpack('<fff', blob[i * stride:(i + 1) * stride])
                all_x.append(x)
                all_y.append(y)
                all_z.append(z)

    print('Asset: %s' % os.path.relpath(glb_path))
    print('Vertex count: %d' % len(all_x))
    print('X range: [%.3f, %.3f]' % (min(all_x), max(all_x)))
    print('Y range: [%.3f, %.3f]' % (min(all_y), max(all_y)))
    print('Z range: [%.3f, %.3f]' % (min(all_z), max(all_z)))

    # The "turret" or "topmost feature" is the Y top decile.
    # Where do those vertices sit on Z?
    sorted_y = sorted(all_y)
    top_threshold = sorted_y[int(0.9 * len(sorted_y))]
    top_z = [z for (y, z) in zip(all_y, all_z) if y >= top_threshold]
    if top_z:
        print('Top-decile-Y vertices (likely the turret / superstructure):')
        print('  count: %d' % len(top_z))
        print('  Z range: [%.3f, %.3f], centroid Z: %.3f' % (
            min(top_z), max(top_z), sum(top_z) / len(top_z)
        ))

    # Also: the "front" should be where the vertices extend further
    # in one Z direction than the other. The bias tells us which
    # end is "front" - but only if the model is asymmetric in Z.
    if abs(max(all_z) + min(all_z)) > 0.05 * (max(all_z) - min(all_z)):
        print('Asset is Z-symmetric - cannot infer front direction from AABB alone.')


if __name__ == '__main__':
    main()
