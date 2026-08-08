"""Rebuilds ONLY the terrain props (boulders, resource-node dressing).

Same reasoning as build_resource_bay.py: build_meshes.py's __main__
regenerates the entire hull/part library, which is the wrong tool for adding
one new family of assets - this imports the same module and calls the exact
function build_meshes.generate_parts() would eventually grow to call, so
there is no second copy of the geometry to drift.

    blender.exe --background --python tools/blender/build_terrain_props.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_meshes as bm


def main():
    bm.clear_scene()
    bm.generate_terrain_props()


if __name__ == "__main__":
    main()
