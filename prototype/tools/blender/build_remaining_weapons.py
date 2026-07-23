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

def build_all_remaining():
	# ----------------------------------------------------
	# 1. HEAVY LASER (heavy_laser)
	# ----------------------------------------------------
	clear_scene()
	# 1A. Mount (heavy_laser_mount.glb)
	bm1 = bmesh.new()
	add_cyl_z(bm1, (0, 0, 0.03), 0.26, 0.06, segments=20)
	for sx in (-0.16, 0.16):
		add_box(bm1, (sx, 0.0, 0.16), (0.05, 0.24, 0.18), bevel=0.01)
		add_cyl_x(bm1, (sx * 1.12, 0.0, 0.24), 0.045, 0.03, segments=12)
	export_bmesh(bm1, "heavy_laser_mount", "heavy_laser_mount.glb", color=(0.20, 0.22, 0.26))

	# 1B. Housing Body (heavy_laser_housing.glb)
	bm2 = bmesh.new()
	add_box(bm2, (0, 0, 0), (0.34, 0.50, 0.26), bevel=0.02)
	# Side Radiator Cooling Fins
	for sx in (-0.20, 0.20):
		for iz in range(3):
			add_box(bm2, (sx, 0.0, -0.06 + iz * 0.06), (0.04, 0.40, 0.015), bevel=0.002)
	export_bmesh(bm2, "heavy_laser_housing", "heavy_laser_housing.glb", color=(0.24, 0.28, 0.32))

	# 1C. Telescope Lens Barrel (heavy_laser_lens.glb)
	bm3 = bmesh.new()
	add_cyl_y(bm3, (0, 0.25, 0), 0.10, 0.50, segments=20) # Main telescope tube
	add_cyl_y(bm3, (0, 0.52, 0), 0.13, 0.08, segments=20) # Front lens aperture shroud ring
	add_cyl_y(bm3, (0, 0.53, 0), 0.11, 0.02, segments=20) # Optical glass lens face
	export_bmesh(bm3, "heavy_laser_lens", "heavy_laser_lens.glb", color=(0.15, 0.18, 0.22))

	# ----------------------------------------------------
	# 2. PLASMA LOBBER (plasma_lobber)
	# ----------------------------------------------------
	clear_scene()
	# 2A. Mount (plasma_lobber_mount.glb)
	bm4 = bmesh.new()
	add_box(bm4, (0, 0, 0.03), (0.52, 0.52, 0.06), bevel=0.02)
	add_cyl_z(bm4, (0, 0, 0.08), 0.24, 0.04, segments=20)
	for sx in (-0.18, 0.18):
		add_box(bm4, (sx, 0.0, 0.18), (0.06, 0.26, 0.18), bevel=0.012)
	export_bmesh(bm4, "plasma_lobber_mount", "plasma_lobber_mount.glb", color=(0.22, 0.22, 0.24))

	# 2B. Plasma Containment Chamber (plasma_lobber_chamber.glb)
	bm5 = bmesh.new()
	pitch = math.radians(35.0)
	add_cyl_y(bm5, (0, 0, 0), 0.22, 0.36, segments=20, rot_x=pitch) # Spherical/cylindrical chamber
	# Magnetic Containment Coils
	for off_y in (-0.10, 0.10):
		cy = off_y * math.cos(pitch)
		cz = off_y * math.sin(pitch)
		add_cyl_y(bm5, (0, cy, cz), 0.25, 0.05, segments=20, rot_x=pitch)
	export_bmesh(bm5, "plasma_lobber_chamber", "plasma_lobber_chamber.glb", color=(0.30, 0.20, 0.35)) # Metallic violet

	# 2C. Plasma Accelerator Barrel (plasma_lobber_barrel.glb)
	bm6 = bmesh.new()
	add_cyl_y(bm6, (0, 0.28 * math.cos(pitch), 0.28 * math.sin(pitch)), 0.13, 0.45, segments=18, rot_x=pitch)
	add_cone_y(bm6, (0, 0.52 * math.cos(pitch), 0.52 * math.sin(pitch)), 0.13, 0.16, 0.08, segments=18)
	export_bmesh(bm6, "plasma_lobber_barrel", "plasma_lobber_barrel.glb", color=(0.20, 0.18, 0.25))

	# ----------------------------------------------------
	# 3. CIWS (ciws) - Phalanx 20mm Vulcan style
	# ----------------------------------------------------
	clear_scene()
	# 3A. Pedestal Mount (ciws_mount.glb)
	bm7 = bmesh.new()
	add_cyl_z(bm7, (0, 0, 0.04), 0.26, 0.08, segments=24) # Base ring
	add_cyl_z(bm7, (0, 0, 0.14), 0.20, 0.12, segments=24) # Lower ammo drum housing
	for sx in (-0.15, 0.15):
		add_box(bm7, (sx, 0.0, 0.28), (0.05, 0.24, 0.18), bevel=0.01)
		add_cyl_x(bm7, (sx * 1.12, 0.0, 0.34), 0.045, 0.03, segments=12)
	export_bmesh(bm7, "ciws_mount", "ciws_mount.glb", color=(0.85, 0.85, 0.85)) # Phalanx White/Grey

	# 3B. Radar Tracking Dome (ciws_radar.glb)
	bm8 = bmesh.new()
	add_cyl_z(bm8, (0, 0.05, 0.18), 0.16, 0.36, segments=24) # Top radome cylinder
	add_cone_y(bm8, (0, 0.05, 0.38), 0.16, 0.001, 0.12, segments=24) # Top radome cap
	export_bmesh(bm8, "ciws_radar", "ciws_radar.glb", color=(0.90, 0.90, 0.90))

	# 3C. 20mm 6-Barrel Vulcan Rotary Cluster (ciws_barrel.glb)
	bm9 = bmesh.new()
	# Central Rotor Shaft
	add_cyl_y(bm9, (0, 0.30, 0), 0.04, 0.60, segments=16)
	# 6 Vulcan Barrels in circular array
	for i in range(6):
		ang = i * (math.pi / 3.0)
		bx = math.cos(ang) * 0.07
		bz = math.sin(ang) * 0.07
		add_cyl_y(bm9, (bx, 0.35, bz), 0.018, 0.70, segments=12)
	# Front Clamp Ring
	add_cyl_y(bm9, (0, 0.65, 0), 0.095, 0.04, segments=16)
	export_bmesh(bm9, "ciws_barrel", "ciws_barrel.glb", color=(0.20, 0.22, 0.25))

	# ----------------------------------------------------
	# 4. POINT DEFENSE LASER (pd_laser)
	# ----------------------------------------------------
	clear_scene()
	# 4A. Agile Gimbal Mount (pd_laser_mount.glb)
	bm10 = bmesh.new()
	add_cyl_z(bm10, (0, 0, 0.03), 0.20, 0.06, segments=20)
	add_cyl_z(bm10, (0, 0, 0.12), 0.14, 0.12, segments=16)
	export_bmesh(bm10, "pd_laser_mount", "pd_laser_mount.glb", color=(0.22, 0.25, 0.30))

	# 4B. Optics Housing & Cooling Jacket (pd_laser_housing.glb)
	bm11 = bmesh.new()
	add_box(bm11, (0, 0, 0), (0.24, 0.35, 0.20), bevel=0.015)
	# Cooling Jacket Ribbing
	for iz in range(4):
		add_box(bm11, (0, 0.0, -0.06 + iz * 0.04), (0.26, 0.32, 0.015), bevel=0.002)
	export_bmesh(bm11, "pd_laser_housing", "pd_laser_housing.glb", color=(0.25, 0.30, 0.35))

	# 4C. Fast-Tracking Emitter Lens (pd_laser_lens.glb)
	bm12 = bmesh.new()
	add_cyl_y(bm12, (0, 0.22, 0), 0.08, 0.28, segments=16)
	add_cyl_y(bm12, (0, 0.37, 0), 0.095, 0.04, segments=16) # Lens bezel
	export_bmesh(bm12, "pd_laser_lens", "pd_laser_lens.glb", color=(0.15, 0.50, 0.75))

	# ----------------------------------------------------
	# 5. FLAK CANNON (flak_cannon) - Quad Flak 88mm / Bofors Style
	# ----------------------------------------------------
	clear_scene()
	# 5A. Turntable Mount Plate & Shield (flak_cannon_mount.glb)
	bm13 = bmesh.new()
	add_cyl_z(bm13, (0, 0, 0.03), 0.32, 0.06, segments=24) # Heavy Flak base turntable
	for sx in (-0.20, 0.20):
		add_box(bm13, (sx, 0.0, 0.18), (0.06, 0.30, 0.24), bevel=0.015)
		add_cyl_x(bm13, (sx * 1.12, 0.0, 0.26), 0.05, 0.04, segments=14)
	# Curved Gunner Armor Shield Plate
	add_box(bm13, (0, 0.16, 0.24), (0.64, 0.03, 0.30), bevel=0.01)
	export_bmesh(bm13, "flak_cannon_mount", "flak_cannon_mount.glb", color=(0.24, 0.26, 0.22))

	# 5B. Armored Breech Block (flak_cannon_breech.glb)
	bm14 = bmesh.new()
	add_box(bm14, (0, 0, 0), (0.32, 0.42, 0.24), bevel=0.015)
	add_box(bm14, (0, -0.22, 0.0), (0.24, 0.08, 0.20), bevel=0.005) # Shell tray/loading trough
	export_bmesh(bm14, "flak_cannon_breech", "flak_cannon_breech.glb", color=(0.20, 0.22, 0.18))

	# 5C. Flak Barrel & Conical Flash Hider (flak_cannon_barrel.glb)
	bm15 = bmesh.new()
	add_cyl_y(bm15, (0, 0.45, 0), 0.06, 0.90, segments=18) # Main barrel tube
	add_cyl_y(bm15, (0, 0.15, 0), 0.08, 0.25, segments=18) # Heavy recoil sleeve collar
	add_cone_y(bm15, (0, 0.94, 0), 0.06, 0.11, 0.10, segments=18) # Conical Flak flash hider
	export_bmesh(bm15, "flak_cannon_barrel", "flak_cannon_barrel.glb", color=(0.15, 0.16, 0.14))

if __name__ == "__main__":
	build_all_remaining()
