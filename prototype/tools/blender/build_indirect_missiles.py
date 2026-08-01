import sys
import os
import math
import bmesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _greeble import *  # noqa: F401,F403 - shared authoring vocabulary

# Indirect Fire (+2) and Missiles (+6) for the roster expansion.
#
#   spigot_mortar            - huge low-velocity demolition bomb
#   rocket_artillery         - saturation barrage off a rail rack
#   hypervelocity_missile    - flat, brutally fast, kinetic kill
#   sam_launcher             - air only, long reach
#   loitering_munition       - launches, circles, dives
#   anti_radiation_missile   - only locks units that carry sensors
#   bunker_buster            - top-attack anti-structure
#   cruise_missile           - long range, slow, big, interceptable
#
# See _greeble.py for the conventions. The one that shapes every part here is
# the trunnion/centre-of-gravity rule: a launcher is mostly empty tube out
# front, so without deliberate mass behind the trunnion these all read as
# scaffolding. Each one gets a counterweight with a real identity - a reload
# magazine, a tracker, a receiver array - rather than a blank ballast block.


# ---------------------------------------------------------------------------
# SPIGOT MORTAR
# The bomb is bigger than the weapon. A spigot mortar has no barrel at all -
# the projectile slides OVER a rod, so the silhouette is an oversized finned
# bomb sitting on a spike, which is exactly the sort of thing the roster's
# tone target wants: straight-faced hardware that happens to look absurd.
# ---------------------------------------------------------------------------
def build_spigot_mortar():
	# 1. BASEPLATE MOUNT - origin at deck
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.022), 0.210, 0.044, segments=24)
	bolt_ring_z(bm, 0.046, 0.185, count=14, bolt_r=0.011, bolt_len=0.018)
	for i in range(6):                                             # spade ribs
		a = (i / 6) * math.tau
		add_tube_between(bm, (0, 0, 0.050), (math.cos(a) * 0.195, math.sin(a) * 0.195, 0.030), 0.016)
	add_cyl_z(bm, (0, 0, 0.082), 0.115, 0.078, segments=20)
	for side in (-1, 1):
		add_box(bm, (side * 0.128, 0.010, 0.180), (0.042, 0.110, 0.180), bevel=0.008)
		add_cyl_x(bm, (side * 0.150, 0.010, 0.250), 0.040, 0.032, segments=14)
		add_cyl_z(bm, (side * 0.098, -0.100, 0.120), 0.026, 0.130, segments=12)   # elevation jack
		add_cyl_z(bm, (side * 0.098, -0.100, 0.208), 0.013, 0.070, segments=10)
	add_servo_drive(bm, (0, 0.120, 0.082), axis='Y')
	export_bmesh(bm, "spigot_mount", "spigot_mount.glb", color=(0.19, 0.20, 0.22, 1.0))

	# 2. BREECH - origin at trunnion, and the counterweight. A spigot's gas
	#    generator and recoil gear all live behind the pivot, which is
	#    convenient: the bomb out front is enormous.
	bm = bmesh.new()
	add_box(bm, (0, -0.150, 0.0), (0.190, 0.300, 0.180), bevel=0.013)
	add_cyl_y(bm, (0, -0.320, 0.0), 0.098, 0.070, segments=18)      # gas generator drum
	add_cyl_y(bm, (0, -0.362, 0.0), 0.074, 0.024, segments=16)
	for i in range(4):                                               # cooling ribs
		add_cyl_y(bm, (0, -0.300 + i * 0.030, 0.0), 0.106, 0.014, segments=18)
	for side in (-1, 1):                                             # recoil rams
		add_cyl_y(bm, (side * 0.118, -0.170, 0.050), 0.032, 0.240, segments=14)
		add_helix(bm, (side * 0.118, -0.170, 0.050), 0.044, 0.180, 5.0, 0.008, axis='Y')
		add_cyl_y(bm, (side * 0.118, -0.055, 0.050), 0.040, 0.030, segments=14)
	add_junction_box(bm, (-0.130, -0.250, -0.070))
	add_camera_head(bm, (0.135, -0.060, 0.060), scale=0.85)
	# Trunnion lugs
	for side in (-1, 1):
		add_box(bm, (side * 0.108, 0.0, 0.0), (0.028, 0.078, 0.078), bevel=0.006)
		add_cyl_x(bm, (side * 0.128, 0.0, 0.0), 0.032, 0.020, segments=14)
	# Spigot rod base
	add_cyl_y(bm, (0, 0.030, 0.0), 0.070, 0.060, segments=18)
	bolt_ring(bm, 0.052, 0.058, count=8, bolt_r=0.009, bolt_len=0.016)
	export_bmesh(bm, "spigot_breech", "spigot_breech.glb", color=(0.21, 0.22, 0.20, 1.0))

	# 3. ROD - the ONLY part rod_thickness scales. Origin at the breech face.
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0.190, 0), 0.030, 0.360, segments=14)
	add_cyl_y(bm, (0, 0.020, 0), 0.044, 0.036, segments=16)
	add_taper_y(bm, (0, 0.382, 0), 0.030, 0.014, 0.030, segments=12)
	for i in range(3):
		add_cyl_y(bm, (0, 0.090 + i * 0.110, 0), 0.036, 0.014, segments=14)
	export_bmesh(bm, "spigot_rod", "spigot_rod.glb", color=(0.14, 0.15, 0.16, 1.0))

	# 4. BOMB - the ONLY part payload_size scales. Origin at its own tail, so
	#    it slides onto the rod. Deliberately, comically oversized.
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0.180, 0), 0.140, 0.300, segments=22)         # body
	add_nose_y(bm, (0, 0.330, 0), 0.140, 0.170, segments=22)        # ogive nose
	add_cyl_y(bm, (0, 0.028, 0), 0.100, 0.056, segments=20)         # tail boat-tail
	add_taper_y(bm, (0, -0.010, 0), 0.100, 0.062, 0.040, segments=18)
	for i in range(3):                                               # banding
		add_cyl_y(bm, (0, 0.075 + i * 0.100, 0), 0.148, 0.020, segments=22)
	for i in range(4):                                               # tail fins
		a = (i / 4) * math.tau + math.pi / 4.0
		add_box(bm, (math.cos(a) * 0.105, 0.040, math.sin(a) * 0.105), (0.014, 0.110, 0.100), bevel=0.004)
	add_cyl_y(bm, (0, 0.508, 0), 0.024, 0.050, segments=12)         # fuse probe
	add_cyl_y(bm, (0, 0.538, 0), 0.034, 0.016, segments=12)
	export_bmesh(bm, "spigot_bomb", "spigot_bomb.glb", color=(0.30, 0.32, 0.26, 1.0),
				 metallic=0.42, roughness=0.60)


# ---------------------------------------------------------------------------
# ROCKET ARTILLERY
# Saturation, not precision. A rack of open rails, an autoloader magazine
# behind the trunnion that is visibly where the reload comes from, and blast
# shielding - because the crew compartment of whatever carries this is a few
# feet from the exhaust.
# ---------------------------------------------------------------------------
def build_rocket_artillery():
	# 1. TURNTABLE MOUNT - origin at deck
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.022), 0.195, 0.044, segments=24)
	bolt_ring_z(bm, 0.046, 0.172, count=14, bolt_r=0.010, bolt_len=0.016)
	add_cyl_z(bm, (0, 0, 0.078), 0.128, 0.068, segments=22)
	add_grid_vents(bm, (0, -0.130, 0.078), (0.16, 0.0, 0.09), 4, 2, depth=0.012)
	for side in (-1, 1):
		add_box(bm, (side * 0.140, 0.0, 0.190), (0.046, 0.120, 0.200), bevel=0.009)
		add_cyl_x(bm, (side * 0.164, 0.0, 0.272), 0.042, 0.034, segments=16)
		# Big elevation rams - a rail rack elevates a long way
		add_cyl_z(bm, (side * 0.100, -0.110, 0.130), 0.030, 0.150, segments=14)
		add_cyl_z(bm, (side * 0.100, -0.110, 0.232), 0.015, 0.080, segments=10)
		add_box(bm, (side * 0.100, -0.110, 0.272), (0.040, 0.034, 0.024), bevel=0.004)
	add_servo_drive(bm, (0, 0.135, 0.078), axis='Y')
	add_junction_box(bm, (0.140, -0.130, 0.060))
	export_bmesh(bm, "rocket_arty_mount", "rocket_arty_mount.glb", color=(0.19, 0.20, 0.22, 1.0))

	# 2. CRADLE + MAGAZINE - origin at trunnion. The reload magazine is the
	#    counterweight AND the explanation for the reload time.
	bm = bmesh.new()
	add_box(bm, (0, -0.020, 0.0), (0.300, 0.180, 0.090), bevel=0.010)      # cradle beam
	for side in (-1, 1):
		add_box(bm, (side * 0.155, -0.020, 0.010), (0.026, 0.170, 0.120), bevel=0.006)
	# Blast shield standing up behind the rails
	add_box(bm, (0, -0.130, 0.115), (0.320, 0.030, 0.190), bevel=0.008)
	for i in range(5):
		add_box(bm, (-0.120 + i * 0.060, -0.150, 0.115), (0.020, 0.014, 0.170), bevel=0.003)
	# Autoloader magazine: a blocky drum of spare rounds slung behind
	add_box(bm, (0, -0.310, -0.010), (0.290, 0.230, 0.210), bevel=0.013)
	for row in range(2):
		for col in range(3):
			add_cyl_y(bm, (-0.090 + col * 0.090, -0.430, -0.070 + row * 0.090), 0.036, 0.030, segments=14)
	add_grid_vents(bm, (0, -0.428, 0.075), (0.22, 0.0, 0.07), 5, 2, depth=0.010)
	add_junction_box(bm, (-0.160, -0.300, 0.090))
	add_camera_head(bm, (0.170, -0.120, 0.100), scale=0.9)
	# Trunnion lugs
	for side in (-1, 1):
		add_box(bm, (side * 0.176, 0.0, 0.0), (0.026, 0.080, 0.080), bevel=0.006)
		add_cyl_x(bm, (side * 0.196, 0.0, 0.0), 0.032, 0.020, segments=14)
	export_bmesh(bm, "rocket_arty_cradle", "rocket_arty_cradle.glb", color=(0.22, 0.24, 0.21, 1.0))

	# 3. RAIL - a SINGLE rail with its rocket, repeated and spaced by
	#    visual_builder so rail_count is visible. Origin at its rear.
	bm = bmesh.new()
	add_box(bm, (0, 0.300, -0.030), (0.070, 0.560, 0.020), bevel=0.004)   # rail beam
	for i in range(4):                                                     # rail ribs
		add_box(bm, (0, 0.080 + i * 0.150, -0.046), (0.078, 0.020, 0.018), bevel=0.003)
	add_cyl_y(bm, (0, 0.290, 0.020), 0.052, 0.480, segments=16)           # rocket body
	add_nose_y(bm, (0, 0.530, 0.020), 0.052, 0.110, segments=16)          # warhead
	add_cyl_y(bm, (0, 0.048, 0.020), 0.044, 0.048, segments=14)           # motor nozzle
	add_taper_y(bm, (0, 0.020, 0.020), 0.044, 0.030, 0.030, segments=14)
	for i in range(4):                                                     # fins
		a = (i / 4) * math.tau + math.pi / 4.0
		add_box(bm, (math.cos(a) * 0.048, 0.075, 0.020 + math.sin(a) * 0.048),
				(0.010, 0.075, 0.048), bevel=0.003)
	add_cyl_y(bm, (0, 0.170, 0.020), 0.056, 0.014, segments=16)           # banding
	add_cyl_y(bm, (0, 0.420, 0.020), 0.056, 0.014, segments=16)
	export_bmesh(bm, "rocket_arty_rail", "rocket_arty_rail.glb", color=(0.26, 0.27, 0.24, 1.0),
				 metallic=0.50, roughness=0.52)


# ---------------------------------------------------------------------------
# Shared missile-launcher chassis
# The six missile modules differ in what they LAUNCH and what they carry
# behind the trunnion to justify it; the pedestal underneath is the same
# fabricated turntable. One authored mount reused six times is honest reuse -
# these are all the same class of bolt-on launcher - and it keeps the count of
# near-identical .glb files down.
# ---------------------------------------------------------------------------
def build_missile_pedestal():
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.020), 0.175, 0.040, segments=24)
	bolt_ring_z(bm, 0.042, 0.153, count=12, bolt_r=0.010, bolt_len=0.016)
	add_cyl_z(bm, (0, 0, 0.072), 0.115, 0.064, segments=22)
	add_grid_vents(bm, (0, -0.118, 0.072), (0.14, 0.0, 0.08), 4, 2, depth=0.010)
	for side in (-1, 1):
		add_box(bm, (side * 0.126, 0.005, 0.170), (0.042, 0.105, 0.180), bevel=0.008)
		add_cyl_x(bm, (side * 0.148, 0.005, 0.242), 0.038, 0.030, segments=14)
		add_cyl_z(bm, (side * 0.094, -0.098, 0.120), 0.026, 0.125, segments=12)
		add_cyl_z(bm, (side * 0.094, -0.098, 0.205), 0.013, 0.068, segments=10)
	add_servo_drive(bm, (0, 0.122, 0.072), axis='Y')
	add_junction_box(bm, (0.132, -0.118, 0.056))
	for i in range(3):
		add_tube_between(bm, (-0.140, -0.110 - i * 0.010, 0.050), (-0.120, -0.040, 0.215), 0.009, segments=6)
	export_bmesh(bm, "missile_pedestal", "missile_pedestal.glb", color=(0.19, 0.20, 0.22, 1.0))


def _launcher_body(bm, depth=0.290, width=0.185, height=0.170, vents=True):
	"""Common launcher body block sitting on the trunnion, extending BACK.
	Callers add the part that gives it its identity."""
	add_box(bm, (0, -depth * 0.5 + 0.030, 0.0), (width, depth, height), bevel=0.012)
	if vents:
		add_grid_vents(bm, (0, -depth + 0.028, 0.0), (width * 0.72, 0.0, height * 0.60), 4, 2, depth=0.010)
	for side in (-1, 1):
		add_box(bm, (side * (width * 0.5 + 0.010), 0.0, 0.0), (0.024, 0.070, 0.070), bevel=0.005)
		add_cyl_x(bm, (side * (width * 0.5 + 0.026), 0.0, 0.0), 0.030, 0.018, segments=14)


# ---------------------------------------------------------------------------
# HYPERVELOCITY MISSILE
# Flat, brutally fast, kinetic kill - no warhead, the round IS the damage.
# Reads as darts in slim sealed canisters with a beam-riding designator on
# top, rather than as a missile pod: nothing about it should suggest an arc.
# ---------------------------------------------------------------------------
def build_hypervelocity():
	bm = bmesh.new()
	_launcher_body(bm, depth=0.300, width=0.180, height=0.160)
	# Beam-rider designator: this weapon guides by holding a laser on the
	# target, so the designator is the identity part and sits up top.
	add_box(bm, (0, -0.060, 0.118), (0.140, 0.150, 0.070), bevel=0.008)
	add_cyl_y(bm, (0, 0.030, 0.118), 0.030, 0.040, segments=16)
	add_cyl_y(bm, (0, 0.056, 0.118), 0.021, 0.016, segments=14)
	add_camera_head(bm, (0.098, -0.040, 0.128), scale=0.75)
	# Coolant plumbing for a designator that has to stay on target
	add_cyl_x(bm, (0, -0.190, 0.090), 0.038, 0.150, segments=16)
	for i in range(4):
		add_cyl_x(bm, (0, -0.190, 0.090), 0.044, 0.014, segments=16)
	add_junction_box(bm, (-0.120, -0.230, -0.050))
	export_bmesh(bm, "hvm_body", "hvm_body.glb", color=(0.21, 0.23, 0.25, 1.0))

	# Single sealed canister, repeated by tube_count. Origin at its rear.
	bm = bmesh.new()
	add_box(bm, (0, 0.230, 0), (0.084, 0.460, 0.084), bevel=0.010)      # square canister
	for i in range(4):
		add_box(bm, (0, 0.060 + i * 0.115, 0), (0.094, 0.020, 0.094), bevel=0.003)
	add_box(bm, (0, 0.466, 0), (0.088, 0.014, 0.088), bevel=0.003)      # frangible cover
	for i in range(2):
		add_box(bm, (0, 0.466, -0.020 + i * 0.040), (0.080, 0.016, 0.008), bevel=0.002)
	add_box(bm, (0, 0.010, 0), (0.090, 0.024, 0.090), bevel=0.004)      # breech plate
	add_cyl_y(bm, (0.052, 0.010, 0.052), 0.012, 0.040, segments=8)      # firing lead
	export_bmesh(bm, "hvm_canister", "hvm_canister.glb", color=(0.24, 0.25, 0.22, 1.0),
				 metallic=0.45, roughness=0.55)


# ---------------------------------------------------------------------------
# SAM LAUNCHER
# Air only. The tracking radar is the identity part and the counterweight -
# a SAM that cannot see is scrap, so the dish is as important as the rail.
# ---------------------------------------------------------------------------
def build_sam_launcher():
	bm = bmesh.new()
	_launcher_body(bm, depth=0.280, width=0.190, height=0.165)
	# Tracking radar: a slab planar array on a short mast, canted back.
	add_cyl_z(bm, (0, -0.150, 0.120), 0.034, 0.110, segments=14)
	add_box(bm, (0, -0.150, 0.210), (0.230, 0.036, 0.150), bevel=0.008)
	add_grid_vents(bm, (0, -0.170, 0.210), (0.20, 0.0, 0.12), 5, 3, depth=0.008)
	for side in (-1, 1):
		add_tube_between(bm, (side * 0.100, -0.150, 0.140), (side * 0.100, -0.152, 0.270), 0.008, segments=6)
	# IFF whip and a rotating acquisition puck
	add_cyl_z(bm, (0.090, -0.060, 0.110), 0.008, 0.150, segments=8)
	add_cyl_z(bm, (-0.090, -0.060, 0.108), 0.032, 0.044, segments=16)
	add_cyl_z(bm, (-0.090, -0.060, 0.134), 0.034, 0.014, segments=16)
	add_junction_box(bm, (-0.130, -0.220, -0.045))
	export_bmesh(bm, "sam_body", "sam_body.glb", color=(0.21, 0.23, 0.25, 1.0))

	# Rail + missile, repeated by tube_count. Origin at the rail's rear.
	bm = bmesh.new()
	add_box(bm, (0, 0.250, -0.034), (0.048, 0.480, 0.024), bevel=0.004)
	for i in range(3):
		add_box(bm, (0, 0.090 + i * 0.160, -0.050), (0.056, 0.018, 0.016), bevel=0.003)
	add_cyl_y(bm, (0, 0.250, 0.010), 0.040, 0.440, segments=16)
	add_nose_y(bm, (0, 0.464, 0.010), 0.040, 0.130, segments=16)
	add_cyl_y(bm, (0, 0.042, 0.010), 0.034, 0.044, segments=14)
	for i in range(4):                                                   # tail fins
		a = (i / 4) * math.tau + math.pi / 4.0
		add_box(bm, (math.cos(a) * 0.040, 0.070, 0.010 + math.sin(a) * 0.040),
				(0.008, 0.070, 0.044), bevel=0.003)
	for i in range(4):                                                   # canards
		a = (i / 4) * math.tau
		add_box(bm, (math.cos(a) * 0.038, 0.420, 0.010 + math.sin(a) * 0.038),
				(0.008, 0.048, 0.030), bevel=0.002)
	export_bmesh(bm, "sam_missile", "sam_missile.glb", color=(0.72, 0.72, 0.70, 1.0),
				 metallic=0.40, roughness=0.55)


# ---------------------------------------------------------------------------
# LOITERING MUNITION
# Launches, circles, then dives. A revolver magazine of sealed tubes canted
# upward - the read is "these go up and come back down somewhere else", not
# "this points at a thing".
# ---------------------------------------------------------------------------
def build_loitering_munition():
	bm = bmesh.new()
	_launcher_body(bm, depth=0.250, width=0.175, height=0.150, vents=False)
	# Revolver magazine drum lying across the body, behind the trunnion
	add_cyl_x(bm, (0, -0.185, 0.030), 0.135, 0.230, segments=22)
	for side in (-1, 1):
		add_cyl_x(bm, (side * 0.118, -0.185, 0.030), 0.115, 0.020, segments=20)
		bolt_ring_z(bm, 0.030, 0.090, count=8, bolt_r=0.008, bolt_len=0.012)
	for i in range(6):                                                    # chambers
		a = (i / 6) * math.tau
		add_cyl_x(bm, (0, -0.185 + math.cos(a) * 0.088, 0.030 + math.sin(a) * 0.088),
				  0.036, 0.240, segments=12)
	add_servo_drive(bm, (-0.150, -0.185, 0.030), axis='Y')
	# Datalink mast - a loitering weapon has to phone home
	add_cyl_z(bm, (0.090, -0.070, 0.110), 0.012, 0.140, segments=10)
	add_box(bm, (0.090, -0.070, 0.190), (0.070, 0.020, 0.040), bevel=0.004)
	add_camera_head(bm, (-0.090, -0.040, 0.110), scale=0.7)
	add_junction_box(bm, (0.128, -0.230, -0.040))
	export_bmesh(bm, "loiter_body", "loiter_body.glb", color=(0.22, 0.24, 0.22, 1.0))

	# One launch tube, canted up by visual_builder. Origin at its base.
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0.185, 0), 0.062, 0.370, segments=18)
	add_cyl_y(bm, (0, 0.008, 0), 0.074, 0.028, segments=18)             # base flange
	bolt_ring(bm, 0.008, 0.064, count=8, bolt_r=0.007, bolt_len=0.012)
	for i in range(3):
		add_cyl_y(bm, (0, 0.090 + i * 0.100, 0), 0.070, 0.016, segments=18)
	add_cyl_y(bm, (0, 0.378, 0), 0.068, 0.020, segments=18)             # muzzle ring
	add_box(bm, (0, 0.392, 0), (0.100, 0.012, 0.100), bevel=0.003)      # blow-off cap
	add_box(bm, (0.070, 0.120, 0), (0.024, 0.060, 0.024), bevel=0.003)  # umbilical boss
	export_bmesh(bm, "loiter_tube", "loiter_tube.glb", color=(0.25, 0.27, 0.23, 1.0),
				 metallic=0.42, roughness=0.58)


# ---------------------------------------------------------------------------
# ANTI-RADIATION MISSILE
# Only locks units that carry sensors, which makes radar a liability. The
# identity part is a big passive ESM receiver array - spiral antennas and
# horns - and it is deliberately the most distinctive thing on the module,
# because the weapon's whole gimmick is listening rather than looking.
# ---------------------------------------------------------------------------
def build_anti_radiation():
	bm = bmesh.new()
	_launcher_body(bm, depth=0.300, width=0.185, height=0.160)
	# ESM receiver array: four spiral-antenna horns on a canted frame
	add_box(bm, (0, -0.140, 0.132), (0.240, 0.120, 0.032), bevel=0.006)
	for i in range(4):
		x = -0.084 + i * 0.056
		add_cyl_z(bm, (x, -0.140, 0.164), 0.026, 0.036, segments=14)
		add_taper_z(bm, (x, -0.140, 0.196), 0.026, 0.040, 0.030, segments=14)
		add_cyl_z(bm, (x, -0.140, 0.214), 0.040, 0.010, segments=14)
	# Wideband horn facing forward, and a blade antenna
	add_box(bm, (0, 0.020, 0.108), (0.110, 0.070, 0.070), bevel=0.006)
	add_taper_y(bm, (0, 0.078, 0.108), 0.048, 0.078, 0.055, segments=16)
	add_box(bm, (-0.110, -0.230, 0.120), (0.012, 0.110, 0.100), bevel=0.004)
	# Signal-processing rack behind, with vents - the counterweight
	add_box(bm, (0, -0.310, 0.010), (0.200, 0.120, 0.170), bevel=0.010)
	add_grid_vents(bm, (0, -0.372, 0.010), (0.17, 0.0, 0.13), 4, 3, depth=0.010)
	add_junction_box(bm, (0.130, -0.300, -0.070))
	export_bmesh(bm, "arm_body", "arm_body.glb", color=(0.20, 0.22, 0.24, 1.0))

	# Missile on a rail. Origin at the rail's rear.
	bm = bmesh.new()
	add_box(bm, (0, 0.260, -0.036), (0.052, 0.500, 0.026), bevel=0.004)
	add_cyl_y(bm, (0, 0.265, 0.014), 0.044, 0.470, segments=16)
	# Distinctive faceted seeker nose - a passive homer, not a radome
	add_taper_y(bm, (0, 0.520, 0.014), 0.044, 0.030, 0.070, segments=8)
	add_cyl_y(bm, (0, 0.562, 0.014), 0.030, 0.020, segments=8)
	add_cyl_y(bm, (0, 0.046, 0.014), 0.038, 0.048, segments=14)
	for i in range(4):
		a = (i / 4) * math.tau + math.pi / 4.0
		add_box(bm, (math.cos(a) * 0.044, 0.080, 0.014 + math.sin(a) * 0.044),
				(0.009, 0.080, 0.052), bevel=0.003)
	for i in range(4):
		a = (i / 4) * math.tau
		add_box(bm, (math.cos(a) * 0.042, 0.430, 0.014 + math.sin(a) * 0.042),
				(0.009, 0.055, 0.034), bevel=0.002)
	export_bmesh(bm, "arm_missile", "arm_missile.glb", color=(0.34, 0.36, 0.33, 1.0),
				 metallic=0.45, roughness=0.55)


# ---------------------------------------------------------------------------
# BUNKER BUSTER
# Top-attack anti-structure. Short, immensely fat penetrator with a hardened
# nose, in a heavy cradle - it should look like it weighs more than the
# vehicle carrying it.
# ---------------------------------------------------------------------------
def build_bunker_buster():
	bm = bmesh.new()
	_launcher_body(bm, depth=0.310, width=0.210, height=0.185)
	# Heavy rear ballast + hydraulic erector - this thing has to be tipped up
	add_box(bm, (0, -0.330, -0.010), (0.240, 0.150, 0.200), bevel=0.012)
	for side in (-1, 1):
		add_cyl_y(bm, (side * 0.090, -0.230, 0.110), 0.030, 0.230, segments=14)
		add_cyl_y(bm, (side * 0.090, -0.110, 0.110), 0.016, 0.100, segments=10)
		add_box(bm, (side * 0.090, -0.055, 0.110), (0.040, 0.030, 0.028), bevel=0.004)
	add_grid_vents(bm, (0, -0.404, 0.010), (0.20, 0.0, 0.15), 4, 3, depth=0.010)
	# Terminal-guidance sensor and a laser designator
	add_camera_head(bm, (0.110, -0.040, 0.135), scale=0.95)
	add_cyl_y(bm, (-0.100, 0.020, 0.130), 0.024, 0.090, segments=14)
	add_cyl_y(bm, (-0.100, 0.072, 0.130), 0.018, 0.016, segments=12)
	add_junction_box(bm, (-0.140, -0.300, -0.080))
	export_bmesh(bm, "bb_body", "bb_body.glb", color=(0.22, 0.23, 0.25, 1.0))

	# The penetrator. Short, very fat, hardened nose. Origin at its tail.
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0.210, 0), 0.098, 0.360, segments=20)
	add_taper_y(bm, (0, 0.410, 0), 0.098, 0.062, 0.045, segments=20)   # shoulder
	add_cyl_y(bm, (0, 0.455, 0), 0.062, 0.050, segments=18)
	add_taper_y(bm, (0, 0.500, 0), 0.062, 0.028, 0.045, segments=18)   # hardened tip
	add_cyl_y(bm, (0, 0.526, 0), 0.028, 0.020, segments=14)
	for i in range(4):                                                  # reinforcing bands
		add_cyl_y(bm, (0, 0.075 + i * 0.095, 0), 0.106, 0.020, segments=20)
	add_cyl_y(bm, (0, 0.026, 0), 0.078, 0.052, segments=18)            # motor
	add_taper_y(bm, (0, -0.008, 0), 0.078, 0.052, 0.030, segments=16)
	for i in range(4):
		a = (i / 4) * math.tau + math.pi / 4.0
		add_box(bm, (math.cos(a) * 0.080, 0.055, math.sin(a) * 0.080), (0.012, 0.090, 0.070), bevel=0.003)
	export_bmesh(bm, "bb_penetrator", "bb_penetrator.glb", color=(0.19, 0.20, 0.21, 1.0),
				 metallic=0.62, roughness=0.44)


# ---------------------------------------------------------------------------
# CRUISE MISSILE
# Long range, slow, big warhead, very interceptable. Ships in a sealed
# rectangular container that never opens in the Design Lab, which is exactly
# the read: you are bolting a shipping crate of ordnance to your vehicle.
# ---------------------------------------------------------------------------
def build_cruise_missile():
	bm = bmesh.new()
	_launcher_body(bm, depth=0.240, width=0.180, height=0.150, vents=False)
	# Erector frame and gas-generator bottle - a container this size is
	# tipped up before launch, and that gear is the counterweight.
	add_box(bm, (0, -0.290, 0.020), (0.220, 0.170, 0.180), bevel=0.011)
	add_cyl_x(bm, (0, -0.360, -0.060), 0.052, 0.190, segments=16)
	for side in (-1, 1):
		add_cyl_y(bm, (side * 0.098, -0.215, 0.120), 0.028, 0.210, segments=14)
		add_cyl_y(bm, (side * 0.098, -0.105, 0.120), 0.014, 0.090, segments=10)
	add_grid_vents(bm, (0, -0.372, 0.070), (0.18, 0.0, 0.09), 4, 2, depth=0.010)
	add_junction_box(bm, (0.120, -0.280, -0.055))
	add_camera_head(bm, (-0.105, -0.050, 0.115), scale=0.7)
	export_bmesh(bm, "cruise_body", "cruise_body.glb", color=(0.21, 0.22, 0.24, 1.0))

	# The sealed container. Origin at its rear.
	bm = bmesh.new()
	add_box(bm, (0, 0.340, 0), (0.190, 0.660, 0.180), bevel=0.014)
	for i in range(5):                                                  # ribs
		add_box(bm, (0, 0.070 + i * 0.140, 0), (0.204, 0.026, 0.194), bevel=0.004)
	add_box(bm, (0, 0.674, 0), (0.184, 0.014, 0.174), bevel=0.004)      # frangible front
	for i in range(2):
		add_box(bm, (0, 0.676, -0.045 + i * 0.090), (0.170, 0.016, 0.010), bevel=0.002)
	add_box(bm, (0, 0.012, 0), (0.196, 0.026, 0.186), bevel=0.005)      # rear plate
	for i in range(4):
		a = (i / 4) * math.tau + math.pi / 4.0
		add_cyl_y(bm, (math.cos(a) * 0.070, 0.012, math.sin(a) * 0.070), 0.014, 0.040, segments=8)
	# Hoist lugs on top, and stencilled panel plates
	for i in range(2):
		add_box(bm, (0, 0.180 + i * 0.320, 0.098), (0.036, 0.028, 0.028), bevel=0.004)
		add_cyl_x(bm, (0, 0.180 + i * 0.320, 0.108), 0.011, 0.040, segments=8)
	add_box(bm, (0.098, 0.400, 0.030), (0.010, 0.150, 0.070), bevel=0.003)
	export_bmesh(bm, "cruise_container", "cruise_container.glb", color=(0.29, 0.31, 0.27, 1.0),
				 metallic=0.38, roughness=0.62)


if __name__ == "__main__":
	clear_scene()
	build_spigot_mortar()
	build_rocket_artillery()
	build_missile_pedestal()
	build_hypervelocity()
	build_sam_launcher()
	build_loitering_munition()
	build_anti_radiation()
	build_bunker_buster()
	build_cruise_missile()
	print("INDIRECT_MISSILE_PARTS_DONE")
