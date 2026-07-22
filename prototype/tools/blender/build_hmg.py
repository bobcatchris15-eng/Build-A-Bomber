import bpy
import bmesh
import math
import os
import mathutils

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
PARTS_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "parts")
os.makedirs(PARTS_DIR, exist_ok=True)

def clear_scene():
	bpy.ops.object.select_all(action='SELECT')
	bpy.ops.object.delete(use_global=False)

def add_box(bm, pos, size, bevel=0.0):
	loc = mathutils.Vector(pos)
	res = bmesh.ops.create_cube(bm, size=1.0)
	for v in res['verts']:
		v.co = loc + mathutils.Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
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

def add_cyl_y(bm, pos, radius, height, segments=16):
	"""Cylinder along Blender Y axis (FORWARD)."""
	res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius, radius2=radius, depth=height)
	rot = mathutils.Matrix.Rotation(math.radians(90), 4, 'X')
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
		bsdf.inputs['Base Color'].default_value = (0.20, 0.22, 0.24, 1.0)
		bsdf.inputs['Metallic'].default_value = 0.75
		bsdf.inputs['Roughness'].default_value = 0.30
	obj.data.materials.append(mat)

	filepath = os.path.join(PARTS_DIR, filename)
	bpy.ops.export_scene.gltf(
		filepath=filepath,
		use_selection=True,
		export_format='GLB'
	)
	print("Successfully exported HMG sub-part GLB to:", filepath)
	clear_scene()

def build_hmg_parts():
	clear_scene()

	# 1. PINTLE MOUNT (hmg_pintle_mount.glb)
	bm1 = bmesh.new()
	# Base socket ring sitting flush on deck (Z = 0 to 0.06)
	add_cyl_z(bm1, (0, 0, 0.03), 0.16, 0.06, segments=16)

	# U-shaped trunnion fork arms (extending up to Z = 0.22)
	yoke_w = 0.04
	yoke_d = 0.16
	yoke_h = 0.20
	for side in (-1, 1):
		add_box(bm1, (side * 0.12, 0, 0.13), (yoke_w, yoke_d, yoke_h), bevel=0.008)
		add_cyl_x(bm1, (side * 0.14, 0, 0.22), 0.04, 0.03, segments=12)

	export_bmesh(bm1, "hmg_pintle_mount", "hmg_pintle_mount.glb")

	# 2. RECEIVER / ACTION (hmg_receiver.glb)
	# Origin at trunnion height (0, 0, 0)
	bm2 = bmesh.new()
	rec_w = 0.14
	rec_d = 0.34
	rec_h = 0.16
	rec_y_center = -0.06
	# Main Boxy Receiver
	add_box(bm2, (0, rec_y_center, 0.02), (rec_w, rec_d, rec_h), bevel=0.01)

	# Top Feed Cover Lid & Latch
	add_box(bm2, (0, rec_y_center + 0.02, 0.11), (rec_w * 0.9, rec_d * 0.6, 0.03), bevel=0.005)
	add_box(bm2, (0, rec_y_center - rec_d * 0.3, 0.11), (rec_w * 0.5, 0.04, 0.04), bevel=0.005)

	# Right-side Charging Handle
	add_cyl_x(bm2, (rec_w * 0.5 + 0.02, rec_y_center, 0.02), 0.015, 0.04, segments=8)
	add_cyl_y(bm2, (rec_w * 0.5 + 0.04, rec_y_center, 0.02), 0.02, 0.06, segments=10)

	# Rear Spade Grips (Twin D-handles for operator traverse/elevation)
	add_cyl_z(bm2, (0, rec_y_center - rec_d * 0.5 - 0.04, 0.02), 0.02, 0.10, segments=10)
	for d_side in (-1, 1):
		add_cyl_y(bm2, (d_side * 0.08, rec_y_center - rec_d * 0.5 - 0.04, 0.02), 0.015, 0.06, segments=8)
		add_cyl_z(bm2, (d_side * 0.08, rec_y_center - rec_d * 0.5 - 0.07, 0.02), 0.018, 0.12, segments=10)

	export_bmesh(bm2, "hmg_receiver", "hmg_receiver.glb")

	# 3. AMMO DRUM (hmg_ammo_drum.glb)
	# Origin at side feed tray connection (0, 0, 0)
	bm3 = bmesh.new()
	drum_r = 0.13
	drum_h = 0.14
	# Cylindrical Ammo Drum attached on left side
	add_cyl_x(bm3, (-0.12, 0.0, 0.0), drum_r, drum_h, segments=20)
	# Belt feed bracket leading into receiver
	add_box(bm3, (-0.05, 0.0, 0.01), (0.08, 0.10, 0.04), bevel=0.005)
	export_bmesh(bm3, "hmg_ammo_drum", "hmg_ammo_drum.glb")

	# 4. HEAVY BARREL & COOLING JACKET (hmg_barrel.glb)
	# Origin at front face of receiver socket (0, 0, 0) extending along +Y
	bm4 = bmesh.new()
	# Rear mounting collar
	add_cyl_y(bm4, (0, 0.05, 0), 0.055, 0.10, segments=16)

	# Perforated Cooling Jacket Cylinder
	jacket_r = 0.045
	jacket_len = 0.50
	jacket_mid_y = 0.10 + jacket_len * 0.5
	add_cyl_y(bm4, (0, jacket_mid_y, 0), jacket_r, jacket_len, segments=16)

	# Cooling Jacket ventilation slots/rings along length
	for i in range(5):
		ring_y = 0.15 + i * 0.09
		add_cyl_y(bm4, (0, ring_y, 0), jacket_r * 1.12, 0.02, segments=16)

	# Barrel Tube extending forward out of jacket
	barrel_r = 0.028
	barrel_len = 0.35
	barrel_start_y = 0.10 + jacket_len
	barrel_mid_y = barrel_start_y + barrel_len * 0.5
	add_cyl_y(bm4, (0, barrel_mid_y, 0), barrel_r, barrel_len, segments=16)

	# Flash Hider Muzzle Tip
	tip_start_y = barrel_start_y + barrel_len
	add_cyl_y(bm4, (0, tip_start_y + 0.03, 0), 0.038, 0.06, segments=12)
	add_cyl_y(bm4, (0, tip_start_y + 0.07, 0), 0.032, 0.03, segments=12)

	export_bmesh(bm4, "hmg_barrel", "hmg_barrel.glb")

if __name__ == "__main__":
	build_hmg_parts()
