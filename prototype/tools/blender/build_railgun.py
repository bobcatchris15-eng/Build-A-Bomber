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
		bsdf.inputs['Base Color'].default_value = (0.18, 0.20, 0.22, 1.0)
		bsdf.inputs['Metallic'].default_value = 0.80
		bsdf.inputs['Roughness'].default_value = 0.25
	obj.data.materials.append(mat)

	filepath = os.path.join(PARTS_DIR, filename)
	bpy.ops.export_scene.gltf(
		filepath=filepath,
		use_selection=True,
		export_format='GLB'
	)
	print("Successfully exported Railgun sub-part GLB to:", filepath)
	clear_scene()

def build_railgun_parts():
	clear_scene()

	# 1. HEAVY CASEMATE HULL MOUNT (railgun_casemate_mount.glb)
	# Substantial non-traversing armored citadel base built directly into the hull
	bm1 = bmesh.new()
	# Heavy Deck Mounting Flange Plate sitting flush on deck (Z = 0 to 0.06)
	add_box(bm1, (0, 0, 0.03), (0.58, 0.68, 0.06), bevel=0.015)
	# Heavy Industrial Bolt Line around flange edge
	for side_x in (-0.26, 0.26):
		for i in range(4):
			b_y = -0.28 + i * 0.18
			add_cyl_z(bm1, (side_x, b_y, 0.06), 0.02, 0.02, segments=6)

	# Sloped Armored Casemate Citadel Structure (Z = 0.06 to 0.26)
	add_box(bm1, (0, -0.05, 0.16), (0.52, 0.58, 0.20), bevel=0.025)
	# Recessed Central Slot for elevation trunnions
	add_box(bm1, (0, 0.0, 0.22), (0.34, 0.48, 0.12), bevel=0.01)

	export_bmesh(bm1, "railgun_casemate_mount", "railgun_casemate_mount.glb")

	# 2. CAPACITOR / BREECH HOUSING (railgun_capacitor_housing.glb)
	# Origin at trunnion height (0, 0, 0)
	bm2 = bmesh.new()
	cap_w = 0.28
	cap_d = 0.42
	cap_h = 0.22
	cap_y_center = -0.12

	# Main Capacitor Power Bank Box
	add_box(bm2, (0, cap_y_center, 0), (cap_w, cap_d, cap_h), bevel=0.015)
	# Rear Energy Heatsink Cooling Fins
	for i in range(5):
		fin_y = cap_y_center - cap_d * 0.5 - 0.02 - i * 0.025
		add_box(bm2, (0, fin_y, 0), (cap_w * 0.85, 0.015, cap_h * 0.9), bevel=0.002)

	# Side High-Voltage Cable Conduits
	for side in (-1, 1):
		add_cyl_y(bm2, (side * (cap_w * 0.5 + 0.03), cap_y_center + 0.05, 0.04), 0.03, cap_d * 0.7, segments=12)

	export_bmesh(bm2, "railgun_capacitor_housing", "railgun_capacitor_housing.glb")

	# 3. ELECTROMAGNETIC RAILS & BRACES (railgun_rails.glb)
	# Origin at front of capacitor housing (0, 0, 0) extending along +Y
	bm3 = bmesh.new()
	rail_len = 1.40
	rail_w = 0.035
	rail_h = 0.04

	# Twin Parallel Accelerator Rails (Upper & Lower)
	for z_off in (-0.06, 0.06):
		add_box(bm3, (0, rail_len * 0.5, z_off), (rail_w, rail_len, rail_h), bevel=0.005)

	# Central Accelerator Bore Core Tube
	add_cyl_y(bm3, (0, rail_len * 0.5, 0), 0.045, rail_len, segments=16)

	# Rectangular Insulating Ring Braces spaced along rails
	num_rings = 6
	for i in range(num_rings):
		ring_y = 0.15 + i * (rail_len - 0.25) / (num_rings - 1)
		add_box(bm3, (0, ring_y, 0), (0.16, 0.04, 0.20), bevel=0.008)

	# Muzzle Reinforcement Ring
	add_box(bm3, (0, rail_len - 0.02, 0), (0.18, 0.05, 0.22), bevel=0.01)

	export_bmesh(bm3, "railgun_rails", "railgun_rails.glb")

if __name__ == "__main__":
	build_railgun_parts()
