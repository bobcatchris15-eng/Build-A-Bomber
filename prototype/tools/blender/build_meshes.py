"""
Build-A-Bomber mesh generator (Milestone: Visual Refinement pass 2)
Run headlessly with UPBGE's bundled Blender:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python tools\\blender\\build_meshes.py

Produces two families of assets:
  1. assets/models/hulls/*.glb  - one full chassis/foundation mesh per hull
     catalog entry, authored to match that hull's catalog "size" Vector3
     exactly, with fused-on greeble detail (vents, hatches, rivets,
     antennae, gussets...) so hulls read as distinct silhouettes rather
     than plain boxes/wedges.
  2. assets/models/parts/*.glb  - small reusable "kit" pieces (barrels,
     breeches, drums, domes, missile bodies, wheels, legs, rings...)
     referenced by multiple weapon/locomotion modules in visual_builder.gd.

COORDINATE CONVENTION (verified empirically against this exact export
pipeline - see scratch/probe_axes_*.py/gd):
  Blender is authored Z-up. The bundled glTF exporter's Y-up conversion
  maps  Godot_X = Blender_X,  Godot_Y = Blender_Z,  Godot_Z = Blender_Y.
  Every helper below takes GODOT-space (x, y_up, z_depth) coordinates and
  internally swaps to raw Blender coordinates via GV()/GS(), so all
  authoring code in this file can be written purely in terms of the same
  X/Y/Z semantics used everywhere else in the project (module_catalog.gd
  "size" Vector3, etc.) - no manual axis juggling needed at call sites.

  Runtime contract: authored assets are pre-oriented in final local space
  (no rotation compensation needed). This differs from the old pass-1
  script, which authored barrels along raw Blender Z relying on a
  runtime PI/2 rotation - that convention is retired. mesh_asset_loader.gd
  callers (module_placer.gd, visual_builder.gd) use authored meshes
  directly and only apply the OLD rotation to the procedural fallback
  primitives, which still default to Godot's Y-up CylinderMesh.
"""

import bpy
import bmesh
import math
import os
import mathutils

PROJECT_ROOT = r"E:\Build-A-Bomber\prototype"
PARTS_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "parts")
HULLS_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "hulls")

os.makedirs(PARTS_DIR, exist_ok=True)
os.makedirs(HULLS_DIR, exist_ok=True)


# ---------------------------------------------------------------------------
# Core helpers
# ---------------------------------------------------------------------------

def clear_scene():
	bpy.ops.object.select_all(action='SELECT')
	bpy.ops.object.delete(use_global=False)
	for block in list(bpy.data.meshes):
		if block.users == 0:
			bpy.data.meshes.remove(block)
	for block in list(bpy.data.materials):
		if block.users == 0:
			bpy.data.materials.remove(block)


def GV(x, y, z):
	"""Godot-space (x, y_up, z_depth) -> raw Blender-space tuple."""
	return (x, z, y)


def GS(sx, sy, sz):
	"""Godot-space (width, height, depth) size -> raw Blender-space size."""
	return (sx, sz, sy)


def rot_matrix(godot_axis, angle_rad):
	"""Rotation matrix for a rotation of angle_rad around the given
	GODOT-space axis ('x','y','z'), expressed for raw Blender-space geometry."""
	if godot_axis == 'y':
		return mathutils.Matrix.Rotation(angle_rad, 3, 'Z')
	elif godot_axis == 'x':
		return mathutils.Matrix.Rotation(angle_rad, 3, 'X')
	else:
		return mathutils.Matrix.Rotation(angle_rad, 3, 'Y')


def new_material(name, color, metallic=0.7, roughness=0.4):
	mat = bpy.data.materials.get(name)
	if mat is None:
		mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes.get("Principled BSDF")
	if bsdf:
		bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
		bsdf.inputs["Metallic"].default_value = metallic
		bsdf.inputs["Roughness"].default_value = roughness
	return mat


def make_object_from_bmesh(bm, name):
	mesh = bpy.data.meshes.new(name + "_mesh")
	bm.to_mesh(mesh)
	bm.free()
	mesh.update()
	obj = bpy.data.objects.new(name, mesh)
	bpy.context.collection.objects.link(obj)
	return obj


def finalize(obj, name, color=(0.55, 0.56, 0.58), metallic=0.75, roughness=0.35):
	obj.name = name
	bpy.ops.object.select_all(action='DESELECT')
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.shade_smooth()
	try:
		obj.data.use_auto_smooth = True
		obj.data.auto_smooth_angle = math.radians(35)
	except Exception:
		pass
	mat = new_material(name + "_mat", color, metallic, roughness)
	if obj.data.materials:
		obj.data.materials[0] = mat
	else:
		obj.data.materials.append(mat)


def export_glb(obj, filepath):
	bpy.ops.object.select_all(action='DESELECT')
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.export_scene.gltf(
		filepath=filepath,
		use_selection=True,
		export_format='GLB',
		export_yup=True,
		export_apply=True
	)
	print("Exported: " + filepath)


def export_and_cleanup(obj, out_dir, filename):
	path = os.path.join(out_dir, filename + ".glb")
	export_glb(obj, path)
	mesh_data = obj.data
	bpy.data.objects.remove(obj, do_unlink=True)
	if mesh_data and mesh_data.users == 0:
		bpy.data.meshes.remove(mesh_data)


# ---------------------------------------------------------------------------
# Greeble primitives - all operate on a caller-supplied bm using GODOT-space
# center/size, so calling code never has to think about the Blender swap.
# ---------------------------------------------------------------------------

def add_box(bm, center, size, rot_axis=None, rot_angle=0.0, bevel=0.0):
	ret = bmesh.ops.create_cube(bm, size=1.0)
	verts = ret['verts']
	bmesh.ops.scale(bm, verts=verts, vec=GS(*size))
	if rot_axis and rot_angle:
		bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=rot_matrix(rot_axis, rot_angle))
	bmesh.ops.translate(bm, verts=verts, vec=GV(*center))
	if bevel > 0.0:
		edges = [e for e in bm.edges if all(v in verts for v in e.verts)]
		if edges:
			bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=1, affect='EDGES')
	return verts


def add_cyl_y(bm, center, radius, height, segments=12, radius2=None):
	"""Vertical (Godot-Y-axis) cylinder/cone centered at `center`."""
	r2 = radius2 if radius2 is not None else radius
	ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
		radius1=radius, radius2=r2, depth=height)
	bmesh.ops.translate(bm, verts=ret['verts'], vec=GV(*center))
	return ret['verts']


def add_cyl_axis(bm, center, radius, length, godot_axis, segments=10, radius2=None):
	"""Cylinder lying along a horizontal Godot axis ('x' or 'z'), centered at `center`."""
	r2 = radius2 if radius2 is not None else radius
	ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
		radius1=radius, radius2=r2, depth=length)
	bmesh.ops.rotate(bm, verts=ret['verts'], cent=(0, 0, 0), matrix=rot_matrix(godot_axis, math.pi / 2.0))
	bmesh.ops.translate(bm, verts=ret['verts'], vec=GV(*center))
	return ret['verts']


def add_ring(bm, center, major_radius, minor_radius, major_segments=20, minor_segments=8):
	"""A horizontal torus/ring (Godot-Y-axis normal), swept around `center`."""
	before = set(bm.verts)
	ret = bmesh.ops.create_circle(bm, cap_ends=True, radius=minor_radius, segments=minor_segments)
	bmesh.ops.rotate(bm, verts=ret['verts'], cent=(0, 0, 0), matrix=mathutils.Matrix.Rotation(math.pi / 2.0, 3, 'Y'))
	bmesh.ops.translate(bm, verts=ret['verts'], vec=(major_radius, 0, 0))
	geom = list(ret['verts'])
	geom += [e for v in ret['verts'] for e in v.link_edges]
	geom += [f for v in ret['verts'] for f in v.link_faces]
	geom = list(set(geom))
	bmesh.ops.spin(bm, geom=geom, cent=(0, 0, 0), axis=(0, 0, 1),
		angle=math.radians(360), steps=major_segments, use_duplicate=False)
	new_verts = [v for v in bm.verts if v not in before]
	if center != (0, 0, 0):
		bmesh.ops.translate(bm, verts=new_verts, vec=GV(*center))
	return new_verts


# ---------------------------------------------------------------------------
# Greeble "kits" - reusable clusters of detail merged straight into a bm.
# ---------------------------------------------------------------------------

def greeble_rivet_row(bm, start, end, count, radius=0.025, height=0.02, axis='y'):
	for i in range(count):
		t = (i / (count - 1)) if count > 1 else 0.5
		c = tuple(start[k] + (end[k] - start[k]) * t for k in range(3))
		if axis == 'y':
			add_cyl_y(bm, c, radius, height, segments=7)
		else:
			add_cyl_axis(bm, c, radius, height, axis, segments=7)


def greeble_vent(bm, center, size, slats=4):
	add_box(bm, center, size, bevel=0.01)
	slat_w = size[0] / (slats * 2.2)
	for i in range(slats):
		t = (i + 0.5) / slats - 0.5
		c = (center[0] + t * size[0] * 0.8, center[1], center[2])
		add_box(bm, c, (slat_w, size[1] * 1.2, size[2] * 0.85))


def greeble_headlight_pair(bm, hx, y_level, front_z, radius=0.09):
	for side in (-1, 1):
		add_cyl_axis(bm, (side * hx * 0.55, y_level, front_z), radius, 0.09, 'z', segments=10)


def greeble_exhaust_stack(bm, center, radius=0.08, height=0.35):
	add_cyl_y(bm, center, radius, height, segments=10)
	add_cyl_y(bm, (center[0], center[1] + height * 0.5 + 0.02, center[2]), radius * 1.2, 0.04, segments=10)


def greeble_antenna(bm, base, height=0.55, radius=0.018):
	add_cyl_y(bm, (base[0], base[1] + height / 2.0, base[2]), radius, height, segments=6)
	add_cyl_y(bm, (base[0], base[1], base[2]), radius * 2.2, 0.03, segments=8)


def greeble_hatch(bm, center, size, rim=0.03):
	add_box(bm, center, size, bevel=0.008)
	add_box(bm, (center[0], center[1] + size[1] * 0.5 + 0.008, center[2]),
		(size[0] - rim, 0.015, size[2] - rim))


def greeble_corner_gusset(bm, x_sign, hx, hy, z_pos, size=(0.32, 0.28, 0.45)):
	add_box(bm, (x_sign * (hx - size[0] * 0.35), -hy * 0.35, z_pos), size, bevel=0.02)


def greeble_toolbox(bm, center, size=(0.5, 0.28, 0.32)):
	add_box(bm, center, size, bevel=0.015)
	add_box(bm, (center[0], center[1] + size[1] * 0.5, center[2]), (size[0] * 0.9, 0.03, size[2] * 0.9))


def greeble_spotlight(bm, center, radius=0.11):
	add_cyl_axis(bm, center, radius, 0.14, 'z', segments=10)
	add_box(bm, (center[0], center[1] - radius * 0.9, center[2] - 0.05), (0.05, 0.16, 0.05))


def greeble_bolt_ring(bm, center, radius, count=8, bolt_radius=0.025, axis='y'):
	for i in range(count):
		angle = i * (2.0 * math.pi / count)
		if axis == 'y':
			pos = (center[0] + math.cos(angle) * radius, center[1], center[2] + math.sin(angle) * radius)
			add_cyl_y(bm, pos, bolt_radius, 0.02, segments=6)
		else:
			pos = (center[0] + math.cos(angle) * radius, center[1] + math.sin(angle) * radius, center[2])
			add_cyl_axis(bm, pos, bolt_radius, 0.02, 'z', segments=6)


def greeble_cooling_fins(bm, center, count, span, radius, thickness=0.012, axis='z'):
	for i in range(count):
		t = (i / (count - 1)) if count > 1 else 0.5
		off = (t - 0.5) * span
		if axis == 'z':
			pos = (center[0], center[1], center[2] + off)
			add_box(bm, pos, (radius * 2.1, radius * 2.1, thickness))
		else:
			pos = (center[0], center[1] + off, center[2])
			add_box(bm, pos, (radius * 2.1, thickness, radius * 2.1))


# ---------------------------------------------------------------------------
# Part builders - small reusable kit pieces referenced by visual_builder.gd.
# Cylinders/cones are authored with their length along Godot Z (forward),
# matching how they're mounted on weapons (barrels point along local -Z).
# ---------------------------------------------------------------------------

def build_barrel(name, length=1.0, radius=0.1, muzzle_radius=None, segments=16,
		fins=0, color=(0.12, 0.12, 0.13)):
	"""Barrel along Godot +Y, base at origin (y=0..length) - matches the
	existing runtime convention (Godot's own CylinderMesh default axis),
	so weapon assembly code keeps applying its existing PI/2 X rotation to
	point barrels forward, and existing caliber(X)/length(Y) tweak scaling
	on this child index keeps working unchanged."""
	bm = bmesh.new()
	r2 = muzzle_radius if muzzle_radius is not None else radius
	add_cyl_y(bm, (0, length / 2.0, 0), radius, length, segments=segments, radius2=r2)
	# Muzzle brake ring fused on the tip
	add_cyl_y(bm, (0, length * 0.94, 0), r2 * 1.35, length * 0.1, segments=segments)
	if fins > 0:
		greeble_cooling_fins(bm, (0, length * 0.35, 0), fins, length * 0.45, radius * 1.15, axis='y')
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.85, roughness=0.3)
	return obj


def build_cylinder_part(name, radius=0.15, height=0.15, segments=20, bevel=True,
		bolts=True, color=(0.35, 0.35, 0.38)):
	"""Squat drum along Godot Y (up), base at origin - ammo drums, canisters,
	fuel tanks, turret base plates, muzzle brakes."""
	bm = bmesh.new()
	add_cyl_y(bm, (0, height / 2.0, 0), radius, height, segments=segments)
	if bolts:
		greeble_bolt_ring(bm, (0, height * 0.9, 0), radius * 0.82, count=max(6, segments // 2), axis='y')
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color)
	return obj


def build_dome(name, radius=0.15, squash=0.6, segments=16, rings=10,
		color=(0.85, 0.85, 0.85)):
	bm = bmesh.new()
	ret = bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
	bmesh.ops.scale(bm, verts=ret['verts'], vec=GS(1.0, squash, 1.0))
	bmesh.ops.translate(bm, verts=ret['verts'], vec=GV(0, radius * squash * 0.15, 0))
	# Base collar ring
	add_cyl_y(bm, (0, 0.02, 0), radius * 1.05, 0.04, segments=segments)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.1, roughness=0.15)
	return obj


def build_missile_body(name, length=1.0, radius=0.08, nose_frac=0.25, segments=14,
		fins=4, color=(0.9, 0.9, 0.9)):
	"""Missile body + nose cone along Godot +Y, base (tail) at origin -
	matches the existing runtime PI/2 X rotation convention."""
	bm = bmesh.new()
	body_len = length * (1.0 - nose_frac)
	nose_len = length * nose_frac
	add_cyl_y(bm, (0, body_len / 2.0, 0), radius, body_len, segments=segments)
	add_cyl_y(bm, (0, body_len + nose_len / 2.0, 0), radius, nose_len, segments=segments, radius2=0.0)
	# Rear stabilizer fins, fanned around the tail end
	fin_len = radius * 2.4
	for i in range(fins):
		angle = i * (2.0 * math.pi / fins)
		add_box(bm, (0, radius * 0.5, 0),
			(0.012, radius * 1.6, fin_len), rot_axis='y', rot_angle=angle)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.3, roughness=0.4)
	return obj


def build_pintle_mount(name, width=0.34, height=0.22, depth=0.22, wall=0.045,
		color=(0.2, 0.2, 0.22)):
	"""Small U-shaped yoke bracket: base plate + two side arms."""
	bm = bmesh.new()
	add_box(bm, (0, wall / 2.0, 0), (width, wall, depth), bevel=0.006)
	for side in (-1, 1):
		add_box(bm, (side * (width / 2.0 - wall / 2.0), height / 2.0, 0), (wall, height, depth), bevel=0.006)
	greeble_bolt_ring(bm, (0, wall * 0.5, 0), width * 0.32, count=4, axis='y')
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.6, roughness=0.5)
	return obj


def build_box_part(name, size=(0.5, 0.3, 0.4), bevel_amt=0.02, bolts=True,
		color=(0.3, 0.3, 0.33)):
	"""Beveled box - turret bases, launcher frames, weapon housings."""
	bm = bmesh.new()
	add_box(bm, (0, size[1] / 2.0, 0), size, bevel=bevel_amt)
	if bolts:
		for x_sign in (-1, 1):
			for z_sign in (-1, 1):
				pos = (x_sign * size[0] * 0.4, size[1] * 0.92, z_sign * size[2] * 0.4)
				add_cyl_y(bm, pos, 0.02, 0.015, segments=6)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color)
	return obj


def build_howitzer_breech(name, width=0.9, height=0.5, depth=0.55, color=(0.28, 0.28, 0.3)):
	"""Chunky breech block with twin recoil-buffer cylinders on top."""
	bm = bmesh.new()
	add_box(bm, (0, height / 2.0, 0), (width, height, depth), bevel=0.03)
	for side in (-1, 1):
		add_cyl_axis(bm, (side * width * 0.28, height * 0.85, -depth * 0.05), 0.09, depth * 1.3, 'z', segments=12)
	greeble_bolt_ring(bm, (0, height * 0.95, depth * 0.3), width * 0.3, count=6, axis='y')
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.6, roughness=0.5)
	return obj


def build_rotary_jacket(name, radius=0.22, height=0.5, barrels=6, color=(0.2, 0.2, 0.21)):
	"""Cooling jacket ring around a rotary-cannon barrel cluster, along Godot +Y."""
	bm = bmesh.new()
	add_cyl_y(bm, (0, height * 0.5, 0), radius, height * 0.3, segments=20)
	add_cyl_y(bm, (0, height * 0.95, 0), radius * 1.08, height * 0.12, segments=20)
	greeble_cooling_fins(bm, (0, height * 0.55, 0), 5, height * 0.5, radius, axis='y')
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.75, roughness=0.35)
	return obj


def build_rail_array(name, length=1.6, gap=0.16, rail_h=0.12, color=(0.15, 0.15, 0.15)):
	"""Twin magnetic rail assembly with connecting spars, for the railgun."""
	bm = bmesh.new()
	for side in (-1, 1):
		add_box(bm, (side * gap, rail_h / 2.0, length / 2.0), (0.06, rail_h, length), bevel=0.01)
	for i in range(4):
		t = (i + 0.5) / 4.0
		add_box(bm, (0, rail_h * 0.5, length * t), (gap * 2.0 + 0.08, 0.03, 0.03))
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.7, roughness=0.25)
	return obj


def build_flak_breech(name, width=0.5, height=0.32, depth=0.4, color=(0.18, 0.18, 0.18)):
	bm = bmesh.new()
	add_box(bm, (0, height / 2.0, 0), (width, height, depth), bevel=0.02)
	greeble_bolt_ring(bm, (0, height * 0.9, 0), width * 0.32, count=6, axis='y')
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.65, roughness=0.4)
	return obj


def build_wheel(name, radius=0.45, width=0.35, spokes=6, color=(0.08, 0.08, 0.08)):
	"""Wheel + hub, built Y-vertical (radius in X/Z, thickness along Y) -
	matches the existing runtime convention where locomotion code applies
	rotation.z = PI/2 at runtime to stand it up with the axle along X."""
	bm = bmesh.new()
	add_cyl_y(bm, (0, width / 2.0, 0), radius, width, segments=22)
	add_cyl_y(bm, (0, width * 0.53, 0), radius * 0.42, width * 1.06, segments=16)
	for i in range(spokes):
		angle = i * (2.0 * math.pi / spokes)
		pos = (math.cos(angle) * radius * 0.55, width / 2.0, math.sin(angle) * radius * 0.55)
		add_box(bm, pos, (radius * 0.5, width * 0.9, 0.05), rot_axis='y', rot_angle=angle)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.2, roughness=0.7)
	return obj


def build_leg_segment(name, length=0.5, radius_top=0.12, radius_bottom=0.08, color=(0.3, 0.3, 0.32)):
	"""Armored leg segment along Godot Y, base(wide) at origin."""
	bm = bmesh.new()
	add_cyl_y(bm, (0, length / 2.0, 0), radius_top, length, segments=12, radius2=radius_bottom)
	greeble_bolt_ring(bm, (0, length * 0.05, 0), radius_top * 0.85, count=6, axis='y')
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.55, roughness=0.4)
	return obj


def build_hover_ring(name, major_radius=0.5, minor_radius=0.1, color=(0.2, 0.6, 0.9)):
	bm = bmesh.new()
	add_ring(bm, (0, 0, 0), major_radius, minor_radius, major_segments=24, minor_segments=8)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.4, roughness=0.3)
	return obj


def build_tread_plate(name, width=1.0, length=1.0, links=6, color=(0.16, 0.16, 0.17)):
	"""Tracked-tread belt block with raised link ridges along its length."""
	bm = bmesh.new()
	add_box(bm, (0, 0.15, 0), (width, 0.3, length), bevel=0.02)
	for i in range(links):
		t = (i + 0.5) / links - 0.5
		add_box(bm, (0, 0.31, t * length), (width * 1.02, 0.04, length / links * 0.55))
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.4, roughness=0.6)
	return obj


def build_accessory(name, kind, color, **kwargs):
	"""Standalone small greeble accessories - also usable directly as weapon
	sub-parts (headlight cluster, exhaust, antenna, hatch, vent, toolbox)."""
	bm = bmesh.new()
	if kind == "exhaust":
		greeble_exhaust_stack(bm, (0, kwargs.get("height", 0.35) / 2.0, 0),
			radius=kwargs.get("radius", 0.08), height=kwargs.get("height", 0.35))
	elif kind == "antenna":
		greeble_antenna(bm, (0, 0, 0), height=kwargs.get("height", 0.55), radius=kwargs.get("radius", 0.018))
	elif kind == "vent":
		greeble_vent(bm, (0, kwargs.get("size", (0.4, 0.1, 0.25))[1] / 2.0, 0), kwargs.get("size", (0.4, 0.1, 0.25)))
	elif kind == "hatch":
		greeble_hatch(bm, (0, kwargs.get("size", (0.6, 0.06, 0.6))[1] / 2.0, 0), kwargs.get("size", (0.6, 0.06, 0.6)))
	elif kind == "toolbox":
		greeble_toolbox(bm, (0, kwargs.get("size", (0.5, 0.28, 0.32))[1] / 2.0, 0), kwargs.get("size", (0.5, 0.28, 0.32)))
	elif kind == "spotlight":
		greeble_spotlight(bm, (0, 0, 0), radius=kwargs.get("radius", 0.11))
	elif kind == "sensor_mast":
		add_cyl_y(bm, (0, kwargs.get("height", 1.0) / 2.0, 0), 0.05, kwargs.get("height", 1.0), segments=10, radius2=0.03)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=kwargs.get("metallic", 0.5), roughness=kwargs.get("roughness", 0.5))
	return obj


# ---------------------------------------------------------------------------
# Hull chassis builder - convex hull from a hand-placed "keel" point cloud,
# with fused-on greebles for detail. Robust (convex_hull is always
# manifold) and lets a handful of numeric parameters produce meaningfully
# different silhouettes.
# ---------------------------------------------------------------------------

def build_wedge_hull(name, size_x, size_y, size_z, nose_frac=0.0, spine_w=0.5, spine_h=1.1,
		rear_flare=0.9, front_flare=1.0, color=(0.55, 0.56, 0.58), greebles=None):
	hx, hy, hz = size_x / 2.0, size_y / 2.0, size_z / 2.0
	bm = bmesh.new()
	pts = []
	pts += [(-hx, -hy, -hz), (hx, -hy, -hz), (-hx, -hy, hz), (hx, -hy, hz)]
	pts += [(-hx * rear_flare, hy, hz), (hx * rear_flare, hy, hz)]
	fx = hx * front_flare * (1.0 - nose_frac)
	pts += [(-fx, hy, -hz), (fx, hy, -hz)]
	if nose_frac > 0.01:
		pts.append((0.0, hy * 0.6, -hz))
	pts += [(-hx * spine_w, hy * spine_h, hz * 0.1), (hx * spine_w, hy * spine_h, hz * 0.1)]
	pts += [(-hx * spine_w, hy * spine_h, -hz * 0.3), (hx * spine_w, hy * spine_h, -hz * 0.3)]

	verts = [bm.verts.new(GV(*p)) for p in pts]
	bmesh.ops.convex_hull(bm, input=verts)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

	if greebles:
		greebles(bm, hx, hy, hz)

	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.6, roughness=0.45)
	return obj


def build_bunker_hull(name, size_x, size_y, size_z, sides=8, taper=0.72,
		color=(0.45, 0.45, 0.4), greebles=None):
	"""Low static defensive bunker: tapered polygonal frustum + domed cap."""
	hx, hy, hz = size_x / 2.0, size_y / 2.0, size_z / 2.0
	bm = bmesh.new()
	base_r = max(hx, hz)
	top_r = base_r * taper
	base_pts = []
	top_pts = []
	for i in range(sides):
		angle = i * (2.0 * math.pi / sides)
		base_pts.append((math.cos(angle) * base_r * (hx / base_r), -hy, math.sin(angle) * base_r * (hz / base_r)))
		top_pts.append((math.cos(angle) * top_r * (hx / base_r), hy * 0.7, math.sin(angle) * top_r * (hz / base_r)))
	all_pts = base_pts + top_pts
	verts = [bm.verts.new(GV(*p)) for p in all_pts]
	bmesh.ops.convex_hull(bm, input=verts)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

	# Domed roof cap
	dome_verts = bmesh.ops.create_uvsphere(bm, u_segments=sides, v_segments=6, radius=top_r * 0.9)['verts']
	bmesh.ops.scale(bm, verts=dome_verts, vec=GS(1.0, 0.45, 1.0))
	bmesh.ops.translate(bm, verts=dome_verts, vec=GV(0, hy * 0.7, 0))

	if greebles:
		greebles(bm, hx, hy, hz)

	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.5, roughness=0.6)
	return obj


def build_tower_hull(name, size_x, size_y, size_z, tiers=3, color=(0.5, 0.48, 0.44), greebles=None):
	"""Tall stepped defensive tower: tiers stacked wide-to-narrow."""
	hx, hy, hz = size_x / 2.0, size_y / 2.0, size_z / 2.0
	bm = bmesh.new()
	tier_h = (size_y) / tiers
	for t in range(tiers):
		shrink = 1.0 - (t * 0.22)
		y0 = -hy + t * tier_h
		y1 = y0 + tier_h * (1.05 if t < tiers - 1 else 1.0)
		tx, tz = hx * shrink, hz * shrink
		pts = [
			(-tx, y0, -tz), (tx, y0, -tz), (-tx, y0, tz), (tx, y0, tz),
			(-tx, y1, -tz), (tx, y1, -tz), (-tx, y1, tz), (tx, y1, tz),
		]
		verts = [bm.verts.new(GV(*p)) for p in pts]
		bmesh.ops.convex_hull(bm, input=verts)

	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

	# Rooftop platform railing posts
	top_shrink = 1.0 - ((tiers - 1) * 0.22)
	rx, rz = hx * top_shrink * 0.9, hz * top_shrink * 0.9
	for i in range(4):
		angle = i * (math.pi / 2.0) + math.pi / 4.0
		pos = (math.cos(angle) * rx, hy * 0.85, math.sin(angle) * rz)
		add_cyl_y(bm, pos, 0.03, 0.35, segments=6)
	greeble_antenna(bm, (0, hy, 0), height=0.7, radius=0.025)
	for side in (-1, 1):
		greeble_spotlight(bm, (side * rx * 0.7, hy * 0.75, -rz * 0.7), radius=0.09)

	if greebles:
		greebles(bm, hx, hy, hz)

	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.55, roughness=0.5)
	return obj


# ---------------------------------------------------------------------------
# Generate: reusable parts
# ---------------------------------------------------------------------------

def generate_parts():
	print("--- Building parts library ---")

	export_and_cleanup(build_barrel("barrel_thin", length=1.0, radius=0.06, muzzle_radius=0.05), PARTS_DIR, "barrel_thin")
	export_and_cleanup(build_barrel("barrel_standard", length=1.0, radius=0.1, muzzle_radius=0.09), PARTS_DIR, "barrel_standard")
	export_and_cleanup(build_barrel("barrel_heavy", length=1.0, radius=0.16, muzzle_radius=0.22, fins=3), PARTS_DIR, "barrel_heavy")
	export_and_cleanup(build_barrel("barrel_taper_wide", length=1.0, radius=0.08, muzzle_radius=0.1), PARTS_DIR, "barrel_taper_wide")

	export_and_cleanup(build_cylinder_part("turret_base_round", radius=0.4, height=0.35, color=(0.32, 0.32, 0.35)), PARTS_DIR, "turret_base_round")
	export_and_cleanup(build_box_part("turret_base_box", size=(1.0, 0.5, 0.7), color=(0.32, 0.32, 0.35)), PARTS_DIR, "turret_base_box")

	export_and_cleanup(build_cylinder_part("ammo_drum", radius=0.5, height=0.4, color=(0.22, 0.24, 0.2)), PARTS_DIR, "ammo_drum")
	export_and_cleanup(build_cylinder_part("canister_small", radius=0.4, height=1.0, color=(0.5, 0.15, 0.12)), PARTS_DIR, "canister_small")
	export_and_cleanup(build_cylinder_part("fuel_tank", radius=0.5, height=1.0, color=(0.4, 0.1, 0.1)), PARTS_DIR, "fuel_tank")

	export_and_cleanup(build_dome("sensor_dome", radius=0.5, squash=0.65, color=(0.9, 0.92, 0.95)), PARTS_DIR, "sensor_dome")
	export_and_cleanup(build_dome("focal_lens", radius=0.5, squash=0.8, color=(1.0, 0.3, 0.3)), PARTS_DIR, "focal_lens")

	export_and_cleanup(build_missile_body("missile_body", length=1.0, radius=0.1, color=(0.92, 0.92, 0.9)), PARTS_DIR, "missile_body")
	export_and_cleanup(build_pintle_mount("pintle_mount", color=(0.18, 0.18, 0.2)), PARTS_DIR, "pintle_mount")
	export_and_cleanup(build_cylinder_part("muzzle_brake", radius=0.5, height=0.5, segments=10, color=(0.15, 0.15, 0.16)), PARTS_DIR, "muzzle_brake")

	export_and_cleanup(build_howitzer_breech("howitzer_breech", color=(0.28, 0.28, 0.3)), PARTS_DIR, "howitzer_breech")
	export_and_cleanup(build_rotary_jacket("rotary_jacket", color=(0.2, 0.2, 0.21)), PARTS_DIR, "rotary_jacket")
	export_and_cleanup(build_rail_array("rail_array", color=(0.15, 0.15, 0.15)), PARTS_DIR, "rail_array")
	export_and_cleanup(build_flak_breech("flak_breech", color=(0.18, 0.18, 0.18)), PARTS_DIR, "flak_breech")

	export_and_cleanup(build_wheel("wheel_hub", color=(0.08, 0.08, 0.08)), PARTS_DIR, "wheel_hub")
	export_and_cleanup(build_leg_segment("leg_thigh", length=0.55, radius_top=0.13, radius_bottom=0.09, color=(0.3, 0.3, 0.32)), PARTS_DIR, "leg_thigh")
	export_and_cleanup(build_leg_segment("leg_shin", length=0.5, radius_top=0.09, radius_bottom=0.06, color=(0.16, 0.16, 0.17)), PARTS_DIR, "leg_shin")
	export_and_cleanup(build_hover_ring("hover_ring", major_radius=0.5, minor_radius=0.1, color=(0.2, 0.6, 0.9)), PARTS_DIR, "hover_ring")
	export_and_cleanup(build_hover_ring("antigrav_ring", major_radius=0.5, minor_radius=0.07, color=(0.3, 0.5, 1.0)), PARTS_DIR, "antigrav_ring")
	export_and_cleanup(build_tread_plate("tread_plate", color=(0.16, 0.16, 0.17)), PARTS_DIR, "tread_plate")

	export_and_cleanup(build_accessory("headlight_cluster", "spotlight", (0.9, 0.9, 0.75), radius=0.07, metallic=0.3, roughness=0.2), PARTS_DIR, "headlight_cluster")
	export_and_cleanup(build_accessory("exhaust_stack", "exhaust", (0.15, 0.15, 0.15), height=0.35, metallic=0.7, roughness=0.5), PARTS_DIR, "exhaust_stack")
	export_and_cleanup(build_accessory("antenna_whip", "antenna", (0.12, 0.12, 0.12), height=0.6, metallic=0.6, roughness=0.4), PARTS_DIR, "antenna_whip")
	export_and_cleanup(build_accessory("vent_grille", "vent", (0.14, 0.14, 0.15), size=(0.4, 0.08, 0.25), metallic=0.55, roughness=0.5), PARTS_DIR, "vent_grille")
	export_and_cleanup(build_accessory("roof_hatch", "hatch", (0.38, 0.38, 0.4), size=(0.6, 0.06, 0.6), metallic=0.6, roughness=0.45), PARTS_DIR, "roof_hatch")
	export_and_cleanup(build_accessory("tool_box", "toolbox", (0.28, 0.32, 0.24), size=(0.5, 0.28, 0.32), metallic=0.3, roughness=0.6), PARTS_DIR, "tool_box")
	export_and_cleanup(build_accessory("sensor_mast", "sensor_mast", (0.15, 0.15, 0.15), height=1.0, metallic=0.6, roughness=0.4), PARTS_DIR, "sensor_mast")

	print("--- Parts library done ---")


# ---------------------------------------------------------------------------
# Generate: hull chassis (size = catalog "size" Vector3, matched exactly)
# ---------------------------------------------------------------------------

def _light_hull_greebles(bm, hx, hy, hz):
	greeble_headlight_pair(bm, hx, -hy * 0.2, -hz * 0.96, radius=0.08)
	greeble_antenna(bm, (hx * 0.5, hy * 1.0, hz * 0.3), height=0.22)
	greeble_vent(bm, (hx * 0.92, hy * 0.1, hz * 0.1), (0.1, 0.3, 0.5), slats=3)
	greeble_vent(bm, (-hx * 0.92, hy * 0.1, hz * 0.1), (0.1, 0.3, 0.5), slats=3)


def _medium_hull_greebles(bm, hx, hy, hz):
	greeble_headlight_pair(bm, hx, -hy * 0.15, -hz * 0.97, radius=0.1)
	greeble_hatch(bm, (0, hy * 1.05, hz * 0.1), (0.7, 0.06, 0.6))
	greeble_toolbox(bm, (hx * 0.7, -hy * 0.55, hz * 0.5))
	greeble_exhaust_stack(bm, (-hx * 0.75, hy * 0.6, hz * 0.85), radius=0.09, height=0.4)
	greeble_exhaust_stack(bm, (-hx * 0.55, hy * 0.6, hz * 0.85), radius=0.09, height=0.32)
	greeble_corner_gusset(bm, -1, hx, hy, -hz * 0.85)
	greeble_corner_gusset(bm, 1, hx, hy, -hz * 0.85)
	greeble_rivet_row(bm, (-hx * 0.9, hy * 0.9, -hz * 0.6), (-hx * 0.9, hy * 0.9, hz * 0.6), 6)
	greeble_rivet_row(bm, (hx * 0.9, hy * 0.9, -hz * 0.6), (hx * 0.9, hy * 0.9, hz * 0.6), 6)


def _heavy_hull_greebles(bm, hx, hy, hz):
	greeble_headlight_pair(bm, hx * 0.8, -hy * 0.1, -hz * 0.97, radius=0.13)
	greeble_hatch(bm, (0, hy * 1.08, 0), (1.0, 0.08, 0.9))
	add_cyl_y(bm, (0, hy * 1.15, 0), 0.45, 0.22, segments=14)  # commander cupola
	for x_sign in (-1, 1):
		for z_frac in (-0.75, 0.6):
			greeble_corner_gusset(bm, x_sign, hx, hy, hz * z_frac, size=(0.5, 0.42, 0.7))
	greeble_exhaust_stack(bm, (-hx * 0.7, hy * 0.65, hz * 0.9), radius=0.12, height=0.5)
	greeble_exhaust_stack(bm, (-hx * 0.45, hy * 0.65, hz * 0.9), radius=0.12, height=0.42)
	greeble_rivet_row(bm, (-hx * 0.95, hy * 0.85, -hz * 0.8), (-hx * 0.95, hy * 0.85, hz * 0.8), 8)
	greeble_rivet_row(bm, (hx * 0.95, hy * 0.85, -hz * 0.8), (hx * 0.95, hy * 0.85, hz * 0.8), 8)
	greeble_toolbox(bm, (hx * 0.75, -hy * 0.6, -hz * 0.3), size=(0.6, 0.32, 0.4))


def _interceptor_hull_greebles(bm, hx, hy, hz):
	# Sleek - fewer greebles, small canopy bump + tail fins + intakes
	add_box(bm, (0, hy * 1.0, hz * 0.15), (hx * 0.7, hy * 0.25, hz * 0.5), bevel=0.04)
	greeble_vent(bm, (hx * 0.85, 0, hz * 0.3), (0.08, 0.3, 0.6), slats=4)
	greeble_vent(bm, (-hx * 0.85, 0, hz * 0.3), (0.08, 0.3, 0.6), slats=4)
	for side in (-1, 1):
		add_box(bm, (side * hx * 0.5, hy * 0.3, hz * 0.92), (0.04, hy * 0.5, 0.3), rot_axis='x', rot_angle=0.3)
	greeble_antenna(bm, (0, hy * 1.05, -hz * 0.2), height=0.18)


def _assault_hull_greebles(bm, hx, hy, hz):
	greeble_headlight_pair(bm, hx * 0.75, -hy * 0.1, -hz * 0.97, radius=0.11)
	# Applique armor plates
	for x_sign in (-1, 1):
		for z_frac in (-0.5, 0.0, 0.5):
			add_box(bm, (x_sign * hx * 0.98, hy * 0.1, hz * z_frac), (0.1, hy * 1.1, hz * 0.28), bevel=0.015)
	add_cyl_y(bm, (0, hy * 1.1, hz * 0.1), 0.5, 0.14, segments=16)  # turret ring
	greeble_hatch(bm, (0, hy * 1.15, hz * 0.1), (0.55, 0.05, 0.5))
	# Front dozer-style plate
	add_box(bm, (0, -hy * 0.4, -hz * 1.0), (hx * 1.3, hy * 0.6, 0.15), bevel=0.03)
	greeble_exhaust_stack(bm, (-hx * 0.6, hy * 0.55, hz * 0.9), radius=0.1, height=0.4)


def _pillbox_greebles(bm, hx, hy, hz):
	for i in range(8):
		angle = i * (2.0 * math.pi / 8.0) + math.pi / 8.0
		pos = (math.cos(angle) * hx * 0.95, -hy * 0.75, math.sin(angle) * hz * 0.95)
		add_box(bm, pos, (0.35, 0.35, 0.35), bevel=0.05)  # sandbag corner fillets
	greeble_vent(bm, (0, hy * 0.55, hz * 0.9), (0.5, 0.15, 0.1), slats=5)
	greeble_antenna(bm, (hx * 0.3, hy * 1.15, hz * 0.3), height=0.5)
	greeble_rivet_row(bm, (-hx * 0.85, -hy * 0.2, hz * 0.85), (hx * 0.85, -hy * 0.2, hz * 0.85), 5)


def _tower_greebles(bm, hx, hy, hz):
	pass  # railing posts / spotlights / antenna already added in build_tower_hull


def generate_hulls():
	print("--- Building hull library ---")

	export_and_cleanup(build_wedge_hull("light_hull", 3.0, 1.0, 4.0,
		nose_frac=0.6, spine_w=0.35, spine_h=1.08, rear_flare=0.85, front_flare=0.55,
		color=(0.72, 0.73, 0.75), greebles=_light_hull_greebles), HULLS_DIR, "light_hull")

	export_and_cleanup(build_wedge_hull("medium_hull", 4.0, 1.0, 6.0,
		nose_frac=0.25, spine_w=0.6, spine_h=1.15, rear_flare=1.0, front_flare=0.85,
		color=(0.5, 0.5, 0.52), greebles=_medium_hull_greebles), HULLS_DIR, "medium_hull")

	export_and_cleanup(build_wedge_hull("heavy_hull", 6.0, 1.5, 8.0,
		nose_frac=0.08, spine_w=0.75, spine_h=1.2, rear_flare=1.0, front_flare=1.0,
		color=(0.32, 0.32, 0.34), greebles=_heavy_hull_greebles), HULLS_DIR, "heavy_hull")

	export_and_cleanup(build_wedge_hull("interceptor_hull", 2.4, 0.8, 3.2,
		nose_frac=0.95, spine_w=0.22, spine_h=1.05, rear_flare=0.75, front_flare=0.3,
		color=(0.55, 0.65, 0.78), greebles=_interceptor_hull_greebles), HULLS_DIR, "interceptor_hull")

	export_and_cleanup(build_wedge_hull("assault_hull", 5.0, 1.3, 7.0,
		nose_frac=0.4, spine_w=0.7, spine_h=1.22, rear_flare=1.0, front_flare=0.9,
		color=(0.4, 0.32, 0.28), greebles=_assault_hull_greebles), HULLS_DIR, "assault_hull")

	export_and_cleanup(build_bunker_hull("pillbox_foundation", 3.0, 1.2, 3.0,
		sides=8, taper=0.7, color=(0.45, 0.45, 0.4), greebles=_pillbox_greebles), HULLS_DIR, "pillbox_foundation")

	export_and_cleanup(build_tower_hull("tower_foundation", 3.0, 4.0, 3.0,
		tiers=3, color=(0.5, 0.48, 0.44), greebles=_tower_greebles), HULLS_DIR, "tower_foundation")

	print("--- Hull library done ---")


clear_scene()
generate_parts()
generate_hulls()
print("=== Mesh generation complete ===")
