# Axis + winding probe: authored in RAW BLENDER coordinates, no helper swaps.
#
# Builds one object with 7 material slots so the export becomes 7 glTF
# primitives -> 7 Godot mesh surfaces, each individually identifiable by
# its material name. Six are axis markers on the six raw-Blender half-axes;
# the seventh is a cube pushed through a determinant=-1 matrix to prove what
# a mirrored transform does to face winding.
#
# Run:
#   & "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" --background \
#       --python scratch/hull_probe/probe_build.py -- <out.glb>

import sys
import os
import bpy
import bmesh
import mathutils

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "probe.glb"

# (material_name, center, half_size) all in RAW BLENDER space.
# Long axis of each marker points along the axis it marks, so the AABB
# read back on the other side is unambiguous about which axis it became.
MARKERS = [
    ("mk_bx_pos", (2.0, 0.0, 0.0), (1.0, 0.15, 0.15)),
    ("mk_bx_neg", (-2.0, 0.0, 0.0), (0.6, 0.15, 0.15)),
    ("mk_by_pos", (0.0, 2.0, 0.0), (0.15, 1.0, 0.15)),
    ("mk_by_neg", (0.0, -2.0, 0.0), (0.15, 0.6, 0.15)),
    ("mk_bz_pos", (0.0, 0.0, 2.0), (0.15, 0.15, 1.0)),
    ("mk_bz_neg", (0.0, 0.0, -2.0), (0.15, 0.15, 0.6)),
]

# The suspect matrix from build_meshes.py:2969 (_hull_orient_matrix).
# T(a,b,c) = (b, -c, a). Its determinant is -1, so it is a REFLECTION,
# not a rotation. Applied to this marker only, to show the effect on winding.
MIRROR_MATRIX = mathutils.Matrix(((0, 1, 0), (0, 0, -1), (1, 0, 0)))


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for m in list(bpy.data.meshes):
        if m.users == 0:
            bpy.data.meshes.remove(m)
    for m in list(bpy.data.materials):
        if m.users == 0:
            bpy.data.materials.remove(m)


def add_box(bm, center, half, mat_index):
    """Axis-aligned box with correct outward winding, tagged to a slot."""
    before = set(bm.faces)
    bmesh.ops.create_cube(bm, size=2.0)
    new_faces = [f for f in bm.faces if f not in before]
    new_verts = set()
    for f in new_faces:
        new_verts.update(f.verts)
    for v in new_verts:
        v.co.x = v.co.x * half[0] + center[0]
        v.co.y = v.co.y * half[1] + center[1]
        v.co.z = v.co.z * half[2] + center[2]
    for f in new_faces:
        f.material_index = mat_index
    return new_faces, list(new_verts)


def main():
    clear_scene()
    bm = bmesh.new()

    for i, (_name, center, half) in enumerate(MARKERS):
        add_box(bm, center, half, i)

    # Slot 6: a cube run through the det=-1 matrix, winding NOT recalculated.
    mirror_faces, mirror_verts = add_box(bm, (0.0, 0.0, 0.0), (0.5, 0.5, 0.5), 6)
    for v in mirror_verts:
        v.co = MIRROR_MATRIX @ v.co

    bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces if f not in set(mirror_faces)])

    mesh = bpy.data.meshes.new("probe_mesh")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    obj = bpy.data.objects.new("probe", mesh)
    bpy.context.collection.objects.link(obj)

    names = [m[0] for m in MARKERS] + ["mk_mirrored_det_neg1"]
    for n in names:
        mat = bpy.data.materials.new(n)
        mat.use_nodes = True
        obj.data.materials.append(mat)

    print("PROBE det(MIRROR_MATRIX) = %s" % MIRROR_MATRIX.determinant())

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    # Exactly the flags build_meshes.py's export_glb() uses.
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        use_selection=True,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
    )
    print("PROBE wrote %s" % OUT)


main()
