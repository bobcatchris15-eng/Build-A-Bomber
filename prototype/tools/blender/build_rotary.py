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
		bsdf.inputs['Base Color'].default_value = (0.22, 0.24, 0.26, 1.0)
		bsdf.inputs['Metallic'].default_value = 0.75
		bsdf.inputs['Roughness'].default_value = 0.30
	obj.data.materials.append(mat)

	filepath = os.path.join(PARTS_DIR, filename)
	bpy.ops.export_scene.gltf(
		filepath=filepath,
		use_selection=True,
		export_format='GLB'
	)
	print("Successfully exported Rotary sub-part GLB to:", filepath)
	clear_scene()

def build_rotary_parts():
	clear_scene()

	# 1. PINTLE MOUNT (rotary_pintle_mount.glb)
	bm1 = bmesh.new()
	# Base Socket Ring sitting on deck (Z = 0 to 0.08)
	add_cyl_z(bm1, (0, 0, 0.04), 0.24, 0.08, segments=20)

	# Heavy Yoke Carriage Arms
	yoke_w = 0.06
	yoke_d = 0.24
	yoke_h = 0.22
	for side in (-1, 1):
		add_box(bm1, (side * 0.18, 0, 0.17), (yoke_w, yoke_d, yoke_h), bevel=0.012)
		add_cyl_x(bm1, (side * 0.21, 0, 0.24), 0.06, 0.04, segments=16)

	export_bmesh(bm1, "rotary_pintle_mount", "rotary_pintle_mount.glb")

	# 2. ROTOR HOUSING & DRIVE MOTOR (rotary_housing.glb)
	# Origin at trunnion height (0, 0, 0)
	bm2 = bmesh.new()
	housing_r = 0.20
	housing_len = 0.35
	housing_y_center = -0.05
	# Main Cylindrical Rotor Housing
	add_cyl_y(bm2, (0, housing_y_center, 0), housing_r, housing_len, segments=24)
	add_cyl_y(bm2, (0, housing_y_center + housing_len * 0.5, 0), housing_r * 1.10, 0.04, segments=24)

	# Rear Electric Drive Motor (Top-rear of housing)
	motor_r = 0.09
	motor_len = 0.24
	add_cyl_y(bm2, (0, housing_y_center - housing_len * 0.5 - motor_len * 0.5, 0.12), motor_r, motor_len, segments=16)
	add_box(bm2, (0, housing_y_center - 0.10, 0.12), (0.16, 0.20, 0.08), bevel=0.01)

	# Side Ammo Chute Bracket
	add_box(bm2, (-housing_r * 1.05, housing_y_center, 0), (0.08, 0.16, 0.12), bevel=0.008)

	export_bmesh(bm2, "rotary_housing", "rotary_housing.glb")

	# 3. SINGLE GATLING BARREL (rotary_barrel_single.glb)
	# Origin at base (0, 0, 0) extending along +Y
	bm3 = bmesh.new()
	# Rear breech locking socket
	add_cyl_y(bm3, (0, 0.04, 0), 0.040, 0.08, segments=12)

	# Slender main barrel tube
	barrel_r = 0.024
	barrel_len = 1.10
	barrel_mid_y = 0.08 + barrel_len * 0.5
	add_cyl_y(bm3, (0, barrel_mid_y, 0), barrel_r, barrel_len, segments=14)

	# Muzzle Tip
	add_cyl_y(bm3, (0, 0.08 + barrel_len + 0.02, 0), 0.030, 0.04, segments=12)

	export_bmesh(bm3, "rotary_barrel_single", "rotary_barrel_single.glb")

	# 4. FRONT BARREL CLAMP DISK (rotary_clamp_ring.glb)
	# Circular spacer ring holding barrels together in a ring
	bm4 = bmesh.new()
	add_cyl_y(bm4, (0, 0, 0), 0.18, 0.04, segments=24)
	export_bmesh(bm4, "rotary_clamp_ring", "rotary_clamp_ring.glb")

if __name__ == "__main__":
	build_rotary_parts()
