import bpy
import bmesh
import math
import os
import mathutils

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
PARTS_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "parts")
os.makedirs(PARTS_DIR, exist_ok=True)

PITCH_ANGLE = math.radians(40.0)

def clear_scene():
	bpy.ops.object.select_all(action='SELECT')
	bpy.ops.object.delete(use_global=False)

def add_box(bm, pos, size, bevel=0.0, rot_x=0.0):
	loc = mathutils.Vector(pos)
	res = bmesh.ops.create_cube(bm, size=1.0)
	rot_mat = mathutils.Matrix.Rotation(rot_x, 4, 'X')
	for v in res['verts']:
		v.co = rot_mat @ mathutils.Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + loc
	if bevel > 0.001:
		edges = [e for e in bm.edges if any(v in res['verts'] for v in e.verts)]
		try:
			bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=2, affect='EDGES')
		except Exception:
			pass

def add_cyl_z(bm, pos, radius, height, segments=16):
	"""Cylinder along Blender Z axis (UP)."""
	res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius, radius2=radius, depth=height)
	loc = mathutils.Vector(pos)
	for v in res['verts']:
		v.co += loc

def add_cyl_y(bm, pos, radius, height, segments=16, rot_x=0.0):
	"""Cylinder along Blender Y axis (FORWARD), optionally pitched by rot_x."""
	res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius, radius2=radius, depth=height)
	rot = mathutils.Matrix.Rotation(math.radians(90) + rot_x, 4, 'X')
	loc = mathutils.Vector(pos)
	for v in res['verts']:
		v.co = rot @ v.co + loc

def add_cyl_x(bm, pos, radius, height, segments=16):
	"""Cylinder along Blender X axis (SIDEWAYS)."""
	res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius, radius2=radius, depth=height)
	rot = mathutils.Matrix.Rotation(math.radians(90), 4, 'Y')
	loc = mathutils.Vector(pos)
	for v in res['verts']:
		v.co = rot @ v.co + loc

def export_bmesh(bm, object_name, filename):
	me = bpy.data.meshes.new(object_name + "_mesh")
	bm.to_mesh(me)
	bm.free()

	obj = bpy.data.objects.new(object_name, me)
	bpy.context.collection.objects.link(obj)

	bpy.ops.object.select_all(action='DESELECT')
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.shade_smooth()
	try:
		obj.data.use_auto_smooth = True
		obj.data.auto_smooth_angle = math.radians(35)
	except Exception:
		pass

	mat = bpy.data.materials.new(name=object_name + "_mat")
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes.get("Principled BSDF")
	if bsdf:
		bsdf.inputs['Base Color'].default_value = (0.28, 0.22, 0.18, 1.0)
		bsdf.inputs['Metallic'].default_value = 0.70
		bsdf.inputs['Roughness'].default_value = 0.35
	obj.data.materials.append(mat)

	filepath = os.path.join(PARTS_DIR, filename)
	bpy.ops.export_scene.gltf(
		filepath=filepath,
		use_selection=True,
		export_format='GLB'
	)
	print("Successfully exported Cluster Dispenser sub-part GLB to:", filepath)
	clear_scene()

def build_cluster_dispenser_parts():
	clear_scene()

	# 1. MOUNT (cluster_dispenser_mount.glb)
	# Heavy deck mounting base plate with swiveling turntable ring and elevation yoke cheeks
	bm1 = bmesh.new()
	# Flanged Deck Base Plate (Z = 0 to 0.05)
	add_box(bm1, (0, 0, 0.025), (0.50, 0.50, 0.05), bevel=0.015)

	# Rotating Base Socket Turntable Ring (Z = 0.05 to 0.10)
	add_cyl_z(bm1, (0, 0, 0.075), 0.22, 0.05, segments=20)

	# Dual Angled Trunnion Support Cheek Plates (Z = 0.10 to 0.24)
	for side_x in (-0.18, 0.18):
		add_box(bm1, (side_x, 0.0, 0.17), (0.05, 0.24, 0.14), bevel=0.01)
		add_cyl_x(bm1, (side_x * 1.10, 0.0, 0.22), 0.045, 0.03, segments=12)

	export_bmesh(bm1, "cluster_dispenser_mount", "cluster_dispenser_mount.glb")

	# 2. CONTAINER HOUSING RACK (cluster_dispenser_housing.glb)
	# Armored projector rack housing pitched at 40 degrees for mine/depth charge launching
	bm2 = bmesh.new()
	h_w = 0.44
	h_h = 0.32
	h_d = 0.72

	# Main Armored Projector Box (pitched 40 degrees up)
	add_box(bm2, (0, 0, 0), (h_w, h_d, h_h), bevel=0.02, rot_x=PITCH_ANGLE)

	# Side Trunnion Pivot Brackets
	for side_x in (-0.23, 0.23):
		add_box(bm2, (side_x, 0, 0), (0.03, 0.22, 0.12), bevel=0.005, rot_x=PITCH_ANGLE)

	# Front Projector Muzzle Grid Plate
	m_y = (h_d * 0.5 + 0.01) * math.cos(PITCH_ANGLE)
	m_z = (h_d * 0.5 + 0.01) * math.sin(PITCH_ANGLE)
	add_box(bm2, (0, m_y, m_z), (h_w * 0.90, 0.02, h_h * 0.90), bevel=0.005, rot_x=PITCH_ANGLE)

	export_bmesh(bm2, "cluster_dispenser_housing", "cluster_dispenser_housing.glb")

	# 3. SUBMUNITION CANISTER / DEPTH CHARGE (cluster_dispenser_canister.glb)
	# Cylindrical cluster munition / depth charge canister with ribbed bands and end caps
	bm3 = bmesh.new()
	can_r = 0.06
	can_len = 0.24

	# Main Canister Body (pitched 40 degrees up)
	add_cyl_y(bm3, (0, 0, 0), can_r, can_len, segments=18, rot_x=PITCH_ANGLE)

	# Heavy Reinforced End Cap Rings
	for y_off in (-can_len * 0.45, can_len * 0.45):
		cy = y_off * math.cos(PITCH_ANGLE)
		cz = y_off * math.sin(PITCH_ANGLE)
		add_cyl_y(bm3, (0, cy, cz), can_r * 1.15, 0.03, segments=18, rot_x=PITCH_ANGLE)

	# Center Ribbed Reinforcement Band
	add_cyl_y(bm3, (0, 0, 0), can_r * 1.10, 0.04, segments=18, rot_x=PITCH_ANGLE)

	export_bmesh(bm3, "cluster_dispenser_canister", "cluster_dispenser_canister.glb")

if __name__ == "__main__":
	build_cluster_dispenser_parts()
