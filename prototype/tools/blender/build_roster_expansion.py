import bpy
import bmesh
import math
import os
import mathutils

# Authored sub-parts for the roster expansion (MK19 grenade launcher,
# recoilless rifle, coil gun, autocannon, napalm mortar, mine layer,
# ballista, smoke discharger).
#
# Conventions copied exactly from build_hmg.py / build_artillery.py so these
# parts drop into visual_builder.gd's existing _part() assembly path with no
# special handling:
#   - Blender +Y is FORWARD (the barrel/muzzle direction). Godot's glTF
#     import turns that into the -Z the whole codebase treats as "front".
#   - Blender +Z is UP.
#   - MOUNT parts have their origin at deck level (Z=0), so they sit flush
#     on the hull surface a module is placed against.
#   - RECEIVER/BREECH parts have their origin at trunnion height, matching
#     how visual_builder positions them at Vector3(x, trunnion_y, 0).
#   - BARREL parts have their origin at the receiver's front face and
#     extend along +Y, so barrel_length scaling grows them forward.
#   - Parts are authored at roughly 0.1-0.6 units, the same scale as the
#     existing weapon parts, since visual_builder applies only tweak-driven
#     scaling on top.
#
# Detail level deliberately matches basic_cannon/HMG rather than the
# "primitive box" fallback: latches, bolt rings, cooling slots, hinges,
# handles. VISUAL_ART_DIRECTION.md puts the goofiness at DETAIL scale, never
# in silhouette, so every part here reads as straight-faced hardware.

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
	# create_cone's radius1 is at -depth/2, radius2 at +depth/2; the X
	# rotation below flips Z->Y, so radius1 ends up at the +Y side.
	_cone(bm, pos, r_front, r_back, height, segments, mathutils.Matrix.Rotation(math.radians(90), 4, 'X'))


def bolt_ring(bm, y, radius, count=8, bolt_r=0.008, bolt_len=0.014):
	"""A ring of small bolt heads around a barrel/collar at station `y`."""
	for i in range(count):
		a = (i / count) * math.tau
		add_cyl_y(bm, (math.cos(a) * radius, y, math.sin(a) * radius), bolt_r, bolt_len, segments=6)


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
# MK19 GRENADE LAUNCHER
# Squat, boxy, belt-fed. The real weapon's read is a big rectangular
# receiver with a short fat low-velocity tube and a chunky side feed.
# ---------------------------------------------------------------------------
def build_mk19():
	# 1. CRADLE MOUNT - origin at deck level
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.025), 0.17, 0.05, segments=18)      # deck ring
	add_cyl_z(bm, (0, 0, 0.07), 0.12, 0.05, segments=14)       # swivel collar
	for i in range(6):                                          # ring of bolts
		a = (i / 6) * math.tau
		add_cyl_z(bm, (math.cos(a) * 0.145, math.sin(a) * 0.145, 0.055), 0.012, 0.02, segments=6)
	for side in (-1, 1):                                        # trunnion fork
		add_box(bm, (side * 0.13, 0, 0.16), (0.045, 0.15, 0.19), bevel=0.008)
		add_cyl_x(bm, (side * 0.15, 0, 0.25), 0.038, 0.035, segments=12)
	add_box(bm, (0, -0.11, 0.11), (0.10, 0.05, 0.07), bevel=0.006)  # elevation screw block
	add_cyl_z(bm, (0, -0.11, 0.19), 0.014, 0.14, segments=10)
	export_bmesh(bm, "mk19_mount", "mk19_mount.glb", color=(0.16, 0.18, 0.15, 1.0))

	# 2. RECEIVER - origin at trunnion height
	bm = bmesh.new()
	rw, rd, rh = 0.17, 0.40, 0.20
	add_box(bm, (0, -0.04, 0.0), (rw, rd, rh), bevel=0.012)          # main body
	add_box(bm, (0, -0.02, 0.115), (rw * 0.86, rd * 0.62, 0.035), bevel=0.006)  # feed cover
	add_box(bm, (0, -0.20, 0.115), (rw * 0.45, 0.05, 0.045), bevel=0.005)       # cover latch
	add_cyl_x(bm, (0, -0.20, 0.115), 0.012, rw * 0.5, segments=8)              # hinge pin
	# Side cocking rails, both sides
	for side in (-1, 1):
		add_box(bm, (side * (rw * 0.5 + 0.012), -0.02, 0.03), (0.02, rd * 0.7, 0.03), bevel=0.004)
		add_cyl_x(bm, (side * (rw * 0.5 + 0.04), 0.06, 0.03), 0.018, 0.05, segments=10)
	# Rear spade grips + butterfly trigger
	add_box(bm, (0, -0.245, 0.02), (rw * 0.8, 0.04, rh * 0.7), bevel=0.006)
	for d in (-1, 1):
		add_cyl_y(bm, (d * 0.085, -0.285, 0.03), 0.016, 0.07, segments=8)
		add_cyl_z(bm, (d * 0.085, -0.315, 0.005), 0.019, 0.11, segments=10)
	add_cyl_x(bm, (0, -0.30, -0.01), 0.012, 0.10, segments=8)
	# Top optic rail + blade sight
	add_box(bm, (0, 0.08, 0.14), (0.035, 0.14, 0.016), bevel=0.003)
	add_box(bm, (0, 0.14, 0.165), (0.03, 0.012, 0.04), bevel=0.003)
	export_bmesh(bm, "mk19_receiver", "mk19_receiver.glb", color=(0.17, 0.19, 0.16, 1.0))

	# 3. BARREL - origin at receiver front face, extends +Y
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0.045, 0), 0.062, 0.09, segments=16)      # breech collar
	bolt_ring(bm, 0.045, 0.052, count=8)
	add_cyl_y(bm, (0, 0.20, 0), 0.045, 0.22, segments=16)       # short fat tube
	for i in range(4):                                          # cooling bands
		add_cyl_y(bm, (0, 0.115 + i * 0.055, 0), 0.052, 0.016, segments=16)
	add_taper_y(bm, (0, 0.335, 0), 0.045, 0.055, 0.06, segments=16)  # flared muzzle
	export_bmesh(bm, "mk19_barrel", "mk19_barrel.glb", color=(0.13, 0.14, 0.13, 1.0))

	# 4. AMMO CAN - origin at the side feed tray
	bm = bmesh.new()
	add_box(bm, (-0.15, 0.0, 0.0), (0.19, 0.24, 0.20), bevel=0.012)   # can body
	add_box(bm, (-0.15, 0.0, 0.105), (0.17, 0.22, 0.02), bevel=0.005)  # lid
	add_cyl_x(bm, (-0.15, 0.0, 0.125), 0.018, 0.10, segments=10)       # carry handle
	for i in range(3):                                                  # rib stiffeners
		add_box(bm, (-0.15, -0.08 + i * 0.08, -0.02), (0.20, 0.014, 0.13), bevel=0.003)
	# Belt of linked rounds curving up into the receiver
	for i in range(5):
		add_box(bm, (-0.10 + i * 0.018, 0.02 + i * 0.012, 0.06 + i * 0.012),
				(0.030, 0.028, 0.022), bevel=0.004)
	export_bmesh(bm, "mk19_ammo_can", "mk19_ammo_can.glb", color=(0.22, 0.26, 0.18, 1.0),
				 metallic=0.4, roughness=0.6)


# ---------------------------------------------------------------------------
# RECOILLESS RIFLE
# One long open tube with a flared venturi at the BACK. The venturi is the
# whole visual identity, and it points where the backblast damage cone goes.
# ---------------------------------------------------------------------------
def build_recoilless():
	# 1. TRIPOD/PINTLE MOUNT - origin at deck
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.02), 0.15, 0.04, segments=18)
	for i in range(3):                                       # three splayed legs
		a = (i / 3) * math.tau + 0.5
		lx, ly = math.cos(a) * 0.16, math.sin(a) * 0.16
		add_box(bm, (lx * 0.6, ly * 0.6, 0.05), (0.05, 0.05, 0.03), bevel=0.005)
		add_cyl_z(bm, (lx, ly, 0.03), 0.022, 0.06, segments=8)
	add_cyl_z(bm, (0, 0, 0.10), 0.055, 0.12, segments=14)    # centre post
	for side in (-1, 1):                                     # yoke arms
		add_box(bm, (side * 0.10, 0, 0.20), (0.035, 0.13, 0.16), bevel=0.007)
		add_cyl_x(bm, (side * 0.115, 0, 0.27), 0.032, 0.03, segments=12)
	export_bmesh(bm, "recoilless_mount", "recoilless_mount.glb", color=(0.24, 0.23, 0.20, 1.0))

	# 2. BREECH ASSEMBLY - origin at trunnion. Split out of the tube so
	#    barrel_length stretches ONLY the tube: the breech ring, sight and
	#    trigger grip are fixed hardware and must keep their proportions
	#    whatever length the tube is set to.
	bm = bmesh.new()
	add_cyl_y(bm, (0, -0.04, 0), 0.082, 0.12, segments=20)    # breech ring
	bolt_ring(bm, -0.04, 0.070, count=10)
	add_cyl_y(bm, (0, 0.03, 0), 0.070, 0.03, segments=20)     # tube collar
	# Optical sight on a riser, offset left as on the real weapon
	add_box(bm, (-0.075, 0.04, 0.075), (0.03, 0.05, 0.07), bevel=0.005)
	add_cyl_y(bm, (-0.075, 0.08, 0.115), 0.026, 0.16, segments=14)
	add_cyl_y(bm, (-0.075, 0.165, 0.115), 0.032, 0.03, segments=14)
	# Trigger grip below the breech
	add_box(bm, (0, 0.0, -0.085), (0.035, 0.07, 0.09), bevel=0.006)
	add_cyl_x(bm, (0, -0.015, -0.055), 0.010, 0.035, segments=8)
	export_bmesh(bm, "recoilless_breech", "recoilless_breech.glb", color=(0.24, 0.23, 0.20, 1.0))

	# 3. TUBE - origin at the breech's front face, extends +Y so a
	#    barrel_length scale grows it forward and nothing else moves.
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0.36, 0), 0.062, 0.72, segments=20)     # main tube
	add_cyl_y(bm, (0, 0.70, 0), 0.070, 0.05, segments=20)     # muzzle collar
	for i in range(3):                                        # reinforcing bands
		add_cyl_y(bm, (0, 0.14 + i * 0.20, 0), 0.070, 0.022, segments=20)
	# Carry handle over the balance point
	add_box(bm, (0, 0.30, 0.085), (0.022, 0.16, 0.018), bevel=0.004)
	for hy in (0.23, 0.37):
		add_box(bm, (0, hy, 0.072), (0.022, 0.02, 0.03), bevel=0.003)
	export_bmesh(bm, "recoilless_tube", "recoilless_tube.glb", color=(0.26, 0.25, 0.21, 1.0))

	# 4. VENTURI / BLAST NOZZLE - origin at tube rear, flares toward -Y
	bm = bmesh.new()
	add_cyl_y(bm, (0, -0.03, 0), 0.075, 0.06, segments=20)          # throat
	add_taper_y(bm, (0, -0.14, 0), 0.155, 0.072, 0.17, segments=22)  # bell, wide at -Y
	add_cyl_y(bm, (0, -0.228, 0), 0.158, 0.022, segments=22)         # lip ring
	for i in range(6):                                               # external ribs
		a = (i / 6) * math.tau
		add_box(bm, (math.cos(a) * 0.115, -0.14, math.sin(a) * 0.115),
				(0.016, 0.16, 0.016), bevel=0.003)
	export_bmesh(bm, "recoilless_venturi", "recoilless_venturi.glb", color=(0.12, 0.12, 0.12, 1.0),
				 metallic=0.85, roughness=0.45)


# ---------------------------------------------------------------------------
# COIL GUN
# Reads as a related-but-distinct sibling to the railgun: a slim rail
# wrapped in a stack of copper accelerator coils, fed by capacitor cans.
# ---------------------------------------------------------------------------
def build_coilgun():
	# 1. MOUNT - origin at deck
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.025), 0.19, 0.05, segments=20)
	add_cyl_z(bm, (0, 0, 0.075), 0.14, 0.05, segments=16)
	for i in range(8):
		a = (i / 8) * math.tau
		add_box(bm, (math.cos(a) * 0.165, math.sin(a) * 0.165, 0.05), (0.03, 0.03, 0.035), bevel=0.004)
	for side in (-1, 1):
		add_box(bm, (side * 0.145, -0.02, 0.17), (0.05, 0.18, 0.20), bevel=0.008)
		add_cyl_x(bm, (side * 0.17, 0.02, 0.27), 0.042, 0.035, segments=14)
	# Cable conduit running up the rear of the mount
	add_cyl_z(bm, (0, -0.14, 0.13), 0.026, 0.24, segments=12)
	add_cyl_y(bm, (0, -0.10, 0.25), 0.026, 0.09, segments=12)
	export_bmesh(bm, "coilgun_mount", "coilgun_mount.glb", color=(0.20, 0.24, 0.28, 1.0))

	# 2. BREECH BLOCK - origin at trunnion. Separate from the rail so the
	#    stage-count tweak can lengthen the rail without stretching the
	#    breech, its hatch or its hinge.
	bm = bmesh.new()
	add_box(bm, (0, -0.06, 0.0), (0.17, 0.20, 0.17), bevel=0.014)    # breech block
	add_box(bm, (0, -0.06, 0.10), (0.12, 0.14, 0.03), bevel=0.005)   # loading hatch
	add_cyl_x(bm, (0, -0.13, 0.10), 0.012, 0.13, segments=8)         # hatch hinge
	add_box(bm, (0, -0.16, 0.0), (0.14, 0.03, 0.14), bevel=0.005)    # rear plate
	export_bmesh(bm, "coilgun_breech", "coilgun_breech.glb", color=(0.22, 0.25, 0.28, 1.0))

	# 3. RAIL SPINE - origin at the breech's front face, extends +Y.
	bm = bmesh.new()
	add_box(bm, (0, 0.40, 0), (0.085, 0.80, 0.075), bevel=0.010)     # spine
	for side in (-1, 1):                                             # guide rails
		add_box(bm, (side * 0.055, 0.40, 0), (0.018, 0.78, 0.035), bevel=0.004)
	add_cyl_y(bm, (0, 0.82, 0), 0.072, 0.10, segments=18)            # muzzle shroud
	add_cyl_y(bm, (0, 0.885, 0), 0.058, 0.035, segments=18)
	export_bmesh(bm, "coilgun_rail", "coilgun_rail.glb", color=(0.24, 0.27, 0.30, 1.0))

	# 4. ACCELERATOR COIL - a single copper coil, repeated along the rail by
	#    visual_builder so the stage-count tweak is visible. Origin centred.
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0, 0), 0.105, 0.055, segments=20)              # winding body
	add_cyl_y(bm, (0, 0, 0), 0.118, 0.014, segments=20)              # outer band
	for i in range(4):                                               # winding grooves
		add_cyl_y(bm, (0, -0.018 + i * 0.012, 0), 0.112, 0.005, segments=20)
	add_box(bm, (0, 0, 0.115), (0.035, 0.045, 0.035), bevel=0.005)   # terminal block
	add_cyl_z(bm, (0, 0, 0.145), 0.010, 0.035, segments=8)           # lug
	export_bmesh(bm, "coilgun_coil", "coilgun_coil.glb", color=(0.62, 0.36, 0.14, 1.0),
				 metallic=0.9, roughness=0.30)

	# 5. CAPACITOR BANK - origin at its mounting face under the breech
	bm = bmesh.new()
	add_box(bm, (0, 0, -0.06), (0.26, 0.24, 0.10), bevel=0.010)      # chassis
	for cx in (-1, 1):                                               # four cans
		for cy in (-1, 1):
			add_cyl_z(bm, (cx * 0.07, cy * 0.07, 0.03), 0.048, 0.14, segments=14)
			add_cyl_z(bm, (cx * 0.07, cy * 0.07, 0.105), 0.030, 0.02, segments=10)
	add_box(bm, (0, 0, 0.115), (0.20, 0.03, 0.016), bevel=0.003)     # busbar
	export_bmesh(bm, "coilgun_capacitors", "coilgun_capacitors.glb", color=(0.30, 0.33, 0.36, 1.0))


# ---------------------------------------------------------------------------
# AUTOCANNON - M230 chain gun (AH-64 Apache chin turret)
#
# Remodelled from a generic "long thin barrel with a pepper-pot brake"
# autocannon. The M230's read is specific and nothing like that:
#   - a SHORT, boxy, almost square receiver, not a long rifle action
#   - the chain drive housing bulging off the LEFT flank as a flat oval cover
#     with the sprocket boss standing proud of it - this is THE signature
#     feature and the reason it's called a chain gun
#   - a plain unbraked muzzle (a chin gun firing forward over open ground has
#     nothing to protect, and a brake would blast the airframe)
#   - a slim barrel of genuinely large diameter relative to the receiver
#   - the whole thing hung in a U-shaped chin YOKE with visible elevation
#     actuators, rather than sat on a pintle
#   - a linkless feed chute curving up into the receiver's underside
# ---------------------------------------------------------------------------
def build_autocannon():
	# 1. CHIN YOKE MOUNT - origin at deck
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.020), 0.165, 0.040, segments=22)        # azimuth ring
	for i in range(12):                                            # ring bolts
		a = (i / 12) * math.tau
		add_cyl_z(bm, (math.cos(a) * 0.145, math.sin(a) * 0.145, 0.042), 0.010, 0.016, segments=6)
	add_cyl_z(bm, (0, 0, 0.070), 0.115, 0.062, segments=20)        # turret drum
	add_box(bm, (0, 0.075, 0.075), (0.13, 0.055, 0.070), bevel=0.008)   # drive gearbox
	add_cyl_y(bm, (0, 0.112, 0.075), 0.030, 0.030, segments=12)

	# U-shaped yoke arms carrying the trunnions. Swept forward and taller
	# than a pintle's fork - the gun hangs INSIDE the yoke.
	for side in (-1, 1):
		add_box(bm, (side * 0.135, 0.010, 0.175), (0.042, 0.115, 0.180), bevel=0.009)
		add_box(bm, (side * 0.135, -0.045, 0.105), (0.038, 0.075, 0.055), bevel=0.006)
		add_cyl_x(bm, (side * 0.158, 0.010, 0.250), 0.040, 0.034, segments=14)   # trunnion boss
		for i in range(6):                                                       # trunnion bolts
			a = (i / 6) * math.tau
			add_cyl_x(bm, (side * 0.176, 0.010 + math.cos(a) * 0.028, 0.250 + math.sin(a) * 0.028),
					  0.007, 0.012, segments=6)
		# Elevation actuator: cylinder + exposed ram running up to the cradle
		add_cyl_z(bm, (side * 0.112, -0.085, 0.130), 0.026, 0.115, segments=12)
		add_cyl_z(bm, (side * 0.112, -0.085, 0.205), 0.013, 0.070, segments=10)
		add_box(bm, (side * 0.112, -0.085, 0.245), (0.036, 0.030, 0.022), bevel=0.004)
	# Hydraulic lines looping between the actuators
	for i in range(4):
		add_cyl_x(bm, (0, -0.085, 0.085 + i * 0.012), 0.008, 0.20, segments=6)
	export_bmesh(bm, "autocannon_mount", "autocannon_mount.glb", color=(0.19, 0.20, 0.22, 1.0))

	# 2. RECEIVER - origin at trunnion. Squat and square, with the chain
	#    drive housing on the left flank.
	bm = bmesh.new()
	rw, rd, rh = 0.155, 0.30, 0.175
	add_box(bm, (0, -0.045, 0.0), (rw, rd, rh), bevel=0.012)          # main body
	add_box(bm, (0, -0.035, 0.098), (rw * 0.80, rd * 0.80, 0.026), bevel=0.006)   # top cover
	for i in range(3):                                                # cover latches
		add_box(bm, (0, -0.13 + i * 0.085, 0.115), (rw * 0.55, 0.018, 0.012), bevel=0.003)

	# THE CHAIN HOUSING - flat oval cover on the left flank, sprocket boss
	# standing proud of it. This is the part that makes it read as an M230.
	add_box(bm, (-0.098, -0.045, 0.010), (0.048, 0.245, 0.135), bevel=0.020)
	add_cyl_x(bm, (-0.128, 0.040, 0.010), 0.052, 0.026, segments=18)   # front sprocket boss
	add_cyl_x(bm, (-0.128, -0.130, 0.010), 0.044, 0.026, segments=16)  # rear sprocket boss
	add_cyl_x(bm, (-0.142, 0.040, 0.010), 0.020, 0.020, segments=10)   # sprocket hub cap
	for i in range(6):                                                 # housing screws
		a = (i / 6) * math.tau
		add_cyl_x(bm, (-0.124, 0.040 + math.cos(a) * 0.062, 0.010 + math.sin(a) * 0.062),
				  0.007, 0.014, segments=6)
	# Drive motor stub off the back of the chain housing
	add_cyl_y(bm, (-0.098, -0.215, 0.010), 0.042, 0.075, segments=14)
	add_cyl_y(bm, (-0.098, -0.258, 0.010), 0.030, 0.020, segments=12)

	# Right flank: ejection port and a flat inspection plate (deliberately
	# plainer than the left - the asymmetry IS the silhouette)
	add_box(bm, (rw * 0.5 + 0.008, -0.075, -0.020), (0.014, 0.105, 0.058), bevel=0.004)
	add_box(bm, (rw * 0.5 + 0.006, 0.035, 0.020), (0.010, 0.085, 0.075), bevel=0.004)

	# Recoil buffer through the back face, and the mounting lugs
	add_cyl_y(bm, (0, -0.205, 0.020), 0.040, 0.070, segments=14)
	add_cyl_y(bm, (0, -0.245, 0.020), 0.048, 0.022, segments=14)
	for side in (-1, 1):
		add_box(bm, (side * (rw * 0.5 + 0.012), 0.010, 0.0), (0.028, 0.070, 0.075), bevel=0.006)
		add_cyl_x(bm, (side * (rw * 0.5 + 0.030), 0.010, 0.0), 0.030, 0.020, segments=14)

	# Feed throat on the underside (linkless feed comes up from below on a
	# chin gun, not in from the side)
	add_box(bm, (0, -0.020, -0.105), (0.105, 0.115, 0.045), bevel=0.008)
	export_bmesh(bm, "autocannon_receiver", "autocannon_receiver.glb", color=(0.20, 0.21, 0.23, 1.0))

	# 3. BARREL - origin at receiver face, extends +Y. Plain muzzle: no brake.
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0.045, 0), 0.058, 0.090, segments=18)      # barrel nut / breech collar
	bolt_ring(bm, 0.045, 0.048, count=8)
	add_cyl_y(bm, (0, 0.115, 0), 0.046, 0.060, segments=16)      # chamber shoulder
	add_taper_y(bm, (0, 0.175, 0), 0.046, 0.036, 0.060, segments=16)
	add_cyl_y(bm, (0, 0.480, 0), 0.034, 0.560, segments=16)      # the tube
	for i in range(2):                                           # barrel clamps
		add_cyl_y(bm, (0, 0.290 + i * 0.230, 0), 0.042, 0.026, segments=16)
		add_box(bm, (0, 0.290 + i * 0.230, 0.048), (0.030, 0.022, 0.030), bevel=0.004)
	add_cyl_y(bm, (0, 0.768, 0), 0.038, 0.026, segments=16)      # muzzle band
	add_cyl_y(bm, (0, 0.790, 0), 0.033, 0.022, segments=16)      # crown
	export_bmesh(bm, "autocannon_barrel", "autocannon_barrel.glb", color=(0.13, 0.14, 0.15, 1.0))

	# 4. LINKLESS AMMO MAGAZINE - its own part so the drum_size tweak scales
	#    ONLY the magazine. Origin at the receiver's underside feed throat.
	bm = bmesh.new()
	add_cyl_z(bm, (0, -0.055, -0.185), 0.140, 0.150, segments=20)      # drum body
	add_cyl_z(bm, (0, -0.055, -0.108), 0.115, 0.020, segments=20)      # drum lid
	add_cyl_z(bm, (0, -0.055, -0.265), 0.120, 0.018, segments=20)      # drum floor
	for i in range(8):                                                  # drum ribs
		a = (i / 8) * math.tau
		add_box(bm, (math.cos(a) * 0.132, -0.055 + math.sin(a) * 0.132, -0.185),
				(0.022, 0.022, 0.140), bevel=0.004)
	add_cyl_z(bm, (0, -0.055, -0.185), 0.038, 0.170, segments=12)      # centre auger
	# Linkless feed chute curving up into the receiver's underside throat
	for i in range(5):
		add_box(bm, (0, -0.048 + i * 0.011, -0.115 + i * 0.026), (0.075, 0.040, 0.034), bevel=0.006)
	add_box(bm, (0, 0.005, 0.010), (0.085, 0.055, 0.040), bevel=0.006)  # throat collar
	export_bmesh(bm, "autocannon_ammo_box", "autocannon_ammo_box.glb", color=(0.21, 0.24, 0.20, 1.0),
				 metallic=0.4, roughness=0.6)


# ---------------------------------------------------------------------------
# ANTI-MATERIEL RIFLE - Bushmaster-III-derived precision cannon
#
# The roster has no PRECISION weapon at all: everything is DPS or splash.
# This one lives or dies on a single very large per-shot number against the
# armor thresholds, so its silhouette has to promise that - long, thin,
# deliberate, and covered in sighting equipment rather than ammunition.
#
# Reference read (Bushmaster III 35mm), plus Chris's two specifics:
#   - a LONG greebled breech running back THROUGH the trunnions, so the gun
#     is visibly balanced about its middle rather than hung off its back end
#   - an expanded sensor package: day/thermal sight block, laser rangefinder
#     and a meteorological probe, all on the left of the breech
#   - a very long slim tube with a big multi-baffle muzzle brake, authored as
#     a SEPARATE part so barrel_length stretches only the tube
# ---------------------------------------------------------------------------
def build_anti_materiel_rifle():
	# 1. TRUNNION CRADLE MOUNT - origin at deck
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.018), 0.180, 0.036, segments=24)         # base ring
	for i in range(14):
		a = (i / 14) * math.tau
		add_cyl_z(bm, (math.cos(a) * 0.160, math.sin(a) * 0.160, 0.040), 0.009, 0.016, segments=6)
	add_cyl_z(bm, (0, 0, 0.078), 0.120, 0.084, segments=20)         # traverse drum
	add_box(bm, (0, -0.115, 0.070), (0.10, 0.075, 0.075), bevel=0.008)   # traverse gearbox
	add_cyl_y(bm, (0, -0.155, 0.070), 0.028, 0.030, segments=12)

	# Tall trunnion forks - taller than the autocannon's, because the breech
	# they carry passes right through them.
	for side in (-1, 1):
		add_box(bm, (side * 0.150, -0.010, 0.190), (0.046, 0.130, 0.210), bevel=0.009)
		add_cyl_x(bm, (side * 0.176, -0.010, 0.278), 0.046, 0.036, segments=16)
		add_cyl_x(bm, (side * 0.198, -0.010, 0.278), 0.022, 0.016, segments=10)
		for i in range(8):
			a = (i / 8) * math.tau
			add_cyl_x(bm, (side * 0.194, -0.010 + math.cos(a) * 0.033, 0.278 + math.sin(a) * 0.033),
					  0.007, 0.012, segments=6)
		# Equilibrator spring stack alongside each fork
		add_cyl_z(bm, (side * 0.105, -0.100, 0.150), 0.030, 0.150, segments=14)
		for i in range(5):
			add_cyl_z(bm, (side * 0.105, -0.100, 0.090 + i * 0.030), 0.036, 0.012, segments=14)
		add_cyl_z(bm, (side * 0.105, -0.100, 0.240), 0.014, 0.070, segments=10)
	export_bmesh(bm, "amr_mount", "amr_mount.glb", color=(0.19, 0.20, 0.22, 1.0))

	# 2. BREECH - origin at the trunnion. Deliberately LONG, running well
	#    behind the trunnion line, and heavily greebled.
	bm = bmesh.new()
	add_box(bm, (0, -0.150, 0.0), (0.150, 0.520, 0.165), bevel=0.013)      # long breech body
	add_box(bm, (0, -0.140, 0.096), (0.120, 0.440, 0.030), bevel=0.006)    # top rail deck
	for i in range(7):                                                     # rail teeth
		add_box(bm, (0, -0.320 + i * 0.062, 0.117), (0.100, 0.026, 0.016), bevel=0.003)

	# Vertical sliding breech block, part-open, with its operating lever
	add_box(bm, (0, 0.050, 0.010), (0.130, 0.075, 0.150), bevel=0.008)
	add_box(bm, (0, 0.050, 0.058), (0.108, 0.055, 0.030), bevel=0.005)
	add_cyl_x(bm, (0.088, 0.050, 0.052), 0.018, 0.055, segments=12)
	add_box(bm, (0.115, 0.012, 0.052), (0.022, 0.090, 0.020), bevel=0.004)  # operating lever

	# Recoil slides either side, with exposed rods and buffer heads
	for side in (-1, 1):
		add_cyl_y(bm, (side * 0.098, -0.060, 0.070), 0.028, 0.380, segments=14)
		add_cyl_y(bm, (side * 0.098, 0.145, 0.070), 0.036, 0.045, segments=14)
		add_cyl_y(bm, (side * 0.098, -0.265, 0.070), 0.040, 0.055, segments=14)
		for i in range(4):
			add_cyl_y(bm, (side * 0.098, -0.190 + i * 0.075, 0.070), 0.034, 0.014, segments=14)

	# Dual feed chutes off the rear quarters - the Bushmaster's other
	# signature. Kept small: this weapon is not about volume of fire.
	for side in (-1, 1):
		add_box(bm, (side * 0.105, -0.330, -0.030), (0.062, 0.140, 0.085), bevel=0.007)
		add_box(bm, (side * 0.088, -0.240, -0.020), (0.040, 0.080, 0.060), bevel=0.005)
		for i in range(3):
			add_box(bm, (side * 0.105, -0.395 + i * 0.030, -0.075), (0.058, 0.020, 0.016), bevel=0.003)

	# Rear plate: buffer cap, junction box, cable runs
	add_box(bm, (0, -0.415, 0.010), (0.140, 0.030, 0.150), bevel=0.007)
	add_cyl_y(bm, (0, -0.445, 0.010), 0.050, 0.040, segments=16)
	add_box(bm, (-0.075, -0.440, -0.055), (0.055, 0.045, 0.050), bevel=0.005)
	for i in range(4):
		add_cyl_y(bm, (-0.075 + i * 0.012, -0.470, -0.055), 0.006, 0.030, segments=6)
	# Ammunition ready-rack strapped along the right flank
	add_box(bm, (0.098, -0.230, 0.075), (0.055, 0.190, 0.055), bevel=0.006)
	for i in range(4):
		add_cyl_y(bm, (0.098, -0.305 + i * 0.050, 0.075), 0.020, 0.042, segments=10)
	export_bmesh(bm, "amr_breech", "amr_breech.glb", color=(0.20, 0.22, 0.21, 1.0))

	# 3. BARREL - origin at the breech's front face, along +Y. Long and thin.
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0.055, 0), 0.062, 0.110, segments=18)       # barrel nut
	bolt_ring(bm, 0.055, 0.052, count=10)
	add_taper_y(bm, (0, 0.155, 0), 0.052, 0.034, 0.090, segments=18)  # chamber taper
	add_cyl_y(bm, (0, 0.620, 0), 0.030, 0.840, segments=18)       # the long tube
	for i in range(4):                                             # barrel bands
		add_cyl_y(bm, (0, 0.290 + i * 0.200, 0), 0.037, 0.020, segments=18)
	# Fluting along the tube, so it doesn't read as a plain pipe at length
	for i in range(3):
		a = (i / 3) * math.tau
		add_box(bm, (math.cos(a) * 0.031, 0.620, math.sin(a) * 0.031), (0.010, 0.700, 0.010))
	export_bmesh(bm, "amr_barrel", "amr_barrel.glb", color=(0.13, 0.14, 0.15, 1.0))

	# 4. MUZZLE BRAKE - separate part, positioned at the barrel's actual tip
	#    by visual_builder so barrel_length never stretches it. Origin at its
	#    own rear face.
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0.020, 0), 0.048, 0.040, segments=18)       # collar
	add_cyl_y(bm, (0, 0.115, 0), 0.058, 0.155, segments=18)       # body
	for i in range(3):                                            # baffle slots
		for side in (-1, 1):
			add_box(bm, (side * 0.056, 0.060 + i * 0.045, 0), (0.026, 0.024, 0.070), bevel=0.004)
			add_cyl_x(bm, (side * 0.058, 0.060 + i * 0.045, 0), 0.016, 0.024, segments=10)
	add_cyl_y(bm, (0, 0.205, 0), 0.050, 0.030, segments=18)       # crown ring
	add_cyl_y(bm, (0, 0.228, 0), 0.038, 0.020, segments=16)
	export_bmesh(bm, "amr_muzzle_brake", "amr_muzzle_brake.glb", color=(0.115, 0.10, 0.095, 1.0),
				 metallic=0.62, roughness=0.72)

	# 5. SENSOR POD - the "expanded sensors". Day sight, thermal aperture,
	#    laser rangefinder and a met probe, on a shock-mounted raft. Origin at
	#    its mounting face on the breech's left flank; apertures face +Y.
	bm = bmesh.new()
	add_box(bm, (0, -0.010, 0.0), (0.135, 0.230, 0.115), bevel=0.010)   # pod body
	add_box(bm, (0, -0.010, 0.070), (0.115, 0.200, 0.030), bevel=0.006) # sunshade roof
	# Day sight: big square window with a hood
	add_box(bm, (-0.028, 0.108, 0.018), (0.062, 0.024, 0.062), bevel=0.005)
	add_box(bm, (-0.028, 0.126, 0.040), (0.070, 0.030, 0.020), bevel=0.004)
	# Thermal aperture: round, recessed
	add_cyl_y(bm, (0.048, 0.108, 0.010), 0.032, 0.028, segments=16)
	add_cyl_y(bm, (0.048, 0.124, 0.010), 0.026, 0.014, segments=16)
	# Laser rangefinder tube slung underneath
	add_cyl_y(bm, (0.020, 0.060, -0.070), 0.024, 0.180, segments=14)
	add_cyl_y(bm, (0.020, 0.152, -0.070), 0.030, 0.020, segments=14)
	# Meteorological probe on a whip off the back corner
	add_cyl_z(bm, (-0.050, -0.110, 0.095), 0.008, 0.120, segments=8)
	add_cyl_z(bm, (-0.050, -0.110, 0.165), 0.020, 0.028, segments=12)
	# Shock mounts and a cable loom back toward the breech
	for side in (-1, 1):
		add_cyl_x(bm, (side * 0.070, -0.090, -0.050), 0.018, 0.030, segments=10)
	for i in range(4):
		add_cyl_y(bm, (-0.085, -0.140 - i * 0.006, -0.030 + i * 0.012), 0.007, 0.060, segments=6)
	export_bmesh(bm, "amr_sensor_pod", "amr_sensor_pod.glb", color=(0.17, 0.19, 0.18, 1.0),
				 metallic=0.45, roughness=0.55)

	# 6. BIPOD - shown only when the bipod_deploy tweak is on. Origin at the
	#    deck under the barrel; legs splay out and forward.
	bm = bmesh.new()
	add_box(bm, (0, 0.020, 0.140), (0.070, 0.055, 0.045), bevel=0.006)   # yoke clamp
	add_cyl_x(bm, (0, 0.020, 0.140), 0.020, 0.090, segments=12)
	for side in (-1, 1):
		# Upper leg, splayed out and down
		add_cyl_z(bm, (side * 0.075, 0.020, 0.080), 0.016, 0.130, segments=10)
		add_cyl_z(bm, (side * 0.115, 0.020, 0.020), 0.013, 0.055, segments=10)
		# Foot pad with a spade
		add_cyl_z(bm, (side * 0.130, 0.020, 0.008), 0.038, 0.016, segments=14)
		add_box(bm, (side * 0.130, 0.045, 0.006), (0.050, 0.030, 0.012), bevel=0.003)
		# Adjustment collar
		add_cyl_z(bm, (side * 0.105, 0.020, 0.048), 0.022, 0.020, segments=12)
	export_bmesh(bm, "amr_bipod", "amr_bipod.glb", color=(0.18, 0.19, 0.20, 1.0))


# ---------------------------------------------------------------------------
# NAPALM MORTAR
# Short very fat tube at a steep fixed elevation, with a pressurised fuel
# drum and plumbing alongside.
# ---------------------------------------------------------------------------
def build_napalm_mortar():
	# 1. BASEPLATE MOUNT - origin at deck
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.02), 0.24, 0.04, segments=22)          # baseplate
	for i in range(8):                                            # plate ribs
		a = (i / 8) * math.tau
		add_box(bm, (math.cos(a) * 0.15, math.sin(a) * 0.15, 0.045), (0.10, 0.02, 0.02), bevel=0.003)
	add_cyl_z(bm, (0, 0, 0.075), 0.09, 0.07, segments=16)         # swivel
	add_box(bm, (0, 0.06, 0.14), (0.14, 0.10, 0.10), bevel=0.010)  # elevation cradle
	for side in (-1, 1):
		add_cyl_x(bm, (side * 0.075, 0.06, 0.18), 0.028, 0.03, segments=12)
	export_bmesh(bm, "napalm_mount", "napalm_mount.glb", color=(0.30, 0.24, 0.16, 1.0))

	# 2. BREECH CAP - origin at cradle trunnion. Separate part so
	#    barrel_length stretches only the tube, never the sealed breech or
	#    its ignition gear.
	bm = bmesh.new()
	add_cyl_y(bm, (0, -0.05, 0), 0.135, 0.10, segments=20)        # breech cap
	bolt_ring(bm, -0.05, 0.115, count=10, bolt_r=0.010, bolt_len=0.018)
	add_box(bm, (0.10, -0.02, 0.06), (0.045, 0.06, 0.045), bevel=0.005)  # igniter box
	add_cyl_z(bm, (0.10, -0.02, 0.10), 0.010, 0.05, segments=8)
	export_bmesh(bm, "napalm_breech", "napalm_breech.glb", color=(0.30, 0.28, 0.24, 1.0))

	# 3. TUBE - origin at the breech's front face, bore along +Y
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0.25, 0), 0.115, 0.50, segments=20)         # fat short tube
	add_taper_y(bm, (0, 0.53, 0), 0.115, 0.135, 0.07, segments=20)  # flared mouth
	for i in range(4):                                            # cooling bands
		add_cyl_y(bm, (0, 0.09 + i * 0.11, 0), 0.126, 0.022, segments=20)
	add_cyl_y(bm, (0.10, 0.23, 0.06), 0.012, 0.42, segments=10)   # ignition line
	export_bmesh(bm, "napalm_tube", "napalm_tube.glb", color=(0.32, 0.30, 0.26, 1.0))

	# 4. FUEL DRUM - origin at its mounting face beside the tube
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.16), 0.115, 0.30, segments=20)         # drum
	add_cyl_z(bm, (0, 0, 0.315), 0.09, 0.03, segments=16)         # top dome
	add_cyl_z(bm, (0, 0, 0.012), 0.12, 0.025, segments=20)        # foot ring
	for i in range(3):                                            # banding hoops
		add_cyl_z(bm, (0, 0, 0.07 + i * 0.09), 0.122, 0.018, segments=20)
	add_cyl_z(bm, (0.0, 0.0, 0.35), 0.022, 0.05, segments=10)     # filler neck
	add_box(bm, (0, 0.0, 0.375), (0.06, 0.06, 0.02), bevel=0.004)  # pressure gauge plate
	# Feed hose curving out toward the tube
	for i in range(5):
		add_cyl_y(bm, (0.0, -0.02 - i * 0.03, 0.30 - i * 0.045), 0.016, 0.05, segments=8)
	export_bmesh(bm, "napalm_fuel_drum", "napalm_fuel_drum.glb", color=(0.52, 0.24, 0.09, 1.0),
				 metallic=0.35, roughness=0.62)


# ---------------------------------------------------------------------------
# MINE LAYER
# Reads as cargo being dispensed, not as a gun: a rack of canisters over a
# rear chute.
# ---------------------------------------------------------------------------
def build_mine_layer():
	# 1. RACK CHASSIS - origin at deck
	bm = bmesh.new()
	add_box(bm, (0, 0, 0.05), (0.46, 0.52, 0.10), bevel=0.010)     # deck pallet
	for cx in (-1, 1):                                             # corner posts
		for cy in (-1, 1):
			add_box(bm, (cx * 0.20, cy * 0.23, 0.20), (0.03, 0.03, 0.22), bevel=0.004)
	add_box(bm, (0, 0, 0.30), (0.46, 0.52, 0.025), bevel=0.005)    # top rail frame
	# Cross bracing on both sides
	for side in (-1, 1):
		add_box(bm, (side * 0.21, 0, 0.19), (0.012, 0.50, 0.02), bevel=0.003)
	add_box(bm, (0, -0.27, 0.16), (0.14, 0.03, 0.12), bevel=0.005)  # control box
	add_cyl_y(bm, (0.05, -0.29, 0.20), 0.012, 0.03, segments=8)
	export_bmesh(bm, "mine_layer_rack", "mine_layer_rack.glb", color=(0.34, 0.32, 0.20, 1.0))

	# 2. SINGLE MINE CANISTER - repeated by visual_builder so the
	#    mines-per-volley tweak is visible on the rack. Origin at its base.
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.035), 0.085, 0.07, segments=18)         # puck body
	add_cyl_z(bm, (0, 0, 0.075), 0.055, 0.02, segments=14)         # fuze well
	add_cyl_z(bm, (0, 0, 0.09), 0.018, 0.02, segments=10)          # pressure plug
	add_cyl_z(bm, (0, 0, 0.035), 0.092, 0.014, segments=18)        # carry band
	for i in range(4):                                             # handle lugs
		a = (i / 4) * math.tau + 0.4
		add_box(bm, (math.cos(a) * 0.088, math.sin(a) * 0.088, 0.05), (0.02, 0.02, 0.02), bevel=0.003)
	export_bmesh(bm, "mine_canister", "mine_canister.glb", color=(0.28, 0.30, 0.18, 1.0),
				 metallic=0.4, roughness=0.6)

	# 3. DISPENSER CHUTE - origin at the rack's rear face, opens toward -Y
	bm = bmesh.new()
	add_box(bm, (0, -0.06, 0.06), (0.20, 0.16, 0.14), bevel=0.008)   # chute body
	add_box(bm, (0, -0.16, 0.02), (0.22, 0.06, 0.10), bevel=0.006)   # exit lip
	for side in (-1, 1):                                             # guide rails
		add_box(bm, (side * 0.10, -0.12, 0.01), (0.014, 0.14, 0.05), bevel=0.003)
	add_cyl_x(bm, (0, -0.02, 0.14), 0.016, 0.20, segments=10)        # feed roller
	export_bmesh(bm, "mine_layer_chute", "mine_layer_chute.glb", color=(0.19, 0.20, 0.17, 1.0))


# ---------------------------------------------------------------------------
# BALLISTA
# The straight-faced absurdity piece. Has to read as a genuine siege engine
# from across the battlefield: torsion bundles, swept arms, a bowstring, a
# ratcheted windlass and a loaded bolt.
# ---------------------------------------------------------------------------
def build_ballista():
	# 1. TURNTABLE + TIMBER FRAME - origin at deck
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.03), 0.30, 0.06, segments=24)          # iron turntable
	for i in range(10):                                           # rivets
		a = (i / 10) * math.tau
		add_cyl_z(bm, (math.cos(a) * 0.26, math.sin(a) * 0.26, 0.062), 0.014, 0.014, segments=6)
	add_cyl_z(bm, (0, 0, 0.09), 0.16, 0.06, segments=18)          # pivot boss
	# Timber side frames running fore-aft
	for side in (-1, 1):
		add_box(bm, (side * 0.17, 0.02, 0.20), (0.055, 0.62, 0.16), bevel=0.010)
		# Iron strapping across the timbers
		for sy in (-0.20, 0.06, 0.26):
			add_box(bm, (side * 0.17, sy, 0.20), (0.062, 0.028, 0.17), bevel=0.004)
	add_box(bm, (0, -0.26, 0.16), (0.34, 0.06, 0.07), bevel=0.008)  # rear cross-beam
	add_box(bm, (0, 0.30, 0.16), (0.34, 0.06, 0.07), bevel=0.008)   # front cross-beam
	export_bmesh(bm, "ballista_frame", "ballista_frame.glb", color=(0.40, 0.29, 0.17, 1.0),
				 metallic=0.15, roughness=0.75)

	# 2. STOCK / SLIDER with windlass - origin at frame top centre
	bm = bmesh.new()
	add_box(bm, (0, 0.02, 0.03), (0.11, 0.80, 0.055), bevel=0.008)   # stock beam
	add_box(bm, (0, 0.02, 0.065), (0.045, 0.78, 0.022), bevel=0.004)  # bolt groove
	# Windlass drum and crank at the rear
	add_cyl_x(bm, (0, -0.34, 0.06), 0.055, 0.20, segments=16)
	for side in (-1, 1):
		add_cyl_x(bm, (side * 0.115, -0.34, 0.06), 0.070, 0.02, segments=14)   # ratchet discs
		for i in range(8):                                                     # ratchet teeth
			a = (i / 8) * math.tau
			add_box(bm, (side * 0.125, -0.34 + math.cos(a) * 0.062, 0.06 + math.sin(a) * 0.062),
					(0.014, 0.018, 0.018), bevel=0.002)
		add_cyl_z(bm, (side * 0.145, -0.34, 0.12), 0.012, 0.10, segments=8)    # crank handles
	add_box(bm, (0, -0.20, 0.09), (0.03, 0.10, 0.03), bevel=0.004)             # trigger claw
	export_bmesh(bm, "ballista_stock", "ballista_stock.glb", color=(0.44, 0.32, 0.19, 1.0),
				 metallic=0.15, roughness=0.75)

	# 3. TORSION BUNDLE + ARM - one side, mirrored by visual_builder.
	#    Origin at the bundle's mounting point on the frame.
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.10), 0.062, 0.20, segments=16)          # sinew bundle
	add_cyl_z(bm, (0, 0, 0.205), 0.075, 0.03, segments=16)         # top washer
	add_cyl_z(bm, (0, 0, 0.005), 0.075, 0.03, segments=16)         # bottom washer
	for i in range(6):                                             # tensioning pegs
		a = (i / 6) * math.tau
		add_cyl_z(bm, (math.cos(a) * 0.058, math.sin(a) * 0.058, 0.225), 0.011, 0.05, segments=6)
	# Swept throwing arm, angled forward and slightly out
	add_box(bm, (0.055, 0.14, 0.15), (0.045, 0.30, 0.05), bevel=0.008)
	add_box(bm, (0.115, 0.30, 0.15), (0.035, 0.16, 0.04), bevel=0.006)
	add_cyl_z(bm, (0.135, 0.375, 0.15), 0.022, 0.055, segments=12)  # string nock
	export_bmesh(bm, "ballista_arm", "ballista_arm.glb", color=(0.38, 0.27, 0.16, 1.0),
				 metallic=0.15, roughness=0.78)

	# 4. BOLT - origin at its rear, points +Y
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0.16, 0), 0.022, 0.56, segments=14)          # shaft
	add_taper_y(bm, (0, 0.49, 0), 0.038, 0.004, 0.14, segments=14)  # iron head
	add_cyl_y(bm, (0, 0.41, 0), 0.030, 0.03, segments=14)          # head collar
	for i in range(3):                                             # fletching vanes
		a = (i / 3) * math.tau
		add_box(bm, (math.cos(a) * 0.035, -0.08, math.sin(a) * 0.035),
				(0.010, 0.10, 0.055), bevel=0.002)
	export_bmesh(bm, "ballista_bolt", "ballista_bolt.glb", color=(0.24, 0.22, 0.19, 1.0),
				 metallic=0.6, roughness=0.5)


# ---------------------------------------------------------------------------
# SMOKE DISCHARGER
# Replaces the procedural stub with real hardware: a bracket and a proper
# launcher tube with a fitted canister.
# ---------------------------------------------------------------------------
def build_smoke_discharger():
	# 1. BRACKET - origin at deck
	bm = bmesh.new()
	add_box(bm, (0, 0, 0.03), (0.36, 0.20, 0.06), bevel=0.008)      # base plate
	for cx in (-1, 1):
		add_cyl_z(bm, (cx * 0.15, 0, 0.032), 0.018, 0.024, segments=8)  # bolt bosses
	add_box(bm, (0, 0.02, 0.09), (0.30, 0.13, 0.06), bevel=0.006)   # riser
	add_box(bm, (0, -0.08, 0.075), (0.10, 0.04, 0.045), bevel=0.004)  # wiring junction
	add_cyl_y(bm, (0, -0.115, 0.075), 0.012, 0.04, segments=8)
	export_bmesh(bm, "smoke_discharger_bracket", "smoke_discharger_bracket.glb",
				 color=(0.26, 0.27, 0.28, 1.0))

	# 2. SINGLE LAUNCHER TUBE with canister - repeated and splayed by
	#    visual_builder so the tube-count tweak is visible. Origin at its
	#    base, bore along +Y (visual_builder cants it upward).
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0.10, 0), 0.048, 0.20, segments=16)           # tube
	add_cyl_y(bm, (0, 0.005, 0), 0.058, 0.03, segments=16)          # base flange
	bolt_ring(bm, 0.005, 0.050, count=6, bolt_r=0.007, bolt_len=0.012)
	add_cyl_y(bm, (0, 0.19, 0), 0.054, 0.025, segments=16)          # muzzle ring
	add_cyl_y(bm, (0, 0.215, 0), 0.042, 0.03, segments=14)          # canister nose
	add_box(bm, (0.05, 0.06, 0), (0.022, 0.05, 0.022), bevel=0.003)  # firing lead boss
	export_bmesh(bm, "smoke_discharger_tube", "smoke_discharger_tube.glb",
				 color=(0.20, 0.21, 0.19, 1.0))


if __name__ == "__main__":
	clear_scene()
	build_mk19()
	build_recoilless()
	build_coilgun()
	build_autocannon()
	build_anti_materiel_rifle()
	build_napalm_mortar()
	build_mine_layer()
	build_ballista()
	build_smoke_discharger()
	print("ROSTER_EXPANSION_PARTS_DONE")
