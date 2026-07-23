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

def add_torus_z(bm, pos, r_major, r_minor, seg_major=20, seg_minor=10):
	add_cyl_z(bm, pos, r_major + r_minor, r_minor * 2.0, segments=seg_major)

def export_bmesh(bm, object_name, filename, color=(0.20, 0.22, 0.28)):
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
		bsdf.inputs['Roughness'].default_value = 0.25
	obj.data.materials.append(mat)

	filepath = os.path.join(PARTS_DIR, filename)
	bpy.ops.export_scene.gltf(
		filepath=filepath,
		use_selection=True,
		export_format='GLB'
	)
	print("Successfully exported Tesla Coil sub-part GLB to:", filepath)
	clear_scene()

def build_tesla_coil_parts():
	clear_scene()

	# 1. MOUNT (tesla_coil_mount.glb)
	# Heavy octagonal deck pedestal with ceramic insulator feet
	bm1 = bmesh.new()
	add_cyl_z(bm1, (0, 0, 0.03), 0.26, 0.06, segments=8) # Octagonal base plate
	add_cyl_z(bm1, (0, 0, 0.08), 0.22, 0.04, segments=16) # Secondary socket ring

	# 4 Ceramic Insulator Ribbed Ribs
	for angle in (0, 90, 180, 270):
		rad = math.radians(angle)
		ix = math.cos(rad) * 0.18
		iy = math.sin(rad) * 0.18
		add_cyl_z(bm1, (ix, iy, 0.08), 0.04, 0.06, segments=12)

	export_bmesh(bm1, "tesla_coil_mount", "tesla_coil_mount.glb", color=(0.18, 0.20, 0.24))

	# 2. TRANSFORMER TOWER HOUSING (tesla_coil_housing.glb)
	# High-voltage secondary winding coil column
	# Origin at base socket interface (0, 0, 0)
	bm2 = bmesh.new()
	tower_h = 0.80
	tower_r = 0.16

	# Primary Winding Cylinder
	add_cyl_z(bm2, (0, 0, tower_h * 0.5), tower_r, tower_h, segments=20)

	# 6 Copper Field Collector Rings along coil height
	for i in range(6):
		zh = (i + 1) * (tower_h / 7.0)
		add_torus_z(bm2, (0, 0, zh), tower_r * 1.10, 0.025, seg_major=20, seg_minor=10)

	# Spark Gap Regulator Box
	add_box(bm2, (0, 0.18, tower_h * 0.3), (0.12, 0.08, 0.16), bevel=0.008)

	export_bmesh(bm2, "tesla_coil_housing", "tesla_coil_housing.glb", color=(0.70, 0.45, 0.20)) # Metallic copper/amber

	# 3. DISCHARGE TOROID DOME (tesla_coil_toroid.glb)
	# Polished high-voltage discharge toroid ring with spark electrode tip
	# Origin at top of tower (0, 0, 0)
	bm3 = bmesh.new()
	toroid_r = 0.26
	toroid_thick = 0.065

	# Main Stainless Steel Discharge Toroid Ring
	add_torus_z(bm3, (0, 0, 0), toroid_r, toroid_thick, seg_major=24, seg_minor=14)

	# Top High-Voltage Spark Electrode Ball Tip
	add_cyl_z(bm3, (0, 0, toroid_thick * 1.5), 0.06, 0.08, segments=16)

	export_bmesh(bm3, "tesla_coil_toroid", "tesla_coil_toroid.glb", color=(0.85, 0.90, 0.95)) # Polished steel/chrome

if __name__ == "__main__":
	build_tesla_coil_parts()
