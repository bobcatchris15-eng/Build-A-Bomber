import sys
import os
import math
import bmesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _greeble import *  # noqa: F401,F403

# Point Defense (+5), Deployables (+3) and bolt-on Armor (+3).
#
#   chaff_dispenser   - consumable lock-break cloud
#   laser_dazzler     - directional seeker blinding
#   aps_interceptor   - hard kill at very short range
#   aa_autocannon     - dedicated flak, engages air rather than only munitions
#   jammer_mast       - passive aura degrading guided weapons
#   sentry_deployer   - drops an autonomous turret
#   sensor_beacon_launcher - lobs a beacon that reveals fog
#   decoy_projector   - draws AI fire
#   slat_armor        - light cage, pre-detonates shaped charges
#   spaced_composite  - heavy, big kinetic threshold
#   ablative_foam     - thermal
#
# See _greeble.py for conventions and the two rules (exterior modules, and
# balance about the trunnion).
#
# ARMOR is different in kind from everything else in this file: it is a
# category-"armor" module that auto-fits the facet it is placed on, so it has
# no trunnion, no mount and no elevation. Those three are authored as flat
# panels whose origin is the mounting face, and visual_builder scales them to
# the facet rather than by a tweak.


# ===========================================================================
# POINT DEFENSE
# ===========================================================================

# ---------------------------------------------------------------------------
# CHAFF DISPENSER
# Consumable lock-break. A block of stubby upward-canted cartridge tubes with
# a magazine underneath - closer to the smoke discharger's family than to a
# gun, which is correct: it never points at anything.
# ---------------------------------------------------------------------------
def build_chaff_dispenser():
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.018), 0.135, 0.036, segments=20)
	bolt_ring_z(bm, 0.038, 0.116, count=10, bolt_r=0.009, bolt_len=0.014)
	add_box(bm, (0, -0.020, 0.090), (0.200, 0.180, 0.115), bevel=0.010)      # magazine body
	add_grid_vents(bm, (0, -0.112, 0.090), (0.16, 0.0, 0.08), 4, 2, depth=0.010)
	add_box(bm, (0, 0.040, 0.170), (0.190, 0.110, 0.055), bevel=0.008)       # tube block
	add_junction_box(bm, (-0.130, -0.070, 0.060))
	add_servo_drive(bm, (0.130, -0.040, 0.080), axis='Z')
	# Reload cassettes stacked behind - the counterweight, and the reason it
	# is a consumable rather than an always-on effect.
	add_box(bm, (0, -0.180, 0.075), (0.180, 0.130, 0.100), bevel=0.008)
	for i in range(3):
		add_box(bm, (0, -0.248, 0.040 + i * 0.036), (0.150, 0.020, 0.024), bevel=0.003)
	export_bmesh(bm, "chaff_body", "chaff_body.glb", color=(0.24, 0.26, 0.23, 1.0))

	# One cartridge tube, repeated and splayed by visual_builder.
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0.075, 0), 0.030, 0.150, segments=14)
	add_cyl_y(bm, (0, 0.006, 0), 0.036, 0.020, segments=14)
	add_cyl_y(bm, (0, 0.156, 0), 0.033, 0.016, segments=14)
	add_box(bm, (0, 0.166, 0), (0.048, 0.010, 0.048), bevel=0.002)          # foil cap
	add_box(bm, (0.032, 0.050, 0), (0.014, 0.030, 0.014), bevel=0.002)      # firing lead
	export_bmesh(bm, "chaff_tube", "chaff_tube.glb", color=(0.30, 0.31, 0.27, 1.0),
				 metallic=0.45, roughness=0.55)


# ---------------------------------------------------------------------------
# LASER DAZZLER
# Directional seeker blinding. A gimballed optical head - it has to POINT, so
# unlike the chaff dispenser it gets a real trunnion and a real emitter.
# ---------------------------------------------------------------------------
def build_laser_dazzler():
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.018), 0.140, 0.036, segments=20)
	bolt_ring_z(bm, 0.038, 0.120, count=10, bolt_r=0.009, bolt_len=0.014)
	add_cyl_z(bm, (0, 0, 0.062), 0.098, 0.052, segments=18)
	for side in (-1, 1):
		add_box(bm, (side * 0.104, 0.0, 0.140), (0.034, 0.090, 0.130), bevel=0.007)
		add_cyl_x(bm, (side * 0.122, 0.0, 0.196), 0.030, 0.026, segments=14)
	add_servo_drive(bm, (0, 0.100, 0.062), axis='Y')
	add_junction_box(bm, (0.115, -0.090, 0.050))
	export_bmesh(bm, "dazzler_mount", "dazzler_mount.glb", color=(0.19, 0.20, 0.22, 1.0))

	# Gimbal head. Chiller and driver electronics BEHIND the trunnion.
	bm = bmesh.new()
	add_box(bm, (0, -0.070, 0.0), (0.150, 0.200, 0.140), bevel=0.011)       # driver box
	add_grid_vents(bm, (0, -0.172, 0.0), (0.12, 0.0, 0.11), 3, 3, depth=0.010)
	add_cyl_x(bm, (0, -0.140, 0.088), 0.042, 0.130, segments=16)           # chiller drum
	for i in range(4):
		add_cyl_x(bm, (0, -0.140, 0.088), 0.048, 0.012, segments=16)
	# Emitter aperture: a short wide barrel with a protective iris, plus a
	# co-axial tracking camera. Never an eyepiece.
	add_cyl_y(bm, (0, 0.070, 0.010), 0.062, 0.090, segments=20)
	add_cyl_y(bm, (0, 0.122, 0.010), 0.070, 0.020, segments=20)
	for i in range(8):                                                      # iris leaves
		a = (i / 8) * math.tau
		add_box(bm, (math.cos(a) * 0.044, 0.130, 0.010 + math.sin(a) * 0.044),
				(0.018, 0.008, 0.018), bevel=0.002)
	add_camera_head(bm, (0.090, 0.010, 0.075), scale=0.8)
	for side in (-1, 1):
		add_box(bm, (side * 0.088, 0.0, 0.0), (0.024, 0.070, 0.070), bevel=0.005)
		add_cyl_x(bm, (side * 0.106, 0.0, 0.0), 0.028, 0.018, segments=14)
	export_bmesh(bm, "dazzler_head", "dazzler_head.glb", color=(0.22, 0.24, 0.26, 1.0))


# ---------------------------------------------------------------------------
# APS INTERCEPTOR
# Hard kill at very short range: a ring of fixed, outward-facing charge
# launchers around a small radar. It does not traverse - it covers the whole
# arc at once, which is what an active protection system does.
# ---------------------------------------------------------------------------
def build_aps_interceptor():
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.018), 0.150, 0.036, segments=22)
	bolt_ring_z(bm, 0.038, 0.130, count=12, bolt_r=0.009, bolt_len=0.014)
	add_cyl_z(bm, (0, 0, 0.070), 0.098, 0.068, segments=20)                # base drum
	add_grid_vents(bm, (0, -0.098, 0.070), (0.10, 0.0, 0.07), 3, 2, depth=0.010)
	# Ring of outward-facing countermeasure launchers, canted up and out.
	for i in range(6):
		a = (i / 6) * math.tau
		cx, cy = math.cos(a) * 0.115, math.sin(a) * 0.115
		add_box(bm, (cx, cy, 0.140), (0.058, 0.058, 0.070), bevel=0.007)
		add_tube_between(bm, (cx, cy, 0.170), (cx * 1.55, cy * 1.55, 0.230), 0.026, segments=10)
		add_tube_between(bm, (cx * 1.55, cy * 1.55, 0.230), (cx * 1.62, cy * 1.62, 0.240), 0.030, segments=10)
	# Small search/track radar on a stub in the middle
	add_cyl_z(bm, (0, 0, 0.180), 0.048, 0.070, segments=16)
	add_cyl_z(bm, (0, 0, 0.222), 0.060, 0.026, segments=18)
	add_cyl_z(bm, (0, 0, 0.242), 0.062, 0.014, segments=18)
	for i in range(4):
		a = (i / 4) * math.tau
		add_box(bm, (math.cos(a) * 0.052, math.sin(a) * 0.052, 0.212), (0.020, 0.020, 0.030), bevel=0.003)
	add_junction_box(bm, (0.120, -0.090, 0.058))
	export_bmesh(bm, "aps_body", "aps_body.glb", color=(0.21, 0.23, 0.24, 1.0))


# ---------------------------------------------------------------------------
# AA AUTOCANNON
# Dedicated flak. Twin high-elevation barrels, a ring sight replaced by a
# tracking radar, and an ammo box behind the trunnion. Unlike the CIWS this
# engages AIRCRAFT, not just incoming munitions.
# ---------------------------------------------------------------------------
def build_aa_autocannon():
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.020), 0.165, 0.040, segments=22)
	bolt_ring_z(bm, 0.042, 0.144, count=12, bolt_r=0.010, bolt_len=0.016)
	add_cyl_z(bm, (0, 0, 0.076), 0.115, 0.072, segments=20)
	for side in (-1, 1):
		add_box(bm, (side * 0.128, 0.0, 0.190), (0.042, 0.100, 0.190), bevel=0.008)
		add_cyl_x(bm, (side * 0.150, 0.0, 0.268), 0.038, 0.030, segments=14)
		add_cyl_z(bm, (side * 0.096, -0.100, 0.130), 0.026, 0.130, segments=12)
		add_cyl_z(bm, (side * 0.096, -0.100, 0.216), 0.013, 0.070, segments=10)
	add_servo_drive(bm, (0, 0.126, 0.076), axis='Y')
	add_junction_box(bm, (0.132, -0.110, 0.058))
	export_bmesh(bm, "aa_mount", "aa_mount.glb", color=(0.19, 0.20, 0.22, 1.0))

	# Receiver + ammo boxes + tracking radar, all behind the trunnion.
	bm = bmesh.new()
	add_box(bm, (0, -0.060, 0.0), (0.185, 0.230, 0.150), bevel=0.012)
	for side in (-1, 1):                                                    # ammo boxes
		add_box(bm, (side * 0.140, -0.130, -0.010), (0.090, 0.170, 0.140), bevel=0.009)
		for i in range(3):
			add_box(bm, (side * 0.140, -0.190, -0.055 + i * 0.045), (0.096, 0.024, 0.018), bevel=0.003)
	# Tracking radar: a small dish on a short canted mast
	add_cyl_z(bm, (0, -0.180, 0.090), 0.026, 0.090, segments=12)
	add_cyl_y(bm, (0, -0.180, 0.156), 0.078, 0.020, segments=20)
	add_cyl_y(bm, (0, -0.190, 0.156), 0.060, 0.016, segments=18)
	add_cyl_y(bm, (0, -0.158, 0.156), 0.016, 0.045, segments=10)
	add_camera_head(bm, (0.112, 0.010, 0.088), scale=0.8)
	# Spent-case chutes out the bottom
	for side in (-1, 1):
		add_box(bm, (side * 0.058, -0.030, -0.098), (0.052, 0.130, 0.050), bevel=0.005)
	for side in (-1, 1):
		add_box(bm, (side * 0.100, 0.0, 0.0), (0.026, 0.072, 0.072), bevel=0.005)
		add_cyl_x(bm, (side * 0.120, 0.0, 0.0), 0.030, 0.020, segments=14)
	export_bmesh(bm, "aa_receiver", "aa_receiver.glb", color=(0.22, 0.24, 0.22, 1.0))

	# One barrel, mirrored by visual_builder. Origin at the receiver face.
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0.040, 0), 0.044, 0.080, segments=16)
	bolt_ring(bm, 0.040, 0.038, count=8, bolt_r=0.007, bolt_len=0.012)
	add_cyl_y(bm, (0, 0.400, 0), 0.026, 0.640, segments=16)
	for i in range(5):                                                      # cooling jacket rings
		add_cyl_y(bm, (0, 0.140 + i * 0.130, 0), 0.034, 0.020, segments=16)
	# Flash hider: a slotted cone, so a night flak burst does not blind the
	# vehicle's own sensors.
	add_taper_y(bm, (0, 0.745, 0), 0.030, 0.048, 0.060, segments=18)
	for i in range(4):
		a = (i / 4) * math.tau
		add_box(bm, (math.cos(a) * 0.040, 0.755, math.sin(a) * 0.040), (0.012, 0.048, 0.012), bevel=0.002)
	add_cyl_y(bm, (0, 0.782, 0), 0.044, 0.016, segments=18)
	export_bmesh(bm, "aa_barrel", "aa_barrel.glb", color=(0.13, 0.14, 0.15, 1.0))


# ---------------------------------------------------------------------------
# JAMMER MAST
# Passive aura. No barrel, no traverse - a mast of crossed dipole antennas
# over a transmitter cabinet. Should read as equipment, not as a weapon.
# ---------------------------------------------------------------------------
def build_jammer_mast():
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.018), 0.145, 0.036, segments=20)
	bolt_ring_z(bm, 0.038, 0.124, count=10, bolt_r=0.009, bolt_len=0.014)
	# Transmitter cabinet: big, finned, and obviously drawing power
	add_box(bm, (0, 0.0, 0.130), (0.220, 0.200, 0.190), bevel=0.012)
	for side in (-1, 1):
		for i in range(7):
			add_box(bm, (side * 0.118, -0.075 + i * 0.026, 0.130), (0.020, 0.014, 0.170), bevel=0.002)
	add_grid_vents(bm, (0, -0.104, 0.130), (0.17, 0.0, 0.14), 4, 3, depth=0.010)
	add_junction_box(bm, (0.150, -0.090, 0.050), size=(0.080, 0.060, 0.055), conduits=4)
	# Mast with crossed dipoles at three stations
	add_cyl_z(bm, (0, 0, 0.330), 0.030, 0.220, segments=14)
	for i in range(3):
		z = 0.290 + i * 0.090
		add_cyl_z(bm, (0, 0, z), 0.040, 0.020, segments=14)
		for k in range(4):
			a = (k / 4) * math.tau
			add_tube_between(bm, (0, 0, z), (math.cos(a) * 0.130, math.sin(a) * 0.130, z + 0.030), 0.009, segments=6)
			add_cyl_z(bm, (math.cos(a) * 0.130, math.sin(a) * 0.130, z + 0.036), 0.014, 0.026, segments=8)
	add_cyl_z(bm, (0, 0, 0.452), 0.020, 0.040, segments=12)
	add_cyl_z(bm, (0, 0, 0.480), 0.008, 0.060, segments=8)                 # whip
	export_bmesh(bm, "jammer_body", "jammer_body.glb", color=(0.23, 0.25, 0.24, 1.0))


# ===========================================================================
# DEPLOYABLES
# ===========================================================================

# ---------------------------------------------------------------------------
# SENTRY DEPLOYER
# Carries folded autonomous turrets and puts them on the ground. The rack is
# the module; the sentry itself is a separate small mesh reused by the
# spawned turret so what you see loaded is what you get deployed.
# ---------------------------------------------------------------------------
def build_sentry_deployer():
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.018), 0.150, 0.036, segments=20)
	bolt_ring_z(bm, 0.038, 0.128, count=10, bolt_r=0.009, bolt_len=0.014)
	add_box(bm, (0, -0.030, 0.120), (0.230, 0.260, 0.170), bevel=0.012)    # rack body
	add_grid_vents(bm, (0, -0.162, 0.120), (0.18, 0.0, 0.13), 4, 3, depth=0.010)
	# Deployment chute and ramp out the back
	add_box(bm, (0, -0.190, 0.048), (0.190, 0.130, 0.050), bevel=0.007)
	for side in (-1, 1):
		add_tube_between(bm, (side * 0.085, -0.245, 0.040), (side * 0.085, -0.330, 0.008), 0.014)
	# Overhead gantry that lifts a sentry out of the rack
	for side in (-1, 1):
		add_box(bm, (side * 0.118, -0.030, 0.230), (0.024, 0.250, 0.030), bevel=0.004)
	add_box(bm, (0, -0.120, 0.240), (0.100, 0.060, 0.040), bevel=0.005)
	add_cyl_z(bm, (0, -0.120, 0.200), 0.012, 0.060, segments=8)
	add_servo_drive(bm, (0.130, -0.030, 0.200), axis='Z')
	add_junction_box(bm, (-0.150, -0.100, 0.060))
	export_bmesh(bm, "sentry_rack", "sentry_rack.glb", color=(0.24, 0.26, 0.22, 1.0))

	# The sentry itself: a squat tripod-legged turret. Small, and legible at
	# a distance as "a gun that is not on a vehicle".
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.016), 0.075, 0.032, segments=16)
	for i in range(3):                                                      # legs
		a = (i / 3) * math.tau + math.pi / 6.0
		add_tube_between(bm, (0, 0, 0.030), (math.cos(a) * 0.105, math.sin(a) * 0.105, 0.004), 0.012)
		add_cyl_z(bm, (math.cos(a) * 0.105, math.sin(a) * 0.105, 0.006), 0.024, 0.012, segments=10)
	add_cyl_z(bm, (0, 0, 0.062), 0.052, 0.056, segments=16)                # turret drum
	add_box(bm, (0, -0.010, 0.104), (0.086, 0.090, 0.052), bevel=0.006)    # gun housing
	add_cyl_y(bm, (0, 0.075, 0.104), 0.016, 0.110, segments=12)            # barrel
	add_cyl_y(bm, (0, 0.132, 0.104), 0.021, 0.016, segments=12)
	add_box(bm, (-0.052, -0.020, 0.126), (0.030, 0.050, 0.026), bevel=0.004)  # sensor
	add_cyl_z(bm, (0.048, -0.030, 0.132), 0.010, 0.048, segments=8)        # antenna
	export_bmesh(bm, "sentry_turret", "sentry_turret.glb", color=(0.27, 0.29, 0.24, 1.0),
				 metallic=0.50, roughness=0.52)


# ---------------------------------------------------------------------------
# SENSOR BEACON LAUNCHER
# Lobs a beacon that reveals fog where it lands. Reuses the reveal_area()
# beacon system built for illumination ammo. A short wide mortar over a
# carousel of beacons.
# ---------------------------------------------------------------------------
def build_sensor_beacon_launcher():
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.018), 0.145, 0.036, segments=20)
	bolt_ring_z(bm, 0.038, 0.124, count=10, bolt_r=0.009, bolt_len=0.014)
	add_cyl_z(bm, (0, 0, 0.068), 0.098, 0.064, segments=18)
	# Beacon carousel lying behind - the counterweight and the ammo supply
	add_cyl_x(bm, (0, -0.150, 0.110), 0.105, 0.180, segments=20)
	for side in (-1, 1):
		add_cyl_x(bm, (side * 0.092, -0.150, 0.110), 0.088, 0.018, segments=18)
	for i in range(5):
		a = (i / 5) * math.tau
		add_cyl_x(bm, (0, -0.150 + math.cos(a) * 0.068, 0.110 + math.sin(a) * 0.068),
				  0.028, 0.190, segments=10)
	add_servo_drive(bm, (-0.120, -0.150, 0.110), axis='Y')
	# Short fat launch tube, canted well up
	for side in (-1, 1):
		add_box(bm, (side * 0.098, 0.010, 0.150), (0.030, 0.080, 0.110), bevel=0.006)
		add_cyl_x(bm, (side * 0.114, 0.010, 0.196), 0.026, 0.022, segments=12)
	add_camera_head(bm, (0.110, -0.060, 0.150), scale=0.7)
	add_junction_box(bm, (-0.130, -0.070, 0.055))
	export_bmesh(bm, "beacon_body", "beacon_body.glb", color=(0.23, 0.26, 0.24, 1.0))

	bm = bmesh.new()
	add_cyl_y(bm, (0, 0.110, 0), 0.058, 0.220, segments=18)
	add_cyl_y(bm, (0, 0.008, 0), 0.070, 0.024, segments=18)
	bolt_ring(bm, 0.008, 0.060, count=8, bolt_r=0.007, bolt_len=0.012)
	for i in range(3):
		add_cyl_y(bm, (0, 0.060 + i * 0.060, 0), 0.066, 0.014, segments=18)
	add_cyl_y(bm, (0, 0.228, 0), 0.064, 0.018, segments=18)
	add_box(bm, (0.052, 0.090, 0), (0.018, 0.050, 0.018), bevel=0.003)
	export_bmesh(bm, "beacon_tube", "beacon_tube.glb", color=(0.26, 0.29, 0.25, 1.0),
				 metallic=0.45, roughness=0.55)


# ---------------------------------------------------------------------------
# DECOY PROJECTOR
# Deploys an inflatable/holographic false contact that draws fire. Reads as a
# folded canopy pack with an inflation bottle - deliberately NOT a weapon, and
# deliberately a bit shabby, since the joke is that it works.
# ---------------------------------------------------------------------------
def build_decoy_projector():
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.018), 0.145, 0.036, segments=20)
	bolt_ring_z(bm, 0.038, 0.124, count=10, bolt_r=0.009, bolt_len=0.014)
	# Canopy pack: a big soft-cornered box with strap detail
	add_box(bm, (0, -0.010, 0.120), (0.240, 0.220, 0.160), bevel=0.020)
	for i in range(3):
		add_box(bm, (0, -0.010, 0.040 + i * 0.070), (0.250, 0.230, 0.014), bevel=0.004)
	add_box(bm, (0, 0.118, 0.120), (0.190, 0.026, 0.130), bevel=0.008)     # blow-out panel
	for i in range(4):
		add_cyl_y(bm, (-0.060 + i * 0.040, 0.134, 0.120), 0.010, 0.020, segments=6)
	# Inflation bottles behind - the counterweight
	for side in (-1, 1):
		add_cyl_y(bm, (side * 0.090, -0.190, 0.090), 0.052, 0.150, segments=16)
		add_cyl_y(bm, (side * 0.090, -0.272, 0.090), 0.030, 0.030, segments=12)
		add_cyl_z(bm, (side * 0.090, -0.150, 0.150), 0.014, 0.050, segments=8)
	add_box(bm, (0, -0.230, 0.170), (0.130, 0.090, 0.060), bevel=0.007)    # regulator
	add_junction_box(bm, (0.140, -0.120, 0.055))
	# Emitter horns that sell the "false radar contact" half
	for side in (-1, 1):
		add_taper_y(bm, (side * 0.080, 0.150, 0.190), 0.020, 0.044, 0.060, segments=14)
	export_bmesh(bm, "decoy_body", "decoy_body.glb", color=(0.29, 0.30, 0.25, 1.0),
				 metallic=0.35, roughness=0.68)


# ===========================================================================
# ARMOR (bolt-on modules, not the hull's armor MATERIAL dropdown)
# These have no trunnion and no mount: module_placer auto-fits an armor
# module to the facet it is dropped on. Origin is the mounting face, panel
# lies in XY with thickness in +Z, and visual_builder scales X/Y to the facet
# while leaving thickness alone.
# ===========================================================================

def build_slat_armor():
	"""Light cage. Pre-detonates shaped charges, useless against solid shot -
	strong explosive threshold, weak kinetic. Reads as an open grid you can
	see through, which is exactly why it is bad against kinetic."""
	bm = bmesh.new()
	# Frame
	for sx in (-1, 1):
		add_box(bm, (sx * 0.48, 0, 0.030), (0.040, 0.980, 0.055), bevel=0.005)
	for sy in (-1, 1):
		add_box(bm, (0, sy * 0.48, 0.030), (0.980, 0.040, 0.055), bevel=0.005)
	# The slats themselves: vertical bars with real gaps between them
	for i in range(11):
		x = -0.42 + i * 0.084
		add_box(bm, (x, 0, 0.030), (0.026, 0.930, 0.048), bevel=0.003)
	# Two horizontal stringers tying them together
	for sy in (-1, 1):
		add_box(bm, (0, sy * 0.26, 0.044), (0.930, 0.028, 0.020), bevel=0.003)
	# Standoff brackets - slat armour only works held away from the hull
	for sx in (-1, 1):
		for sy in (-1, 1):
			add_box(bm, (sx * 0.42, sy * 0.42, 0.008), (0.070, 0.070, 0.020), bevel=0.004)
			add_tube_between(bm, (sx * 0.42, sy * 0.42, 0.010), (sx * 0.46, sy * 0.46, 0.052), 0.014)
	export_bmesh(bm, "armor_slat", "armor_slat.glb", color=(0.30, 0.31, 0.28, 1.0),
				 metallic=0.55, roughness=0.55)


def build_spaced_composite():
	"""Heavy layered plate. Big kinetic threshold, and it looks like it: a
	thick outer plate, a visible air gap, and a backing plate."""
	bm = bmesh.new()
	add_box(bm, (0, 0, 0.014), (0.990, 0.990, 0.028), bevel=0.008)        # backing plate
	# Spacer blocks holding the outer plate off
	for sx in (-1, 0, 1):
		for sy in (-1, 0, 1):
			add_box(bm, (sx * 0.36, sy * 0.36, 0.048), (0.080, 0.080, 0.045), bevel=0.005)
	add_box(bm, (0, 0, 0.086), (0.960, 0.960, 0.036), bevel=0.010)        # outer plate
	# Panel seams and bolt heads on the face
	for i in range(2):
		add_box(bm, (0, -0.24 + i * 0.48, 0.106), (0.940, 0.020, 0.012), bevel=0.003)
	for sx in (-1, 1):
		for sy in (-1, 1):
			bolt_ring_z(bm, 0.108, 0.060, count=6, bolt_r=0.014, bolt_len=0.016)
	for i in range(4):
		a = (i / 4) * math.tau + math.pi / 4.0
		add_cyl_z(bm, (math.cos(a) * 0.400, math.sin(a) * 0.400, 0.110), 0.020, 0.020, segments=8)
	# Corner chamfer plates, so it does not read as a plain slab
	for sx in (-1, 1):
		for sy in (-1, 1):
			add_box(bm, (sx * 0.455, sy * 0.455, 0.070), (0.110, 0.110, 0.030), bevel=0.010)
	export_bmesh(bm, "armor_spaced", "armor_spaced.glb", color=(0.34, 0.35, 0.36, 1.0),
				 metallic=0.62, roughness=0.46)


def build_ablative_foam():
	"""Thermal. A quilted sacrificial blanket over a thin backing - soft,
	matte and obviously not metal, which is the whole read."""
	bm = bmesh.new()
	add_box(bm, (0, 0, 0.010), (0.990, 0.990, 0.020), bevel=0.006)        # backing
	# Quilted pillows in a grid, each slightly domed
	for i in range(4):
		for j in range(4):
			x = -0.36 + i * 0.24
			y = -0.36 + j * 0.24
			add_box(bm, (x, y, 0.052), (0.205, 0.205, 0.056), bevel=0.024)
			add_cyl_z(bm, (x, y, 0.082), 0.016, 0.012, segments=10)       # quilting stud
	# Retaining straps between the rows
	for i in range(3):
		add_box(bm, (0, -0.24 + i * 0.24, 0.084), (0.960, 0.022, 0.010), bevel=0.004)
		add_box(bm, (-0.24 + i * 0.24, 0, 0.084), (0.022, 0.960, 0.010), bevel=0.004)
	# Edge trim clamping the blanket down
	for sx in (-1, 1):
		add_box(bm, (sx * 0.478, 0, 0.034), (0.040, 0.990, 0.052), bevel=0.006)
	for sy in (-1, 1):
		add_box(bm, (0, sy * 0.478, 0.034), (0.990, 0.040, 0.052), bevel=0.006)
	export_bmesh(bm, "armor_ablative", "armor_ablative.glb", color=(0.52, 0.50, 0.44, 1.0),
				 metallic=0.05, roughness=0.88)


if __name__ == "__main__":
	clear_scene()
	build_chaff_dispenser()
	build_laser_dazzler()
	build_aps_interceptor()
	build_aa_autocannon()
	build_jammer_mast()
	build_sentry_deployer()
	build_sensor_beacon_launcher()
	build_decoy_projector()
	build_slat_armor()
	build_spaced_composite()
	build_ablative_foam()
	print("PD_DEPLOY_ARMOR_PARTS_DONE")
