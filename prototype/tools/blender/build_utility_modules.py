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

def add_cone_y(bm, pos, r_base, r_top, height, segments=16):
	"""Cone / Frustum along Blender Y axis (FORWARD)."""
	res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=r_top, radius2=r_base, depth=height)
	rot = mathutils.Matrix.Rotation(math.radians(90), 4, 'X')
	loc = mathutils.Vector(pos)
	for v in res['verts']:
		v.co = rot @ v.co + loc

def export_bmesh(bm, object_name, filename, color=(0.24, 0.26, 0.28)):
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
		bsdf.inputs['Metallic'].default_value = 0.65
		bsdf.inputs['Roughness'].default_value = 0.35
	obj.data.materials.append(mat)

	filepath = os.path.join(PARTS_DIR, filename)
	bpy.ops.export_scene.gltf(
		filepath=filepath,
		use_selection=True,
		export_format='GLB'
	)
	print("Successfully exported utility sub-part GLB to:", filepath)
	clear_scene()

def build_utility_parts():
	# ----------------------------------------------------
	# 1. DRONE CARRIER / HANGAR BAY (drone_carrier)
	# ----------------------------------------------------
	clear_scene()
	# 1A. Catapult Launch Deck Mount (drone_carrier_mount.glb)
	bm1 = bmesh.new()
	add_box(bm1, (0, 0, 0.03), (0.50, 0.80, 0.06), bevel=0.015)
	add_box(bm1, (-0.12, 0.0, 0.07), (0.04, 0.76, 0.03), bevel=0.005) # Left catapult rail
	add_box(bm1, (0.12, 0.0, 0.07), (0.04, 0.76, 0.03), bevel=0.005) # Right catapult rail
	export_bmesh(bm1, "drone_carrier_mount", "drone_carrier_mount.glb", color=(0.20, 0.22, 0.26))

	# 1B. Hangar Bay Enclosure Casing (drone_carrier_housing.glb)
	bm2 = bmesh.new()
	add_box(bm2, (0, 0.15, 0.16), (0.46, 0.44, 0.22), bevel=0.02)
	# Launch Bay Door Frame
	add_box(bm2, (0, -0.06, 0.16), (0.42, 0.04, 0.18), bevel=0.01)
	export_bmesh(bm2, "drone_carrier_housing", "drone_carrier_housing.glb", color=(0.28, 0.30, 0.34))

	# 1C. Scout Drone Aircraft (drone_carrier_drone.glb)
	bm3 = bmesh.new()
	add_box(bm3, (0, 0, 0), (0.06, 0.18, 0.04), bevel=0.008) # Drone fuselage
	add_box(bm3, (0, 0, 0.01), (0.24, 0.05, 0.015), bevel=0.003) # Delta wings
	add_box(bm3, (0, 0.08, 0.02), (0.02, 0.04, 0.03), bevel=0.002) # Tail fin
	export_bmesh(bm3, "drone_carrier_drone", "drone_carrier_drone.glb", color=(0.85, 0.85, 0.88))

	# ----------------------------------------------------
	# 2. RESOURCE HARVESTER (resource_harvester)
	# ----------------------------------------------------
	clear_scene()
	# 2A. Hydraulic Turntable Mount (resource_harvester_mount.glb)
	bm4 = bmesh.new()
	add_cyl_z(bm4, (0, 0, 0.04), 0.28, 0.08, segments=24) # Base turntable plate
	for sx in (-0.16, 0.16):
		add_box(bm4, (sx, 0.0, 0.18), (0.06, 0.26, 0.20), bevel=0.012)
	export_bmesh(bm4, "resource_harvester_mount", "resource_harvester_mount.glb", color=(0.22, 0.24, 0.20))

	# 2B. Articulated Extractor Boom Arm (resource_harvester_arm.glb)
	bm5 = bmesh.new()
	add_box(bm5, (0, 0.15, 0.24), (0.16, 0.40, 0.14), bevel=0.01, rot_x=math.radians(-25)) # Lower boom arm
	add_cyl_y(bm5, (0, 0.32, 0.14), 0.04, 0.18, segments=16) # Hydraulic cylinder piston
	export_bmesh(bm5, "resource_harvester_arm", "resource_harvester_arm.glb", color=(0.75, 0.50, 0.15)) # Industrial Hazard Yellow/Amber

	# 2C. Rotary Extractor Drill Bit (resource_harvester_drill.glb)
	bm6 = bmesh.new()
	add_cone_y(bm6, (0, 0.42, 0.04), 0.14, 0.02, 0.28, segments=18) # Conical diamond bit
	for i in range(4):
		ang = i * (math.pi / 2.0)
		bx = math.cos(ang) * 0.08
		bz = math.sin(ang) * 0.08
		add_box(bm6, (bx, 0.38, 0.04 + bz), (0.02, 0.20, 0.02), bevel=0.003) # Carbide cutter flutes
	export_bmesh(bm6, "resource_harvester_drill", "resource_harvester_drill.glb", color=(0.35, 0.38, 0.42))

	# ----------------------------------------------------
	# 3. REPAIR ARRAY (repair_array)
	# ----------------------------------------------------
	clear_scene()
	# 3A. Octagonal Deck Base Socket (repair_array_mount.glb)
	bm7 = bmesh.new()
	add_cyl_z(bm7, (0, 0, 0.03), 0.26, 0.06, segments=8)
	add_cyl_z(bm7, (0, 0, 0.08), 0.18, 0.04, segments=16) # Central energy coupling socket
	export_bmesh(bm7, "repair_array_mount", "repair_array_mount.glb", color=(0.20, 0.22, 0.26))

	# 3B. Multi-Joint Welder Arm Segment (repair_array_arm.glb)
	bm8 = bmesh.new()
	add_cyl_z(bm8, (0, 0, 0.16), 0.035, 0.20, segments=12) # Vertical shoulder post
	add_box(bm8, (0, 0.08, 0.24), (0.04, 0.20, 0.04), bevel=0.005, rot_x=math.radians(-30)) # Arm segment
	export_bmesh(bm8, "repair_array_arm", "repair_array_arm.glb", color=(0.25, 0.28, 0.32))

	# 3C. Plasma Torch Welder Tip (repair_array_welder.glb)
	bm9 = bmesh.new()
	add_cone_y(bm9, (0, 0.22, 0.16), 0.04, 0.012, 0.14, segments=14) # Torch nozzle
	add_cyl_y(bm9, (0, 0.29, 0.16), 0.015, 0.04, segments=12) # Plasma arc electrode tip
	export_bmesh(bm9, "repair_array_welder", "repair_array_welder.glb", color=(0.15, 0.65, 0.85)) # Glowing cyan arc tip

	# ----------------------------------------------------
	# 4. SENSOR SUITE / RADAR (sensor_suite)
	# ----------------------------------------------------
	clear_scene()
	# 4A. Octagonal Mast Pedestal Base (sensor_suite_mount.glb)
	bm10 = bmesh.new()
	add_cyl_z(bm10, (0, 0, 0.03), 0.22, 0.06, segments=8)
	add_cyl_z(bm10, (0, 0, 0.08), 0.14, 0.04, segments=16) # Mast socket collar
	export_bmesh(bm10, "sensor_suite_mount", "sensor_suite_mount.glb", color=(0.18, 0.20, 0.24))

	# 4B. Structural Lattice Mast Tower Column (sensor_suite_mast.glb)
	# Origin at base socket (0, 0, 0)
	bm11 = bmesh.new()
	mast_h = 1.00
	add_cyl_z(bm11, (0, 0, mast_h * 0.5), 0.04, mast_h, segments=12) # Central mast rod
	# 4 Corner Truss Legs
	for angle in (0, 90, 180, 270):
		rad = math.radians(angle)
		tx = math.cos(rad) * 0.08
		ty = math.sin(rad) * 0.08
		add_cyl_z(bm11, (tx, ty, mast_h * 0.5), 0.015, mast_h, segments=8)
	# 3 Cross-Truss Ring Collars
	for iz in range(3):
		zh = (iz + 1) * (mast_h / 4.0)
		add_cyl_z(bm11, (0, 0, zh), 0.09, 0.02, segments=12)
	export_bmesh(bm11, "sensor_suite_mast", "sensor_suite_mast.glb", color=(0.25, 0.28, 0.32))

	# 4C. Rotating Parabolic Antenna Dish (sensor_suite_dish.glb)
	# Origin at top of mast (0, 0, 0)
	bm12 = bmesh.new()
	add_cone_y(bm12, (0, 0.06, 0), 0.28, 0.02, 0.12, segments=24) # Parabolic reflector dish bowl
	add_cyl_y(bm12, (0, 0.18, 0), 0.015, 0.14, segments=10) # Feed horn receiver probe
	add_cyl_y(bm12, (0, 0.25, 0), 0.035, 0.03, segments=12) # Feed horn cap
	export_bmesh(bm12, "sensor_suite_dish", "sensor_suite_dish.glb", color=(0.85, 0.88, 0.90))

if __name__ == "__main__":
	build_utility_parts()
