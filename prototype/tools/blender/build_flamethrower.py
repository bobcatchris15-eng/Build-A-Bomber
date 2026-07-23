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

def add_cone_y(bm, pos, r_base, r_top, height, segments=16):
	"""Cone / Frustum along Blender Y axis (FORWARD)."""
	res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=r_top, radius2=r_base, depth=height)
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
		bsdf.inputs['Base Color'].default_value = (0.35, 0.20, 0.12, 1.0)
		bsdf.inputs['Metallic'].default_value = 0.65
		bsdf.inputs['Roughness'].default_value = 0.35
	obj.data.materials.append(mat)

	filepath = os.path.join(PARTS_DIR, filename)
	bpy.ops.export_scene.gltf(
		filepath=filepath,
		use_selection=True,
		export_format='GLB'
	)
	print("Successfully exported Flamethrower Emitter sub-part GLB to:", filepath)
	clear_scene()

def build_flamethrower_parts():
	clear_scene()

	# 1. PINTLE MOUNT (flamethrower_mount.glb)
	bm1 = bmesh.new()
	# Pedestal Base Socket sitting flush on deck (Z = 0 to 0.05)
	add_cyl_z(bm1, (0, 0, 0.025), 0.18, 0.05, segments=20)

	# Elevation Yoke Trunnion Arms (Z = 0.05 to 0.20)
	for side_x in (-0.13, 0.13):
		add_box(bm1, (side_x, 0.0, 0.12), (0.04, 0.18, 0.14), bevel=0.01)
		add_cyl_x(bm1, (side_x * 1.12, 0.0, 0.20), 0.04, 0.03, segments=12)

	export_bmesh(bm1, "flamethrower_mount", "flamethrower_mount.glb")

	# 2. BODY & DUAL NAPALM FUEL CYLINDERS (flamethrower_body.glb)
	# Origin at trunnion height (0, 0, 0)
	bm2 = bmesh.new()

	# Main Central Pressure Manifold Block (centered at Y = 0)
	add_box(bm2, (0, 0, 0), (0.20, 0.40, 0.18), bevel=0.015)

	# Side-Mounted Napalm Fuel Pressure Tanks
	for side_x in (-0.16, 0.16):
		add_cyl_y(bm2, (side_x, 0.0, 0.02), 0.07, 0.38, segments=16)
		# Tank end caps
		add_cyl_y(bm2, (side_x, -0.19, 0.02), 0.065, 0.03, segments=16)
		add_cyl_y(bm2, (side_x, 0.19, 0.02), 0.065, 0.03, segments=16)
		# Tank mounting straps
		add_box(bm2, (side_x, -0.08, 0.02), (0.15, 0.03, 0.15), bevel=0.003)
		add_box(bm2, (side_x, 0.08, 0.02), (0.15, 0.03, 0.15), bevel=0.003)

	# Top Pressure Valve Regulator Knob & Dial Gauge
	add_cyl_z(bm2, (0, 0.05, 0.12), 0.04, 0.05, segments=12)
	add_cyl_y(bm2, (0.05, -0.08, 0.08), 0.035, 0.03, segments=14)

	export_bmesh(bm2, "flamethrower_body", "flamethrower_body.glb")

	# 3. NOZZLE & PILOT ARC IGNITER (flamethrower_nozzle.glb)
	# Origin at rear interface with body (0, 0, 0)
	bm3 = bmesh.new()

	# Emitter Barrel Tube extending forward along Z negative (Blender Y positive = forward)
	# Y = 0.0 to 0.35
	add_cyl_y(bm3, (0, 0.15, 0), 0.05, 0.30, segments=16)

	# Flared Emitter Nozzle Shroud (bell cone tip)
	add_cone_y(bm3, (0, 0.32, 0), 0.05, 0.085, 0.08, segments=16)

	# Pilot Arc Spark Igniter Rod (underneath nozzle tip)
	add_cyl_y(bm3, (0, 0.30, -0.07), 0.012, 0.16, segments=10)
	add_box(bm3, (0, 0.36, -0.07), (0.02, 0.02, 0.04), bevel=0.002) # Pilot flame shield box

	export_bmesh(bm3, "flamethrower_nozzle", "flamethrower_nozzle.glb")

if __name__ == "__main__":
	build_flamethrower_parts()
