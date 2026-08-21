import bpy
import bmesh
from mathutils import Vector
import random
import math

def test_fracture():
    rng = random.Random(42)
    bm = bmesh.new()
    ret = bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0)
    
    cuts = 4
    for c in range(cuts):
        theta = rng.uniform(0, 2.0 * math.pi)
        phi = rng.uniform(-math.pi * 0.4, math.pi * 0.4)
        nx = math.cos(phi) * math.cos(theta)
        ny = math.cos(phi) * math.sin(theta)
        nz = math.sin(phi) * 0.8
        n = Vector((nx, ny, nz)).normalized()
        dist = 1.0 * rng.uniform(0.35, 0.75)
        plane_co = n * dist
        res = bmesh.ops.bisect_plane(
            bm,
            geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
            plane_co=plane_co,
            plane_no=n,
            clear_outer=True,
            clear_inner=False
        )
        cut_edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        print(f"Cut {c}: cut_edges count = {len(cut_edges)}")
        
        # Check boundary edges before fill
        boundary = [e for e in bm.edges if len(e.link_faces) == 1]
        print(f"  Boundary edges before fill: {len(boundary)}")
        
        # Try holes_fill on boundary
        if boundary:
            res_fill = bmesh.ops.holes_fill(bm, edges=boundary)
            print(f"  holes_fill created faces: {len(res_fill.get('faces', []))}")
        
        boundary_after = [e for e in bm.edges if len(e.link_faces) == 1]
        print(f"  Boundary edges after fill: {len(boundary_after)}")

test_fracture()
