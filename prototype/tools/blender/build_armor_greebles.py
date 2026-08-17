import sys
import os
import math
import bmesh
import bpy
import mathutils

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _greeble import *  # noqa: F401,F403

# SQUASH DEPTH, NOT FOOTPRINT
# ---------------------------------------------------------------------------
# The four hull ARMOR MATERIALS are scattered by greeble_field.gd, which
# places every instance at its AUTHORED SIZE on the hull face and aligns +Z
# to the surface normal. The X/Y footprint of the part is the read - a bolt
# field, an ERA mosaic, a tile lattice - and changing that footprint
# re-engineers the silhouette. The Z extent is the THICKNESS - how far the
# part stands off the hull - and that is a different knob.
#
# 2026-08-16: THICKNESS_SCALE was briefly set to 0.1 here, on the read of
# "the armor modules are too thick, make them a tenth of what they are".
# That was the wrong target. "Modules" in the design-lab vocabulary is the
# PLACEABLE PARTS FROM THE CATALOG (armor_plating, slat_armor,
# spaced_composite, ablative_foam), which are scaled at runtime by
# module_placer._measure_hull_facet / the auto-scale block, not authored
# in Blender. The greeble scatter on the hull (the bolts, ERA bricks,
# tiles) is a separate, deliberately protruding system, and the rest of
# the file's comments are right that they should keep their depth.
# Reverted to 1.0 (no-op); the helper is kept so the constant stays
# discoverable if a different read needs it later.
THICKNESS_SCALE = 1.0


def squash_z(bm, factor: float) -> None:
	"""Compress every vertex's +Z toward z=0 by `factor`. The mounting face
	(z=0 by convention, per _greeble.py header) does not move; everything
	above it flattens. Run just before export_bmesh.

	A plain vertex loop rather than bmesh.ops.scale because Blender 5.2's
	bmesh scale operator has no `geom` keyword - it operates on a selection
	that has to come from the active mesh, and a free-floating bmesh has no
	selection. The result is the same; the form is just more honest about
	what it does."""
	if abs(factor - 1.0) < 1e-6:
		return
	for v in bm.verts:
		v.co.z *= float(factor)

# Repeating surface greebles that make the four hull ARMOR MATERIALS visually
# distinguishable, rather than distinguishable only by shader tint.
#
#   armor_stud_bolt      - riveted bolt-head plate      (hardened_steel)
#   armor_reactive_block - ERA brick                    (reactive_armor)
#   armor_ceramic_tile   - hex ablative tile            (ablative_ceramic)
#   armor_shield_emitter - projector array              (energy_shielding)
#
# WHY MESHES AND NOT MORE SHADER
# ---------------------------------------------------------------------------
# hull_material_builder.gd already parameterises colour, wear, grime and
# metallic/roughness per material, and that is exactly the problem: at
# gameplay distance four materials that differ only in tint and gloss read as
# one material in four paint schemes. Silhouette-scale repetition is what
# actually distinguishes armour types in reality - a riveted plate, a brick
# of ERA, a lattice of ceramic tiles - and it survives being small on screen
# in a way a roughness value does not.
#
# CONVENTIONS
#   - Each greeble is authored with its MOUNTING FACE at Z=0 and its detail
#     rising in +Z (Blender up), which the placer aligns to the hull's own
#     surface normal.
#   - Authored small and at TRUE size: these are instanced many times across a
#     hull and must never be stretched to fit, exactly like the structural
#     hardware. Density scales with hull size; the greeble does not.
#   - Deliberately low-poly. A large hull can carry 100+ of these, so each one
#     has to be cheap; the read comes from repetition, not from detail.

def build_stud_bolt():
	"""hardened_steel: a riveted plate section. The classic 'this is thick
	steel bolted together' cue, and the most common greeble by count."""
	bm = bmesh.new()
	# Shallow backing plate with a single-segment chamfer. A 2-segment bevel
	# here cost about 130 triangles on a part that ships 150 copies per hull;
	# the chamfer reads identically at the size this is ever drawn.
	add_box(bm, (0, 0, 0.010), (0.130, 0.130, 0.020), bevel=0.006, bevel_segments=1)
	# Domed rivet heads at the corners plus one in the middle. One tapered
	# cylinder each rather than a stacked pair - the taper gives the dome, and
	# the second stacked disc was invisible at any distance this is seen from.
	for sx in (-1, 1):
		for sy in (-1, 1):
			add_taper_z(bm, (sx * 0.042, sy * 0.042, 0.028), 0.018, 0.011, 0.020, segments=6)
	add_taper_z(bm, (0, 0, 0.028), 0.020, 0.012, 0.022, segments=6)
	# A weld seam running across it, so a field of these reads as panels
	add_cyl_x(bm, (0, 0.068, 0.020), 0.008, 0.130, segments=5)
	export_bmesh(bm, "armor_stud_bolt", "armor_stud_bolt.glb",
				 color=(0.36, 0.37, 0.39, 1.0), metallic=0.80, roughness=0.42)


def build_reactive_block():
	"""reactive_armor: an ERA brick. Chunky, angled, individually replaceable
	and obviously a box of explosive strapped to the outside of the vehicle -
	which is precisely what it is."""
	bm = bmesh.new()
	# The brick, canted so a field of them reads as sloped. Chamfer only - see
	# build_stud_bolt; this part ships up to 90 copies per hull.
	add_box(bm, (0, 0, 0.048), (0.165, 0.115, 0.076), bevel=0.010, bevel_segments=1)
	# Sloped front lip
	add_box(bm, (0, 0.052, 0.070), (0.150, 0.040, 0.030), bevel=0.008, bevel_segments=1)
	# Retaining frame around the base - ERA is held in a cradle, not glued on.
	# Two side rails only: the fore-and-aft pair sat under the brick's own
	# overhang and never showed, so they were 200 triangles of nothing.
	for sx in (-1, 1):
		add_box(bm, (sx * 0.086, 0, 0.016), (0.018, 0.125, 0.030))
	# Corner clamps, unbevelled and 4-sided - at 1cm across a hexagonal clamp
	# and a square one are the same pixel.
	for sx in (-1, 1):
		for sy in (-1, 1):
			add_cyl_z(bm, (sx * 0.078, sy * 0.052, 0.034), 0.011, 0.020, segments=4)
	# Stencil plate on the face
	add_box(bm, (0, -0.020, 0.088), (0.070, 0.040, 0.008))
	export_bmesh(bm, "armor_reactive_block", "armor_reactive_block.glb",
				 color=(0.30, 0.33, 0.27, 1.0), metallic=0.35, roughness=0.62)


def build_ceramic_tile():
	"""ablative_ceramic: a hexagonal tile. Hex because a tessellating lattice
	is the read - ceramic armour is a mosaic of small replaceable tiles, and
	hexagons make that legible even when each tile is a few pixels."""
	bm = bmesh.new()
	r = 0.095
	# The tile: a hex prism with a bevelled top face
	add_cyl_z(bm, (0, 0, 0.016), r, 0.032, segments=6)
	add_cyl_z(bm, (0, 0, 0.036), r * 0.82, 0.014, segments=6)
	# Retaining grout ridge around the base, so tiles read as SET into
	# something rather than stuck on
	add_cyl_z(bm, (0, 0, 0.005), r * 1.10, 0.012, segments=6)
	# A single central fixing stud
	add_cyl_z(bm, (0, 0, 0.046), 0.014, 0.012, segments=6)
	export_bmesh(bm, "armor_ceramic_tile", "armor_ceramic_tile.glb",
				 color=(0.68, 0.66, 0.60, 1.0), metallic=0.02, roughness=0.52)


def build_shield_emitter():
	"""energy_shielding: a projector array. Placed only at the hull's upper
	corners - four of them, not a field - because a shield is generated by a
	few emitters rather than by cladding. This is the piece that has to sell
	the ellipsoid it projects, so it gets more detail than the others."""
	bm = bmesh.new()
	# Base pad and a short mast
	add_cyl_z(bm, (0, 0, 0.014), 0.070, 0.028, segments=14)
	bolt_ring_z(bm, 0.030, 0.056, count=6, bolt_r=0.008, bolt_len=0.012)
	add_cyl_z(bm, (0, 0, 0.055), 0.036, 0.055, segments=12)
	# Gimbal yoke carrying the emitter head
	for side in (-1, 1):
		add_box(bm, (side * 0.042, 0, 0.100), (0.016, 0.050, 0.070), bevel=0.005)
	add_cyl_x(bm, (0, 0, 0.128), 0.014, 0.090, segments=10)
	# Emitter head: a stack of rings around a central rod, ending in a node
	add_cyl_z(bm, (0, 0, 0.150), 0.030, 0.040, segments=14)
	for i in range(3):
		add_cyl_z(bm, (0, 0, 0.142 + i * 0.020), 0.044 - i * 0.006, 0.010, segments=14)
	add_cyl_z(bm, (0, 0, 0.186), 0.012, 0.045, segments=10)
	add_cyl_z(bm, (0, 0, 0.212), 0.024, 0.020, segments=12)
	# Three field vanes fanning out from the node - the bit that reads as
	# "this projects something"
	for i in range(3):
		a = (i / 3) * math.tau
		add_tube_between(bm, (0, 0, 0.212),
						 (math.cos(a) * 0.062, math.sin(a) * 0.062, 0.258), 0.007, segments=6)
		add_cyl_z(bm, (math.cos(a) * 0.062, math.sin(a) * 0.062, 0.262), 0.013, 0.014, segments=8)
	# Coolant/HT feed down the back of the mast
	add_tube_between(bm, (-0.040, -0.030, 0.030), (-0.030, -0.020, 0.130), 0.008, segments=6)
	add_box(bm, (-0.046, -0.036, 0.024), (0.034, 0.030, 0.026), bevel=0.004)
	export_bmesh(bm, "armor_shield_emitter", "armor_shield_emitter.glb",
				 color=(0.30, 0.34, 0.40, 1.0), metallic=0.70, roughness=0.30)


if __name__ == "__main__":
	clear_scene()
	build_stud_bolt()
	build_reactive_block()
	build_ceramic_tile()
	build_shield_emitter()
	print("ARMOR_GREEBLE_PARTS_DONE")
