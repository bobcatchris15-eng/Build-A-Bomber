import bpy
import bmesh
import math
import os
import mathutils

# Authored HARDWARE DETAIL parts for the six structural pieces (block, dome,
# slab, wedge, girder, i-beam).
#
# WHY THIS FILE LOOKS DIFFERENT FROM build_roster_expansion.py / build_hmg.py
# ---------------------------------------------------------------------------
# Every other part family in this project authors the WHOLE part as a .glb and
# lets visual_builder scale it. That is correct for a weapon: a cannon has one
# silhouette and its tweaks stretch along known axes.
#
# Structural pieces are the opposite case. They are the only modules the
# player can freely scale on all three axes at once (module_placer.gd's
# gizmo-category switch gives them X, Y AND Z handles), and they are expected
# to be stretched hard - a girder pulled out to four times its length, a slab
# squashed to a thin deck. Authoring "a whole girder" as one mesh and scaling
# it 4x in Z would smear every bolt head into a 4x-long capsule and turn the
# bevels into ramps. That is precisely the failure that made these six read as
# below the standard of the rest of the roster.
#
# So the split is: the BODY of each structural piece stays procedural in
# visual_builder.gd (it is a stretched box/wedge/dome - trivial geometry that
# WANTS to be parametric), and the DETAIL is authored here as small,
# fixed-size hardware that gets instanced onto the body at a constant real-
# world size no matter how far the body is stretched. Stretch a girder and you
# get more splice collars, not longer ones. That is also how real structure
# works, which is why it reads correctly.
#
# CONVENTIONS
#   - Blender +Z is UP, +Y is FORWARD (Godot -Z), matching every other builder
#     script here, so the glTF import lands in the same axis space.
#   - Every part's origin is at its MOUNTING FACE, so visual_builder can place
#     one by setting position alone and never has to compensate for a centroid.
#   - Parts are authored at their true final size (roughly 0.05-0.25 units).
#     visual_builder must NOT scale them - that is the entire point.
#   - Detail level matches basic_cannon/HMG: bolt heads, rolled edges,
#     lightening holes, weld beads. VISUAL_ART_DIRECTION.md 1.2 puts the
#     goofiness at detail scale and never in silhouette, so this is all
#     straight-faced structural steel.

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


def add_torus(bm, pos, major_r, minor_r, major_seg=20, minor_seg=8, rot=None):
	"""A ring. Authored in the XY plane (axis +Z) before `rot` is applied."""
	verts = []
	for i in range(major_seg):
		a = (i / major_seg) * math.tau
		ring = []
		cx, cy = math.cos(a) * major_r, math.sin(a) * major_r
		for j in range(minor_seg):
			b = (j / minor_seg) * math.tau
			r = major_r + math.cos(b) * minor_r
			co = mathutils.Vector((math.cos(a) * r, math.sin(a) * r, math.sin(b) * minor_r))
			if rot:
				co = rot @ co
			ring.append(bm.verts.new(co + mathutils.Vector(pos)))
		verts.append(ring)
	for i in range(major_seg):
		for j in range(minor_seg):
			a0 = verts[i][j]
			a1 = verts[i][(j + 1) % minor_seg]
			b0 = verts[(i + 1) % major_seg][j]
			b1 = verts[(i + 1) % major_seg][(j + 1) % minor_seg]
			try:
				bm.faces.new((a0, a1, b1, b0))
			except ValueError:
				pass


def hex_bolt(bm, pos, radius=0.011, height=0.016, axis='Z'):
	"""A single hex bolt head. 6 segments so it actually reads as a fastener
	rather than a smooth stud at the sizes these are used at."""
	if axis == 'Z':
		add_cyl_z(bm, pos, radius, height, segments=6)
	elif axis == 'Y':
		add_cyl_y(bm, pos, radius, height, segments=6)
	else:
		add_cyl_x(bm, pos, radius, height, segments=6)


def export_bmesh(bm, object_name, filename, color=(0.24, 0.24, 0.26, 1.0),
				 metallic=0.80, roughness=0.42):
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
# CORNER BRACKET
# An L-angle gusset that wraps a vertical edge of a block/slab/wedge. Origin
# at the inner corner, arms running along +X and +Y, plate rising in +Z.
# ---------------------------------------------------------------------------
def build_corner_bracket():
	bm = bmesh.new()
	arm = 0.13
	thick = 0.022
	tall = 0.15
	# Two plate arms meeting at the origin corner
	add_box(bm, (arm / 2.0, thick / 2.0, tall / 2.0), (arm, thick, tall), bevel=0.005)
	add_box(bm, (thick / 2.0, arm / 2.0, tall / 2.0), (thick, arm, tall), bevel=0.005)
	# Weld bead down the inside corner
	add_cyl_z(bm, (thick * 0.7, thick * 0.7, tall / 2.0), 0.016, tall * 0.96, segments=8)
	# Triangular stiffener across the inside of the angle, top and bottom
	for z in (tall * 0.18, tall * 0.82):
		add_box(bm, (0.045, 0.045, z), (0.075, 0.075, 0.016), bevel=0.004)
	# Bolts through each arm
	for t in (0.30, 0.72):
		hex_bolt(bm, (arm * t, thick + 0.006, tall * 0.28), axis='Y')
		hex_bolt(bm, (arm * t, thick + 0.006, tall * 0.72), axis='Y')
		hex_bolt(bm, (thick + 0.006, arm * t, tall * 0.28), axis='X')
		hex_bolt(bm, (thick + 0.006, arm * t, tall * 0.72), axis='X')
	export_bmesh(bm, "struct_corner_bracket", "struct_corner_bracket.glb",
				 color=(0.26, 0.26, 0.28, 1.0))


# ---------------------------------------------------------------------------
# BOLT PAD
# A round bolted mounting pad. The workhorse: rims, hardpoints, anywhere a
# surface needs to read as fastened rather than extruded. Origin at its base,
# axis +Z.
# ---------------------------------------------------------------------------
def build_bolt_pad():
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.010), 0.062, 0.020, segments=18)   # base flange
	add_cyl_z(bm, (0, 0, 0.028), 0.042, 0.018, segments=16)   # raised boss
	hex_bolt(bm, (0, 0, 0.044), radius=0.016, height=0.014)   # centre fastener
	for i in range(4):
		a = (i / 4) * math.tau + math.pi / 4.0
		hex_bolt(bm, (math.cos(a) * 0.048, math.sin(a) * 0.048, 0.024),
				 radius=0.009, height=0.014)
	export_bmesh(bm, "struct_bolt_pad", "struct_bolt_pad.glb",
				 color=(0.28, 0.28, 0.30, 1.0))


# ---------------------------------------------------------------------------
# STIFFENER RIB
# A pressed web rib with a lightening hole and a rolled edge - the thing that
# makes a flat plate read as a structural panel instead of a slab of butter.
# Origin at the base of the rib, web in the YZ plane, thickness in X, so
# visual_builder places it standing on a deck and running along +Y.
# ---------------------------------------------------------------------------
def build_stiffener_rib():
	bm = bmesh.new()
	length = 0.30
	height = 0.10
	web = 0.016
	# Web plate
	add_box(bm, (0, 0, height / 2.0), (web, length, height), bevel=0.004)
	# Rolled top edge (a bead, so the silhouette isn't a bare rectangle)
	add_cyl_y(bm, (0, 0, height), 0.017, length, segments=10)
	# Lightening holes punched through the web, read as recessed rings
	for t in (-0.26, 0.0, 0.26):
		add_cyl_x(bm, (0, length * t, height * 0.48), 0.028, web * 1.6, segments=12)
	# Base foot flanges either side, welded down
	for side in (-1, 1):
		add_box(bm, (side * 0.020, 0, 0.008), (0.026, length, 0.016), bevel=0.003)
	export_bmesh(bm, "struct_stiffener_rib", "struct_stiffener_rib.glb",
				 color=(0.25, 0.25, 0.27, 1.0))


# ---------------------------------------------------------------------------
# GUSSET
# A right-triangle web brace with a lightening hole, for the inside of a
# wedge and the junctions of a girder. Origin at the right-angle corner,
# triangle in the YZ plane (legs along +Y and +Z), thickness in X.
# ---------------------------------------------------------------------------
def build_gusset():
	bm = bmesh.new()
	leg = 0.16
	thick = 0.018
	# The triangle itself, built as an explicit prism rather than a beveled box
	pts = [(0.0, 0.0), (leg, 0.0), (0.0, leg)]
	front, back = [], []
	for (y, z) in pts:
		front.append(bm.verts.new((thick / 2.0, y, z)))
		back.append(bm.verts.new((-thick / 2.0, y, z)))
	bm.faces.new(front)
	bm.faces.new(list(reversed(back)))
	for i in range(3):
		j = (i + 1) % 3
		bm.faces.new((front[i], front[j], back[j], back[i]))
	# Rolled edge along the hypotenuse
	hyp_rot = mathutils.Matrix.Rotation(math.radians(-45), 4, 'X')
	_cone(bm, (0, leg / 2.0, leg / 2.0), 0.014, 0.014, leg * 1.414, 10,
		  mathutils.Matrix.Rotation(math.radians(90), 4, 'X') @ hyp_rot)
	# Lightening hole
	add_cyl_x(bm, (0, leg * 0.30, leg * 0.30), 0.032, thick * 1.8, segments=14)
	# Bolts along both legs
	for t in (0.35, 0.75):
		hex_bolt(bm, (0, leg * t, 0.016), radius=0.008, height=thick * 1.9, axis='X')
		hex_bolt(bm, (0, 0.016, leg * t), radius=0.008, height=thick * 1.9, axis='X')
	export_bmesh(bm, "struct_gusset", "struct_gusset.glb",
				 color=(0.25, 0.25, 0.27, 1.0))


# ---------------------------------------------------------------------------
# SPLICE COLLAR
# A bolted band clamped around a beam at a joint. Instanced along a girder or
# I-beam at a fixed spacing, so a longer beam gets MORE collars rather than a
# stretched one. Ring axis is +Y (the beam's run), origin at the ring centre.
# ---------------------------------------------------------------------------
def build_splice_collar():
	bm = bmesh.new()
	r = 0.075
	# The band
	add_cyl_y(bm, (0, 0, 0), r, 0.045, segments=20)
	add_cyl_y(bm, (0, 0, 0), r * 1.10, 0.020, segments=20)
	# Clamp lugs on both flanks, with the through-bolt
	for side in (-1, 1):
		add_box(bm, (side * (r + 0.020), 0, 0), (0.038, 0.048, 0.026), bevel=0.004)
		hex_bolt(bm, (side * (r + 0.020), 0, 0.020), radius=0.010, height=0.018)
	# Bolt heads around the band face
	for i in range(6):
		a = (i / 6) * math.tau
		hex_bolt(bm, (math.cos(a) * r * 0.98, 0.026, math.sin(a) * r * 0.98),
				 radius=0.008, height=0.014, axis='Y')
	export_bmesh(bm, "struct_splice_collar", "struct_splice_collar.glb",
				 color=(0.27, 0.27, 0.29, 1.0))


# ---------------------------------------------------------------------------
# BEAM END CAP
# A bolted plate closing off the end of a girder or I-beam, with a lifting
# shackle. Origin at the plate's inner face, cap facing +Y.
# ---------------------------------------------------------------------------
def build_beam_end_cap():
	bm = bmesh.new()
	add_box(bm, (0, 0.014, 0), (0.17, 0.028, 0.17), bevel=0.006)   # cap plate
	add_box(bm, (0, 0.034, 0), (0.11, 0.014, 0.11), bevel=0.004)   # raised centre
	for i in range(4):
		a = (i / 4) * math.tau + math.pi / 4.0
		hex_bolt(bm, (math.cos(a) * 0.062, 0.034, math.sin(a) * 0.062),
				 radius=0.010, height=0.018, axis='Y')
	# Shackle eye on top of the cap
	add_torus(bm, (0, 0.030, 0.098), 0.028, 0.010, major_seg=16, minor_seg=7,
			  rot=mathutils.Matrix.Rotation(math.radians(90), 4, 'X'))
	add_box(bm, (0, 0.030, 0.076), (0.034, 0.020, 0.022), bevel=0.004)
	export_bmesh(bm, "struct_beam_end_cap", "struct_beam_end_cap.glb",
				 color=(0.27, 0.27, 0.29, 1.0))


# ---------------------------------------------------------------------------
# DOME HATCH
# The crown of the turret base: a hinged armoured hatch with dog handles and a
# periscope stub. This is what gives the dome a scale reference and stops it
# reading as an undifferentiated grey hemisphere. Origin at its base, axis +Z.
# ---------------------------------------------------------------------------
def build_dome_hatch():
	bm = bmesh.new()
	add_cyl_z(bm, (0, 0, 0.012), 0.115, 0.024, segments=22)   # coaming ring
	add_cyl_z(bm, (0, 0, 0.036), 0.098, 0.026, segments=22)   # hatch lid
	add_cyl_z(bm, (0, 0, 0.052), 0.060, 0.014, segments=18)   # raised lid centre
	# Dog handles across the lid
	for side in (-1, 1):
		add_box(bm, (side * 0.042, 0, 0.066), (0.020, 0.090, 0.014), bevel=0.004)
		add_cyl_z(bm, (side * 0.042, 0.052, 0.062), 0.013, 0.020, segments=10)
	# Hinge at the back
	add_cyl_x(bm, (0, -0.104, 0.038), 0.016, 0.070, segments=12)
	for side in (-1, 1):
		add_box(bm, (side * 0.040, -0.104, 0.024), (0.022, 0.030, 0.030), bevel=0.004)
	# Periscope stub off to one side
	add_cyl_z(bm, (0.074, 0.052, 0.044), 0.024, 0.042, segments=12)
	add_box(bm, (0.074, 0.062, 0.070), (0.038, 0.024, 0.018), bevel=0.004)
	# Coaming bolts
	for i in range(10):
		a = (i / 10) * math.tau
		hex_bolt(bm, (math.cos(a) * 0.104, math.sin(a) * 0.104, 0.026),
				 radius=0.008, height=0.014)
	export_bmesh(bm, "struct_dome_hatch", "struct_dome_hatch.glb",
				 color=(0.26, 0.26, 0.28, 1.0))


# ---------------------------------------------------------------------------
# VISION BLOCK
# A small armoured periscope/vision slit that rings the dome's shoulder.
# Origin at its mounting face, glass facing +Y, so it can be rotated around
# the dome by code.
# ---------------------------------------------------------------------------
def build_vision_block():
	bm = bmesh.new()
	add_box(bm, (0, 0.020, 0), (0.086, 0.040, 0.052), bevel=0.006)     # armoured housing
	add_box(bm, (0, 0.042, 0.004), (0.062, 0.010, 0.024), bevel=0.002)  # the slit itself
	add_box(bm, (0, 0.030, 0.032), (0.090, 0.026, 0.014), bevel=0.004)  # brow / rain shield
	for side in (-1, 1):
		hex_bolt(bm, (side * 0.036, 0.016, -0.020), radius=0.008, height=0.016, axis='Y')
	export_bmesh(bm, "struct_vision_block", "struct_vision_block.glb",
				 color=(0.22, 0.22, 0.24, 1.0))


# ---------------------------------------------------------------------------
# TIE-DOWN
# A recessed D-ring cargo tie-down for deck surfaces (block tops, slab faces).
# Small, cheap, and instanced on a grid - the detail that makes a large flat
# panel read as a real deck. Origin at the deck surface, ring standing in +Z.
# ---------------------------------------------------------------------------
def build_tie_down():
	bm = bmesh.new()
	add_box(bm, (0, 0, 0.006), (0.070, 0.048, 0.012), bevel=0.003)   # recessed base plate
	for side in (-1, 1):                                              # lugs
		add_box(bm, (side * 0.022, 0, 0.020), (0.014, 0.020, 0.020), bevel=0.003)
	add_torus(bm, (0, 0, 0.034), 0.024, 0.008, major_seg=14, minor_seg=6,
			  rot=mathutils.Matrix.Rotation(math.radians(90), 4, 'Y'))
	for side in (-1, 1):
		hex_bolt(bm, (side * 0.028, 0.018, 0.012), radius=0.007, height=0.012)
	export_bmesh(bm, "struct_tie_down", "struct_tie_down.glb",
				 color=(0.29, 0.29, 0.31, 1.0))


# ---------------------------------------------------------------------------
# STEP CLEAT
# A non-slip step welded to a sloped face (the wedge) or the edge of a slab.
# Origin at the mounting face, tread running along +Y, standing out in +Z.
# ---------------------------------------------------------------------------
def build_step_cleat():
	bm = bmesh.new()
	add_box(bm, (0, 0, 0.010), (0.048, 0.170, 0.020), bevel=0.004)   # tread bar
	for i in range(5):                                                # grip ridges
		add_box(bm, (0, -0.064 + i * 0.032, 0.021), (0.050, 0.010, 0.008), bevel=0.002)
	for side in (-1, 1):                                              # welded feet
		add_box(bm, (0, side * 0.082, 0.004), (0.044, 0.014, 0.010), bevel=0.002)
	export_bmesh(bm, "struct_step_cleat", "struct_step_cleat.glb",
				 color=(0.24, 0.24, 0.25, 1.0))


if __name__ == "__main__":
	clear_scene()
	build_corner_bracket()
	build_bolt_pad()
	build_stiffener_rib()
	build_gusset()
	build_splice_collar()
	build_beam_end_cap()
	build_dome_hatch()
	build_vision_block()
	build_tie_down()
	build_step_cleat()
	print("STRUCTURAL_PARTS_DONE")
