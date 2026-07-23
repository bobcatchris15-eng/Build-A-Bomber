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
		bsdf.inputs['Base Color'].default_value = (0.24, 0.26, 0.28, 1.0)
		bsdf.inputs['Metallic'].default_value = 0.70
		bsdf.inputs['Roughness'].default_value = 0.30
	obj.data.materials.append(mat)

	filepath = os.path.join(PARTS_DIR, filename)
	bpy.ops.export_scene.gltf(
		filepath=filepath,
		use_selection=True,
		export_format='GLB'
	)
	print("Successfully exported Swarm Missile Pod sub-part GLB to:", filepath)
	clear_scene()

def build_missile_pod_parts():
	clear_scene()

	# 1. PINTLE MOUNT (missile_pod_pintle_mount.glb)
	bm1 = bmesh.new()
	# Pedestal Base Socket sitting flush on deck (Z = 0 to 0.05)
	add_cyl_z(bm1, (0, 0, 0.025), 0.22, 0.05, segments=20)

	# Elevation Yoke Trunnion Arms (Z = 0.05 to 0.24)
	for side_x in (-0.16, 0.16):
		add_box(bm1, (side_x, 0.0, 0.15), (0.05, 0.22, 0.18), bevel=0.01)
		add_cyl_x(bm1, (side_x * 1.12, 0.0, 0.24), 0.045, 0.03, segments=12)

	export_bmesh(bm1, "missile_pod_pintle_mount", "missile_pod_pintle_mount.glb")

	# 2. ROCKET LAUNCHER HOUSING BOX (missile_pod_housing.glb)
	# Origin at trunnion height (0, 0, 0)
	bm2 = bmesh.new()
	pod_w = 0.48
	pod_h = 0.38
	pod_d = 0.85

	# Main Armored Shell Box (centered at Y = 0 so it tilts on trunnion pivot)
	add_box(bm2, (0, 0, 0), (pod_w, pod_d, pod_h), bevel=0.025)

	# Side Trunnion Mounting Brackets
	for side_x in (-0.25, 0.25):
		add_box(bm2, (side_x, 0.0, 0.0), (0.04, 0.24, 0.14), bevel=0.008)

	# Front Recessed Cell Face Plate (dark interior mask)
	add_box(bm2, (0, -pod_d * 0.5 + 0.01, 0), (pod_w * 0.92, 0.02, pod_h * 0.90), bevel=0.005)

	# Rear Exhaust Vent Slits
	for i in range(4):
		z_pos = -pod_h * 0.35 + i * (pod_h * 0.7 / 3)
		add_box(bm2, (0, pod_d * 0.5 + 0.01, z_pos), (pod_w * 0.80, 0.02, 0.03), bevel=0.002)

	export_bmesh(bm2, "missile_pod_housing", "missile_pod_housing.glb")

	# 3. INDIVIDUAL SWARM ROCKET (missile_pod_missile.glb)
	# Origin at rocket warhead tip / front face (0, 0, 0)
	bm3 = bmesh.new()
	r_radius = 0.04
	r_len = 0.70

	# Aerodynamic Warhead Nose Cone
	add_cone_y(bm3, (0, 0.12, 0), r_radius, 0.12, segments=16)

	# Rocket Motor Body Tube
	add_cyl_y(bm3, (0, -r_len * 0.5 + 0.12, 0), r_radius, r_len, segments=16)

	# Rear Exhaust Nozzle Ring
	add_cyl_y(bm3, (0, -r_len + 0.12, 0), r_radius * 1.15, 0.05, segments=16)

	# 4 Tail Stabilizer Fins (X-pattern)
	for angle_deg in (45, 135, 225, 315):
		rad = math.radians(angle_deg)
		fx = math.cos(rad) * (r_radius + 0.025)
		fz = math.sin(rad) * (r_radius + 0.025)
		add_box(bm3, (fx, -r_len + 0.20, fz), (0.008, 0.12, 0.04), bevel=0.001)

	export_bmesh(bm3, "missile_pod_missile", "missile_pod_missile.glb")

if __name__ == "__main__":
	build_missile_pod_parts()
