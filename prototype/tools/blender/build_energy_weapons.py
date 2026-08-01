import bpy
import bmesh
import math
import os
import mathutils

# Authored sub-parts for the Energy & Electromagnetic expansion:
#   arc_projector    - activating an orphan that was already 80% implemented
#   microwave_emitter - cone denial, drains target energy
#   particle_lance   - charge-up single devastating beam
#
# Conventions are the roster's, unchanged:
#   - Blender +Y is FORWARD (Godot -Z), +Z is UP.
#   - MOUNT parts have their origin at deck level (Z=0).
#   - EMITTER/RECEIVER parts have their origin at the trunnion.
#   - Anything a barrel_length-style tweak stretches is its OWN part, so a
#     tweak never smears a bolt head or a baffle.
#   - Mount stations are MEASURED off the exported AABBs afterwards, never
#     estimated - that mistake left the anti-materiel rifle's barrel hanging
#     in mid air.
#
# TWO RULES THAT SHAPE EVERY PART HERE
# ---------------------------------------------------------------------------
# 1. EXTERIOR MODULES, NOT CREW-SERVED GUNS (VISUAL_ART_DIRECTION.md). No
#    grips, triggers, handwheels, carry handles or eyepieced sights anywhere.
#    Aiming and firing gear is servos, solenoids and conduit; optics are
#    boxed cameras with the lens on the outside, never a telescope.
#
# 2. BALANCE ABOUT THE TRUNNION. The trunnion sits directly above the module's
#    own origin, so real mass has to sit BEHIND it or the module reads as an
#    emitter stuck on a post. On an energy weapon that mass has an obvious
#    identity - capacitor banks, coolant reservoirs, transformer cans - which
#    is convenient, because it means the counterweight is also the thing that
#    explains where the shot's energy comes from. Checked by
#    test_weapon_modules_balance_about_their_mount.

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
	_cone(bm, pos, r_front, r_back, height, segments, mathutils.Matrix.Rotation(math.radians(90), 4, 'X'))


def add_taper_z(bm, pos, r_bot, r_top, height, segments=16):
	_cone(bm, pos, r_bot, r_top, height, segments)


def bolt_ring(bm, y, radius, count=8, bolt_r=0.008, bolt_len=0.014):
	for i in range(count):
		a = (i / count) * math.tau
		add_cyl_y(bm, (math.cos(a) * radius, y, math.sin(a) * radius), bolt_r, bolt_len, segments=6)


def bolt_ring_z(bm, z, radius, count=8, bolt_r=0.008, bolt_len=0.014):
	for i in range(count):
		a = (i / count) * math.tau
		add_cyl_z(bm, (math.cos(a) * radius, math.sin(a) * radius, z), bolt_r, bolt_len, segments=6)


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


def add_helix(bm, pos, coil_r, length, turns, wire_r, segs_per_turn=12, minor_seg=6, axis='Z'):
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
			a0 = rings[i][j]
			a1 = rings[i][(j + 1) % minor_seg]
			b0 = rings[i + 1][j]
			b1 = rings[i + 1][(j + 1) % minor_seg]
			try:
				bm.faces.new((a0, a1, b1, b0))
			except ValueError:
				pass



def add_paraboloid_y(bm, pos, outer_r, depth, rings=9, segs=28, thickness=0.014):
	"""An open parabolic dish facing +Y, built as a genuine swept surface with
	a thickness offset so it has a back as well as a front.

	The obvious version - a stack of solid add_cyl_y discs of decreasing
	radius - does NOT work: each disc is capped, so the largest one occludes
	every smaller one behind it and the result renders as a flat plate. A dish
	has to be a surface."""
	loc = mathutils.Vector(pos)
	front = []
	back = []
	for i in range(rings):
		t = i / float(rings - 1)
		r = outer_r * t
		# y = depth * (1 - t^2) puts the vertex at the deepest point and the
		# rim at y=0, i.e. a dish that opens forward.
		y = depth * (1.0 - t * t)
		fr = []
		br = []
		for j in range(segs):
			a = (j / segs) * math.tau
			c, sn = math.cos(a) * r, math.sin(a) * r
			fr.append(bm.verts.new(loc + mathutils.Vector((c, y, sn))))
			br.append(bm.verts.new(loc + mathutils.Vector((c, y - thickness, sn))))
		front.append(fr)
		back.append(br)
	for i in range(rings - 1):
		for j in range(segs):
			k = (j + 1) % segs
			try:
				bm.faces.new((front[i][j], front[i][k], front[i + 1][k], front[i + 1][j]))
			except ValueError:
				pass
			try:
				bm.faces.new((back[i + 1][j], back[i + 1][k], back[i][k], back[i][j]))
			except ValueError:
				pass
	# Close the rim so the dish reads as plate with an edge, not as paper.
	for j in range(segs):
		k = (j + 1) % segs
		try:
			bm.faces.new((front[-1][j], back[-1][j], back[-1][k], front[-1][k]))
		except ValueError:
			pass


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
# ARC PROJECTOR
# The dedicated disabler: minor HP damage, enormous energy drain. Reads as a
# Jacob's-ladder apparatus rather than a gun - two divergent electrodes with
# nothing between them but air, fed by an unreasonable amount of high-tension
# gear. Its `containment` tweak scales the field emitter, so that is its own
# part; the electrodes and the transformer are not.
# ---------------------------------------------------------------------------
def build_arc_projector():
	# 1. MOUNT - origin at deck. Insulator stack rather than a plain pintle:
	#    a weapon at this voltage has to be visibly isolated from its vehicle.
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.020), 0.170, 0.040, segments=22)
	bolt_ring_z(bm, 0.042, 0.148, count=12, bolt_r=0.010, bolt_len=0.016)
	# Ceramic insulator stack - stacked skirts, unmistakable at a glance
	for i in range(5):
		add_cyl_z(bm, (0, 0, 0.062 + i * 0.036), 0.082 - i * 0.004, 0.020, segments=20)
		add_cyl_z(bm, (0, 0, 0.078 + i * 0.036), 0.052, 0.018, segments=16)
	add_cyl_z(bm, (0, 0, 0.250), 0.070, 0.038, segments=20)
	# Trunnion forks
	for side in (-1, 1):
		add_box(bm, (side * 0.120, 0.010, 0.300), (0.040, 0.110, 0.140), bevel=0.008)
		add_cyl_x(bm, (side * 0.142, 0.010, 0.352), 0.036, 0.030, segments=14)
	# Earthing strap and HT feed conduit running down the outside
	add_tube_between(bm, (-0.150, -0.060, 0.320), (-0.150, -0.060, 0.030), 0.014, segments=8)
	add_box(bm, (-0.150, -0.060, 0.020), (0.050, 0.050, 0.030), bevel=0.005)
	for i in range(3):
		add_tube_between(bm, (0.140, -0.055 - i * 0.010, 0.330), (0.140, -0.055 - i * 0.010, 0.060), 0.010, segments=6)
	export_bmesh(bm, "arc_projector_mount", "arc_projector_mount.glb", color=(0.19, 0.20, 0.22, 1.0))

	# 2. TRANSFORMER BODY - origin at trunnion. This is the counterweight:
	#    a big oil-filled HT transformer sitting BEHIND the trunnion, which is
	#    both where the balance needs mass and where the energy plausibly
	#    comes from.
	bm = bmesh.new()
	add_box(bm, (0, -0.170, 0.0), (0.230, 0.340, 0.220), bevel=0.014)
	# Cooling fin stacks down both flanks - the classic transformer read
	for side in (-1, 1):
		for i in range(9):
			add_box(bm, (side * 0.132, -0.300 + i * 0.036, 0.0), (0.024, 0.018, 0.200), bevel=0.002)
	# Bushings on top, porcelain, with their own skirts
	for side in (-1, 1):
		for i in range(3):
			add_cyl_z(bm, (side * 0.062, -0.240, 0.126 + i * 0.026), 0.032 - i * 0.004, 0.020, segments=16)
		add_cyl_z(bm, (side * 0.062, -0.240, 0.196), 0.014, 0.040, segments=10)
	# Conservator drum across the back
	add_cyl_x(bm, (0, -0.352, 0.078), 0.062, 0.190, segments=18)
	add_cyl_z(bm, (0, -0.352, 0.148), 0.020, 0.040, segments=10)
	# Front face: the arc chamber's mounting flange
	add_cyl_y(bm, (0, 0.010, 0.0), 0.098, 0.040, segments=20)
	bolt_ring(bm, 0.020, 0.084, count=10, bolt_r=0.010, bolt_len=0.018)
	# Trunnion lugs
	for side in (-1, 1):
		add_box(bm, (side * 0.128, 0.0, 0.0), (0.026, 0.080, 0.080), bevel=0.006)
		add_cyl_x(bm, (side * 0.146, 0.0, 0.0), 0.030, 0.020, segments=14)
	export_bmesh(bm, "arc_projector_body", "arc_projector_body.glb", color=(0.22, 0.24, 0.26, 1.0))

	# 3. CONTAINMENT EMITTER - the ONLY part the containment tweak scales.
	#    Origin at the body's front face, growing along +Y.
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0.060, 0), 0.086, 0.110, segments=20)         # field coil housing
	for i in range(4):
		add_cyl_y(bm, (0, 0.022 + i * 0.026, 0), 0.096, 0.016, segments=20)
	add_helix(bm, (0, 0.170, 0), 0.072, 0.120, 5.0, 0.010, axis='Y')  # exposed field coil
	add_cyl_y(bm, (0, 0.248, 0), 0.070, 0.036, segments=20)         # front ring
	# Twin divergent electrodes - a Jacob's ladder, so the gap widens forward
	for side in (-1, 1):
		add_tube_between(bm, (side * 0.036, 0.262, 0.0), (side * 0.105, 0.470, 0.0), 0.013, segments=10)
		add_cyl_y(bm, (side * 0.036, 0.270, 0.0), 0.022, 0.030, segments=12)
		# Ball terminal at the tip
		add_cyl_y(bm, (side * 0.105, 0.478, 0.0), 0.024, 0.026, segments=14)
	# Striker pin on the centreline, where the arc initiates
	add_cyl_y(bm, (0, 0.310, 0.0), 0.014, 0.090, segments=12)
	add_cyl_y(bm, (0, 0.362, 0.0), 0.022, 0.018, segments=12)
	export_bmesh(bm, "arc_projector_emitter", "arc_projector_emitter.glb",
				 color=(0.30, 0.33, 0.36, 1.0), metallic=0.85, roughness=0.25)


# ---------------------------------------------------------------------------
# MICROWAVE EMITTER
# Area denial by cooking electronics rather than by damage. A parabolic dish
# is the whole silhouette - nothing else in the roster has one - and the
# `dish_aperture` tweak scales the dish alone, which is exactly the sort of
# read a player can predict before dragging the slider: a bigger dish means a
# wider, shorter-ranged cone.
# ---------------------------------------------------------------------------
def build_microwave_emitter():
	# 1. MOUNT - origin at deck. Waveguide plumbing rather than a gun cradle.
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.020), 0.165, 0.040, segments=22)
	bolt_ring_z(bm, 0.042, 0.144, count=12, bolt_r=0.010, bolt_len=0.016)
	add_cyl_z(bm, (0, 0, 0.070), 0.110, 0.060, segments=20)          # azimuth drum
	# Rectangular waveguide running up from the deck - the tell that this is
	# a microwave device and not an optic.
	add_box(bm, (0, -0.090, 0.150), (0.070, 0.045, 0.230), bevel=0.006)
	for i in range(5):                                                # choke flanges
		add_box(bm, (0, -0.090, 0.060 + i * 0.052), (0.090, 0.062, 0.014), bevel=0.003)
	add_box(bm, (0, -0.050, 0.256), (0.070, 0.100, 0.048), bevel=0.006)   # elbow
	# Trunnion forks
	for side in (-1, 1):
		add_box(bm, (side * 0.118, 0.020, 0.180), (0.038, 0.100, 0.190), bevel=0.008)
		add_cyl_x(bm, (side * 0.140, 0.020, 0.262), 0.036, 0.030, segments=14)
	# Cooling blower slung to one side
	add_cyl_y(bm, (0.130, -0.090, 0.090), 0.052, 0.090, segments=16)
	add_cyl_y(bm, (0.130, -0.140, 0.090), 0.036, 0.020, segments=12)
	for i in range(6):
		a = (i / 6) * math.tau
		add_box(bm, (0.130 + math.cos(a) * 0.040, -0.146, 0.090 + math.sin(a) * 0.040),
				(0.012, 0.008, 0.012), bevel=0.002)
	export_bmesh(bm, "microwave_mount", "microwave_mount.glb", color=(0.19, 0.20, 0.22, 1.0))

	# 2. MAGNETRON BODY - origin at trunnion, and the counterweight. Sits
	#    behind the trunnion so the dish out front does not tip the module.
	bm = bmesh.new()
	add_cyl_y(bm, (0, -0.150, 0.0), 0.105, 0.300, segments=20)       # magnetron can
	for i in range(7):                                                # cooling fins
		add_cyl_y(bm, (0, -0.285 + i * 0.045, 0.0), 0.128, 0.020, segments=20)
	add_cyl_y(bm, (0, -0.310, 0.0), 0.084, 0.040, segments=18)       # rear cap
	add_cyl_y(bm, (0, -0.340, 0.0), 0.040, 0.030, segments=12)       # HT feedthrough
	# Modulator box slung underneath, blocky and obviously electrical
	add_box(bm, (0, -0.180, -0.135), (0.170, 0.240, 0.090), bevel=0.010)
	for i in range(4):
		add_box(bm, (0, -0.270 + i * 0.058, -0.185), (0.140, 0.030, 0.016), bevel=0.003)
	# Waveguide run forward from the magnetron to the dish feed
	add_box(bm, (0, 0.030, 0.0), (0.062, 0.100, 0.062), bevel=0.005)
	for i in range(3):
		add_box(bm, (0, -0.010 + i * 0.038, 0.0), (0.080, 0.014, 0.080), bevel=0.003)
	# Trunnion lugs
	for side in (-1, 1):
		add_box(bm, (side * 0.116, 0.0, 0.0), (0.026, 0.076, 0.076), bevel=0.006)
		add_cyl_x(bm, (side * 0.134, 0.0, 0.0), 0.030, 0.020, segments=14)
	export_bmesh(bm, "microwave_body", "microwave_body.glb", color=(0.24, 0.25, 0.27, 1.0))

	# 3. DISH - the ONLY part dish_aperture scales. Origin at the body's front
	#    face. Built as a real shallow paraboloid ring stack so it reads as a
	#    dish from every angle rather than as a disc.
	bm = bmesh.new()
	outer_r = 0.300
	add_paraboloid_y(bm, (0, 0.030, 0.0), outer_r, 0.135, rings=10, segs=30, thickness=0.016)
	# Rim lip, so the dish edge catches light and reads as fabricated plate
	add_cyl_y(bm, (0, 0.026, 0.0), outer_r * 1.02, 0.020, segments=30)
	add_cyl_y(bm, (0, 0.036, 0.0), outer_r * 1.05, 0.012, segments=30)
	# Radial stiffener spokes on the BACK of the dish. Built as tubes from the
	# hub out to the rim so they are radial BY CONSTRUCTION - the obvious
	# version, add_box at a radial position, has no rotation argument, so all
	# eight came out axis-aligned and rendered as a ring of vertical spikes
	# standing off the back of the dish rather than as ribs following it.
	for i in range(8):
		a = (i / 8) * math.tau
		add_tube_between(bm, (0.0, 0.026, 0.0),
						 (math.cos(a) * outer_r * 0.94, 0.014, math.sin(a) * outer_r * 0.94),
						 0.012, segments=6)
	# Circumferential hoop tying the spokes together
	for i in range(24):
		a0 = (i / 24) * math.tau
		a1 = ((i + 1) / 24) * math.tau
		add_tube_between(bm, (math.cos(a0) * outer_r * 0.62, 0.018, math.sin(a0) * outer_r * 0.62),
						 (math.cos(a1) * outer_r * 0.62, 0.018, math.sin(a1) * outer_r * 0.62),
						 0.008, segments=5)
	# Hub casting where the ribs meet
	add_cyl_y(bm, (0, 0.030, 0.0), 0.058, 0.060, segments=18)
	add_cyl_y(bm, (0, 0.064, 0.0), 0.040, 0.020, segments=14)
	# Feed horn on a tripod out in FRONT of the dish - the detail that makes a
	# dish read as a dish and not as a shield.
	add_taper_y(bm, (0, 0.235, 0.0), 0.028, 0.056, 0.090, segments=18)
	add_cyl_y(bm, (0, 0.180, 0.0), 0.028, 0.032, segments=16)
	add_cyl_y(bm, (0, 0.286, 0.0), 0.058, 0.016, segments=18)
	for i in range(3):
		a = (i / 3) * math.tau + math.pi / 6.0
		add_tube_between(bm, (math.cos(a) * outer_r * 0.86, 0.050, math.sin(a) * outer_r * 0.86),
						 (math.cos(a) * 0.028, 0.190, math.sin(a) * 0.028), 0.011, segments=6)
	# Waveguide running from the hub out to the feed horn
	add_cyl_y(bm, (0.020, 0.120, 0.0), 0.014, 0.160, segments=10)
	export_bmesh(bm, "microwave_dish", "microwave_dish.glb",
				 color=(0.62, 0.62, 0.60, 1.0), metallic=0.55, roughness=0.42)


# ---------------------------------------------------------------------------
# PARTICLE LANCE
# Charge, then fire one devastating beam. The silhouette has to promise the
# wind-up: a long accelerator spine with visible stage rings, a capacitor
# stack that is plainly most of the module's mass, and a cryo reservoir. Its
# `charge_time` tweak scales the capacitor stack (more stored charge = longer
# wind-up, bigger shot), and `focal_length` scales the accelerator alone.
# ---------------------------------------------------------------------------
def build_particle_lance():
	# 1. MOUNT - origin at deck
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.022), 0.185, 0.044, segments=24)
	bolt_ring_z(bm, 0.046, 0.162, count=14, bolt_r=0.010, bolt_len=0.016)
	add_cyl_z(bm, (0, 0, 0.080), 0.125, 0.072, segments=22)
	add_box(bm, (0, 0.100, 0.075), (0.115, 0.060, 0.070), bevel=0.008)   # traverse drive
	add_cyl_y(bm, (0, 0.136, 0.075), 0.028, 0.028, segments=12)
	# Tall trunnion forks braced back to the deck
	for side in (-1, 1):
		add_box(bm, (side * 0.148, 0.0, 0.210), (0.044, 0.120, 0.250), bevel=0.009)
		add_cyl_x(bm, (side * 0.174, 0.0, 0.318), 0.042, 0.034, segments=16)
		add_tube_between(bm, (side * 0.148, -0.055, 0.120), (side * 0.070, -0.150, 0.030), 0.016)
		# Elevation jack
		add_cyl_z(bm, (side * 0.110, -0.115, 0.130), 0.028, 0.150, segments=14)
		add_cyl_z(bm, (side * 0.110, -0.115, 0.235), 0.014, 0.080, segments=10)
	# Coolant hoses looping up from the deck
	for i in range(3):
		add_tube_between(bm, (-0.160, -0.090 - i * 0.014, 0.040), (-0.120, -0.070, 0.290), 0.011, segments=6)
	export_bmesh(bm, "lance_mount", "lance_mount.glb", color=(0.19, 0.20, 0.22, 1.0))

	# 2. BREECH / INJECTOR - origin at trunnion, fixed hardware.
	bm = bmesh.new()
	add_box(bm, (0, -0.040, 0.0), (0.180, 0.240, 0.190), bevel=0.013)
	add_cyl_y(bm, (0, 0.100, 0.0), 0.078, 0.060, segments=20)        # accelerator flange
	bolt_ring(bm, 0.118, 0.066, count=10, bolt_r=0.009, bolt_len=0.016)
	# Particle source bottle on top
	add_cyl_z(bm, (0, -0.060, 0.128), 0.052, 0.090, segments=16)
	add_cyl_z(bm, (0, -0.060, 0.180), 0.032, 0.028, segments=12)
	add_box(bm, (0, -0.060, 0.202), (0.058, 0.058, 0.020), bevel=0.004)
	# Cryo reservoir slung under the breech, frosted-looking
	add_cyl_x(bm, (0, -0.050, -0.128), 0.070, 0.200, segments=18)
	for side in (-1, 1):
		add_cyl_x(bm, (side * 0.104, -0.050, -0.128), 0.052, 0.024, segments=16)
	add_cyl_z(bm, (0, -0.050, -0.060), 0.018, 0.060, segments=10)
	# Trunnion lugs
	for side in (-1, 1):
		add_box(bm, (side * 0.100, 0.0, 0.0), (0.028, 0.084, 0.084), bevel=0.006)
		add_cyl_x(bm, (side * 0.120, 0.0, 0.0), 0.032, 0.022, segments=14)
	export_bmesh(bm, "lance_breech", "lance_breech.glb", color=(0.21, 0.23, 0.25, 1.0))

	# 3. CAPACITOR STACK - the ONLY part charge_time scales, and the module's
	#    counterweight. Origin at the breech's rear face, growing back along -Y.
	bm = bmesh.new()
	for row in (-1, 1):
		for i in range(4):
			cy = -0.070 - i * 0.098
			add_cyl_y(bm, (row * 0.078, cy, 0.030), 0.060, 0.086, segments=18)
			add_cyl_y(bm, (row * 0.078, cy + 0.048, 0.030), 0.040, 0.016, segments=14)
			add_cyl_y(bm, (row * 0.078, cy + 0.060, 0.030), 0.014, 0.014, segments=8)
	# Busbars tying the stack together, and a discharge rail down the middle
	for side in (-1, 1):
		add_box(bm, (side * 0.078, -0.245, 0.104), (0.026, 0.400, 0.016), bevel=0.003)
	add_box(bm, (0, -0.245, 0.030), (0.040, 0.400, 0.040), bevel=0.005)
	# Rear bulkhead with warning-plate greebles and a bleed resistor bank
	add_box(bm, (0, -0.470, 0.020), (0.220, 0.030, 0.210), bevel=0.008)
	for i in range(4):
		add_cyl_y(bm, (-0.066 + i * 0.044, -0.500, -0.040), 0.014, 0.040, segments=8)
	add_box(bm, (0, -0.496, 0.090), (0.120, 0.024, 0.060), bevel=0.005)
	export_bmesh(bm, "lance_capacitors", "lance_capacitors.glb",
				 color=(0.28, 0.30, 0.34, 1.0), metallic=0.70, roughness=0.34)

	# 4. ACCELERATOR SPINE - the ONLY part focal_length scales. Origin at the
	#    breech's front flange, running forward along +Y.
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0.030, 0), 0.058, 0.060, segments=18)
	add_cyl_y(bm, (0, 0.430, 0), 0.034, 0.760, segments=18)          # the spine
	# Accelerator stage rings at regular stations, each with its own feed
	for i in range(6):
		sy = 0.110 + i * 0.128
		add_cyl_y(bm, (0, sy, 0), 0.066, 0.034, segments=20)
		add_cyl_y(bm, (0, sy, 0), 0.078, 0.014, segments=20)
		for side in (-1, 1):
			add_box(bm, (side * 0.072, sy, 0.0), (0.026, 0.026, 0.026), bevel=0.003)
			add_tube_between(bm, (side * 0.076, sy, 0.0), (side * 0.076, sy - 0.100, 0.0), 0.008, segments=6)
	# Focusing muzzle: a short flared horn with quadrupole vanes
	add_taper_y(bm, (0, 0.845, 0), 0.036, 0.062, 0.070, segments=20)
	for i in range(4):
		a = (i / 4) * math.tau + math.pi / 4.0
		add_box(bm, (math.cos(a) * 0.048, 0.870, math.sin(a) * 0.048), (0.014, 0.060, 0.014), bevel=0.003)
	add_cyl_y(bm, (0, 0.888, 0), 0.058, 0.022, segments=20)
	export_bmesh(bm, "lance_accelerator", "lance_accelerator.glb",
				 color=(0.16, 0.18, 0.21, 1.0), metallic=0.80, roughness=0.28)


if __name__ == "__main__":
	clear_scene()
	build_arc_projector()
	build_microwave_emitter()
	build_particle_lance()
	print("ENERGY_WEAPON_PARTS_DONE")
