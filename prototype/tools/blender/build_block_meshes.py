"""
Block Builder mesh generator.
Run headlessly with UPBGE's bundled Blender:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python tools\\blender\\build_block_meshes.py
"""

import bpy
import bmesh
import math
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
OUT_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "hull_primitives")
os.makedirs(OUT_DIR, exist_ok=True)


# ---------------------------------------------------------------------------
# Self-contained helpers
# ---------------------------------------------------------------------------

def clear_scene():
	bpy.ops.object.select_all(action='SELECT')
	bpy.ops.object.delete(use_global=False)
	for block in list(bpy.data.meshes):
		if block.users == 0:
			bpy.data.meshes.remove(block)
	for block in list(bpy.data.materials):
		if block.users == 0:
			bpy.data.materials.remove(block)


def GV(x, y, z):
	"""Godot-space (x, y_up, z_depth) -> raw Blender-space tuple."""
	return (x, z, y)


def GS(sx, sy, sz):
	"""Godot-space (width, height, depth) size -> raw Blender-space size."""
	return (sx, sz, sy)


def new_material(name, color, metallic=0.6, roughness=0.4):
	mat = bpy.data.materials.get(name)
	if mat is None:
		mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes.get("Principled BSDF")
	if bsdf:
		bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
		bsdf.inputs["Metallic"].default_value = metallic
		bsdf.inputs["Roughness"].default_value = roughness
	return mat


def make_object_from_bmesh(bm, name):
	mesh = bpy.data.meshes.new(name + "_mesh")
	bm.to_mesh(mesh)
	bm.free()
	mesh.update()
	obj = bpy.data.objects.new(name, mesh)
	bpy.context.collection.objects.link(obj)
	return obj


def finalize(obj, name, color=(0.7, 0.7, 0.75), metallic=0.5, roughness=0.4):
	obj.name = name
	bpy.ops.object.select_all(action='DESELECT')
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.shade_smooth()
	try:
		obj.data.use_auto_smooth = True
		obj.data.auto_smooth_angle = math.radians(35)
	except Exception:
		pass
	mat = new_material(name + "_mat", color, metallic, roughness)
	if obj.data.materials:
		obj.data.materials[0] = mat
	else:
		obj.data.materials.append(mat)


def export_and_cleanup(obj, filename):
	path = os.path.join(OUT_DIR, filename + ".glb")
	bpy.ops.object.select_all(action='DESELECT')
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.export_scene.gltf(
		filepath=path,
		use_selection=True,
		export_format='GLB',
		export_yup=True,
		export_apply=True
	)
	print("Exported: " + path)
	mesh_data = obj.data
	bpy.data.objects.remove(obj, do_unlink=True)
	if mesh_data and mesh_data.users == 0:
		bpy.data.meshes.remove(mesh_data)


def finish_bm(bm):
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
	bmesh.ops.triangulate(bm, faces=bm.faces[:])

# ---------------------------------------------------------------------------
# Shape builders
# ---------------------------------------------------------------------------

def build_block_cube():
	name = "block_cube"
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	bm.edges.ensure_lookup_table()
	bm.verts.ensure_lookup_table()
	bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.025, segments=2, affect='EDGES')
	finish_bm(bm)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=(0.72, 0.72, 0.76), metallic=0.6, roughness=0.35)
	export_and_cleanup(obj, name)

def build_block_wedge():
	name = "block_wedge"
	bm = bmesh.new()
	
	v0 = bm.verts.new(GV(-0.5, -0.5, -0.5)) # front left bottom
	v1 = bm.verts.new(GV(0.5, -0.5, -0.5))  # front right bottom
	v2 = bm.verts.new(GV(0.5, -0.5, 0.5))   # back right bottom
	v3 = bm.verts.new(GV(-0.5, -0.5, 0.5))  # back left bottom
	v4 = bm.verts.new(GV(0.5, 0.5, 0.5))    # back right top
	v5 = bm.verts.new(GV(-0.5, 0.5, 0.5))   # back left top
	
	bm.faces.new([v0, v1, v2, v3]) # bottom
	bm.faces.new([v3, v2, v4, v5]) # back
	bm.faces.new([v5, v4, v1, v0]) # slope
	bm.faces.new([v0, v3, v5])     # left
	bm.faces.new([v1, v4, v2])     # right
	
	bm.edges.ensure_lookup_table()
	bm.verts.ensure_lookup_table()
	bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.025, segments=2, affect='EDGES')
	finish_bm(bm)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=(0.70, 0.72, 0.76), metallic=0.6, roughness=0.35)
	export_and_cleanup(obj, name)

def build_block_inner_corner():
	name = "block_inner_corner"
	bm = bmesh.new()
	
	b0 = bm.verts.new(GV(-0.5, -0.5, -0.5))
	b1 = bm.verts.new(GV(0.5, -0.5, -0.5))
	b2 = bm.verts.new(GV(-0.5, -0.5, 0.5))
	
	t0 = bm.verts.new(GV(-0.5, 0.5, -0.5))
	t1 = bm.verts.new(GV(0.5, 0.5, -0.5))
	t2 = bm.verts.new(GV(-0.5, 0.5, 0.5))
	
	bm.faces.new([b0, b1, b2])
	bm.faces.new([t0, t2, t1])
	bm.faces.new([b0, b2, t2, t0])
	bm.faces.new([b0, t0, t1, b1])
	bm.faces.new([b1, t1, t2, b2])
	
	bm.edges.ensure_lookup_table()
	bm.verts.ensure_lookup_table()
	bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.025, segments=2, affect='EDGES')
	finish_bm(bm)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=(0.70, 0.70, 0.74), metallic=0.6, roughness=0.35)
	export_and_cleanup(obj, name)

def build_block_outer_corner():
	name = "block_outer_corner"
	bm = bmesh.new()
	
	b0 = bm.verts.new(GV(0.5, -0.5, 0.5))
	b1 = bm.verts.new(GV(-0.5, -0.5, 0.5))
	b2 = bm.verts.new(GV(0.5, -0.5, -0.5))
	
	t0 = bm.verts.new(GV(0.5, 0.5, 0.5))
	t1 = bm.verts.new(GV(-0.5, 0.5, 0.5))
	t2 = bm.verts.new(GV(0.5, 0.5, -0.5))
	
	bm.faces.new([b0, b1, b2])
	bm.faces.new([t0, t2, t1])
	bm.faces.new([b0, b2, t2, t0])
	bm.faces.new([b0, t0, t1, b1])
	bm.faces.new([b1, t1, t2, b2])
	
	bm.edges.ensure_lookup_table()
	bm.verts.ensure_lookup_table()
	bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.025, segments=2, affect='EDGES')
	finish_bm(bm)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=(0.72, 0.70, 0.74), metallic=0.6, roughness=0.35)
	export_and_cleanup(obj, name)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

clear_scene()
build_block_cube()
build_block_wedge()
build_block_inner_corner()
build_block_outer_corner()
print("Block meshes build complete: " + OUT_DIR)
