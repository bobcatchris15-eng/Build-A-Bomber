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
	print("LOCOMOTION_REWORK_PARTS_DONE")
