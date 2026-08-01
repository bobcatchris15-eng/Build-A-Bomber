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

def add_tapered_cyl_y(bm, pos, r_rear, r_front, height, segments=16):
	"""Tapered cone along Blender Y axis: r_rear at -Y (breech), r_front at +Y (muzzle)."""
	res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=r_front, radius2=r_rear, depth=height)
	rot = mathutils.Matrix.Rotation(math.radians(90), 4, 'X')
	loc = mathutils.Vector(pos)
	for v in res['verts']:
		v.co = rot @ v.co + loc

def add_bolt_ring(bm, pos, radius, count=6, axis='z', bolt_r=0.015, bolt_h=0.015):
	for i in range(count):
		angle = (2.0 * math.pi * i) / count
		ca, sa = math.cos(angle) * radius, math.sin(angle) * radius
		if axis == 'z':
			b_pos = (pos[0] + ca, pos[1] + sa, pos[2])
			add_cyl_z(bm, b_pos, bolt_r, bolt_h, segments=6)
		elif axis == 'y':
			b_pos = (pos[0] + ca, pos[1], pos[2] + sa)
			add_cyl_y(bm, b_pos, bolt_r, bolt_h, segments=6)
		elif axis == 'x':
			b_pos = (pos[0], pos[1] + ca, pos[2] + sa)
			add_cyl_x(bm, b_pos, bolt_r, bolt_h, segments=6)

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
		bsdf.inputs['Metallic'].default_value = 0.70
		bsdf.inputs['Roughness'].default_value = 0.35
	obj.data.materials.append(mat)

	filepath = os.path.join(PARTS_DIR, filename)
	bpy.ops.export_scene.gltf(
		filepath=filepath,
		use_selection=True,
		export_format='GLB'
	)
	print("Successfully exported sub-part GLB to:", filepath)
	clear_scene()

def build_37mm_m3_parts():
	clear_scene()

	# 1. MOUNT / PINTLE (m3_pintle_mount.glb)
	bm1 = bmesh.new()
	add_cyl_z(bm1, (0, 0, 0.04), 0.22, 0.08, segments=20)
	add_bolt_ring(bm1, (0, 0, 0.08), 0.17, count=6, axis='z')

	yoke_h = 0.26
	yoke_w = 0.05
	yoke_d = 0.22
	for side in (-1, 1):
		add_box(bm1, (side * 0.16, 0, 0.18), (yoke_w, yoke_d, yoke_h), bevel=0.012)
		add_cyl_x(bm1, (side * 0.19, 0, 0.26), 0.055, 0.03, segments=12)

	add_box(bm1, (-0.20, 0.0, 0.22), (0.06, 0.12, 0.10), bevel=0.008)
	add_cyl_x(bm1, (-0.24, 0.02, 0.24), 0.015, 0.06, segments=8)
	add_cyl_x(bm1, (-0.27, 0.02, 0.24), 0.08, 0.02, segments=16)
	export_bmesh(bm1, "m3_pintle_mount", "m3_pintle_mount.glb")

	# 2. ACTION / BREECH (m3_action_breech.glb)
	#
	# Two things this part has to do that it previously did not:
	#
	# 1. PROJECT BEHIND THE TRUNNIONS. The origin IS the trunnion line, and
	#    everything used to sit in front of it or level with it, so the gun
	#    read as a barrel stuck on a post with nothing balancing it. A real
	#    gun of this calibre carries most of its mass behind the trunnion -
	#    recuperator cylinders, the breech ring, the case deflector, the
	#    loader. Blender -Y is behind (Godot +Z), so that is where the blocky
	#    mass goes now.
	#
	# 2. READ AS A REMOTE WEAPON STATION. The old hand operating lever said
	#    "a crew stands here and works this", which is wrong for a module
	#    bolted to the outside of a vehicle. Replaced with an electric breech
	#    actuator - motor, gearbox, linkage arm - which does the same job with
	#    nobody behind it.
	bm2 = bmesh.new()
	breech_w = 0.22
	breech_h = 0.26
	breech_l = 0.38
	breech_y_center = -0.03
	add_box(bm2, (0, breech_y_center, 0), (breech_w, breech_l, breech_h), bevel=0.018)
	add_box(bm2, (0, breech_y_center, 0 + breech_h * 0.45), (breech_w * 0.7, breech_l * 0.6, 0.04), bevel=0.005)
	add_cyl_y(bm2, (0, breech_y_center - breech_l * 0.5, 0), 0.06, 0.04, segments=12)

	# --- Blocky mass projecting BEHIND the trunnion line --------------------
	# Breech ring: a heavy rectangular block immediately aft, wider than the
	# body, which is the anchor for everything else back here.
	add_box(bm2, (0, -0.28, -0.01), (0.27, 0.16, 0.28), bevel=0.016)
	add_bolt_ring(bm2, (0, -0.36, -0.01), 0.10, count=8, axis='y')

	# Twin recuperator cylinders running back either side of it
	for side in (-1, 1):
		add_cyl_y(bm2, (side * 0.155, -0.36, 0.055), 0.048, 0.34, segments=14)
		add_cyl_y(bm2, (side * 0.155, -0.19, 0.055), 0.056, 0.035, segments=14)
		add_cyl_y(bm2, (side * 0.155, -0.53, 0.055), 0.056, 0.035, segments=14)
		# Cooling ribs down each cylinder
		for i in range(4):
			add_cyl_y(bm2, (side * 0.155, -0.26 - i * 0.070, 0.055), 0.054, 0.016, segments=14)

	# Case deflector / recoil guard: a big flat blocky shroud across the back
	add_box(bm2, (0, -0.47, -0.06), (0.30, 0.09, 0.24), bevel=0.012)
	add_box(bm2, (0, -0.53, -0.15), (0.26, 0.11, 0.09), bevel=0.010)   # ejection chute
	# Spent-case bin slung under the chute
	add_box(bm2, (0, -0.50, -0.24), (0.20, 0.20, 0.10), bevel=0.010)

	# Autoloader magazine block, offset to one side and unmistakably square
	add_box(bm2, (0.20, -0.34, 0.13), (0.15, 0.30, 0.20), bevel=0.012)
	for i in range(4):
		add_box(bm2, (0.20, -0.44 + i * 0.068, 0.235), (0.13, 0.030, 0.020), bevel=0.004)
	add_box(bm2, (0.115, -0.24, 0.10), (0.07, 0.11, 0.09), bevel=0.008)   # transfer chute

	# Junction box and conduit runs on the other side - the electrical half
	# of "this thing is operated from somewhere else".
	add_box(bm2, (-0.19, -0.32, 0.10), (0.10, 0.20, 0.14), bevel=0.010)
	for i in range(3):
		add_cyl_y(bm2, (-0.19, -0.44 - i * 0.008, 0.055 + i * 0.030), 0.012, 0.18, segments=8)
	add_cyl_z(bm2, (-0.19, -0.22, 0.15), 0.014, 0.12, segments=8)

	# --- Electric breech actuator, replacing the hand operating lever -------
	add_box(bm2, (breech_w * 0.5 + 0.05, breech_y_center + 0.02, 0.02), (0.09, 0.12, 0.10), bevel=0.008)
	add_cyl_x(bm2, (breech_w * 0.5 + 0.11, breech_y_center + 0.02, 0.02), 0.036, 0.07, segments=14)
	add_cyl_x(bm2, (breech_w * 0.5 + 0.155, breech_y_center + 0.02, 0.02), 0.020, 0.03, segments=10)
	# Linkage arm from the actuator down into the breech block
	add_box(bm2, (breech_w * 0.5 + 0.05, breech_y_center + 0.02, -0.06), (0.022, 0.028, 0.10), bevel=0.004)

	# Hydro-Spring Recoil Cylinder & Collar (forward, unchanged in intent)
	recoil_r = 0.055
	recoil_len = 0.65
	recoil_z = -0.10
	recoil_y_center = recoil_len * 0.5 + breech_y_center + breech_l * 0.3
	add_cyl_y(bm2, (0, recoil_y_center, recoil_z), recoil_r, recoil_len, segments=16)
	add_cyl_y(bm2, (0, recoil_y_center - recoil_len * 0.5, recoil_z), recoil_r * 1.15, 0.04, segments=16)

	collar_y = recoil_y_center + recoil_len * 0.45
	add_box(bm2, (0, collar_y, -0.05), (0.16, 0.06, 0.18), bevel=0.01)
	export_bmesh(bm2, "m3_action_breech", "m3_action_breech.glb")

	# 3. BARREL (m3_barrel.glb)
	bm3 = bmesh.new()
	sleeve_r = 0.075
	sleeve_len = 0.20
	sleeve_y_center = sleeve_len * 0.5
	add_cyl_y(bm3, (0, sleeve_y_center, 0), sleeve_r, sleeve_len, segments=16)

	barrel_len = 1.25
	barrel_start_y = sleeve_len
	barrel_end_y = barrel_start_y + barrel_len
	barrel_mid_y = (barrel_start_y + barrel_end_y) * 0.5
	add_tapered_cyl_y(bm3, (0, barrel_mid_y, 0), 0.065, 0.045, barrel_len, segments=20)

	add_cyl_y(bm3, (0, barrel_end_y + 0.02, 0), 0.052, 0.04, segments=16)
	add_cyl_y(bm3, (0, barrel_end_y + 0.05, 0), 0.048, 0.03, segments=16)
	export_bmesh(bm3, "m3_barrel", "m3_barrel.glb")

if __name__ == "__main__":
	build_37mm_m3_parts()
