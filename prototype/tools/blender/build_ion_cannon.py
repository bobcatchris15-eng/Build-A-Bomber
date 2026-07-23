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

def add_torus_y(bm, pos, r_major, r_minor, seg_major=20, seg_minor=10):
	add_cyl_y(bm, pos, r_major + r_minor, r_minor * 2.0, segments=seg_major)

def export_bmesh(bm, object_name, filename, color=(0.18, 0.22, 0.28)):
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
		bsdf.inputs['Base Color'].default_value = (color[0], color[1], color[2], 1.0)
		bsdf.inputs['Metallic'].default_value = 0.75
		bsdf.inputs['Roughness'].default_value = 0.30
	obj.data.materials.append(mat)

	filepath = os.path.join(PARTS_DIR, filename)
	bpy.ops.export_scene.gltf(
		filepath=filepath,
		use_selection=True,
		export_format='GLB'
	)
	print("Successfully exported Ion Cannon sub-part GLB to:", filepath)
	clear_scene()

def build_ion_cannon_parts():
	clear_scene()

	# 1. MOUNT (ion_cannon_mount.glb)
	# Heavy circular turret pedestal ring with dual elevation trunnion arms
	bm1 = bmesh.new()
	add_cyl_z(bm1, (0, 0, 0.03), 0.28, 0.06, segments=24) # Turret base plate

	for side_x in (-0.18, 0.18):
		add_box(bm1, (side_x, 0.0, 0.18), (0.06, 0.28, 0.20), bevel=0.015)
		add_cyl_x(bm1, (side_x * 1.12, 0.0, 0.26), 0.05, 0.04, segments=14)

	export_bmesh(bm1, "ion_cannon_mount", "ion_cannon_mount.glb", color=(0.18, 0.20, 0.24))

	# 2. ACCELERATOR HOUSING BARREL (ion_cannon_housing.glb)
	# Magnetic particle accelerator barrel casing (centered around Y = 0 trunnion axis)
	bm2 = bmesh.new()
	accel_r = 0.14
	accel_len = 1.20
	half_len = accel_len * 0.5

	# Hexagonal Accelerator Outer Shell (centered at Y = 0)
	add_cyl_y(bm2, (0, 0, 0), accel_r, accel_len, segments=6)

	# 4 High-Voltage Magnetic Induction Ring Collars along barrel
	for i in range(4):
		y_pos = -half_len * 0.6 + i * (accel_len * 0.4)
		add_torus_y(bm2, (0, y_pos, 0), accel_r * 1.15, 0.025, seg_major=18, seg_minor=10)

	# Rear Power Capacitor Battery Pack
	add_box(bm2, (0, -half_len + 0.10, 0.0), (accel_r * 2.4, 0.20, accel_r * 2.2), bevel=0.01)

	export_bmesh(bm2, "ion_cannon_housing", "ion_cannon_housing.glb", color=(0.20, 0.24, 0.30))

	# 3. FOCUSING LENS (ion_cannon_lens.glb)
	# Electromagnetic quad-field focusing lens nozzle shroud (origin at front barrel interface Y = 0)
	bm3 = bmesh.new()
	lens_r = 0.14

	# Outer Bell Lens Shroud
	add_cyl_y(bm3, (0, 0.10, 0), lens_r * 1.15, 0.20, segments=16)

	# 4 Electromagnetic Quad-Field Focus Coils
	for angle in (0, 90, 180, 270):
		rad = math.radians(angle)
		cx = math.cos(rad) * (lens_r * 0.90)
		cz = math.sin(rad) * (lens_r * 0.90)
		add_box(bm3, (cx, 0.12, cz), (0.04, 0.14, 0.04), bevel=0.003)

	# Inner Plasma Emitter Ring
	add_torus_y(bm3, (0, 0.18, 0), lens_r * 0.70, 0.018, seg_major=16, seg_minor=8)

	export_bmesh(bm3, "ion_cannon_lens", "ion_cannon_lens.glb", color=(0.25, 0.60, 0.85)) # Glowing cyan/blue steel

if __name__ == "__main__":
	build_ion_cannon_parts()
