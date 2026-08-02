import bpy
import bmesh
import math
import os
import mathutils

# Authored parts for the seven locomotion types added in
# LOCOMOTION_EXPANSION_PLAN.md 4:
#
#   GROUND       half_track, rocker_bogie
#   HOVER        air_cushion_skirt, anti_grav_plate
#   NAVAL        hydrofoil, water_jet
#   AMPHIBIOUS   pontoon_wheels
#
# CONVENTIONS (the roster's)
#   - Blender +Y is FORWARD (Godot -Z), +Z is UP.
#   - A locomotion part's origin is its MOUNT POINT - the place it attaches to
#     the hull or the running-gear chassis - so visual_builder can position it
#     from the layout's station without a per-part fudge factor.
#   - Anything a tweak stretches is its OWN part, so a slider never smears a
#     bolt head, a fan blade or a tread link.
#   - Detail level targets the reworked-weapons standard (Chris, 2026-08-01:
#     re-author to higher detail to maintain a throughline), not a triangle
#     budget - the baked-module LOD pass (ff757ef) already handles distance.

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


def tread_ring(bm, centre, r_front, r_rear, half_span, width, links=22, link_h=0.022):
	"""A closed track belt as a ring of discrete links around two end radii.

	Authored as real links rather than a smooth torus because a track that
	reads as a track is the entire silhouette cue for a half-track - a smooth
	loop reads as a fairing.
	"""
	cx, cy, cz = centre
	for i in range(links):
		t = (i / links) * math.tau
		# Two straight runs joined by two arcs - a stadium, not a circle.
		if math.sin(t) >= 0:
			r = r_front
			oy = half_span
		else:
			r = r_rear
			oy = -half_span
		y = cy + oy * 0.0 + math.cos(t) * (half_span + r * 0.15)
		z = cz + math.sin(t) * r
		ang = math.atan2(math.sin(t) * r, -math.sin(t) * (half_span))
		add_box(bm, (cx, y, z), (width, 0.085, link_h), bevel=0.004)


def export_bmesh(bm, object_name, filename, color=(0.20, 0.22, 0.24, 1.0),
				 metallic=0.75, roughness=0.35):
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


# ---------------------------------------------------------------------------
# HALF-TRACK
# Steered wheels forward, a short track bogie aft. Origin at the chassis
# mounting face, X pointing outboard.
# ---------------------------------------------------------------------------
def build_half_track():
	# Front steered axle unit: wheel, hub, kingpin, fender.
	bm = bmesh.new()
	add_cyl_x(bm, (0.16, 0, 0), 0.235, 0.170, segments=22)              # tyre
	add_cyl_x(bm, (0.16, 0, 0), 0.245, 0.055, segments=22)              # tread band
	for i in range(14):                                                  # tread blocks
		a = (i / 14) * math.tau
		add_box(bm, (0.16, math.cos(a) * 0.246, math.sin(a) * 0.246),
				(0.150, 0.045, 0.030), bevel=0.004)
	add_cyl_x(bm, (0.245, 0, 0), 0.115, 0.040, segments=18)             # hub face
	bolt_ring_x(bm, 0.262, 0.070, count=6, bolt_r=0.014, bolt_len=0.024)
	add_cyl_x(bm, (0.268, 0, 0), 0.038, 0.030, segments=12)             # cap
	add_cyl_x(bm, (0.070, 0, 0), 0.062, 0.150, segments=14)             # stub axle
	add_box(bm, (0.020, 0, 0.020), (0.075, 0.130, 0.150), bevel=0.010)  # kingpin housing
	add_cyl_z(bm, (0.020, 0, 0.130), 0.038, 0.130, segments=12)         # kingpin
	add_box(bm, (0.020, -0.010, 0.215), (0.130, 0.150, 0.045), bevel=0.008)  # steering arm
	add_tube_between(bm, (0.020, 0.075, 0.215), (-0.060, 0.135, 0.215), 0.018, segments=8)
	add_box(bm, (0.150, 0.010, 0.300), (0.230, 0.420, 0.030), bevel=0.006)   # fender
	for side_y in (-0.190, 0.190):                                            # fender stays
		add_tube_between(bm, (0.060, side_y, 0.290), (0.020, side_y, 0.110), 0.014, segments=6)
	export_bmesh(bm, "ht_front_axle", "ht_front_axle.glb",
				 color=(0.24, 0.25, 0.22, 1.0), metallic=0.70, roughness=0.42)

	# The track bogie moved to build_locomotion_rework.py, where _track_path()
	# and _resample_closed() live - its belt ends never wrapped the sprockets,
	# and duplicating that maths here is how the two tracked types drifted
	# apart in the first place. This function now authors the front axle only.


# ---------------------------------------------------------------------------
# ROCKER-BOGIE
# Free-pivoting arms keeping every wheel loaded on broken ground.
# ---------------------------------------------------------------------------
def build_rocker_bogie():
	# Rocker arm: the long primary arm with its differential pivot.
	bm = bmesh.new()
	add_cyl_x(bm, (0.045, 0, 0.30), 0.055, 0.110, segments=14)          # pivot boss
	bolt_ring_x(bm, 0.098, 0.036, count=6, bolt_r=0.009, bolt_len=0.016)
	add_tube_between(bm, (0.070, 0.0, 0.30), (0.070, 0.42, 0.055), 0.036, segments=10)
	add_tube_between(bm, (0.070, 0.0, 0.30), (0.070, -0.30, 0.155), 0.036, segments=10)
	add_box(bm, (0.070, 0.42, 0.030), (0.070, 0.110, 0.075), bevel=0.008)   # fore knuckle
	add_box(bm, (0.070, -0.30, 0.150), (0.070, 0.110, 0.075), bevel=0.008)  # aft knuckle
	add_box(bm, (0.020, 0.02, 0.34), (0.075, 0.190, 0.085), bevel=0.010)    # chassis bracket
	export_bmesh(bm, "rb_rocker_arm", "rb_rocker_arm.glb",
				 color=(0.44, 0.40, 0.32, 1.0), metallic=0.68, roughness=0.44)

	# Bogie arm: the short secondary arm carrying two wheels.
	bm = bmesh.new()
	add_cyl_x(bm, (0.045, 0, 0), 0.045, 0.100, segments=12)
	add_tube_between(bm, (0.065, 0.0, 0.0), (0.065, 0.20, -0.135), 0.030, segments=10)
	add_tube_between(bm, (0.065, 0.0, 0.0), (0.065, -0.20, -0.135), 0.030, segments=10)
	for y in (0.20, -0.20):
		add_box(bm, (0.065, y, -0.135), (0.060, 0.095, 0.065), bevel=0.007)
	export_bmesh(bm, "rb_bogie_arm", "rb_bogie_arm.glb",
				 color=(0.42, 0.38, 0.31, 1.0), metallic=0.68, roughness=0.44)

	# Wheel: open cleated rim - the "drives on rocks" cue.
	bm = bmesh.new()
	add_cyl_x(bm, (0, 0, 0), 0.185, 0.130, segments=20)
	add_cyl_x(bm, (0, 0, 0), 0.196, 0.040, segments=20)
	for i in range(16):                                                  # grousers
		a = (i / 16) * math.tau
		add_box(bm, (0.0, math.cos(a) * 0.198, math.sin(a) * 0.198),
				(0.125, 0.030, 0.026), bevel=0.003)
	for i in range(6):                                                   # spokes
		a = (i / 6) * math.tau
		add_box(bm, (0.058, math.cos(a) * 0.105, math.sin(a) * 0.105),
				(0.022, 0.150, 0.030), bevel=0.003)
	add_cyl_x(bm, (0.070, 0, 0), 0.062, 0.045, segments=14)              # hub + drive can
	add_cyl_x(bm, (0.105, 0, 0), 0.048, 0.060, segments=12)
	export_bmesh(bm, "rb_wheel", "rb_wheel.glb",
				 color=(0.20, 0.20, 0.22, 1.0), metallic=0.60, roughness=0.55)


# ---------------------------------------------------------------------------
# AIR-CUSHION SKIRT
# ---------------------------------------------------------------------------
def build_air_cushion_skirt():
	# Skirt segment: the flexible bag, authored as a bulging finger segment.
	bm = bmesh.new()
	add_taper_z(bm, (0, 0, -0.075), 0.230, 0.185, 0.150, segments=20)
	add_cyl_z(bm, (0, 0, -0.155), 0.215, 0.045, segments=20)             # bulge
	add_taper_z(bm, (0, 0, -0.200), 0.215, 0.170, 0.045, segments=20)    # lower hem
	for i in range(12):                                                   # skirt fingers
		a = (i / 12) * math.tau
		add_box(bm, (math.cos(a) * 0.200, math.sin(a) * 0.200, -0.190),
				(0.055, 0.055, 0.080), bevel=0.010)
	add_cyl_z(bm, (0, 0, 0.010), 0.245, 0.030, segments=20)              # attachment ring
	for i in range(10):
		a = (i / 10) * math.tau
		add_cyl_z(bm, (math.cos(a) * 0.238, math.sin(a) * 0.238, 0.020), 0.011, 0.026, segments=6)
	export_bmesh(bm, "acs_skirt", "acs_skirt.glb",
				 color=(0.28, 0.27, 0.24, 1.0), metallic=0.15, roughness=0.85)

	# Lift fan: a ducted axial fan sitting in the plenum deck.
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0), 0.185, 0.110, segments=22)                  # duct
	add_cyl_z(bm, (0, 0, 0.062), 0.198, 0.026, segments=22)              # inlet lip
	add_cyl_z(bm, (0, 0, -0.062), 0.190, 0.020, segments=22)
	add_cyl_z(bm, (0, 0, 0.010), 0.052, 0.075, segments=14)              # motor can
	for i in range(7):                                                    # blades
		a = (i / 7) * math.tau
		bx, by = math.cos(a), math.sin(a)
		add_box(bm, (bx * 0.115, by * 0.115, 0.010), (0.115, 0.038, 0.016), bevel=0.003)
	for i in range(4):                                                    # stator struts
		a = (i / 4) * math.tau + math.pi / 4.0
		add_box(bm, (math.cos(a) * 0.120, math.sin(a) * 0.120, -0.045),
				(0.120, 0.022, 0.020), bevel=0.003)
	export_bmesh(bm, "acs_lift_fan", "acs_lift_fan.glb",
				 color=(0.30, 0.32, 0.34, 1.0), metallic=0.78, roughness=0.30)


# ---------------------------------------------------------------------------
# ANTI-GRAV PLATE
# ---------------------------------------------------------------------------
def build_anti_grav_plate():
	# Emitter plate: a machined slab with an inset crystal lattice.
	bm = bmesh.new()
	add_box(bm, (0, 0, 0), (0.36, 0.36, 0.070), bevel=0.014)
	add_box(bm, (0, 0, -0.048), (0.30, 0.30, 0.030), bevel=0.008)        # emitter face
	for ix in (-1, 0, 1):                                                 # lattice cells
		for iy in (-1, 0, 1):
			add_box(bm, (ix * 0.088, iy * 0.088, -0.066), (0.062, 0.062, 0.020), bevel=0.004)
	for i in range(4):                                                    # corner posts
		a = (i / 4) * math.tau + math.pi / 4.0
		add_cyl_z(bm, (math.cos(a) * 0.150, math.sin(a) * 0.150, 0.055), 0.028, 0.055, segments=10)
	add_box(bm, (0, 0, 0.078), (0.180, 0.180, 0.032), bevel=0.008)       # coupling block
	add_cyl_z(bm, (0, 0, 0.110), 0.048, 0.045, segments=14)
	export_bmesh(bm, "agp_plate", "agp_plate.glb",
				 color=(0.30, 0.34, 0.40, 1.0), metallic=0.80, roughness=0.25)

	# Stabiliser ring: the optional toroid that steadies the field.
	bm = bmesh.new()
	seg = 28
	for i in range(seg):
		a = (i / seg) * math.tau
		a2 = ((i + 1) / seg) * math.tau
		add_tube_between(bm,
						 (math.cos(a) * 0.285, math.sin(a) * 0.285, 0.0),
						 (math.cos(a2) * 0.285, math.sin(a2) * 0.285, 0.0),
						 0.030, segments=8)
	for i in range(6):                                                    # coil packs
		a = (i / 6) * math.tau
		add_box(bm, (math.cos(a) * 0.285, math.sin(a) * 0.285, 0.0),
				(0.058, 0.058, 0.062), bevel=0.007)
	for i in range(3):                                                    # radial spars
		a = (i / 3) * math.tau
		add_tube_between(bm, (0, 0, 0.0), (math.cos(a) * 0.285, math.sin(a) * 0.285, 0.0),
						 0.018, segments=6)
	export_bmesh(bm, "agp_ring", "agp_ring.glb",
				 color=(0.38, 0.62, 0.78, 1.0), metallic=0.55, roughness=0.22)


# ---------------------------------------------------------------------------
# HYDROFOIL
# ---------------------------------------------------------------------------
def build_hydrofoil():
	# Strut: the vertical blade that carries the foil down into the water.
	bm = bmesh.new()
	add_box(bm, (0, 0, -0.42), (0.075, 0.30, 0.84), bevel=0.012)
	add_taper_y(bm, (0, 0.155, -0.42), 0.038, 0.010, 0.070, segments=12)  # leading fairing
	add_box(bm, (0, -0.170, -0.42), (0.050, 0.055, 0.80), bevel=0.008)    # trailing edge
	add_box(bm, (0, 0, 0.020), (0.155, 0.360, 0.050), bevel=0.010)        # hull flange
	for i in range(6):
		a = (i / 6) * math.tau
		add_cyl_z(bm, (math.cos(a) * 0.055, math.sin(a) * 0.140, 0.045), 0.013, 0.030, segments=6)
	add_cyl_z(bm, (0, 0, -0.86), 0.048, 0.060, segments=14)               # foil saddle
	export_bmesh(bm, "hf_strut", "hf_strut.glb",
				 color=(0.30, 0.42, 0.46, 1.0), metallic=0.78, roughness=0.28)

	# Foil: the lifting surface itself, spanning outboard along X.
	bm = bmesh.new()
	add_box(bm, (0, 0, 0), (0.90, 0.185, 0.040), bevel=0.010)
	add_taper_x(bm, (0.45, 0, 0), 0.040, 0.012, 0.090, segments=12)       # outboard tip
	add_taper_x(bm, (-0.45, 0, 0), 0.012, 0.040, 0.090, segments=12)
	add_box(bm, (0, 0.100, 0.004), (0.88, 0.032, 0.024), bevel=0.006)     # leading edge
	add_box(bm, (0, -0.100, -0.006), (0.86, 0.040, 0.016), bevel=0.005)   # trailing flap
	for side in (-1, 1):                                                   # end plates
		add_box(bm, (side * 0.46, 0, 0.030), (0.020, 0.170, 0.110), bevel=0.006)
	add_box(bm, (0, 0, 0.038), (0.130, 0.150, 0.045), bevel=0.008)        # strut socket
	export_bmesh(bm, "hf_foil", "hf_foil.glb",
				 color=(0.26, 0.38, 0.42, 1.0), metallic=0.82, roughness=0.22)


# ---------------------------------------------------------------------------
# WATER JET
# ---------------------------------------------------------------------------
def build_water_jet():
	# Intake + pump housing, mounted through the hull bottom.
	bm = bmesh.new()
	add_taper_y(bm, (0, -0.150, 0), 0.175, 0.135, 0.300, segments=20)     # pump body
	add_cyl_y(bm, (0, -0.310, 0), 0.185, 0.038, segments=20)              # inlet flange
	for i in range(10):
		a = (i / 10) * math.tau
		add_cyl_y(bm, (math.cos(a) * 0.160, -0.328, math.sin(a) * 0.160), 0.012, 0.026, segments=6)
	add_box(bm, (0, -0.360, -0.115), (0.300, 0.260, 0.055), bevel=0.010)  # intake grating
	for i in range(5):                                                     # grating bars
		add_box(bm, (-0.100 + i * 0.050, -0.360, -0.140), (0.020, 0.240, 0.024), bevel=0.003)
	add_cyl_y(bm, (0, 0.010, 0), 0.145, 0.070, segments=20)               # stator ring
	for i in range(8):
		a = (i / 8) * math.tau
		add_box(bm, (math.cos(a) * 0.100, 0.010, math.sin(a) * 0.100),
				(0.028, 0.062, 0.028), bevel=0.004)
	add_cyl_y(bm, (0, 0.075, 0), 0.055, 0.075, segments=14)               # shaft housing
	add_box(bm, (0, -0.150, 0.185), (0.220, 0.280, 0.060), bevel=0.010)   # hull flange
	export_bmesh(bm, "wj_pump", "wj_pump.glb",
				 color=(0.32, 0.44, 0.47, 1.0), metallic=0.76, roughness=0.32)

	# Steerable nozzle with its reverser bucket hinged above it.
	bm = bmesh.new()
	add_taper_y(bm, (0, 0.090, 0), 0.130, 0.078, 0.180, segments=20)      # nozzle cone
	add_cyl_y(bm, (0, 0.190, 0), 0.086, 0.030, segments=20)               # nozzle lip
	add_cyl_y(bm, (0, -0.010, 0), 0.140, 0.032, segments=20)              # steering ring
	for side in (-1, 1):                                                   # steering rams
		add_cyl_y(bm, (side * 0.150, 0.010, 0.030), 0.024, 0.130, segments=10)
		add_tube_between(bm, (side * 0.150, 0.070, 0.030), (side * 0.110, 0.150, 0.020), 0.011, segments=6)
	add_box(bm, (0, 0.130, 0.155), (0.230, 0.190, 0.035), bevel=0.008)    # reverser bucket
	add_cyl_x(bm, (0, 0.045, 0.150), 0.018, 0.240, segments=10)           # bucket hinge
	export_bmesh(bm, "wj_nozzle", "wj_nozzle.glb",
				 color=(0.28, 0.40, 0.44, 1.0), metallic=0.80, roughness=0.26)


# ---------------------------------------------------------------------------
# PONTOON WHEELS
# ---------------------------------------------------------------------------
def build_pontoon_wheels():
	# Sealed buoyant drum with paddle vanes - one wheel that is also a float.
	bm = bmesh.new()
	add_cyl_x(bm, (0, 0, 0), 0.250, 0.320, segments=22)                   # drum
	add_taper_x(bm, (0.175, 0, 0), 0.250, 0.190, 0.035, segments=22)      # outboard dome
	add_taper_x(bm, (-0.175, 0, 0), 0.190, 0.250, 0.035, segments=22)
	for band_x in (-0.105, 0.0, 0.105):                                    # strake bands
		add_cyl_x(bm, (band_x, 0, 0), 0.262, 0.030, segments=22)
	for i in range(9):                                                     # paddle vanes
		a = (i / 9) * math.tau
		add_box(bm, (0.0, math.cos(a) * 0.268, math.sin(a) * 0.268),
				(0.290, 0.055, 0.040), bevel=0.005)
		add_box(bm, (0.0, math.cos(a) * 0.288, math.sin(a) * 0.288),
				(0.270, 0.022, 0.028), bevel=0.003)
	add_cyl_x(bm, (0.205, 0, 0), 0.075, 0.045, segments=16)               # hub face
	bolt_ring_x(bm, 0.226, 0.048, count=6, bolt_r=0.011, bolt_len=0.020)
	add_cyl_x(bm, (-0.120, 0, 0), 0.055, 0.180, segments=14)              # stub axle
	add_box(bm, (-0.215, 0, 0.030), (0.075, 0.150, 0.170), bevel=0.010)   # bearing carrier
	add_tube_between(bm, (-0.215, 0.0, 0.115), (-0.215, 0.0, 0.230), 0.024, segments=8)
	add_box(bm, (-0.215, 0, 0.250), (0.110, 0.170, 0.045), bevel=0.008)   # chassis pad
	export_bmesh(bm, "pw_pontoon", "pw_pontoon.glb",
				 color=(0.38, 0.36, 0.31, 1.0), metallic=0.45, roughness=0.60)


if __name__ == "__main__":
	clear_scene()
	build_half_track()
	build_rocker_bogie()
	build_air_cushion_skirt()
	build_anti_grav_plate()
	build_hydrofoil()
	build_water_jet()
	build_pontoon_wheels()
	print("LOCOMOTION_EXPANSION_PARTS_DONE")
