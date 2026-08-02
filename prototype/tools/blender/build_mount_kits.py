import bpy
import bmesh
import math
import os
import mathutils

# MOUNT KITS - the structural interface between a hull and its running gear.
#
# WHY THIS EXISTS
# ---------------------------------------------------------------------------
# Locomotion had no mounting CONVENTION. Every type improvised its own way of
# attaching to the hull - rotors grew a pylon, screws grew a cradle, legs grew a
# hip, wheels grew a gearbox column - so there was nothing for a new type to be
# consistent with, and nothing shared to improve. When a generic ladder-frame
# chassis was tried underneath all of it, the frame and the improvised mounts
# fought each other visually, because two different answers to the same question
# were being drawn at once.
#
# The weapons roster solved the identical problem with a convention rather than
# a part: mount at deck level, origin at the trunnion, anything a tweak stretches
# is its own part. This is the locomotion equivalent - a small vocabulary of
# structural archetypes, authored once, that every type draws from.
#
# THE FIVE KITS
#   SUSPENSION_ARM  swing arm + coil-over + hub carrier   wheels, half_track,
#                                                         rocker_bogie, pontoons
#   TRACK_FRAME     side frame, bearing stations, final   tracked_treads,
#                   drive                                 screw_drive
#   STRUT_LEG       vertical blade, hull flange, actuator  legs, hydrofoil
#   PYLON           tapered strut to a nacelle collar      rotors, fixed_wing,
#                                                         props, water_jet
#   HARDPOINT_PAD   flush pad, standoffs, conduit          hover, air cushion,
#                                                         anti-grav
#
# Five and not one because Chris is right that "not everything makes sense with
# just some axles n springs slapped there" - a hover pad and a road wheel need
# structurally different answers. But each answer is now the SAME everywhere it
# is used, which is what makes it a system rather than a pile of one-offs.
#
# CONVENTIONS (strict - the runtime relies on all four)
#   1. ORIGIN is the ATTACHMENT POINT: where the kit meets the hull or chassis.
#      A kit is positioned by putting its origin on the mount station, nothing
#      else.
#   2. Blender -Z is DOWN toward the running gear (-> Godot -Y).
#   3. Blender +X is OUTBOARD on the starboard side (-> Godot +X). Port-side
#      instances are mirrored by the runtime, not authored twice.
#   4. Blender +Y is FORWARD (-> Godot -Z).
#
# Anything a tweak stretches is its own part, so a slider never smears a spring
# coil or a bolt head.

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


def bolt_ring_z(bm, z, radius, count=6, bolt_r=0.010, bolt_len=0.018):
	for i in range(count):
		a = (i / count) * math.tau
		add_cyl_z(bm, (math.cos(a) * radius, math.sin(a) * radius, z), bolt_r, bolt_len, segments=6)


def add_coil(bm, base, radius, length, turns, wire_r, segs_per_turn=14, minor=6):
	"""A real helical spring, swept rather than stacked.

	The same lesson as the screw drum: a spring drawn as a stack of separate
	rings costs more geometry than sweeping one and still reads as a stack. This
	bridges consecutive rings into a continuous tube.
	"""
	total = int(turns * segs_per_turn)
	rings = []
	for i in range(total + 1):
		t = i / float(total)
		a = t * turns * math.tau
		h = base[2] + t * length
		centre = mathutils.Vector((base[0] + math.cos(a) * radius,
								   base[1] + math.sin(a) * radius, h))
		tangent = mathutils.Vector((-math.sin(a) * radius, math.cos(a) * radius,
									length / (turns * math.tau))).normalized()
		up = mathutils.Vector((0, 0, 1))
		if abs(tangent.dot(up)) > 0.95:
			up = mathutils.Vector((1, 0, 0))
		n1 = tangent.cross(up).normalized()
		n2 = tangent.cross(n1).normalized()
		ring = []
		for j in range(minor):
			b = (j / minor) * math.tau
			off = n1 * (math.cos(b) * wire_r) + n2 * (math.sin(b) * wire_r)
			ring.append(bm.verts.new(centre + off))
		rings.append(ring)
	for i in range(total):
		for j in range(minor):
			k = (j + 1) % minor
			try:
				bm.faces.new((rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]))
			except ValueError:
				pass


def export_bmesh(bm, object_name, filename, color=(0.26, 0.27, 0.29, 1.0),
				 metallic=0.72, roughness=0.44):
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
		obj.data.auto_smooth_angle = math.radians(38)
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
# KIT 1 - SUSPENSION ARM
# Origin at the chassis anchor. Arm swings outboard (+X) and down (-Z) to a hub
# carrier; a coil-over ties the arm back up to the anchor.
# ---------------------------------------------------------------------------
def build_suspension_kit():
	# 1A. Anchor bracket - the part that actually touches the hull.
	bm = bmesh.new()
	add_box(bm, (0, 0, -0.045), (0.150, 0.300, 0.090), bevel=0.012)
	add_box(bm, (0, 0, 0.010), (0.185, 0.340, 0.028), bevel=0.008)        # flange
	for by in (-1, 1):
		for bx in (-1, 1):
			add_cyl_z(bm, (bx * 0.062, by * 0.128, 0.030), 0.014, 0.030, segments=6)
	# Twin shear plates the arm pivots between.
	for sy in (-1, 1):
		add_box(bm, (0.055, sy * 0.105, -0.105), (0.145, 0.036, 0.140), bevel=0.008)
	add_cyl_y(bm, (0.105, 0, -0.150), 0.030, 0.250, segments=14)          # pivot pin
	add_cyl_y(bm, (0.105, 0.128, -0.150), 0.042, 0.020, segments=12)      # pin collar
	add_cyl_y(bm, (0.105, -0.128, -0.150), 0.042, 0.020, segments=12)
	export_bmesh(bm, "mk_susp_anchor", "mk_susp_anchor.glb",
				 color=(0.24, 0.25, 0.27, 1.0), metallic=0.74, roughness=0.42)

	# 1B. Swing arm - an A-arm reaching outboard and down to the hub.
	bm = bmesh.new()
	for sy in (-1, 1):
		add_tube_between(bm, (0.0, sy * 0.105, 0.0), (0.330, sy * 0.048, -0.170), 0.032, segments=10)
	add_box(bm, (0.345, 0, -0.178), (0.090, 0.150, 0.105), bevel=0.012)   # hub yoke
	add_box(bm, (0.165, 0, -0.090), (0.180, 0.040, 0.048), bevel=0.006)   # web
	add_cyl_y(bm, (0.0, 0, 0.0), 0.036, 0.250, segments=12)               # pivot bore
	add_box(bm, (0.215, 0, -0.052), (0.070, 0.070, 0.055), bevel=0.008)   # damper eye
	add_cyl_y(bm, (0.215, 0, -0.030), 0.024, 0.100, segments=10)
	export_bmesh(bm, "mk_susp_arm", "mk_susp_arm.glb",
				 color=(0.28, 0.29, 0.31, 1.0), metallic=0.76, roughness=0.40)

	# 1C. Coil-over damper - a real swept spring around a shock body.
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, -0.050), 0.038, 0.230, segments=14)              # shock body
	add_cyl_z(bm, (0, 0, 0.085), 0.026, 0.130, segments=12)               # piston rod
	add_cyl_z(bm, (0, 0, 0.155), 0.055, 0.030, segments=14)               # top mount
	add_cyl_z(bm, (0, 0, -0.175), 0.060, 0.030, segments=14)              # lower seat
	add_cyl_z(bm, (0, 0, 0.128), 0.062, 0.026, segments=14)               # upper seat
	add_coil(bm, (0, 0, -0.165), 0.072, 0.290, 6.0, 0.017)
	add_box(bm, (0, 0, 0.180), (0.075, 0.055, 0.040), bevel=0.008)        # eye bracket
	add_cyl_y(bm, (0, 0, 0.180), 0.020, 0.080, segments=10)
	export_bmesh(bm, "mk_susp_spring", "mk_susp_spring.glb",
				 color=(0.34, 0.30, 0.26, 1.0), metallic=0.68, roughness=0.48)

	# 1D. Hub carrier - what the wheel/pontoon actually bolts to.
	bm = bmesh.new()
	add_box(bm, (0, 0, 0), (0.105, 0.145, 0.175), bevel=0.014)
	add_cyl_x(bm, (0.075, 0, 0), 0.075, 0.075, segments=16)               # bearing boss
	add_cyl_x(bm, (0.120, 0, 0), 0.052, 0.030, segments=14)               # stub
	for i in range(5):
		a = (i / 5) * math.tau
		add_cyl_x(bm, (0.132, math.cos(a) * 0.036, math.sin(a) * 0.036), 0.009, 0.030, segments=6)
	add_box(bm, (-0.045, 0, 0.095), (0.075, 0.110, 0.048), bevel=0.008)   # upper link eye
	add_cyl_y(bm, (-0.045, 0, 0.095), 0.020, 0.130, segments=10)
	add_box(bm, (-0.020, 0.075, -0.060), (0.055, 0.030, 0.070), bevel=0.006)  # brake caliper
	export_bmesh(bm, "mk_susp_hub", "mk_susp_hub.glb",
				 color=(0.26, 0.27, 0.28, 1.0), metallic=0.78, roughness=0.36)


# ---------------------------------------------------------------------------
# KIT 2 - TRACK FRAME
# Origin at the chassis face. A rigid side frame running fore/aft, with bearing
# stations and a final drive housing.
# ---------------------------------------------------------------------------
def build_track_frame_kit():
	# 2A. Side frame beam - authored one unit long on Y so the runtime stretches
	#     it to the hull, and nothing else with it.
	bm = bmesh.new()
	add_box(bm, (0.055, 0, -0.130), (0.110, 1.0, 0.185), bevel=0.012)
	add_box(bm, (0.055, 0, -0.028), (0.140, 1.0, 0.036), bevel=0.008)     # top flange
	add_box(bm, (0.055, 0, -0.230), (0.140, 1.0, 0.032), bevel=0.008)     # bottom flange
	export_bmesh(bm, "mk_track_frame", "mk_track_frame.glb",
				 color=(0.24, 0.25, 0.24, 1.0), metallic=0.74, roughness=0.46)

	# 2B. Bearing station - repeated along the frame; carries a road wheel axle.
	bm = bmesh.new()
	add_box(bm, (0.055, 0, -0.135), (0.135, 0.150, 0.190), bevel=0.010)
	add_cyl_x(bm, (0.135, 0, -0.170), 0.062, 0.085, segments=16)          # axle boss
	add_cyl_x(bm, (0.180, 0, -0.170), 0.036, 0.030, segments=12)
	for i in range(6):
		a = (i / 6) * math.tau
		add_cyl_x(bm, (0.150, math.cos(a) * 0.042, -0.170 + math.sin(a) * 0.042),
				  0.008, 0.028, segments=6)
	add_box(bm, (0.030, 0, 0.005), (0.100, 0.130, 0.045), bevel=0.008)    # chassis pad
	add_tube_between(bm, (0.055, 0.050, -0.030), (0.055, 0.050, -0.130), 0.014, segments=6)
	export_bmesh(bm, "mk_track_bearing", "mk_track_bearing.glb",
				 color=(0.27, 0.28, 0.28, 1.0), metallic=0.76, roughness=0.40)

	# 2C. Final drive - the reason the track turns at all.
	bm = bmesh.new()
	add_cyl_x(bm, (0.090, 0, 0), 0.165, 0.180, segments=20)
	add_cyl_x(bm, (0.185, 0, 0), 0.105, 0.055, segments=18)
	for i in range(8):
		a = (i / 8) * math.tau
		add_cyl_x(bm, (0.200, math.cos(a) * 0.072, math.sin(a) * 0.072), 0.012, 0.030, segments=6)
	add_box(bm, (0.010, 0, 0.060), (0.120, 0.230, 0.180), bevel=0.012)    # housing
	add_cyl_z(bm, (0.010, 0, 0.170), 0.052, 0.070, segments=12)           # input shaft
	add_box(bm, (0.010, -0.130, 0.020), (0.100, 0.060, 0.120), bevel=0.008)  # brake pack
	for i in range(4):
		add_box(bm, (0.010, -0.150, -0.020 + i * 0.038), (0.110, 0.020, 0.018), bevel=0.003)
	export_bmesh(bm, "mk_track_finaldrive", "mk_track_finaldrive.glb",
				 color=(0.25, 0.26, 0.26, 1.0), metallic=0.78, roughness=0.38)


# ---------------------------------------------------------------------------
# KIT 3 - STRUT LEG
# Origin at the hull flange. A vertical blade reaching down, with an actuator.
# ---------------------------------------------------------------------------
def build_strut_leg_kit():
	# 3A. Hull flange - the bolted interface.
	bm = bmesh.new()
	add_box(bm, (0, 0, -0.028), (0.300, 0.360, 0.055), bevel=0.010)
	add_box(bm, (0, 0, -0.080), (0.220, 0.270, 0.055), bevel=0.010)
	for bx in (-1, 1):
		for by in (-1, 1):
			add_cyl_z(bm, (bx * 0.118, by * 0.148, 0.008), 0.016, 0.032, segments=6)
	add_cyl_z(bm, (0, 0, -0.120), 0.095, 0.055, segments=16)              # socket
	export_bmesh(bm, "mk_strut_flange", "mk_strut_flange.glb",
				 color=(0.25, 0.26, 0.28, 1.0), metallic=0.74, roughness=0.42)

	# 3B. Blade - authored one unit tall on Z so strut_height stretches only it.
	bm = bmesh.new()
	add_box(bm, (0, 0, -0.5), (0.080, 0.230, 1.0), bevel=0.010)
	add_box(bm, (0, 0.128, -0.5), (0.045, 0.045, 1.0), bevel=0.008)       # leading edge
	add_box(bm, (0, -0.132, -0.5), (0.038, 0.040, 1.0), bevel=0.006)      # trailing edge
	export_bmesh(bm, "mk_strut_blade", "mk_strut_blade.glb",
				 color=(0.27, 0.29, 0.31, 1.0), metallic=0.78, roughness=0.34)

	# 3C. Actuator - what articulates or retracts it.
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, -0.115), 0.048, 0.230, segments=14)
	add_cyl_z(bm, (0, 0, -0.290), 0.030, 0.140, segments=12)              # ram
	add_cyl_z(bm, (0, 0, -0.370), 0.048, 0.030, segments=12)              # rod eye
	add_cyl_y(bm, (0, 0, -0.370), 0.018, 0.090, segments=10)
	add_box(bm, (0, 0, 0.010), (0.100, 0.075, 0.045), bevel=0.008)        # top mount
	add_cyl_y(bm, (0, 0, 0.010), 0.020, 0.110, segments=10)
	for i in range(3):                                                     # hydraulic lines
		add_tube_between(bm, (0.045, 0.030, -0.030 - i * 0.045),
						 (0.045, 0.030, -0.190 - i * 0.020), 0.010, segments=6)
	export_bmesh(bm, "mk_strut_actuator", "mk_strut_actuator.glb",
				 color=(0.30, 0.28, 0.24, 1.0), metallic=0.70, roughness=0.44)


# ---------------------------------------------------------------------------
# KIT 4 - PYLON
# Origin at the hull skin. A tapered strut reaching out to a nacelle collar.
# ---------------------------------------------------------------------------
def build_pylon_kit():
	# 4A. Root fairing - where the pylon meets the hull.
	bm = bmesh.new()
	add_box(bm, (0, 0, -0.020), (0.190, 0.420, 0.070), bevel=0.014)
	add_box(bm, (0, 0.170, -0.020), (0.120, 0.110, 0.060), bevel=0.020)   # forward fairing
	add_box(bm, (0, -0.180, -0.020), (0.110, 0.100, 0.055), bevel=0.020)  # aft fairing
	for by in (-1, 1):
		for bx in (-1, 1):
			add_cyl_z(bm, (bx * 0.070, by * 0.160, 0.018), 0.013, 0.028, segments=6)
	export_bmesh(bm, "mk_pylon_root", "mk_pylon_root.glb",
				 color=(0.26, 0.27, 0.30, 1.0), metallic=0.74, roughness=0.40)

	# 4B. Strut - authored one unit long on Z, tapering away from the hull, so
	#     the runtime stretches reach without fattening the ends.
	bm = bmesh.new()
	steps = 8
	for i in range(steps):
		t = i / float(steps - 1)
		w = 0.105 * (1.0 - 0.42 * t)
		c = 0.230 * (1.0 - 0.30 * t)
		add_box(bm, (0, 0, -t), (w, c, 1.05 / steps), bevel=0.006)
	export_bmesh(bm, "mk_pylon_strut", "mk_pylon_strut.glb",
				 color=(0.28, 0.29, 0.32, 1.0), metallic=0.78, roughness=0.34)

	# 4C. Nacelle collar - the clamp at the far end.
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0), 0.135, 0.075, segments=20)
	add_cyl_z(bm, (0, 0, 0.048), 0.150, 0.024, segments=20)
	add_cyl_z(bm, (0, 0, -0.048), 0.150, 0.024, segments=20)
	for i in range(6):
		a = (i / 6) * math.tau
		add_box(bm, (math.cos(a) * 0.142, math.sin(a) * 0.142, 0),
				(0.034, 0.034, 0.090), bevel=0.006)
	add_box(bm, (0, 0, 0.078), (0.110, 0.090, 0.040), bevel=0.008)        # strut socket
	export_bmesh(bm, "mk_pylon_collar", "mk_pylon_collar.glb",
				 color=(0.25, 0.26, 0.29, 1.0), metallic=0.80, roughness=0.32)


# ---------------------------------------------------------------------------
# KIT 5 - HARDPOINT PAD
# Origin at the hull skin. A flush pad on standoffs, with a conduit.
# ---------------------------------------------------------------------------
def build_hardpoint_pad_kit():
	# 5A. Pad plate - the flush interface the emitter sits on.
	bm = bmesh.new()
	add_box(bm, (0, 0, -0.030), (0.420, 0.420, 0.060), bevel=0.016)
	add_box(bm, (0, 0, 0.006), (0.330, 0.330, 0.026), bevel=0.010)
	for i in range(8):
		a = (i / 8) * math.tau
		add_cyl_z(bm, (math.cos(a) * 0.172, math.sin(a) * 0.172, 0.012), 0.016, 0.034, segments=6)
	add_cyl_z(bm, (0, 0, -0.070), 0.185, 0.030, segments=20)              # register boss
	export_bmesh(bm, "mk_pad_plate", "mk_pad_plate.glb",
				 color=(0.26, 0.28, 0.30, 1.0), metallic=0.72, roughness=0.44)

	# 5B. Standoff - repeated around the pad to hold the emitter clear.
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, -0.090), 0.042, 0.180, segments=12)
	add_cyl_z(bm, (0, 0, -0.005), 0.062, 0.030, segments=12)
	add_cyl_z(bm, (0, 0, -0.180), 0.058, 0.030, segments=12)
	add_taper_z(bm, (0, 0, -0.205), 0.058, 0.038, 0.024, segments=12)
	export_bmesh(bm, "mk_pad_standoff", "mk_pad_standoff.glb",
				 color=(0.24, 0.25, 0.27, 1.0), metallic=0.80, roughness=0.34)

	# 5C. Conduit - the power feed, so the pad is visibly connected to something.
	bm = bmesh.new()
	add_box(bm, (0, 0, -0.020), (0.115, 0.115, 0.050), bevel=0.010)       # gland box
	add_cyl_z(bm, (0, 0, -0.060), 0.042, 0.060, segments=12)
	add_tube_between(bm, (0, 0, -0.085), (0, -0.140, -0.230), 0.030, segments=10)
	for i in range(4):                                                     # armour bands
		t = (i + 1) / 5.0
		p = mathutils.Vector((0, -0.140 * t, -0.085 - 0.145 * t))
		add_cyl_z(bm, (p.x, p.y, p.z), 0.038, 0.016, segments=10)
	add_cyl_z(bm, (0, -0.140, -0.245), 0.048, 0.030, segments=12)         # lower gland
	export_bmesh(bm, "mk_pad_conduit", "mk_pad_conduit.glb",
				 color=(0.30, 0.27, 0.22, 1.0), metallic=0.66, roughness=0.52)


if __name__ == "__main__":
	clear_scene()
	build_suspension_kit()
	build_track_frame_kit()
	build_strut_leg_kit()
	build_pylon_kit()
	build_hardpoint_pad_kit()
	print("MOUNT_KIT_PARTS_DONE")
