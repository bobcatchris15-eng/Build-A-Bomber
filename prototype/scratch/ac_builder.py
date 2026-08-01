# ---------------------------------------------------------------------------
# AUTOCANNON - M230 chain gun, second pass
#
# The first remodel was still reading as "bigger machine gun": a boxy receiver
# with a stubby barrel on a pintle, which is the same silhouette as the HMG at
# 120% scale. Rebuilt against Chris's reference photo of an airframe-mounted
# installation, which is a completely different object, and the differences
# are all structural rather than decorative:
#
#   1. THE BARREL IS THE SILHOUETTE. Very long, very slim, and projecting a
#      long way clear of everything else - so the gun reads as "reach" rather
#      than "volume of fire". The old one was barely longer than its receiver.
#   2. A DISTINCTIVE MUZZLE: a ribbed/fluted sleeve near the tip and then a
#      flared bell, unmistakable at a distance and nothing like the plain
#      crowned pipe an HMG carries.
#   3. EXPOSED HELICAL RECOIL SPRINGS. The single most legible cue in the
#      reference - big open coil springs you can see daylight through. No
#      machine gun has these on the outside.
#   4. TUBULAR WELDED FRAMING, not milled blocks. Round tube stock triangulated
#      into an A-frame, so the mount reads as fabricated aircraft structure.
#   5. HYDRAULIC HOSES AND CABLE RUNS everywhere, with connector blocks and
#      P-clips, draped rather than routed in straight lines.
#
# The chain drive housing stays - it is what makes it an M230 rather than a
# generic cannon - but it no longer dominates, because in the reference the
# structure and the barrel do.
# ---------------------------------------------------------------------------
def build_autocannon():
	# 1. TUBULAR CHIN MOUNT - origin at deck. Welded tube A-frame with the
	#    recoil springs standing in it, not a solid pintle.
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.018), 0.170, 0.036, segments=22)          # deck ring
	for i in range(12):
		a = (i / 12) * math.tau
		add_cyl_z(bm, (math.cos(a) * 0.150, math.sin(a) * 0.150, 0.040), 0.010, 0.016, segments=6)
	add_cyl_z(bm, (0, 0, 0.062), 0.108, 0.052, segments=20)          # azimuth drum
	add_box(bm, (0, 0.080, 0.062), (0.115, 0.050, 0.060), bevel=0.007)   # drive gearbox
	add_cyl_y(bm, (0, 0.112, 0.062), 0.026, 0.026, segments=12)

	# Welded tube A-frame: two forward legs up to the trunnions, two rear
	# legs, cross-braced. This is the shape doing most of the work.
	for side in (-1, 1):
		add_tube_between(bm, (side * 0.055, 0.030, 0.090), (side * 0.145, 0.050, 0.265), 0.020)
		add_tube_between(bm, (side * 0.055, -0.045, 0.090), (side * 0.145, 0.010, 0.265), 0.020)
		add_tube_between(bm, (side * 0.145, 0.050, 0.265), (side * 0.145, 0.010, 0.265), 0.018)
		# Cross-brace back down to the drum
		add_tube_between(bm, (side * 0.145, 0.010, 0.265), (0, -0.060, 0.100), 0.014)
		# Trunnion bearing at the apex
		add_cyl_x(bm, (side * 0.150, 0.030, 0.268), 0.040, 0.036, segments=16)
		add_cyl_x(bm, (side * 0.172, 0.030, 0.268), 0.020, 0.014, segments=10)
		for i in range(6):
			a = (i / 6) * math.tau
			add_cyl_x(bm, (side * 0.170, 0.030 + math.cos(a) * 0.028, 0.268 + math.sin(a) * 0.028),
					  0.006, 0.010, segments=6)

	# EXPOSED RECOIL SPRINGS - the reference's loudest cue. Big open coils
	# standing between the deck and the cradle, one each side.
	for side in (-1, 1):
		add_cyl_z(bm, (side * 0.098, -0.075, 0.058), 0.038, 0.028, segments=14)   # lower seat
		add_helix(bm, (side * 0.098, -0.075, 0.150), 0.033, 0.170, 6.0, 0.0085)
		add_cyl_z(bm, (side * 0.098, -0.075, 0.242), 0.038, 0.026, segments=14)   # upper seat
		add_cyl_z(bm, (side * 0.098, -0.075, 0.150), 0.013, 0.190, segments=10)   # guide rod
		add_box(bm, (side * 0.098, -0.075, 0.264), (0.048, 0.036, 0.024), bevel=0.004)

	# Hydraulic actuator on the centreline behind the springs
	add_cyl_z(bm, (0, -0.115, 0.115), 0.030, 0.130, segments=14)
	add_cyl_z(bm, (0, -0.115, 0.200), 0.014, 0.070, segments=10)
	add_box(bm, (0, -0.115, 0.240), (0.040, 0.032, 0.022), bevel=0.004)

	# HOSES AND CABLE RUNS - draped, with P-clips and a connector block.
	for i in range(3):
		add_tube_between(bm, (-0.100, -0.100 + i * 0.014, 0.100 + i * 0.010),
						 (0.100, -0.100 + i * 0.014, 0.100 + i * 0.010), 0.008, segments=6)
	for side in (-1, 1):
		add_tube_between(bm, (side * 0.100, -0.096, 0.106), (side * 0.140, -0.030, 0.230), 0.009, segments=6)
		add_tube_between(bm, (side * 0.140, -0.030, 0.230), (side * 0.120, 0.060, 0.262), 0.009, segments=6)
	add_box(bm, (0, -0.140, 0.072), (0.072, 0.040, 0.036), bevel=0.005)      # connector block
	for i in range(3):
		add_cyl_y(bm, (-0.022 + i * 0.022, -0.166, 0.072), 0.008, 0.020, segments=6)
	export_bmesh(bm, "autocannon_mount", "autocannon_mount.glb", color=(0.19, 0.20, 0.22, 1.0))

	# 2. RECEIVER - origin at trunnion. Slimmer and lower than the last pass:
	#    in the reference the receiver is a modest part of the object, and it
	#    was the chunky receiver that made this read as a machine gun.
	bm = bmesh.new()
	rw, rd, rh = 0.135, 0.285, 0.140
	add_box(bm, (0, -0.040, 0.0), (rw, rd, rh), bevel=0.011)
	add_box(bm, (0, -0.030, 0.080), (rw * 0.78, rd * 0.75, 0.022), bevel=0.005)  # top cover
	for i in range(3):
		add_box(bm, (0, -0.120 + i * 0.080, 0.094), (rw * 0.52, 0.016, 0.010), bevel=0.002)

	# Chain drive housing on the left flank - present and readable, but no
	# longer the widest thing on the gun.
	add_box(bm, (-0.086, -0.040, 0.006), (0.040, 0.225, 0.108), bevel=0.017)
	add_cyl_x(bm, (-0.110, 0.038, 0.006), 0.044, 0.022, segments=18)
	add_cyl_x(bm, (-0.110, -0.116, 0.006), 0.038, 0.022, segments=16)
	add_cyl_x(bm, (-0.124, 0.038, 0.006), 0.017, 0.018, segments=10)
	for i in range(6):
		a = (i / 6) * math.tau
		add_cyl_x(bm, (-0.106, 0.038 + math.cos(a) * 0.053, 0.006 + math.sin(a) * 0.053),
				  0.006, 0.012, segments=6)
	add_cyl_y(bm, (-0.086, -0.196, 0.006), 0.036, 0.068, segments=14)       # drive motor
	add_cyl_y(bm, (-0.086, -0.234, 0.006), 0.026, 0.018, segments=12)

	# Right flank: ejection chute and inspection plate
	add_box(bm, (rw * 0.5 + 0.008, -0.066, -0.018), (0.013, 0.095, 0.050), bevel=0.004)
	add_box(bm, (rw * 0.5 + 0.005, 0.030, 0.016), (0.009, 0.075, 0.062), bevel=0.004)

	# Recoil rails running back either side, with their own small springs -
	# echoes the mount's springs and ties the two together.
	for side in (-1, 1):
		add_cyl_y(bm, (side * 0.082, -0.075, 0.048), 0.020, 0.230, segments=12)
		add_helix(bm, (side * 0.082, -0.075, 0.048), 0.026, 0.140, 5.0, 0.0060, axis='Y')
		add_cyl_y(bm, (side * 0.082, 0.048, 0.048), 0.028, 0.024, segments=12)
		add_cyl_y(bm, (side * 0.082, -0.198, 0.048), 0.030, 0.028, segments=12)

	# Trunnion lugs
	for side in (-1, 1):
		add_box(bm, (side * (rw * 0.5 + 0.010), 0.015, 0.0), (0.024, 0.062, 0.066), bevel=0.005)
		add_cyl_x(bm, (side * (rw * 0.5 + 0.026), 0.015, 0.0), 0.028, 0.018, segments=14)

	# Feed throat underneath
	add_box(bm, (0, -0.015, -0.088), (0.092, 0.100, 0.040), bevel=0.007)
	# Hose stubs off the back plate
	add_box(bm, (0, -0.190, 0.010), (0.120, 0.024, 0.120), bevel=0.006)
	for side in (-1, 1):
		add_cyl_y(bm, (side * 0.040, -0.212, 0.030), 0.010, 0.026, segments=6)
	export_bmesh(bm, "autocannon_receiver", "autocannon_receiver.glb", color=(0.20, 0.21, 0.23, 1.0))

	# 3. BARREL - origin at receiver face, extends +Y. LONG and SLIM, with the
	#    reference's ribbed sleeve and flared bell at the muzzle. This part is
	#    doing most of the work of not looking like a machine gun.
	bm = bmesh.new()
	add_cyl_y(bm, (0, 0.040, 0), 0.050, 0.080, segments=18)       # barrel nut
	bolt_ring(bm, 0.040, 0.042, count=8)
	add_taper_y(bm, (0, 0.110, 0), 0.044, 0.030, 0.060, segments=16)
	add_cyl_y(bm, (0, 0.700, 0), 0.026, 1.120, segments=16)       # the long thin tube
	# Barrel clamps at intervals, with hose clips hanging off them
	for i in range(3):
		var_y = 0.300 + i * 0.290
		add_cyl_y(bm, (0, var_y, 0), 0.034, 0.020, segments=16)
		add_box(bm, (0, var_y, 0.038), (0.024, 0.016, 0.024), bevel=0.003)
	# RIBBED MUZZLE SLEEVE - a stack of raised bands, the reference's tell
	for i in range(7):
		add_cyl_y(bm, (0, 1.190 + i * 0.026, 0), 0.040, 0.017, segments=18)
	add_cyl_y(bm, (0, 1.280, 0), 0.031, 0.070, segments=18)       # gap before the bell
	# FLARED BELL at the tip
	add_taper_y(bm, (0, 1.340, 0), 0.034, 0.052, 0.055, segments=20)
	add_cyl_y(bm, (0, 1.376, 0), 0.052, 0.022, segments=20)
	add_cyl_y(bm, (0, 1.392, 0), 0.044, 0.014, segments=20)
	export_bmesh(bm, "autocannon_barrel", "autocannon_barrel.glb", color=(0.13, 0.14, 0.15, 1.0))

	# 4. LINKLESS AMMO MAGAZINE - its own part so the drum_size tweak scales
	#    ONLY the magazine. Origin at the receiver's underside feed throat.
	bm = bmesh.new()
	add_cyl_z(bm, (0, -0.050, -0.170), 0.130, 0.140, segments=20)      # drum body
	add_cyl_z(bm, (0, -0.050, -0.098), 0.106, 0.018, segments=20)      # lid
	add_cyl_z(bm, (0, -0.050, -0.244), 0.112, 0.016, segments=20)      # floor
	for i in range(8):
		a = (i / 8) * math.tau
		add_box(bm, (math.cos(a) * 0.122, -0.050 + math.sin(a) * 0.122, -0.170),
				(0.020, 0.020, 0.130), bevel=0.004)
	add_cyl_z(bm, (0, -0.050, -0.170), 0.034, 0.158, segments=12)      # centre auger
	# Linkless chute curving up into the throat, with a hose clipped alongside
	for i in range(5):
		add_box(bm, (0, -0.044 + i * 0.010, -0.105 + i * 0.024), (0.068, 0.036, 0.030), bevel=0.005)
	add_tube_between(bm, (0.052, -0.050, -0.120), (0.052, 0.000, 0.010), 0.008, segments=6)
	add_box(bm, (0, 0.004, 0.010), (0.078, 0.050, 0.036), bevel=0.005)
	export_bmesh(bm, "autocannon_ammo_box", "autocannon_ammo_box.glb", color=(0.21, 0.24, 0.20, 1.0),
				 metallic=0.4, roughness=0.6)
