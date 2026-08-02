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
	# Conical noses: pointed at the outer ends like a real auger, widening back
	# into the drum.
	add_taper_y(bm, (0, -length * 0.50, 0), shaft_r, 0.028, length * 0.14, segments=24)
	add_taper_y(bm, (0, length * 0.50, 0), 0.028, shaft_r, length * 0.14, segments=24)
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
def _track_path(half_span, r_drive, road_drop, r_road):
	"""The belt centreline as a real TRACK profile, not a stadium.

	Chris: the treads want "that overall trapezoidal shape of the road wheels
	being lower than the drive wheels". A constant-radius stadium - which is what
	the first pass built - gives an oval, and an oval is what a conveyor looks
	like, not a tracked vehicle. On a real track the sprocket and idler are
	raised and the road wheels ride lower between them, so the silhouette is a
	trapezoid: a high flat top run, a low flat bottom run, and angled runs at
	each end.

	Returned as a closed polyline of (y, z) waypoints in Blender's fore/aft-up
	plane. Corner rounding and uniform spacing are applied by _resample_closed().
	"""
	top = r_drive
	bot = -(road_drop + r_road)
	nose = half_span + r_drive * 0.45
	return [
		(half_span * 0.94, top),                 # top run, rear end
		(-half_span * 0.94, top),                # top run, front end
		(-nose, top * 0.30),                     # over the idler
		(-nose * 0.94, bot * 0.72),              # down the front face
		(-half_span * 0.80, bot),                # onto the road-wheel line
		(half_span * 0.80, bot),                 # bottom run
		(nose * 0.94, bot * 0.72),               # up the rear face
		(nose, top * 0.30),                      # over the sprocket
	]


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
	half_span = 1.0
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
	path = _resample_closed(_track_path(half_span, r_drive, road_drop, r_road), 0.115)
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
	build_hover_skirt()
	build_naval_propeller()
	build_tread_belt_loop()
	build_drive_sprocket()
	print("LOCOMOTION_REWORK_PARTS_DONE")
