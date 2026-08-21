import sys
import os
sys.path.insert(0, os.path.abspath("tools/blender"))

import bpy
import bmesh
import random
from mathutils import Vector
import math

import build_terrain_props

obj = build_terrain_props.build_organic_boulder("test_boulder", radius=1.0, seed=0)

bm = bmesh.new()
bm.from_mesh(obj.data)
open_edges = [e for e in bm.edges if len(e.link_faces) == 1]
print(f"Direct build_organic_boulder open edges: {len(open_edges)}")
for e in open_edges[:10]:
    print(f"  Edge: {e.verts[0].co} -> {e.verts[1].co}, link_faces: {len(e.link_faces)}")
