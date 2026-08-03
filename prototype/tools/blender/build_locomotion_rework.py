import bpy
import bmesh
import math
import os
import mathutils

# Re-authors the EXISTING locomotion parts that were never brought up to the
# roster's standard. Chris, repeatedly: re-author the existing ones and their
# running gear, and the amphibious screw is the worst - "definitely doable more
# simply, with a helix around a drum, instead of a stack of flat things".
#
# He is right about the cause. build_meshes.py's build_screw_drum() approximates
# the auger flighting with 120 separate short boxes scattered along a helical
# path. That is a lot of triangles spent to NOT look like a helix: the segments
# never join, so at any real zoom it reads as a pile of paddles bolted to a pipe.
# A helical flight is a swept surface, and sweeping it properly is both simpler
# and cheaper than faking it - add_helical_flight() below builds one continuous
# ribbon with real thickness out of a single quad strip.
#
# Also re-authored here, for the same reason - they were placeholders next to
# parts like the reworked M230:
#   rotor_blade       12 tris  - a flat plank standing in for a rotor blade
#   leg_foot          88 tris  - a box standing in for a foot
#   hover_skirt       92 tris  - a ring standing in for a skirt
#   naval_propeller  120 tris  - flat paddles standing in for screw blades
#
# CONVENTIONS
#   - These parts are consumed by visual_builder.gd's existing locomotion
#     builders, so their ORIGIN and AXIS must not move. Where the original was
#     built along a particular axis, the replacement is built along the same
#     one, or the runtime placement silently breaks. Each function records
#     which axis it owes the caller.
#   - Detail targets the reworked-weapons standard, not a triangle budget
#     (ff757ef's LOD pass handles distance).

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
PARTS_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "parts")
os.makedirs(PARTS_DIR, exist_ok=True)


def clear_scene():
	bpy.ops.object.select_all(action='SELECT')
	bpy.ops.object.delete(use_global=False)


def add_box(bm, pos, size, bevel=0.0, bevel_segments=1):
	loc = mathutils.Vector(pos)
	res = bmesh.ops.create_cube(bm, size=1.0)
	for v in res['verts']:
		v.co = loc + mathutils.Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
	if bevel > 0.001:
		edges = [e for e in bm.edges if any(v in res['verts'] for v in e.verts)]
		try:
			bmesh.ops.bevel(bm, geom=edges, offset=bevel,
							segments=max(1, int(bevel_segments)), affect='EDGES')
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


def add_taper_z(bm, pos, r_bot, r_top, height, segments=16):
	_cone(bm, pos, r_bot, r_top, height, segments)


def add_taper_y(bm, pos, r_back, r_front, height, segments=16):
	_cone(bm, pos, r_front, r_back, height, segments, mathutils.Matrix.Rotation(math.radians(90), 4, 'X'))


def add_taper_x(bm, pos, r_lo, r_hi, height, segments=16):
	_cone(bm, pos, r_lo, r_hi, height, segments, mathutils.Matrix.Rotation(math.radians(90), 4, 'Y'))


def add_tube_between(bm, p0, p1, radius, segments=8):
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


def bolt_ring_x(bm, x, radius, count=8, bolt_r=0.008, bolt_len=0.014):
	for i in range(count):
		a = (i / count) * math.tau
		add_cyl_x(bm, (x, math.cos(a) * radius, math.sin(a) * radius), bolt_r, bolt_len, segments=6)


def add_helical_flight(bm, length, r_inner, r_outer, turns, thickness,
					   steps=96, axis='x'):
	"""One continuous helical flight - the ribbon that makes an auger an auger.

	This is the whole point of the rework. The previous implementation scattered
	120 unconnected boxes along a helical path, which costs far MORE geometry
	than sweeping the surface and still reads as a pile of paddles because the
	segments never join. Here each station contributes four verts - inner/outer
	x front/back face - and consecutive stations are bridged into quads, giving
	a single solid ribbon with real thickness and a continuous outer edge.

	`axis` is the drum's long axis in Blender space. Built along local Z and
	swizzled at the end, so the caller gets it aligned however the runtime
	expects without a second code path.
	"""
	rings = []
	for i in range(steps + 1):
		t = i / float(steps)
		z = -length * 0.5 + t * length
		a = t * turns * math.tau
		ca, sa = math.cos(a), math.sin(a)
		half = thickness * 0.5
		quad = []
		for r, dz in ((r_inner, -half), (r_outer, -half), (r_outer, half), (r_inner, half)):
			co = mathutils.Vector((ca * r, sa * r, z + dz))
			if axis == 'x':
				co = mathutils.Vector((co.z, co.x, co.y))
			elif axis == 'y':
				co = mathutils.Vector((co.x, co.z, co.y))
			quad.append(bm.verts.new(co))
		rings.append(quad)
	bm.verts.ensure_lookup_table()
	for i in range(steps):
		a0, a1 = rings[i], rings[i + 1]
		for j in range(4):
			k = (j + 1) % 4
			try:
				bm.faces.new((a0[j], a0[k], a1[k], a1[j]))
			except ValueError:
				pass
	# Cap both ends of the ribbon so it is a closed solid, not an open shell.
	for cap in (rings[0], rings[-1]):
		try:
			bm.faces.new(cap)
		except ValueError:
			pass


def export_bmesh(bm, object_name, filename, color=(0.20, 0.22, 0.24, 1.0),
				 metallic=0.70, roughness=0.42):
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
		obj.data.auto_smooth_angle = math.radians(40)
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


# ---------------------------------------------------------------------------
# SCREW DRUM (three flighting-depth variants)
#
# Long axis is Blender +Y, which imports as Godot -Z: the drum lies fore/aft,
# parallel to travel, one per side.
#
# The original was written with add_cyl_axis(..., 'x') plus a comment saying
# that 'x' "is what actually yields a Godot-Z-long result" - true only because
# build_meshes.py's add_cyl_axis carries its own internal axis swap. This file
# does not use that helper, so copying the 'x' literally produced a drum lying
# ACROSS the vehicle: measured 1.895 on Godot X instead of Z, which is why the
# first rework rendered as a short stub poking out sideways. The convention that
# matters is the RESULT (length on Godot Z), not the letter the old call used.
# ---------------------------------------------------------------------------
def build_screw_drum(name, fin_reach, turns, color=(0.35, 0.32, 0.28, 1.0)):
	length = 1.6
	shaft_r = 0.145
	bm = bmesh.new()

	# Drum body: a real pressure vessel, not a bare pipe - rolled shell with
	# welded seams and a reinforcing band at each flight anchor.
	add_cyl_y(bm, (0, 0, 0), shaft_r, length * 0.86, segments=24)
	for i in range(5):
		y = -length * 0.36 + i * (length * 0.18)
		add_cyl_y(bm, (0, y, 0), shaft_r * 1.06, 0.030, segments=24)
	# Conical noses. Both radii swapped from the first authoring (Chris: "flip
	# the cones on each end of the drum around") - add_taper_y's r_back lands
	# at +Y and r_front at -Y after its internal X-rotation, which is the
	# opposite of what the original call assumed, so the noses flared outward
	# into funnels instead of tapering to a point like a real auger.
	add_taper_y(bm, (0, -length * 0.50, 0), 0.028, shaft_r, length * 0.14, segments=24)
	add_taper_y(bm, (0, length * 0.50, 0), shaft_r, 0.028, length * 0.14, segments=24)
	add_cyl_y(bm, (0, -length * 0.575, 0), 0.038, 0.055, segments=12)
	add_cyl_y(bm, (0, length * 0.575, 0), 0.038, 0.055, segments=12)

	# THE FLIGHT: one swept ribbon, the reason for this rework.
	add_helical_flight(bm, length * 0.84, shaft_r * 0.96, shaft_r + fin_reach,
					   turns, 0.036, steps=110, axis='y')
	# A second flight 180 degrees out of phase - real screw-drive vehicles run
	# a double start so the drum bites evenly instead of walking sideways.
	rings_offset = bmesh.new()
	add_helical_flight(rings_offset, length * 0.84, shaft_r * 0.96, shaft_r + fin_reach * 0.72,
					   turns, 0.030, steps=110, axis='y')
	rot = mathutils.Matrix.Rotation(math.pi, 4, 'Y')
	for v in rings_offset.verts:
		v.co = rot @ v.co
	tmp_mesh = bpy.data.meshes.new("tmp_flight")
	rings_offset.to_mesh(tmp_mesh)
	rings_offset.free()
	bm.from_mesh(tmp_mesh)
	bpy.data.meshes.remove(tmp_mesh)

	# Hub end plates and drive coupling, so it reads as something driven.
	for sy in (-1, 1):
		add_cyl_y(bm, (0, sy * length * 0.43, 0), shaft_r * 1.14, 0.040, segments=24)
		for i in range(8):
			a = (i / 8) * math.tau
			add_cyl_y(bm, (math.cos(a) * shaft_r * 0.72, sy * length * 0.455,
						   math.sin(a) * shaft_r * 0.72), 0.014, 0.024, segments=6)
	export_bmesh(bm, name, name + ".glb", color=color, metallic=0.66, roughness=0.52)


# ---------------------------------------------------------------------------
# ROTOR BLADE - was 12 triangles: a flat plank.
# Authored along Blender +X (spanwise), matching _build_helicopter_rotors().
# ---------------------------------------------------------------------------
def build_rotor_blade():
	bm = bmesh.new()
	span = 1.0
	steps = 12
	# A real blade: tapering chord, washout (twist toward the tip), and a
	# thicker cuff at the root where it bolts to the hub.
	for i in range(steps):
		t = i / float(steps - 1)
		x = 0.10 + t * span
		chord = 0.150 * (1.0 - 0.42 * t)
		thick = 0.030 * (1.0 - 0.55 * t)
		twist = math.radians(10.0 * (1.0 - t) - 2.0)
		loc = mathutils.Vector((x, 0, 0))
		res = bmesh.ops.create_cube(bm, size=1.0)
		rotm = mathutils.Matrix.Rotation(twist, 4, 'X')
		for v in res['verts']:
			v.co = loc + rotm @ mathutils.Vector((
				v.co.x * (span / steps) * 1.08, v.co.y * chord, v.co.z * thick))
	# Root cuff and retention bolts.
	add_cyl_x(bm, (0.055, 0, 0), 0.052, 0.110, segments=14)
	add_cyl_x(bm, (0.005, 0, 0), 0.062, 0.030, segments=14)
	bolt_ring_x(bm, 0.012, 0.040, count=4, bolt_r=0.009, bolt_len=0.018)
	# Leading-edge abrasion strip - the strongest read that this is a blade.
	for i in range(steps):
		t = i / float(steps - 1)
		x = 0.10 + t * span
		chord = 0.150 * (1.0 - 0.42 * t)
		add_box(bm, (x, chord * 0.5, 0), ((span / steps) * 1.05, 0.016, 0.020), bevel=0.003)
	# Tip cap, swept back.
	add_box(bm, (0.10 + span + 0.02, -0.012, 0), (0.060, 0.080, 0.014), bevel=0.004)
	export_bmesh(bm, "rotor_blade", "rotor_blade.glb",
				 color=(0.18, 0.19, 0.21, 1.0), metallic=0.62, roughness=0.42)


# ---------------------------------------------------------------------------
# LEG FOOT - was 88 triangles: a box.
# Authored around the origin with the sole downward (-Z), per _build_legs().
# ---------------------------------------------------------------------------
def build_leg_foot():
	bm = bmesh.new()
	add_box(bm, (0, 0.02, 0.055), (0.30, 0.40, 0.075), bevel=0.014)      # ankle plate
	add_cyl_z(bm, (0, 0.02, 0.105), 0.085, 0.070, segments=16)           # ankle boss
	add_box(bm, (0, 0.02, -0.010), (0.34, 0.46, 0.060), bevel=0.012)     # foot body
	# Three-toe sole with independent pads - reads as something that grips.
	for i, ty in ((0, 0.155), (1, 0.0), (2, -0.155)):
		w = 0.30 if i == 1 else 0.24
		add_box(bm, (0, ty + 0.02, -0.058), (w, 0.140, 0.040), bevel=0.010)
		for gx in (-1, 1):                                                # cleats
			add_box(bm, (gx * w * 0.28, ty + 0.02, -0.086), (0.070, 0.100, 0.028), bevel=0.005)
	# Suspension: a shock can and two links from the sole up to the ankle.
	add_cyl_z(bm, (0, -0.145, 0.055), 0.042, 0.110, segments=12)
	for sx in (-1, 1):
		add_tube_between(bm, (sx * 0.115, -0.130, -0.030), (sx * 0.075, 0.020, 0.090), 0.018, segments=8)
	add_box(bm, (0, 0.215, 0.020), (0.180, 0.070, 0.050), bevel=0.008)   # toe guard
	export_bmesh(bm, "leg_foot", "leg_foot.glb",
				 color=(0.26, 0.26, 0.28, 1.0), metallic=0.70, roughness=0.45)


# ---------------------------------------------------------------------------
# LEG THIGH / LEG SHIN - were tapered cylinders with ridges glued on.
#
# Chris: "please try and author better legs here too." The old segments read as
# pipes because that is what they were - a cone plus five longitudinal ribs.
# A walking machine's limb reads as a limb because you can see WHAT MOVES IT:
# a hydraulic ram running alongside the bone, anchored at one joint and pushing
# on the next. Both segments below are built as a structural casting plus a
# visible actuator, which is the whole difference.
#
# AXIS: authored along Blender +Z, base (the upper joint) at the ORIGIN,
# extending to +Z. Blender +Z maps to Godot +Y, and visual_builder.gd scales
# these on local Y by (segment length / authored length) with the top at the
# node origin - so the authored length below and the divisor there are the same
# number and must change together.
# ---------------------------------------------------------------------------
def _leg_segment(name, length, r_top, r_bot, ram_side, color):
	bm = bmesh.new()

	# Structural casting: a faceted spar rather than a smooth cone, with the
	# section stepping down in three stages toward the lower joint.
	stages = 3
	for i in range(stages):
		t0 = i / float(stages)
		t1 = (i + 1) / float(stages)
		r0 = r_top + (r_bot - r_top) * t0
		r1 = r_top + (r_bot - r_top) * t1
		add_taper_z(bm, (0, 0, length * (t0 + t1) * 0.5),
					r0, r1, length * (t1 - t0) * 1.02, segments=10)
		# Collar at each step - the joint between two cast sections.
		add_cyl_z(bm, (0, 0, length * t1), r1 * 1.22, length * 0.035, segments=10)

	# Upper joint yoke: two cheeks and a pivot pin, so the segment visibly
	# HANGS on something instead of ending in a flat disc.
	for sy in (-1, 1):
		add_box(bm, (0, sy * r_top * 0.86, length * 0.045),
				(r_top * 1.5, r_top * 0.34, length * 0.13), bevel=r_top * 0.09)
	add_cyl_y(bm, (0, 0, length * 0.045), r_top * 0.30, r_top * 2.3, segments=10)

	# Hydraulic ram alongside the spar: barrel anchored near the top, polished
	# rod emerging from it, clevis at the far end. ram_side puts it on the
	# front or back face so the thigh's and shin's rams do not overlap.
	rx = r_top * 1.05 * ram_side
	barrel_len = length * 0.44
	add_cyl_z(bm, (rx, 0, length * 0.30), r_top * 0.40, barrel_len, segments=12)
	add_cyl_z(bm, (rx, 0, length * 0.30 - barrel_len * 0.5), r_top * 0.47,
			  length * 0.05, segments=12)                                  # gland
	add_cyl_z(bm, (rx, 0, length * 0.66), r_top * 0.20, length * 0.30, segments=10)  # rod
	add_box(bm, (rx, 0, length * 0.83), (r_top * 0.62, r_top * 0.34, length * 0.075),
			bevel=r_top * 0.06)                                            # clevis
	add_tube_between(bm, (rx, 0, length * 0.12), (0, 0, length * 0.06),
					 r_top * 0.16, segments=8)                             # ram mount
	# Feed lines from the ram back up to the joint.
	for hy in (-1, 1):
		add_tube_between(bm, (rx * 0.7, hy * r_top * 0.42, length * 0.11),
						 (rx * 0.5, hy * r_top * 0.30, length * 0.52),
						 r_top * 0.055, segments=6)

	# Armour shroud over the outboard face of the spar - a plate, not a rib,
	# so the silhouette has a flat side and reads as built rather than grown.
	add_box(bm, (-r_top * 0.92 * ram_side, 0, length * 0.48),
			(r_top * 0.30, r_top * 1.35, length * 0.62), bevel=r_top * 0.10)
	for i in range(3):
		add_box(bm, (-r_top * 1.02 * ram_side, 0, length * (0.26 + 0.22 * i)),
				(r_top * 0.16, r_top * 1.5, length * 0.045), bevel=r_top * 0.04)

	# Lower joint: a boss with a through-pin, matching the yoke at the top so
	# two segments visibly pin together at the knee.
	add_cyl_z(bm, (0, 0, length * 0.965), r_bot * 1.30, length * 0.07, segments=12)
	add_cyl_y(bm, (0, 0, length * 0.985), r_bot * 0.34, r_bot * 2.6, segments=10)

	export_bmesh(bm, name, name + ".glb", color=color, metallic=0.62, roughness=0.40)


def build_leg_thigh():
	# 0.55 - matches the `thigh_len / 0.55` divisor in _build_legs().
	_leg_segment("leg_thigh", 0.55, 0.13, 0.095, ram_side=1.0,
				 color=(0.31, 0.31, 0.34, 1.0))


def build_leg_shin():
	# 0.50 - matches the `shin_len / 0.5` divisor in _build_legs().
	_leg_segment("leg_shin", 0.50, 0.095, 0.062, ram_side=-1.0,
				 color=(0.17, 0.17, 0.19, 1.0))


# ---------------------------------------------------------------------------
# HALF-TRACK BOGIE - moved here from build_locomotion_expansion.py.
#
# Chris: "fix the front and back of the track portion to actually look like a
# track. Look over the dedicated treaded track again, those look okay."
#
# It was authored with two straight runs plus a hand-rolled end loop, and that
# loop was broken on its face - it multiplied its own cosine term by 0.0, so
# every "arc" link landed on the same fore/aft coordinate and the ends read as
# a squared-off stub rather than wrapping anything. tread_belt_loop already
# solves this properly with _track_path(): real arcs sampled around the
# sprocket and idler centres, so the belt wraps them by construction at any
# scale. Using the same two helpers here means the two tracked types cannot
# drift apart again, which is why this function moved files rather than
# growing its own copy of the maths.
#
# AXIS: fore/aft on Blender Y, up on Blender Z, width across X - the plane
# _track_path returns, and what _build_half_track() expects.
# ---------------------------------------------------------------------------
def build_ht_track_bogie():
	half_span = 0.42
	r_drive = 0.150     # rear sprocket
	r_road = 0.085
	road_drop = 0.130   # sprocket centreline down to the road-wheel line
	width = 0.180
	x = 0.10
	bot = -(road_drop + r_road)
	bm = bmesh.new()

	# Frame and top rail, spanning between the two end wheels.
	add_box(bm, (x, 0, -0.030), (0.090, half_span * 1.9, 0.115), bevel=0.010)
	add_box(bm, (x, 0, 0.085), (0.075, half_span * 1.85, 0.030), bevel=0.005)

	# Drive sprocket aft, idler forward - both on the RAISED axle line, which
	# is what gives the track its trapezoid against the low road wheels.
	add_cyl_x(bm, (x, half_span, 0), r_drive, width * 0.86, segments=18)
	for i in range(10):
		a = (i / 10) * math.tau
		add_box(bm, (x, half_span + math.cos(a) * (r_drive * 0.94),
					 math.sin(a) * (r_drive * 0.94)),
				(width * 0.88, 0.038, 0.038), bevel=0.004)
	add_cyl_x(bm, (x, -half_span, 0), r_drive * 0.86, width * 0.80, segments=16)

	# Road wheels along the bottom line, riding the belt's lower run.
	for i in range(4):
		y = -half_span * 0.62 + i * (half_span * 1.24 / 3.0)
		add_cyl_x(bm, (x, y, -road_drop), r_road, width * 0.84, segments=14)
		add_cyl_x(bm, (x + 0.075, y, -road_drop), 0.040, 0.020, segments=10)
	# Return rollers up top, carrying the slack run.
	for i in range(2):
		add_cyl_x(bm, (x, -0.15 + i * 0.30, r_drive * 0.72), 0.048, width * 0.61, segments=12)

	# THE BELT: one closed path, resampled into links that meet.
	path = _resample_closed(_track_path(half_span, r_drive, road_drop, r_road), 0.052)
	for (y, z, ang, step) in path:
		rot = mathutils.Matrix.Rotation(ang, 4, 'X')
		centre = mathutils.Vector((x, y, z))
		res = bmesh.ops.create_cube(bm, size=1.0)
		for v in res['verts']:
			v.co = centre + rot @ mathutils.Vector(
				(v.co.x * width, v.co.y * step * 1.04, v.co.z * 0.024))
		outward = mathutils.Vector((0, y, z))
		outward = outward.normalized() if outward.length > 1e-5 else mathutils.Vector((0, 0, -1))
		res2 = bmesh.ops.create_cube(bm, size=1.0)
		for v in res2['verts']:
			v.co = (centre + outward * 0.022) + rot @ mathutils.Vector(
				(v.co.x * width * 0.84, v.co.y * step * 0.46, v.co.z * 0.022))

	# Mounting spine - the face that meets the hull.
	add_box(bm, (0.010, 0, 0.010), (0.070, half_span * 1.42, 0.150), bevel=0.010)
	export_bmesh(bm, "ht_track_bogie", "ht_track_bogie.glb",
				 color=(0.22, 0.23, 0.21, 1.0), metallic=0.74, roughness=0.40)


# ---------------------------------------------------------------------------
# AIR-CUSHION SKIRT - was a small ring of boxes.
#
# Chris: "it should be the occluding bulky skirt all around the bottom edge of
# the hull, cross section like a thick rounded wedge."
#
# So it is a SWEPT LOOP, not a ring of parts: one cross-section dragged around
# a rounded-rectangle footprint. That footprint is authored at UNIT half-extent
# (0.5 x 0.5) so the runtime can scale X and Z straight to the hull's own
# length and width and have the skirt follow its bottom edge on any hull -
# a circular skirt cannot do that, and a ring of segments leaves gaps at the
# corners exactly where a hovercraft's bag needs to be continuous.
#
# AXIS: footprint on Blender XY, up on Blender Z. Blender Z maps to Godot Y and
# Blender Y to Godot -Z, so the footprint lands on Godot's XZ plane, which is
# the plan view the runtime scales against.
# ---------------------------------------------------------------------------
def _rounded_rect(half_x, half_y, radius, per_corner=7):
	"""Closed CCW path around a rounded rectangle, as (x, y)."""
	rx = min(radius, half_x * 0.95)
	ry = min(radius, half_y * 0.95)
	cx, cy = half_x - rx, half_y - ry
	pts = []
	for sx, sy, a0 in ((1, 1, 0.0), (-1, 1, math.pi * 0.5),
					   (-1, -1, math.pi), (1, -1, math.pi * 1.5)):
		for i in range(per_corner + 1):
			a = a0 + (math.pi * 0.5) * (i / float(per_corner))
			pts.append((cx * sx + math.cos(a) * rx, cy * sy + math.sin(a) * ry))
	return pts


def _sweep_closed(bm, path, section):
	"""Sweep `section` - a closed list of (outward, up) - around `path`.

	The section is oriented per sample by the path's outward normal, so the
	bag's bulge always faces away from the vehicle rather than along a fixed
	axis.
	"""
	n = len(path)
	rings = []
	for i in range(n):
		x, y = path[i]
		nx, ny = path[(i + 1) % n][0] - path[i - 1][0], path[(i + 1) % n][1] - path[i - 1][1]
		# Outward normal = tangent rotated -90 degrees, normalised.
		ln = math.hypot(nx, ny) or 1.0
		ox, oy = ny / ln, -nx / ln
		ring = []
		for (u, v) in section:
			ring.append(bm.verts.new((x + ox * u, y + oy * u, v)))
		rings.append(ring)
	bm.verts.ensure_lookup_table()
	m = len(section)
	for i in range(n):
		a, b = rings[i], rings[(i + 1) % n]
		for j in range(m):
			k = (j + 1) % m
			try:
				bm.faces.new((a[j], a[k], b[k], b[j]))
			except ValueError:
				pass


def build_acs_skirt():
	# THE INNER FACE IS THE MOUNTING FACE. Chris: "attach the INNER side of the
	# ring to the bottom edge of the sides of the hull, instead of
	# bottom-to-top." So the bag laps UP the hull's side walls and is held
	# there, rather than sitting under its floor like a gasket - which is how a
	# real hovercraft skirt is hung, and it stops the hull looking like it is
	# balanced on top of a doughnut.
	#
	# The inner wall is therefore authored at exactly +-0.5 (SKIRT_INNER_UNIT
	# in visual_builder.gd - the two must change together), so scaling X and Z
	# by the hull's own width and length lands that wall flush on the hull's
	# sides. The outer bulge extends past it, which is correct: the bag is
	# wider than the vehicle.
	inner_u = -0.5
	section = []
	# Inner wall, top (lapped up the hull's side) down to the contact edge.
	section.append((inner_u, 0.235))
	section.append((inner_u, -0.240))
	# Contact edge that rides the ground cushion.
	section.append((inner_u + 0.075, -0.285))
	# Outer face: a full rounded bulge from the bottom back up to the top.
	for i in range(9):
		a = math.radians(-78.0) + math.radians(156.0) * (i / 8.0)
		section.append((inner_u + 0.105 + math.cos(a) * 0.175,
						-0.030 + math.sin(a) * 0.215))
	# Top face, running back inboard to the wall.
	section.append((inner_u + 0.060, 0.235))

	bm = bmesh.new()
	# The PATH is the inner wall's line, so the sweep's u=inner_u lands on it.
	path = _rounded_rect(0.5 - inner_u * 0.0, 0.5, 0.22, per_corner=7)
	_sweep_closed(bm, path, [(u - inner_u, v) for (u, v) in section])
	# Attachment flange up the inner wall - bolts into the hull's side skin.
	flange = _rounded_rect(0.5, 0.5, 0.22, per_corner=7)
	_sweep_closed(bm, flange, [(-0.030, 0.120), (0.014, 0.120),
							   (0.014, 0.215), (-0.030, 0.215)])
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
	export_bmesh(bm, "acs_skirt", "acs_skirt.glb",
				 color=(0.24, 0.23, 0.21, 1.0), metallic=0.10, roughness=0.88)


# ---------------------------------------------------------------------------
# BUOYANT-ENVELOPE DRIVE - was a generic prop housing on a strut.
#
# Chris: "it should be a mechanical boxy engine out to either side on a pylon.
# the pylon connecting to a nose cone, then a boxy-enginey-mechanical lookin
# bit, then a wide slow turning prop."
#
# So it is three parts in a row along the shaft, not one nacelle: a faired nose
# the pylon lands on, a boxy engine you can read the machinery of, and the hub
# the prop turns on. An airship's cruise engine is a slow, exposed, serviceable
# thing bolted to an outrigger - closer to a traction engine than to a jet -
# which is why this is boxes and stacks rather than a smooth pod.
#
# AXIS: shaft along Blender Y, nose at -Y, prop end at +Y. Blender +Y maps to
# Godot -Z, so the nose points forward and the prop faces aft, which is what
# _build_buoyant_envelope() expects.
# ---------------------------------------------------------------------------
def build_be_nose_cone():
	bm = bmesh.new()
	add_taper_y(bm, (0, -0.30, 0), 0.021, 0.150, 0.290, segments=20)     # spinner/fairing
	add_cyl_y(bm, (0, -0.150, 0), 0.158, 0.048, segments=20)             # collar

	for i in range(10):                                                   # collar bolts
		a = (i / 10) * math.tau
		add_cyl_y(bm, (math.cos(a) * 0.128, -0.150, math.sin(a) * 0.128),
				  0.012, 0.056, segments=6)
	add_cyl_y(bm, (0, -0.075, 0), 0.150, 0.110, segments=20)             # bearing barrel
	# Cooling intake scoop on top, and a drain on the bottom - the two things
	# that tell you which way up an engine is.
	add_box(bm, (0, -0.140, 0.135), (0.110, 0.190, 0.070), bevel=0.012)
	add_cyl_y(bm, (0, -0.055, -0.140), 0.030, 0.090, segments=10)
	export_bmesh(bm, "be_nose_cone", "be_nose_cone.glb",
				 color=(0.30, 0.31, 0.33, 1.0), metallic=0.68, roughness=0.42)


def build_be_engine_block():
	bm = bmesh.new()
	# Crankcase: a real box, chamfered, with a ribbed sump under it.
	add_box(bm, (0, 0.150, 0), (0.290, 0.360, 0.250), bevel=0.020)
	add_box(bm, (0, 0.150, -0.145), (0.250, 0.320, 0.070), bevel=0.012)
	for i in range(5):                                                    # sump fins
		add_box(bm, (0, 0.020 + i * 0.065, -0.190), (0.270, 0.030, 0.040), bevel=0.006)
	# Cylinder bank down each side, heads outward - the single most legible
	# "this is an engine" cue there is.
	for sx in (-1, 1):
		for i in range(3):
			y = 0.045 + i * 0.100
			add_cyl_x(bm, (sx * 0.170, y, 0.030), 0.058, 0.110, segments=12)
			add_cyl_x(bm, (sx * 0.235, y, 0.030), 0.070, 0.045, segments=12)   # head
			for f in range(3):                                                # fins
				add_cyl_x(bm, (sx * (0.205 + f * 0.022), y, 0.030), 0.076, 0.010, segments=12)
			# Exhaust stub turning up and aft into a collector.
			add_tube_between(bm, (sx * 0.215, y, 0.075), (sx * 0.150, y + 0.030, 0.185),
							 0.024, segments=8)
		add_tube_between(bm, (sx * 0.150, 0.030, 0.195), (sx * 0.150, 0.300, 0.195),
						 0.034, segments=10)                              # collector
		add_cyl_y(bm, (sx * 0.150, 0.330, 0.195), 0.042, 0.070, segments=10)  # stack
	# Accessory gear aft: magneto cans, a pump, and the reduction housing the
	# prop actually hangs off.
	add_box(bm, (0, 0.345, 0.040), (0.230, 0.090, 0.200), bevel=0.010)
	for sx in (-1, 1):
		add_cyl_y(bm, (sx * 0.080, 0.410, 0.040), 0.045, 0.075, segments=12)
	add_cyl_y(bm, (0, 0.430, -0.060), 0.055, 0.100, segments=12)
	add_taper_y(bm, (0, 0.435, 0), 0.185, 0.130, 0.090, segments=18)      # reduction case
	add_cyl_y(bm, (0, 0.500, 0), 0.105, 0.060, segments=18)               # output bearing
	# Mounting saddle on top, where the pylon lands.
	add_box(bm, (0, 0.190, 0.170), (0.150, 0.240, 0.060), bevel=0.010)
	export_bmesh(bm, "be_engine_block", "be_engine_block.glb",
				 color=(0.26, 0.27, 0.29, 1.0), metallic=0.72, roughness=0.44)


# ---------------------------------------------------------------------------
# HOVER SKIRT - was 92 triangles: a plain ring.
# Authored around the origin, Z up, per _build_hover_engine().
# ---------------------------------------------------------------------------
def build_hover_skirt():
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.045), 0.290, 0.045, segments=26)              # mounting ring
	for i in range(12):
		a = (i / 12) * math.tau
		add_cyl_z(bm, (math.cos(a) * 0.278, math.sin(a) * 0.278, 0.058), 0.012, 0.028, segments=6)
	add_taper_z(bm, (0, 0, -0.020), 0.290, 0.325, 0.085, segments=26)    # flare
	add_cyl_z(bm, (0, 0, -0.080), 0.325, 0.045, segments=26)             # bulge
	add_taper_z(bm, (0, 0, -0.130), 0.325, 0.270, 0.055, segments=26)    # hem
	# Segmented fingers around the hem - the cue that this is a flexible bag
	# rather than a machined ring.
	for i in range(16):
		a = (i / 16) * math.tau
		cx, cy = math.cos(a) * 0.300, math.sin(a) * 0.300
		add_box(bm, (cx, cy, -0.130), (0.062, 0.062, 0.080), bevel=0.012)
		add_box(bm, (cx * 1.02, cy * 1.02, -0.175), (0.052, 0.052, 0.030), bevel=0.008)
	export_bmesh(bm, "hover_skirt", "hover_skirt.glb",
				 color=(0.24, 0.24, 0.22, 1.0), metallic=0.12, roughness=0.88)


# ---------------------------------------------------------------------------
# NAVAL PROPELLER - was 120 triangles: flat paddles.
# Authored with the shaft along Blender Y, per _build_pylon_mounted_propeller().
# ---------------------------------------------------------------------------
def build_naval_propeller():
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0, 0), 0.105, 0.130, segments=20)                  # hub
	_cone(bm, (0, 0.090, 0), 0.045, 0.105, 0.060, 20,
		  mathutils.Matrix.Rotation(math.radians(90), 4, 'X'))            # fairwater cone
	add_cyl_y(bm, (0, -0.075, 0), 0.078, 0.045, segments=20)              # shaft collar
	# Four skewed, cambered blades built as swept strips - a real screw blade
	# twists from a coarse root to a fine tip and rakes backward.
	blades = 4
	for b in range(blades):
		base_a = (b / blades) * math.tau
		steps = 9
		for i in range(steps):
			t = i / float(steps - 1)
			r = 0.095 + t * 0.235
			skew = base_a + t * 0.55
			pitch = math.radians(52.0 - 30.0 * t)
			chord = 0.150 * (1.0 - 0.30 * t) * (0.55 + 0.45 * math.sin(math.pi * min(1.0, t + 0.25)))
			thick = 0.026 * (1.0 - 0.62 * t)
			cx, cz = math.cos(skew) * r, math.sin(skew) * r
			loc = mathutils.Vector((cx, -t * 0.045, cz))
			rot = (mathutils.Matrix.Rotation(skew, 4, 'Y')
				   @ mathutils.Matrix.Rotation(pitch, 4, 'Z'))
			res = bmesh.ops.create_cube(bm, size=1.0)
			for v in res['verts']:
				v.co = loc + rot @ mathutils.Vector((
					v.co.x * 0.048, v.co.y * chord, v.co.z * thick))
	export_bmesh(bm, "naval_propeller", "naval_propeller.glb",
				 color=(0.55, 0.42, 0.22, 1.0), metallic=0.85, roughness=0.30)


# ---------------------------------------------------------------------------
# TRACK BELT + DRIVE SPROCKET
#
# tread_belt_loop was 224 triangles for a 2.9-unit belt: a smooth, featureless
# ring. A track's entire visual identity is its LINKS - the repeating plates,
# the grousers biting the ground, the guide horns running between the road
# wheels - and none of it was there. drive_sprocket had no teeth to speak of, so
# nothing explained how the belt was driven.
#
# The authored axes are load-bearing and preserved exactly:
#   tread_belt_loop  Godot X=width, Y=height, Z=length  (0.300 x 1.300 x 2.900)
#   drive_sprocket   Godot X/Z=disc, Y=width
# Blender +Y imports as Godot -Z, so the belt is built as a stadium in Blender's
# YZ plane and extruded across X.
# ---------------------------------------------------------------------------
def _track_path(half_span, r_drive, road_drop, r_road, arc_steps=14):
	"""The belt centreline, with ends that ACTUALLY WRAP THE SPROCKETS.

	The previous version listed hand-picked waypoints including a "nose" at
	half_span + r_drive * 0.45. That is not a point on a circle of radius r_drive
	around the sprocket centre - it traced a shallow polygonal end roughly 0.21
	from the axle while the sprocket itself was 0.46, so the sprocket punched
	straight through the belt. Measured, not guessed: sprocket half-size 0.505
	against a belt end reach of 0.28.

	The ends are now real arcs sampled around the sprocket and idler centres, so
	the belt wraps them by construction at any scale. The trapezoid comes from
	the bottom run sitting on the road-wheel line, well below the axle line, with
	tangential runs down to it at each end.

	Returned as a closed polyline of (y, z) in Blender's fore/aft-up plane.
	"""
	bot = -(road_drop + r_road)
	# Where the belt leaves each end arc to run down to the road-wheel line.
	leave = math.radians(212.0)
	pts = []
	# Top run, rear to front, along the top of both wheels.
	pts.append((half_span, r_drive))
	pts.append((-half_span, r_drive))
	# Front (idler) arc: over the top, round the nose, down to the leave angle.
	for i in range(1, arc_steps + 1):
		a = math.radians(90.0) + (leave - math.radians(90.0)) * (i / float(arc_steps))
		pts.append((-half_span + math.cos(a) * r_drive, math.sin(a) * r_drive))
	# Down onto the road-wheel line, then the bottom run.
	pts.append((-half_span * 0.78, bot))
	pts.append((half_span * 0.78, bot))
	# Rear (sprocket) arc: up from the road line, round the tail, back to the top.
	enter = math.radians(-32.0)
	for i in range(arc_steps + 1):
		a = enter + (math.radians(90.0) - enter) * (i / float(arc_steps))
		pts.append((half_span + math.cos(a) * r_drive, math.sin(a) * r_drive))
	return pts


def _resample_closed(points, spacing):
	"""Walk a closed polyline at a CONSTANT arc-length step.

	This is the other half of Chris's report - "most of the tread links aren't
	actually touching or connected". The first pass emitted one link per waypoint
	and sized them from an average circumference, so on the straight runs the
	waypoints were far apart and the links floated with gaps between them, while
	round the ends they overlapped. Stepping by arc length instead means every
	link is the same distance from its neighbour, so sizing each to exactly that
	step makes the belt continuous by construction.

	Yields (y, z, tangent_angle, step) tuples.
	"""
	n = len(points)
	segs = []
	total = 0.0
	for i in range(n):
		a = mathutils.Vector(points[i])
		b = mathutils.Vector(points[(i + 1) % n])
		d = (b - a).length
		if d > 1e-6:
			segs.append((a, b, d))
			total += d
	count = max(8, int(round(total / spacing)))
	step = total / count
	out = []
	seg_i = 0
	seg_pos = 0.0
	for _k in range(count):
		while seg_pos > segs[seg_i][2]:
			seg_pos -= segs[seg_i][2]
			seg_i = (seg_i + 1) % len(segs)
		a, b, d = segs[seg_i]
		t = seg_pos / d
		p = a.lerp(b, t)
		ang = math.atan2(b.y - a.y, b.x - a.x)
		out.append((p.x, p.y, ang, step))
		seg_pos += step
	return out


def build_tread_belt_loop():
	# ASPECT. Authored 2.6 half-span against a 0.46 sprocket - about 6:1 overall,
	# which is roughly a real hull's proportions. It used to be 1.0 half-span,
	# i.e. 2.75:1, and once the track group was scaled UNIFORMLY (so the belt
	# would actually wrap the sprockets rather than cut through them) that short
	# aspect meant scaling to a 6:1 hull's length blew the sprockets up to nearly
	# hull height. A track is long and low; authoring it that way is what lets one
	# uniform scale serve both the wrap and the proportions.
	half_span = 2.6
	# Chris: the trapezoid should be MORE pronounced. The drop from the sprocket
	# centreline down to the road-wheel line is what makes the shape read, so it
	# goes 0.20 -> 0.38 while the road wheels shrink slightly - a bigger
	# difference between the raised drive wheels and the low road wheels, which
	# is the whole silhouette.
	r_drive = 0.46
	r_road = 0.22
	road_drop = 0.38
	width = 0.30
	bm = bmesh.new()
	path = _resample_closed(_track_path(half_span, r_drive, road_drop, r_road), 0.125)
	for (y, z, ang, step) in path:
		rot = mathutils.Matrix.Rotation(ang, 4, 'X')
		centre = mathutils.Vector((0, y, z))
		# Link plate sized to EXACTLY the sampling step (plus a hair of overlap)
		# so consecutive links meet rather than leaving a gap.
		res = bmesh.ops.create_cube(bm, size=1.0)
		for v in res['verts']:
			v.co = centre + rot @ mathutils.Vector(
				(v.co.x * width, v.co.y * step * 1.04, v.co.z * 0.055))
		# Grouser on the outer face, and a guide horn on the inner one.
		outward = mathutils.Vector((0, y, z))
		outward = outward.normalized() if outward.length > 1e-5 else mathutils.Vector((0, 0, -1))
		res2 = bmesh.ops.create_cube(bm, size=1.0)
		for v in res2['verts']:
			v.co = (centre + outward * 0.048) + rot @ mathutils.Vector(
				(v.co.x * width * 0.84, v.co.y * step * 0.46, v.co.z * 0.052))
		res3 = bmesh.ops.create_cube(bm, size=1.0)
		for v in res3['verts']:
			v.co = (centre - outward * 0.050) + rot @ mathutils.Vector(
				(v.co.x * 0.055, v.co.y * step * 0.40, v.co.z * 0.070))
		# Pin bosses at the link edges - what the links actually hinge on.
		for sx in (-1, 1):
			add_cyl_x(bm, (sx * width * 0.42, y, z), 0.020, 0.028, segments=6)
	export_bmesh(bm, "tread_belt_loop", "tread_belt_loop.glb",
				 color=(0.16, 0.16, 0.17, 1.0), metallic=0.55, roughness=0.62)


def build_drive_sprocket():
	"""Drive sprocket. AXLE ALONG BLENDER Z.

	The axis matters and I got it wrong: the runtime applies rotation.z = PI/2 to
	each sprocket, which maps the part's local Y onto X (across the vehicle). The
	original was authored with its axle on Blender Z (importing as Godot Y), so
	that rotation stood it up correctly. Rebuilding it on Blender Y put the axle
	on Godot Z, and the rotation then left it there - the sprockets rendered
	SIDEWAYS, facing along the vehicle instead of across it (Chris's report).

	The teeth are also no longer free-floating blocks. Each starts INSIDE the rim
	and extends outward through it, so it reads as an extension of the hub rather
	than a separate object parked next to one.
	"""
	radius = 0.40
	width = 0.30
	teeth = 11
	bm = bmesh.new()
	# Hub, web and rim - one stack on the same axis, overlapping so they fuse.
	add_cyl_z(bm, (0, 0, 0), radius * 0.30, width * 1.25, segments=18)      # hub
	add_cyl_z(bm, (0, 0, 0), radius * 0.66, width * 0.70, segments=24)      # web
	add_cyl_z(bm, (0, 0, 0), radius * 0.86, width, segments=26)             # rim
	for sz in (-1, 1):                                                       # rim flanges
		add_cyl_z(bm, (0, 0, sz * width * 0.44), radius * 0.92, width * 0.12, segments=26)

	for i in range(teeth):
		a = (i / teeth) * math.tau
		ca, sa = math.cos(a), math.sin(a)
		# Root starts at 0.78r - well inside the 0.86r rim - and reaches to
		# 1.06r, so the tooth is continuous with the rim it grows out of.
		root_r, tip_r = radius * 0.78, radius * 1.06
		mid_r = (root_r + tip_r) * 0.5
		res = bmesh.ops.create_cube(bm, size=1.0)
		rot = mathutils.Matrix.Rotation(a, 4, 'Z')
		for v in res['verts']:
			v.co = mathutils.Vector((ca * mid_r, sa * mid_r, 0)) + rot @ mathutils.Vector(
				(v.co.x * (tip_r - root_r), v.co.y * 0.085, v.co.z * width * 0.86))
		# Chamfered tip, so the tooth engages a link rather than butting it.
		res2 = bmesh.ops.create_cube(bm, size=1.0)
		for v in res2['verts']:
			v.co = mathutils.Vector((ca * tip_r, sa * tip_r, 0)) + rot @ mathutils.Vector(
				(v.co.x * 0.055, v.co.y * 0.055, v.co.z * width * 0.62))

	for i in range(6):                                                       # lightening holes
		a = (i / 6) * math.tau
		add_cyl_z(bm, (math.cos(a) * radius * 0.47, math.sin(a) * radius * 0.47, 0),
				  0.050, width * 1.10, segments=10)
	for i in range(8):                                                       # hub bolts
		a = (i / 8) * math.tau
		add_cyl_z(bm, (math.cos(a) * radius * 0.20, math.sin(a) * radius * 0.20,
					   width * 0.60), 0.016, 0.030, segments=6)
	export_bmesh(bm, "drive_sprocket", "drive_sprocket.glb",
				 color=(0.19, 0.19, 0.21, 1.0), metallic=0.78, roughness=0.40)


if __name__ == "__main__":
	clear_scene()
	build_screw_drum("screw_drum", fin_reach=0.185, turns=3.2)
	build_screw_drum("screw_drum_shallow", fin_reach=0.115, turns=2.4,
					 color=(0.33, 0.31, 0.27, 1.0))
	build_screw_drum("screw_drum_deep", fin_reach=0.265, turns=4.0,
					 color=(0.37, 0.33, 0.28, 1.0))
	build_rotor_blade()
	build_leg_foot()
	build_leg_thigh()
	build_leg_shin()
	build_ht_track_bogie()
	build_acs_skirt()
	build_be_nose_cone()
	build_be_engine_block()
	build_hover_skirt()
	build_naval_propeller()
	build_tread_belt_loop()
	build_drive_sprocket()
	print("LOCOMOTION_REWORK_PARTS_DONE")
