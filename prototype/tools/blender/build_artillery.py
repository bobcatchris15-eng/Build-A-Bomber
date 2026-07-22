import bpy
import bmesh
import math
import os
import mathutils

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
PARTS_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "parts")
os.makedirs(PARTS_DIR, exist_ok=True)

ELEV_ANGLE = math.radians(35.0)

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

def add_tapered_cyl_y(bm, pos, r_rear, r_front, height, segments=16, rot_x=0.0):
	"""Tapered cone along Blender Y axis (FORWARD), pitched by rot_x."""
	res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=r_front, radius2=r_rear, depth=height)
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
	print("Successfully exported Artillery sub-part GLB to:", filepath)
	clear_scene()

def build_artillery_parts():
	clear_scene()

	# 1. BULKY HEAVY CASEMATE HULL MOUNT (artillery_casemate_mount.glb)
	# Substantial non-traversing armored citadel with heavy hydraulic recoil dampers
	bm1 = bmesh.new()
	# Heavy Flange Base Plate sitting flush on deck (Z = 0 to 0.08)
	add_box(bm1, (0, 0, 0.04), (0.82, 0.88, 0.08), bevel=0.02)

	# Industrial Mounting Bolts along flange perimeter
	for side_x in (-0.37, 0.37):
		for i in range(5):
			b_y = -0.36 + i * 0.18
			add_cyl_z(bm1, (side_x, b_y, 0.08), 0.028, 0.02, segments=6)

	# Sloped Armored Citadel Structure (Z = 0.08 to 0.32)
	add_box(bm1, (0, -0.06, 0.20), (0.74, 0.76, 0.24), bevel=0.035)

	# Heavy Reinforced Side Trunnion Cheek Plates (X = -0.32 and X = +0.32)
	for side_x in (-0.32, 0.32):
		add_box(bm1, (side_x, 0.0, 0.28), (0.12, 0.54, 0.26), bevel=0.02)
		add_cyl_x(bm1, (side_x * 1.05, 0.0, 0.32), 0.07, 0.04, segments=12)

	# External Heavy Hydraulic Recoil Damper Assemblies (mounted to side cheek plates)
	for side_x in (-0.39, 0.39):
		# Damper Outer Housing Tube (angled up at 35 degrees)
		add_cyl_y(bm1, (side_x, -0.10, 0.22), 0.055, 0.42, segments=16, rot_x=ELEV_ANGLE)
		# Chrome Piston Rod extending out forward along 35 deg angle
		piston_y = -0.10 + math.cos(ELEV_ANGLE) * 0.25
		piston_z = 0.22 + math.sin(ELEV_ANGLE) * 0.25
		add_cyl_y(bm1, (side_x, piston_y, piston_z), 0.032, 0.35, segments=16, rot_x=ELEV_ANGLE)
		# Side Hydraulic Fluid Reservoir Canisters
		add_cyl_z(bm1, (side_x * 1.08, -0.05, 0.24), 0.045, 0.22, segments=12)

	# Recessed Elevation Slot between cheek plates
	add_box(bm1, (0, 0.0, 0.28), (0.42, 0.56, 0.16), bevel=0.012)

	export_bmesh(bm1, "artillery_casemate_mount", "artillery_casemate_mount.glb")

	# 2. HEAVY BREECH & RECOIL HOUSING (artillery_breech.glb)
	# Origin at trunnion height (0, 0, 0), angled up at 35 degrees!
	bm2 = bmesh.new()
	breech_w = 0.32
	breech_d = 0.48
	breech_h = 0.30

	# Main Heavy Breech Block (angled up 35 degrees)
	add_box(bm2, (0, -0.12 * math.cos(ELEV_ANGLE), -0.12 * math.sin(ELEV_ANGLE)), (breech_w, breech_d, breech_h), bevel=0.02, rot_x=ELEV_ANGLE)

	# Dual Top/Bottom Hydro-Pneumatic Recoil Buffers (pitched 35 deg)
	for z_off in (-0.14, 0.14):
		by = 0.10 * math.cos(ELEV_ANGLE) - z_off * math.sin(ELEV_ANGLE)
		bz = 0.10 * math.sin(ELEV_ANGLE) + z_off * math.cos(ELEV_ANGLE)
		add_cyl_y(bm2, (0, by - 0.12 * math.cos(ELEV_ANGLE), bz - 0.12 * math.sin(ELEV_ANGLE)), 0.07, breech_d * 0.95, segments=16, rot_x=ELEV_ANGLE)

	# Breech Operating Lever & Counterweight
	add_cyl_x(bm2, (breech_w * 0.5 + 0.03, -0.12, 0), 0.028, 0.06, segments=8)

	export_bmesh(bm2, "artillery_breech", "artillery_breech.glb")

	# 3. HEAVY ARTILLERY BARREL & MUZZLE BRAKE (artillery_barrel.glb)
	# Origin at front of breech block (0, 0, 0) extending along +Y angled up 35 degrees!
	bm3 = bmesh.new()
	sleeve_r = 0.10
	sleeve_len = 0.28
	s_y = (sleeve_len * 0.5) * math.cos(ELEV_ANGLE)
	s_z = (sleeve_len * 0.5) * math.sin(ELEV_ANGLE)

	# Reinforced Rear Barrel Sleeve
	add_cyl_y(bm3, (0, s_y, s_z), sleeve_r, sleeve_len, segments=18, rot_x=ELEV_ANGLE)

	# Tapered Heavy Artillery Barrel Tube (1.45m long, angled up 35 deg)
	barrel_len = 1.45
	b_mid_y = (sleeve_len + barrel_len * 0.5) * math.cos(ELEV_ANGLE)
	b_mid_z = (sleeve_len + barrel_len * 0.5) * math.sin(ELEV_ANGLE)
	add_tapered_cyl_y(bm3, (0, b_mid_y, b_mid_z), 0.09, 0.058, barrel_len, segments=20, rot_x=ELEV_ANGLE)

	# Heavy Double-Baffle Muzzle Brake Tip (angled up 35 deg)
	mb_center1 = (sleeve_len + barrel_len + 0.08)
	mb_center2 = (sleeve_len + barrel_len + 0.18)
	mb_tube_c = (sleeve_len + barrel_len + 0.13)

	add_box(bm3, (0, mb_center1 * math.cos(ELEV_ANGLE), mb_center1 * math.sin(ELEV_ANGLE)), (0.18, 0.18, 0.10), bevel=0.01, rot_x=ELEV_ANGLE)
	add_box(bm3, (0, mb_center2 * math.cos(ELEV_ANGLE), mb_center2 * math.sin(ELEV_ANGLE)), (0.18, 0.18, 0.10), bevel=0.01, rot_x=ELEV_ANGLE)
	add_cyl_y(bm3, (0, mb_tube_c * math.cos(ELEV_ANGLE), mb_tube_c * math.sin(ELEV_ANGLE)), 0.062, 0.28, segments=16, rot_x=ELEV_ANGLE)

	export_bmesh(bm3, "artillery_barrel", "artillery_barrel.glb")

if __name__ == "__main__":
	build_artillery_parts()
