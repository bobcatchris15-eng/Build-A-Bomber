import bpy
import bmesh
import math
import os
import mathutils

# Re-authors the three directed-energy / electromagnetic weapons that never
# matched the roster's design language: heavy_laser, pd_laser and coil_gun.
#
# WHAT WAS WRONG (measured, not eyeballed - scratch/probe_balance_one.gd)
# ---------------------------------------------------------------------------
#   part                 span   forward   aft
#   heavy_laser          0.82    -0.56   +0.26
#   pd_laser             0.59    -0.39   +0.20
#   coil_gun             1.20    -0.94   +0.26
#   ...against the roster they are supposed to sit beside:
#   autocannon           1.74    -1.50   +0.24
#   gauss_railgun        1.86    -1.40   +0.46
#   anti_materiel_rifle  2.24    -1.45   +0.79
#   particle_lance       1.71    -1.03   +0.68
#
# So they were half the length of everything around them, and what length they
# had was almost entirely FORWARD of the trunnion - a lens on a post, with
# nothing behind it. The rebuilt versions target ~2.0-2.2 span with real mass
# on BOTH sides of the trunnion, which is Chris's brief and also what makes a
# weapon read as a self-contained machine rather than a prop.
#
# The old heavy_laser was additionally a straight violation of the art
# direction: its forward part was authored as, and commented as, a "telescope
# lens barrel". VISUAL_ART_DIRECTION.md is explicit that these are exterior
# modules, not crew-served guns - optics are boxed cameras with the lens on the
# outside, never a telescope. It is now a beam director: a squared-off armoured
# trunk with focusing coils and an aperture, nothing you could put an eye to.
#
# CONVENTIONS (the roster's, unchanged)
#   - Blender +Y is FORWARD (Godot -Z), +Z is UP.
#   - MOUNT parts have their origin at deck level (Z=0).
#   - Everything else has its origin at the TRUNNION.
#   - Anything a tweak stretches is its own part, so a tweak never smears a
#     bolt head or a cooling fin. heavy_laser/pd_laser scale only the emitter
#     part by barrel_length, so ALL the aft mass lives in the housing.

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


def add_taper_y(bm, pos, r_back, r_front, height, segments=16):
	_cone(bm, pos, r_front, r_back, height, segments, mathutils.Matrix.Rotation(math.radians(90), 4, 'X'))


def add_taper_z(bm, pos, r_bot, r_top, height, segments=16):
	_cone(bm, pos, r_bot, r_top, height, segments)


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


def bolt_ring_y(bm, y, radius, count=8, bolt_r=0.008, bolt_len=0.014):
	for i in range(count):
		a = (i / count) * math.tau
		add_cyl_y(bm, (math.cos(a) * radius, y, math.sin(a) * radius), bolt_r, bolt_len, segments=6)


def fin_stack(bm, y_centre, y_len, x_at, z_lo, z_hi, count, thickness=0.014, depth=0.055):
	"""A radiator stack: `count` thin plates standing proud of a side face.

	Directed-energy weapons in this roster are supposed to look like they have
	somewhere to put the waste heat, and fins are the cheapest legible way to
	say so. Kept to 1-segment bevels - these repeat a lot.
	"""
	for i in range(count):
		t = i / max(1, count - 1)
		z = z_lo + (z_hi - z_lo) * t
		add_box(bm, (x_at, y_centre, z), (depth, y_len, thickness), bevel=0.002)


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


# ---------------------------------------------------------------------------
# HEAVY LASER
#
# A vehicle-scale beam director. Reads front-to-back as: aperture and focusing
# coils (forward) -> trunnion -> armoured resonator cavity with its radiator
# banks -> coolant drum and capacitor stack (aft, and deliberately the heaviest
# thing on the module).
#
# visual_builder.gd scales the HOUSING by (aperture, aperture, 1.0) and the
# EMITTER by (aperture, aperture, barrel_length). So the housing's length is
# fixed - which is exactly right, since it carries all the counterweight, and a
# barrel_length slider must not be able to unbalance the weapon.
# ---------------------------------------------------------------------------
def build_heavy_laser():
	# 1. MOUNT - origin at deck. Ring, yoke arms, elevation drive.
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.028), 0.30, 0.056, segments=24)           # turret ring
	add_cyl_z(bm, (0, 0, 0.070), 0.235, 0.045, segments=22)          # race
	for i in range(12):                                              # ring bolts
		a = (i / 12) * math.tau
		add_cyl_z(bm, (math.cos(a) * 0.266, math.sin(a) * 0.266, 0.062), 0.014, 0.026, segments=6)
	# Yoke arms carrying the trunnion at Z=0.25. Swept back so the arm sits
	# under the resonator's mass rather than under the aperture.
	for side in (-1, 1):
		add_box(bm, (side * 0.205, -0.045, 0.165), (0.062, 0.30, 0.20), bevel=0.010)
		add_taper_z(bm, (side * 0.205, -0.045, 0.275), 0.075, 0.052, 0.06, segments=14)
		add_cyl_x(bm, (side * 0.238, 0.0, 0.250), 0.058, 0.045, segments=16)   # trunnion boss
		add_cyl_x(bm, (side * 0.262, 0.0, 0.250), 0.030, 0.020, segments=12)   # cap
	# Elevation drive: a servo can and its jackscrew, on the left arm only.
	add_cyl_x(bm, (-0.255, -0.135, 0.150), 0.048, 0.075, segments=14)
	add_tube_between(bm, (-0.255, -0.135, 0.150), (-0.255, -0.135, 0.255), 0.014, segments=8)
	# Power trunk up the rear of the pedestal.
	add_cyl_z(bm, (0, -0.205, 0.130), 0.040, 0.235, segments=14)
	add_cyl_y(bm, (0, -0.165, 0.245), 0.040, 0.090, segments=14)
	export_bmesh(bm, "heavy_laser_mount", "heavy_laser_mount.glb",
				 color=(0.20, 0.22, 0.26, 1.0), metallic=0.72, roughness=0.36)

	# 2. RESONATOR HOUSING - origin at trunnion. THE COUNTERWEIGHT.
	#    Spans Y -0.98 (aft) to +0.34 (forward), so most of its bulk is behind
	#    the trunnion, which is the whole point of the rebuild.
	bm = bmesh.new()
	# Armoured cavity trunk, squared off, running through the trunnion.
	add_box(bm, (0, -0.16, 0.0), (0.30, 0.98, 0.28), bevel=0.018)
	# Chamfered top deck plate so it does not read as a plain crate.
	add_box(bm, (0, -0.16, 0.155), (0.255, 0.92, 0.030), bevel=0.008)
	# Radiator banks down both flanks - this is where the waste heat goes, and
	# the most legible "directed energy" cue the silhouette has.
	for side in (-1, 1):
		fin_stack(bm, -0.20, 0.80, side * 0.175, -0.105, 0.105, 7)
		add_box(bm, (side * 0.168, -0.20, 0.0), (0.020, 0.84, 0.245), bevel=0.004)  # fin root rail
	# Coolant drum slung under the aft end.
	add_cyl_y(bm, (0, -0.60, -0.185), 0.105, 0.44, segments=18)
	add_cyl_y(bm, (0, -0.82, -0.185), 0.115, 0.030, segments=18)
	add_cyl_y(bm, (0, -0.38, -0.185), 0.115, 0.030, segments=18)
	add_tube_between(bm, (0.07, -0.38, -0.185), (0.07, -0.16, -0.075), 0.020, segments=8)
	add_tube_between(bm, (-0.07, -0.38, -0.185), (-0.07, -0.16, -0.075), 0.020, segments=8)
	# Capacitor stack standing on the aft deck - four cans in a block.
	for cx in (-1, 1):
		for cy in (-1, 1):
			add_cyl_z(bm, (cx * 0.088, -0.545 + cy * 0.125, 0.245), 0.062, 0.155, segments=14)
			add_cyl_z(bm, (cx * 0.088, -0.545 + cy * 0.125, 0.330), 0.038, 0.022, segments=10)
	add_box(bm, (0, -0.545, 0.348), (0.235, 0.030, 0.018), bevel=0.003)   # busbar
	# Rear armour plate closing the trunk.
	add_box(bm, (0, -0.655, 0.0), (0.265, 0.032, 0.245), bevel=0.006)
	bolt_ring_y(bm, -0.672, 0.115, count=8, bolt_r=0.011, bolt_len=0.018)
	# Boxed alignment camera on top - a sealed sensor can, NOT a telescope:
	# lens on the outside, nothing to put an eye to.
	add_box(bm, (0.0, 0.14, 0.205), (0.115, 0.185, 0.085), bevel=0.008)
	add_cyl_y(bm, (0.0, 0.238, 0.205), 0.036, 0.030, segments=14)
	add_cyl_y(bm, (0.0, 0.252, 0.205), 0.030, 0.008, segments=14)
	export_bmesh(bm, "heavy_laser_housing", "heavy_laser_housing.glb",
				 color=(0.24, 0.28, 0.32, 1.0), metallic=0.78, roughness=0.30)

	# 3. BEAM DIRECTOR - origin at trunnion, extends +Y. Scaled by
	#    barrel_length, so it holds no counterweight and no fixed hardware
	#    whose proportions a slider could ruin.
	bm = bmesh.new()
	add_box(bm, (0, 0.60, 0.0), (0.175, 0.86, 0.175), bevel=0.014)   # armoured trunk
	# Focusing coil stations - the beam-weapon equivalent of barrel bands.
	for i in range(4):
		y = 0.30 + i * 0.215
		add_cyl_y(bm, (0, y, 0), 0.118, 0.042, segments=18)
		add_cyl_y(bm, (0, y, 0), 0.132, 0.016, segments=18)
		for side in (-1, 1):                                          # feed lugs
			add_box(bm, (side * 0.122, y, 0.0), (0.028, 0.030, 0.028), bevel=0.003)
	# Conduit running the length of the trunk, feeding each station.
	for side in (-1, 1):
		add_tube_between(bm, (side * 0.126, 0.24, 0.0), (side * 0.126, 0.99, 0.0), 0.014, segments=8)
	# Muzzle: aperture shroud with quadrupole vanes and a recessed window.
	add_taper_y(bm, (0, 1.075, 0), 0.115, 0.148, 0.115, segments=20)
	for i in range(4):
		a = (i / 4) * math.tau + math.pi / 4.0
		add_box(bm, (math.cos(a) * 0.118, 1.150, math.sin(a) * 0.118),
				(0.020, 0.105, 0.020), bevel=0.003)
	add_cyl_y(bm, (0, 1.185, 0), 0.140, 0.036, segments=22)          # shroud lip
	add_cyl_y(bm, (0, 1.200, 0), 0.104, 0.012, segments=22)          # window
	export_bmesh(bm, "heavy_laser_lens", "heavy_laser_lens.glb",
				 color=(0.15, 0.18, 0.22, 1.0), metallic=0.82, roughness=0.24)


# ---------------------------------------------------------------------------
# POINT-DEFENCE LASER
#
# Same language, two-thirds the scale, and built to read as FAST: a compact
# high-rate gimbal rather than a scaled-down siege weapon. The aft mass is a
# flywheel-looking drive pack and a pair of capacitor cans, which also explains
# how it slews quickly enough to catch a missile.
# ---------------------------------------------------------------------------
def build_pd_laser():
	# 1. GIMBAL MOUNT - origin at deck.
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.026), 0.215, 0.052, segments=22)
	add_cyl_z(bm, (0, 0, 0.075), 0.155, 0.048, segments=18)
	for i in range(8):
		a = (i / 8) * math.tau
		add_cyl_z(bm, (math.cos(a) * 0.186, math.sin(a) * 0.186, 0.058), 0.012, 0.024, segments=6)
	# Slew ring servos, sitting proud - the "agile" cue.
	for side in (-1, 1):
		add_cyl_z(bm, (side * 0.165, -0.055, 0.105), 0.042, 0.075, segments=12)
	for side in (-1, 1):
		add_box(bm, (side * 0.150, -0.020, 0.150), (0.048, 0.185, 0.155), bevel=0.008)
		add_cyl_x(bm, (side * 0.176, 0.010, 0.205), 0.042, 0.034, segments=14)
	add_cyl_z(bm, (0, -0.150, 0.110), 0.028, 0.185, segments=12)
	export_bmesh(bm, "pd_laser_mount", "pd_laser_mount.glb",
				 color=(0.22, 0.25, 0.30, 1.0), metallic=0.74, roughness=0.34)

	# 2. DIODE PACK / COOLING JACKET - origin at trunnion, carries the aft mass.
	#    Spans Y -0.66 to +0.24.
	bm = bmesh.new()
	add_box(bm, (0, -0.135, 0.0), (0.225, 0.66, 0.205), bevel=0.014)
	add_box(bm, (0, -0.135, 0.115), (0.190, 0.62, 0.024), bevel=0.006)
	for side in (-1, 1):
		fin_stack(bm, -0.155, 0.54, side * 0.132, -0.072, 0.072, 5, thickness=0.012, depth=0.042)
		add_box(bm, (side * 0.126, -0.155, 0.0), (0.016, 0.58, 0.175), bevel=0.003)
	# Drive pack aft - reads as the thing that makes it slew fast.
	add_cyl_y(bm, (0, -0.520, 0.0), 0.108, 0.185, segments=18)
	add_cyl_y(bm, (0, -0.618, 0.0), 0.122, 0.028, segments=18)
	for i in range(6):
		a = (i / 6) * math.tau
		add_box(bm, (math.cos(a) * 0.086, -0.520, math.sin(a) * 0.086),
				(0.020, 0.150, 0.020), bevel=0.002)
	# Two capacitor cans slung either side of the drive pack.
	for side in (-1, 1):
		add_cyl_y(bm, (side * 0.148, -0.430, -0.070), 0.052, 0.220, segments=12)
		add_cyl_y(bm, (side * 0.148, -0.545, -0.070), 0.032, 0.020, segments=10)
	add_box(bm, (0, -0.290, -0.118), (0.245, 0.028, 0.016), bevel=0.003)
	export_bmesh(bm, "pd_laser_housing", "pd_laser_housing.glb",
				 color=(0.25, 0.30, 0.35, 1.0), metallic=0.78, roughness=0.28)

	# 3. TWIN EMITTER - origin at trunnion, extends +Y, scaled by barrel_length.
	#    A paired aperture reads faster and more "point defence" than one big
	#    muzzle, and matches how the module is used against many small targets.
	bm = bmesh.new()
	add_box(bm, (0, 0.34, 0.0), (0.185, 0.42, 0.115), bevel=0.010)   # yoke block
	for side in (-1, 1):
		add_cyl_y(bm, (side * 0.070, 0.50, 0.0), 0.058, 0.62, segments=16)
		for i in range(3):
			add_cyl_y(bm, (side * 0.070, 0.30 + i * 0.215, 0.0), 0.070, 0.026, segments=16)
		add_taper_y(bm, (side * 0.070, 0.835, 0.0), 0.058, 0.074, 0.060, segments=16)
		add_cyl_y(bm, (side * 0.070, 0.872, 0.0), 0.070, 0.022, segments=16)   # bezel
		add_cyl_y(bm, (side * 0.070, 0.884, 0.0), 0.052, 0.008, segments=16)   # window
	# Cross-brace tying the two tubes together near the muzzle.
	add_box(bm, (0, 0.760, 0.0), (0.150, 0.036, 0.036), bevel=0.004)
	export_bmesh(bm, "pd_laser_lens", "pd_laser_lens.glb",
				 color=(0.15, 0.50, 0.75, 1.0), metallic=0.60, roughness=0.22)


# ---------------------------------------------------------------------------
# COIL GUN
#
# The existing part breakdown was already right - mount / breech / rail / coil /
# capacitors, with the rail as the only thing the stage tweak stretches. What
# was wrong was proportion: a 1.20 span with only 0.26 of it behind the
# trunnion, so a machine whose entire premise is "an enormous store of
# electrical energy" had nowhere to keep it.
#
# The breech now carries a real capacitor bank and the rail runs further out.
# ---------------------------------------------------------------------------
def build_coilgun():
	# 1. MOUNT - origin at deck.
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.026), 0.215, 0.052, segments=22)
	add_cyl_z(bm, (0, 0, 0.078), 0.158, 0.052, segments=18)
	for i in range(10):
		a = (i / 10) * math.tau
		add_box(bm, (math.cos(a) * 0.185, math.sin(a) * 0.185, 0.052),
				(0.030, 0.030, 0.036), bevel=0.004)
	for side in (-1, 1):
		add_box(bm, (side * 0.163, -0.035, 0.180), (0.055, 0.215, 0.215), bevel=0.009)
		add_cyl_x(bm, (side * 0.192, 0.020, 0.285), 0.048, 0.038, segments=16)
		add_cyl_x(bm, (side * 0.216, 0.020, 0.285), 0.026, 0.018, segments=10)
	# Heavy power trunk - a coil gun's cable is part of its identity.
	add_cyl_z(bm, (0, -0.175, 0.140), 0.042, 0.250, segments=14)
	add_cyl_y(bm, (0, -0.130, 0.262), 0.042, 0.100, segments=14)
	for i in range(4):
		add_cyl_z(bm, (0, -0.175, 0.055 + i * 0.062), 0.050, 0.014, segments=14)
	export_bmesh(bm, "coilgun_mount", "coilgun_mount.glb",
				 color=(0.20, 0.24, 0.28, 1.0), metallic=0.72, roughness=0.36)

	# 2. BREECH + CAPACITOR MASS - origin at trunnion. Spans Y -0.80 to +0.16.
	#    Everything that does not stretch with the stage tweak lives here.
	bm = bmesh.new()
	add_box(bm, (0, -0.075, 0.0), (0.205, 0.44, 0.205), bevel=0.014)   # breech block
	add_box(bm, (0, -0.075, 0.118), (0.150, 0.30, 0.032), bevel=0.005) # loading hatch
	add_cyl_x(bm, (0, -0.225, 0.118), 0.013, 0.155, segments=8)        # hinge
	for side in (-1, 1):                                               # hatch dogs
		add_box(bm, (side * 0.082, 0.055, 0.126), (0.024, 0.030, 0.020), bevel=0.003)
	# Capacitor bank stretching aft - four large cans in a frame.
	add_box(bm, (0, -0.500, -0.010), (0.235, 0.36, 0.185), bevel=0.010)
	for cx in (-1, 1):
		for cy in (-1, 1):
			add_cyl_y(bm, (cx * 0.078, -0.500 + cy * 0.098, 0.135), 0.058, 0.155, segments=14)
			add_cyl_y(bm, (cx * 0.078, -0.500 + cy * 0.098, 0.135), 0.066, 0.018, segments=14)
	add_box(bm, (0, -0.500, 0.222), (0.205, 0.030, 0.018), bevel=0.003)  # busbar
	for side in (-1, 1):                                                  # bus risers
		add_tube_between(bm, (side * 0.078, -0.500, 0.222), (side * 0.078, -0.180, 0.115), 0.016, segments=8)
	# Rear plate and cooling louvres.
	add_box(bm, (0, -0.690, 0.0), (0.225, 0.032, 0.195), bevel=0.006)
	for i in range(4):
		add_box(bm, (0, -0.712, -0.075 + i * 0.050), (0.185, 0.014, 0.014), bevel=0.002)
	bolt_ring_y(bm, -0.708, 0.098, count=8, bolt_r=0.010, bolt_len=0.016)
	export_bmesh(bm, "coilgun_breech", "coilgun_breech.glb",
				 color=(0.22, 0.25, 0.28, 1.0), metallic=0.76, roughness=0.32)

	# 3. RAIL SPINE - origin at the breech's front face, extends +Y. The only
	#    part the stage-count tweak stretches.
	bm = bmesh.new()
	add_box(bm, (0, 0.58, 0), (0.092, 1.16, 0.082), bevel=0.010)
	for side in (-1, 1):
		add_box(bm, (side * 0.060, 0.58, 0), (0.020, 1.14, 0.038), bevel=0.004)
		add_tube_between(bm, (side * 0.074, 0.04, 0.0), (side * 0.074, 1.10, 0.0), 0.012, segments=8)
	add_cyl_y(bm, (0, 1.185, 0), 0.078, 0.110, segments=18)          # muzzle shroud
	add_cyl_y(bm, (0, 1.258, 0), 0.062, 0.038, segments=18)
	for i in range(4):                                                # muzzle vanes
		a = (i / 4) * math.tau + math.pi / 4.0
		add_box(bm, (math.cos(a) * 0.070, 1.215, math.sin(a) * 0.070),
				(0.016, 0.075, 0.016), bevel=0.002)
	export_bmesh(bm, "coilgun_rail", "coilgun_rail.glb",
				 color=(0.24, 0.27, 0.30, 1.0), metallic=0.80, roughness=0.28)

	# 4. ACCELERATOR COIL - repeated along the rail by visual_builder, so the
	#    stage-count tweak is visible. Origin centred. Unchanged in concept,
	#    slightly heavier so it reads at the rail's new length.
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0, 0), 0.112, 0.062, segments=20)
	add_cyl_y(bm, (0, 0, 0), 0.126, 0.016, segments=20)
	for i in range(4):
		add_cyl_y(bm, (0, -0.020 + i * 0.013, 0), 0.119, 0.006, segments=20)
	add_box(bm, (0, 0, 0.122), (0.038, 0.048, 0.038), bevel=0.005)
	add_cyl_z(bm, (0, 0, 0.155), 0.011, 0.038, segments=8)
	export_bmesh(bm, "coilgun_coil", "coilgun_coil.glb",
				 color=(0.62, 0.36, 0.14, 1.0), metallic=0.90, roughness=0.30)

	# 5. AUXILIARY CAPACITOR PALLET - the under-breech pack. Kept as its own
	#    part because visual_builder mounts it separately.
	bm = bmesh.new()
	add_box(bm, (0, 0, -0.065), (0.285, 0.265, 0.110), bevel=0.010)
	for cx in (-1, 1):
		for cy in (-1, 1):
			add_cyl_z(bm, (cx * 0.078, cy * 0.075, 0.035), 0.052, 0.150, segments=14)
			add_cyl_z(bm, (cx * 0.078, cy * 0.075, 0.115), 0.032, 0.022, segments=10)
	add_box(bm, (0, 0, 0.128), (0.225, 0.032, 0.018), bevel=0.003)
	for side in (-1, 1):
		add_tube_between(bm, (side * 0.078, 0.075, 0.128), (side * 0.078, 0.150, 0.070), 0.014, segments=8)
	export_bmesh(bm, "coilgun_capacitors", "coilgun_capacitors.glb",
				 color=(0.30, 0.33, 0.36, 1.0), metallic=0.74, roughness=0.34)


if __name__ == "__main__":
	clear_scene()
	build_heavy_laser()
	build_pd_laser()
	build_coilgun()
	print("BEAM_WEAPON_PARTS_DONE")
