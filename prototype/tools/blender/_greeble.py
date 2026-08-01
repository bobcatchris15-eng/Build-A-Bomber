"""Shared bmesh greebling helpers for the weapon/module builders.

Every build_*.py in this directory had grown its own copy of add_box,
add_cyl_x/y/z, add_taper_y, bolt_ring and export_bmesh - six near-identical
copies by the time the roster expansion started, which meant a fix to any of
them (the add_box bevel guard, the auto-smooth angle) had to be made six
times or silently diverge. New builders import from here.

The existing scripts are deliberately NOT retrofitted: they are authoring
sources for meshes that are already exported and committed, and rewriting
them risks changing geometry for no gain. This is for new work.

CONVENTIONS (unchanged, and load-bearing for visual_builder's assembly):
  - Blender +Y is FORWARD (Godot -Z), +Z is UP.
  - MOUNT parts have their origin at deck level (Z=0).
  - RECEIVER/BREECH parts have their origin at the trunnion.
  - BARREL/TUBE parts have their origin at the receiver's front face and
    extend along +Y, so a length tweak grows them forward and moves nothing
    else.
  - Anything a tweak scales is its OWN part.
  - Mount stations are MEASURED from the exported AABBs afterwards, never
    estimated. Estimating them is what left the anti-materiel rifle's barrel
    floating 0.11 units in front of its breech.

TWO RULES THAT SHAPE EVERY PART (VISUAL_ART_DIRECTION.md):
  1. These are EXTERIOR MODULES, not crew-served guns. No grips, triggers,
     handwheels, carry handles or eyepieced sights. Aiming and firing gear is
     servos, solenoids and conduit; optics are boxed cameras and LIDAR drums
     with the glass on the outside.
  2. BALANCE ABOUT THE TRUNNION. The trunnion sits directly above the
     module's origin, so real mass must sit behind it. Checked by
     test_weapon_modules_balance_about_their_mount.
"""

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


def _cone(bm, pos, r1, r2, depth, segments, rot=None):
	res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
								radius1=r1, radius2=r2, depth=depth)
	loc = mathutils.Vector(pos)
	for v in res['verts']:
		v.co = (rot @ v.co if rot else v.co) + loc


def add_cyl_z(bm, pos, radius, height, segments=16):
	_cone(bm, pos, radius, radius, height, segments)


def add_cyl_y(bm, pos, radius, height, segments=16):
	_cone(bm, pos, radius, radius, height, segments, mathutils.Matrix.Rotation(math.radians(90), 4, 'X'))


def add_cyl_x(bm, pos, radius, height, segments=16):
	_cone(bm, pos, radius, radius, height, segments, mathutils.Matrix.Rotation(math.radians(90), 4, 'Y'))


def add_taper_y(bm, pos, r_back, r_front, height, segments=16):
	"""Truncated cone along +Y. r_back is the -Y end, r_front the +Y end."""
	_cone(bm, pos, r_front, r_back, height, segments, mathutils.Matrix.Rotation(math.radians(90), 4, 'X'))


def add_taper_z(bm, pos, r_bot, r_top, height, segments=16):
	_cone(bm, pos, r_top, r_bot, height, segments)


def add_nose_y(bm, pos, radius, length, segments=16):
	"""An ogive-ish nose cone pointing +Y, built from stacked tapers so it
	reads as a shaped warhead rather than a party hat."""
	steps = 4
	prev_r = radius
	for i in range(steps):
		t0 = i / float(steps)
		t1 = (i + 1) / float(steps)
		r1 = radius * math.sqrt(max(0.0, 1.0 - t1 * t1))
		add_taper_y(bm, (pos[0], pos[1] + (t0 + t1) * 0.5 * length, pos[2]),
					prev_r, max(0.004, r1), length / steps, segments)
		prev_r = max(0.004, r1)


def bolt_ring(bm, y, radius, count=8, bolt_r=0.008, bolt_len=0.014):
	for i in range(count):
		a = (i / count) * math.tau
		add_cyl_y(bm, (math.cos(a) * radius, y, math.sin(a) * radius), bolt_r, bolt_len, segments=6)


def bolt_ring_z(bm, z, radius, count=8, bolt_r=0.008, bolt_len=0.014):
	for i in range(count):
		a = (i / count) * math.tau
		add_cyl_z(bm, (math.cos(a) * radius, math.sin(a) * radius, z), bolt_r, bolt_len, segments=6)


def add_tube_between(bm, p0, p1, radius, segments=8):
	"""A round tube spanning two points. Use this for anything radial or
	diagonal: add_box has no rotation argument, so 'a box at a radial
	position' comes out axis-aligned and reads as a spike rather than a rib.
	That mistake shipped once already on the microwave dish."""
	a = mathutils.Vector(p0)
	b = mathutils.Vector(p1)
	d = b - a
	length = d.length
	if length < 1e-5:
		return
	res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
								radius1=radius, radius2=radius, depth=length)
	rot = mathutils.Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
	mid = (a + b) / 2.0
	for v in res['verts']:
		v.co = (rot @ v.co) + mid


def add_helix(bm, pos, coil_r, length, turns, wire_r, segs_per_turn=12, minor_seg=6, axis='Z'):
	"""A swept helical coil spring - the most legible 'this absorbs recoil'
	cue there is. A stack of separate rings reads as a threaded collar."""
	total = int(turns * segs_per_turn)
	rings = []
	for i in range(total + 1):
		t = i / segs_per_turn
		a = t * math.tau
		h = (i / max(1, total)) * length - length / 2.0
		cx, cy = math.cos(a) * coil_r, math.sin(a) * coil_r
		tangent = mathutils.Vector((-math.sin(a) * coil_r * math.tau / segs_per_turn,
									 math.cos(a) * coil_r * math.tau / segs_per_turn,
									 length / max(1, total))).normalized()
		up = mathutils.Vector((0, 0, 1))
		if abs(tangent.dot(up)) > 0.95:
			up = mathutils.Vector((1, 0, 0))
		n1 = tangent.cross(up).normalized()
		n2 = tangent.cross(n1).normalized()
		ring = []
		for j in range(minor_seg):
			b = (j / minor_seg) * math.tau
			off = n1 * (math.cos(b) * wire_r) + n2 * (math.sin(b) * wire_r)
			co = mathutils.Vector((cx, cy, h)) + off
			if axis == 'Y':
				co = mathutils.Vector((co.x, co.z, co.y))
			elif axis == 'X':
				co = mathutils.Vector((co.z, co.y, co.x))
			ring.append(bm.verts.new(co + mathutils.Vector(pos)))
		rings.append(ring)
	for i in range(total):
		for j in range(minor_seg):
			try:
				bm.faces.new((rings[i][j], rings[i][(j + 1) % minor_seg],
							  rings[i + 1][(j + 1) % minor_seg], rings[i + 1][j]))
			except ValueError:
				pass


def add_grid_vents(bm, pos, size, cols, rows, depth=0.010, axis='Y'):
	"""A punched louvre/vent panel. Cheap, and the fastest way to make a flat
	box face read as equipment rather than as a slab."""
	for i in range(cols):
		for j in range(rows):
			u = (i + 0.5) / cols - 0.5
			v = (j + 0.5) / rows - 0.5
			p = (pos[0] + u * size[0], pos[1], pos[2] + v * size[2])
			if axis == 'Y':
				add_box(bm, (p[0], pos[1], p[2]),
						(size[0] / cols * 0.72, depth, size[2] / rows * 0.55), bevel=0.002)
			else:
				add_box(bm, (p[0], pos[1] + v * size[2], pos[2]),
						(size[0] / cols * 0.72, size[2] / rows * 0.55, depth), bevel=0.002)


# --- Remote-operation hardware ---------------------------------------------
# The replacements for crew-served fittings. Kept as helpers so every new
# module reaches for the same vocabulary instead of reinventing it.

def add_servo_drive(bm, pos, radius=0.048, length=0.085, axis='Y'):
	"""Servo can + end bell + cable gland. This is what goes where a handwheel
	or a pair of spade grips would have been."""
	if axis == 'Y':
		add_cyl_y(bm, pos, radius, length, segments=16)
		add_cyl_y(bm, (pos[0], pos[1] - length * 0.62, pos[2]), radius * 0.72, length * 0.28, segments=14)
		add_cyl_y(bm, (pos[0], pos[1] - length * 0.80, pos[2]), radius * 0.26, length * 0.24, segments=8)
	else:
		add_cyl_z(bm, pos, radius, length, segments=16)
		add_cyl_z(bm, (pos[0], pos[1], pos[2] - length * 0.62), radius * 0.72, length * 0.28, segments=14)
		add_cyl_z(bm, (pos[0], pos[1], pos[2] - length * 0.80), radius * 0.26, length * 0.24, segments=8)


def add_junction_box(bm, pos, size=(0.075, 0.055, 0.050), conduits=3):
	"""A sealed electrical junction box with conduit stubs - the other half of
	'this is operated from somewhere else'."""
	add_box(bm, pos, size, bevel=0.005)
	for i in range(conduits):
		off = (i - (conduits - 1) * 0.5) * (size[0] * 0.55)
		add_cyl_y(bm, (pos[0] + off, pos[1] - size[1] * 0.75, pos[2]), 0.008, size[1] * 0.6, segments=6)


def add_camera_head(bm, pos, scale=1.0):
	"""A boxed electro-optical head: housing, a lens barrel standing PROUD
	under a sunshade, and a small LIDAR puck. Never an eyepiece - a tube on a
	riser reads as a telescope no matter what it is called."""
	s = scale
	add_box(bm, pos, (0.090 * s, 0.075 * s, 0.070 * s), bevel=0.006 * s)
	add_cyl_y(bm, (pos[0], pos[1] + 0.052 * s, pos[2]), 0.026 * s, 0.030 * s, segments=16)
	add_cyl_y(bm, (pos[0], pos[1] + 0.072 * s, pos[2]), 0.020 * s, 0.014 * s, segments=16)
	add_box(bm, (pos[0], pos[1] + 0.062 * s, pos[2] + 0.044 * s),
			(0.098 * s, 0.055 * s, 0.012 * s), bevel=0.003 * s)
	add_cyl_z(bm, (pos[0] + 0.052 * s, pos[1], pos[2] + 0.052 * s), 0.022 * s, 0.030 * s, segments=14)
	add_cyl_z(bm, (pos[0] + 0.052 * s, pos[1], pos[2] + 0.070 * s), 0.024 * s, 0.010 * s, segments=14)


def export_bmesh(bm, object_name, filename, color=(0.20, 0.22, 0.24, 1.0),
				 metallic=0.75, roughness=0.30):
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
		bsdf.inputs['Base Color'].default_value = color
		bsdf.inputs['Metallic'].default_value = metallic
		bsdf.inputs['Roughness'].default_value = roughness
	obj.data.materials.append(mat)
	filepath = os.path.join(PARTS_DIR, filename)
	bpy.ops.export_scene.gltf(filepath=filepath, use_selection=True, export_format='GLB')
	print("Exported:", filepath)
	clear_scene()
