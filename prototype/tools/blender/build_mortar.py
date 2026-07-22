import bpy
import bmesh
import math
import os
import mathutils

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
PARTS_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "parts")
os.makedirs(PARTS_DIR, exist_ok=True)

ELEV_60_DEG = math.radians(60.0)

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
		bsdf.inputs['Base Color'].default_value = (0.22, 0.25, 0.20, 1.0)
		bsdf.inputs['Metallic'].default_value = 0.70
		bsdf.inputs['Roughness'].default_value = 0.35
	obj.data.materials.append(mat)

	filepath = os.path.join(PARTS_DIR, filename)
	bpy.ops.export_scene.gltf(
		filepath=filepath,
		use_selection=True,
		export_format='GLB'
	)
	print("Successfully exported Mortar sub-part GLB to:", filepath)
	clear_scene()

def build_mortar_parts():
	clear_scene()

	# 1. SWIVEL TURNTABLE MOUNT PLATE (mortar_swivel_mount.glb)
	bm1 = bmesh.new()
	# Outer Base Ring sitting flush on deck (Z = 0 to 0.06, radius = 0.32)
	add_cyl_z(bm1, (0, 0, 0.03), 0.32, 0.06, segments=24)

	# Rotating Inner Swivel Turntable Ring (Z = 0.06 to 0.12, radius = 0.27)
	add_cyl_z(bm1, (0, 0, 0.09), 0.27, 0.06, segments=24)

	# Elevation Yoke Trunnion Brackets (extending up to Z = 0.22)
	for side_x in (-0.18, 0.18):
		add_box(bm1, (side_x, 0.0, 0.16), (0.06, 0.24, 0.14), bevel=0.01)

	export_bmesh(bm1, "mortar_swivel_mount", "mortar_swivel_mount.glb")

	# 2. SINGLE MORTAR TUBE WITH RECOIL DAMPER COLLAR (mortar_tube_single.glb)
	# Origin at (0, 0, 0) angled up at 60 degrees!
	bm2 = bmesh.new()
	tube_r = 0.075
	tube_len = 1.10

	# Base Breech Cap Sphere / Cylinder at bottom of tube
	add_cyl_y(bm2, (0, 0, 0), tube_r * 1.3, 0.14, segments=16, rot_x=ELEV_60_DEG)

	# Main Mortar Tube Cylinder (pitched 60 deg up)
	t_mid_y = (tube_len * 0.5) * math.cos(ELEV_60_DEG)
	t_mid_z = (tube_len * 0.5) * math.sin(ELEV_60_DEG)
	add_cyl_y(bm2, (0, t_mid_y, t_mid_z), tube_r, tube_len, segments=18, rot_x=ELEV_60_DEG)

	# Flared Muzzle Ring at top of tube
	m_y = (tube_len - 0.02) * math.cos(ELEV_60_DEG)
	m_z = (tube_len - 0.02) * math.sin(ELEV_60_DEG)
	add_cyl_y(bm2, (0, m_y, m_z), tube_r * 1.18, 0.06, segments=18, rot_x=ELEV_60_DEG)

	# Small Twin Hydraulic Recoil Damper Collars mounted around lower section of tube
	d_pos_scale = 0.35
	d_y = (tube_len * d_pos_scale) * math.cos(ELEV_60_DEG)
	d_z = (tube_len * d_pos_scale) * math.sin(ELEV_60_DEG)

	# Damper Mounting Ring Box
	add_box(bm2, (0, d_y, d_z), (0.24, 0.12, 0.14), bevel=0.01, rot_x=ELEV_60_DEG)

	# Side Hydraulic Recoil Damper Tubes (Left & Right of tube)
	for side_x in (-0.11, 0.11):
		add_cyl_y(bm2, (side_x, d_y, d_z), 0.032, 0.40, segments=14, rot_x=ELEV_60_DEG)

	export_bmesh(bm2, "mortar_tube_single", "mortar_tube_single.glb")

if __name__ == "__main__":
	build_mortar_parts()
