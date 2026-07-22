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

def add_cone_y(bm, pos, r_base, height, segments=16):
	"""Cone along Blender Y axis (FORWARD)."""
	res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=0.001, radius2=r_base, depth=height)
	rot = mathutils.Matrix.Rotation(math.radians(90), 4, 'X')
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
		bsdf.inputs['Base Color'].default_value = (0.24, 0.26, 0.22, 1.0)
		bsdf.inputs['Metallic'].default_value = 0.65
		bsdf.inputs['Roughness'].default_value = 0.35
	obj.data.materials.append(mat)

	filepath = os.path.join(PARTS_DIR, filename)
	bpy.ops.export_scene.gltf(
		filepath=filepath,
		use_selection=True,
		export_format='GLB'
	)
	print("Successfully exported TOW sub-part GLB to:", filepath)
	clear_scene()

def build_tow_parts():
	clear_scene()

	# 1. PINTLE MOUNT & GUIDANCE OPTIC SIGHT (tow_pintle_mount.glb)
	bm1 = bmesh.new()
	# Pedestal Base Plate sitting flush on deck (Z = 0 to 0.06)
	add_cyl_z(bm1, (0, 0, 0.03), 0.20, 0.06, segments=20)

	# Elevation Yoke Trunnion Arms (Z = 0.06 to 0.24)
	for side_x in (-0.14, 0.14):
		add_box(bm1, (side_x, 0.0, 0.16), (0.05, 0.20, 0.16), bevel=0.01)
		add_cyl_x(bm1, (side_x * 1.15, 0.0, 0.24), 0.045, 0.03, segments=12)

	# Optical Day/Night Tracker Sight Box (mounted on left side of yoke)
	add_box(bm1, (-0.22, 0.02, 0.24), (0.12, 0.28, 0.16), bevel=0.012)
	# Dual Optical Lenses (front of sight box)
	add_cyl_y(bm1, (-0.22, 0.16, 0.27), 0.04, 0.03, segments=16)
	add_cyl_y(bm1, (-0.22, 0.16, 0.21), 0.03, 0.03, segments=16)

	export_bmesh(bm1, "tow_pintle_mount", "tow_pintle_mount.glb")

	# 2. FIBERGLASS LAUNCH CANISTER TUBE (tow_launch_tube.glb)
	# Centered at (0, 0, 0) so trunnion mounts at the MIDWAY point of the tube!
	bm2 = bmesh.new()
	tube_r = 0.09
	tube_len = 1.20
	half_len = tube_len * 0.5

	# Main Launch Tube Cylinder (centered at Y = 0)
	add_cyl_y(bm2, (0, 0, 0), tube_r, tube_len, segments=20)

	# Front & Rear Rubber Shock Absorber Collars
	add_cyl_y(bm2, (0, half_len - 0.05, 0), tube_r * 1.22, 0.10, segments=20)
	add_cyl_y(bm2, (0, -half_len + 0.05, 0), tube_r * 1.22, 0.10, segments=20)

	# Central Mounting Clamp Ring (right at Y = 0 trunnion midway point)
	add_box(bm2, (0, 0, 0), (tube_r * 2.5, 0.08, tube_r * 2.5), bevel=0.008)

	export_bmesh(bm2, "tow_launch_tube", "tow_launch_tube.glb")

	# 3. TOW MISSILE WARHEAD & FINS (tow_missile_warhead.glb)
	# Origin at Y = 0 (centered at front face of tube when placed at Y = +half_len)
	bm3 = bmesh.new()
	m_radius = 0.075

	# Missile Body Nose Section
	add_cyl_y(bm3, (0, 0.15, 0), m_radius, 0.30, segments=18)

	# Aerodynamic Pointed Warhead Probe Tip
	add_cone_y(bm3, (0, 0.30 + 0.10, 0), m_radius, 0.20, segments=18)
	add_cyl_y(bm3, (0, 0.30 + 0.22, 0), 0.015, 0.10, segments=10) # Extended standoff probe pin

	# Folded Guidance Flight Control Fins (X-formation)
	for angle_deg in (45, 135, 225, 315):
		rad = math.radians(angle_deg)
		fx = math.cos(rad) * (m_radius + 0.04)
		fz = math.sin(rad) * (m_radius + 0.04)
		add_box(bm3, (fx, 0.08, fz), (0.01, 0.12, 0.07), bevel=0.002)

	export_bmesh(bm3, "tow_missile_warhead", "tow_missile_warhead.glb")

if __name__ == "__main__":
	build_tow_parts()
