"""Rebuilds ONLY the Resource Bay parts.

build_meshes.py's __main__ regenerates the entire library - every hull and
every part - which is the right thing when the shared helpers change and the
wrong thing when one new part is added: it rewrites ~150 binary .glb files,
so the diff for "added a resource bay" would be unreviewable and any
incidental drift in an unrelated hull would land silently alongside it.

This driver imports the same module, so the two builders here are the exact
functions build_meshes.generate_parts() calls - there is no second copy of the
geometry to drift.

    blender.exe --background --python tools/blender/build_resource_bay.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_meshes as bm


def main():
    bm.clear_scene()
    bm.export_and_cleanup(
        bm.build_resource_bay_tub("resource_bay_tub", color=(0.42, 0.36, 0.20)),
        bm.PARTS_DIR, "resource_bay_tub")
    bm.export_and_cleanup(
        bm.build_resource_bay_lid("resource_bay_lid", color=(0.30, 0.31, 0.33)),
        bm.PARTS_DIR, "resource_bay_lid")
    print("--- Resource Bay parts written to %s ---" % bm.PARTS_DIR)


if __name__ == "__main__":
    main()
