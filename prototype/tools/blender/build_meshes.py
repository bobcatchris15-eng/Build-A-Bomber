"""
Build-A-Bomber mesh generator (Milestone: Visual Refinement pass 2)
Run headlessly with UPBGE's bundled Blender:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python tools\\blender\\build_meshes.py

Produces two families of assets:
  1. assets/models/hulls/*.glb  - one full chassis/foundation mesh per hull
     catalog entry, authored to match that hull's catalog "size" Vector3
     exactly, with fused-on greeble detail (vents, hatches, rivets,
     antennae, gussets...) so hulls read as distinct silhouettes rather
     than plain boxes/wedges.
  2. assets/models/parts/*.glb  - small reusable "kit" pieces (barrels,
     breeches, drums, domes, missile bodies, wheels, legs, rings...)
     referenced by multiple weapon/locomotion modules in visual_builder.gd.

COORDINATE CONVENTION (verified empirically against this exact export
pipeline - see scratch/probe_axes_*.py/gd):
  Blender is authored Z-up. The bundled glTF exporter's Y-up conversion
  maps  Godot_X = Blender_X,  Godot_Y = Blender_Z,  Godot_Z = Blender_Y.
  Every helper below takes GODOT-space (x, y_up, z_depth) coordinates and
  internally swaps to raw Blender coordinates via GV()/GS(), so all
  authoring code in this file can be written purely in terms of the same
  X/Y/Z semantics used everywhere else in the project (module_catalog.gd
  "size" Vector3, etc.) - no manual axis juggling needed at call sites.

  Runtime contract: authored assets are pre-oriented in final local space
  (no rotation compensation needed). This differs from the old pass-1
  script, which authored barrels along raw Blender Z relying on a
  runtime PI/2 rotation - that convention is retired. mesh_asset_loader.gd
  callers (module_placer.gd, visual_builder.gd) use authored meshes
  directly and only apply the OLD rotation to the procedural fallback
  primitives, which still default to Godot's Y-up CylinderMesh.
"""

import bpy
import bmesh
import math
import os
import mathutils

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
PARTS_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "parts")
HULLS_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "hulls")

os.makedirs(PARTS_DIR, exist_ok=True)
os.makedirs(HULLS_DIR, exist_ok=True)


# ---------------------------------------------------------------------------
# Core helpers
# ---------------------------------------------------------------------------

def clear_scene():
	bpy.ops.object.select_all(action='SELECT')
	bpy.ops.object.delete(use_global=False)
	for block in list(bpy.data.meshes):
		if block.users == 0:
			bpy.data.meshes.remove(block)
	for block in list(bpy.data.materials):
		if block.users == 0:
			bpy.data.materials.remove(block)


def GV(x, y, z):
	"""Godot-space (x, y_up, z_depth) -> raw Blender-space tuple."""
	return (x, z, y)


def GS(sx, sy, sz):
	"""Godot-space (width, height, depth) size -> raw Blender-space size."""
	return (sx, sz, sy)


def godot_forward_component(raw_normal):
	"""A bmesh face's raw-Blender-space normal's component along Godot's own
	-Z ("forward"/nose) axis - the inverse of GV()'s (x,y,z)->(x,z,y) swap,
	i.e. raw Blender Y carries Godot's Z-depth. hull_deform.gd's own
	"Forward convention is local -Z: the nose is the most-negative-Z tip"
	comment is the convention this matches - a face whose raw_normal.y is
	strongly negative faces the nose. Used to geometrically classify "hard
	armor" faces (frontal glacis + corner facets) vs. "structural" ones
	without needing to hand-track which named region a face belongs to
	through a convex-hull/bevel/loft construction - see mark_armor_faces().
	"""
	return raw_normal.y


def frontal_armor_predicate(hz, front_frac=0.3, exclude_belly_thresh=-0.6):
	"""Builds a predicate for mark_armor_faces() selecting the frontal arc
	of a hull: any face whose CENTER lies within the front `front_frac` of
	the hull's total length (Godot -Z = nose, see godot_forward_component()'s
	own comment - raw Blender Y carries Godot Z-depth, so a face center's
	raw .y IS its Godot z position directly, no swap needed since this is
	a coordinate VALUE not a normal), excluding belly/underside faces
	(raw normal .z very negative = Godot -Y/downward - see the same axis
	mapping) since those are never visually seen and armoring them would
	be a wasted, invisible area cost against the ~40% ceiling.
	Position-based rather than pure normal-angle: a convex-hull-derived
	hull's glacis/corner faces cluster at unpredictable, hull-specific
	normal angles (found empirically - medium_hull's own glacis+corners
	only reached ~8% of area even at a very permissive normal-angle
	threshold), while "front fraction of length" is a single, directly
	tunable knob per hull that behaves predictably regardless of each
	hull's individual taper geometry."""
	front_z_cutoff = -hz + 2.0 * hz * front_frac
	def predicate(f):
		center = f.calc_center_median()
		is_front = center.y < front_z_cutoff
		is_belly = f.normal.z < exclude_belly_thresh
		return is_front and not is_belly
	return predicate


def outward_face_predicate(threshold=0.4):
	"""For static defenses whose identity is "one hardened outward face,
	one sheltered inward face" rather than a vehicle's nose-to-tail taper
	(pillbox_foundation's embrasure and fortress_wall_foundation's arrow
	slits both face Godot +Z, per those builders' own authoring convention -
	NOT -Z like every vehicle hull's nose) - any face whose normal points
	sufficiently toward Godot +Z (raw Blender +Y, see godot_forward_component())
	is the exposed defensive face, armored; the sheltered back face, top,
	and end caps stay structural."""
	def predicate(f):
		return godot_forward_component(f.normal) > threshold
	return predicate


def vertical_armor_predicate(hy, base_frac=0.4):
	"""For a tall stepped tower with no distinct front/back (tiers stack
	along Godot Y/up, roughly rotationally symmetric per tier) - real
	castle-defense logic instead: the base/lower tiers facing ground-level
	assault are the hardened ones, upper tiers are lighter structural
	stonework. raw Blender Z carries Godot Y-up (see godot_forward_component()'s
	own comment on the GV() axis swap), so a face center's raw .z IS its
	Godot height directly."""
	y_cutoff = -hy + 2.0 * hy * base_frac
	def predicate(f):
		return f.calc_center_median().z < y_cutoff
	return predicate


def mark_armor_faces(bm, predicate):
	"""Sets material_index=1 (hard armor slot, see finalize_dual()) on
	every CURRENT bm.face satisfying predicate(face), leaving everything
	else at the default 0 (structural). Call this AFTER the hull's primary
	silhouette bevel but BEFORE greebles are fused on, so small appliqué
	fixtures (hatches/vents/antennae) default to reading as structural
	details bolted onto the hull, not armor plate, unless a specific
	greeble helper explicitly marks its own faces afterward. Returns the
	fraction of total face AREA marked armor (not face count - a handful of
	large glacis faces vs. many tiny bevel/greeble faces would otherwise
	misrepresent the actual visual area split) so callers can sanity-check
	against the ~40% ceiling."""
	total_area = 0.0
	armor_area = 0.0
	for f in bm.faces:
		area = f.calc_area()
		total_area += area
		if predicate(f):
			f.material_index = 1
			armor_area += area
	return armor_area / total_area if total_area > 0.0 else 0.0


def rot_matrix(godot_axis, angle_rad):
	"""Rotation matrix for a rotation of angle_rad around the given
	GODOT-space axis ('x','y','z'), expressed for raw Blender-space geometry."""
	if godot_axis == 'y':
		return mathutils.Matrix.Rotation(angle_rad, 3, 'Z')
	elif godot_axis == 'x':
		return mathutils.Matrix.Rotation(angle_rad, 3, 'X')
	else:
		return mathutils.Matrix.Rotation(angle_rad, 3, 'Y')


def new_material(name, color, metallic=0.7, roughness=0.4):
	mat = bpy.data.materials.get(name)
	if mat is None:
		mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes.get("Principled BSDF")
	if bsdf:
		bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
		bsdf.inputs["Metallic"].default_value = metallic
		bsdf.inputs["Roughness"].default_value = roughness
	return mat


def make_object_from_bmesh(bm, name):
	mesh = bpy.data.meshes.new(name + "_mesh")
	bm.to_mesh(mesh)
	bm.free()
	mesh.update()
	obj = bpy.data.objects.new(name, mesh)
	bpy.context.collection.objects.link(obj)
	return obj


def finalize(obj, name, color=(0.55, 0.56, 0.58), metallic=0.75, roughness=0.35):
	obj.name = name
	bpy.ops.object.select_all(action='DESELECT')
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.shade_smooth()
	try:
		obj.data.use_auto_smooth = True
		obj.data.auto_smooth_angle = math.radians(35)
	except Exception:
		pass
	mat = new_material(name + "_mat", color, metallic, roughness)
	if obj.data.materials:
		obj.data.materials[0] = mat
	else:
		obj.data.materials.append(mat)


def finalize_dual(obj, name, structural_color=(0.5, 0.5, 0.52), armor_color=(0.55, 0.56, 0.58),
		structural_metallic=0.15, structural_roughness=0.82, armor_metallic=0.75, armor_roughness=0.4):
	"""Same shading/smoothing setup as finalize(), but assigns TWO material
	slots (0=structural, 1=hard armor) instead of one - see hull_material_
	builder.gd's apply_hull_materials() for the runtime side of this
	convention (surface 0 gets build_structural_material(), surface 1+
	gets build_hull_material()). The actual color/metallic/roughness here
	are Blender-preview-only, same as finalize()'s own color param already
	was - Godot replaces BOTH slots' real materials entirely at runtime via
	set_surface_override_material(), so these values never reach the game;
	they just need to be two genuinely different material resources so
	Blender's glTF exporter treats them as two separate primitives.
	Requires mark_armor_faces() to have already set material_index=1 on
	the relevant bm.faces before make_object_from_bmesh() was called -
	this function only assigns the SLOTS, not which face uses which."""
	obj.name = name
	bpy.ops.object.select_all(action='DESELECT')
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.shade_smooth()
	try:
		obj.data.use_auto_smooth = True
		obj.data.auto_smooth_angle = math.radians(35)
	except Exception:
		pass
	# Deliberately NOT obj.data.materials.clear() first, even though the
	# mesh is always freshly created with 0 slots at this point anyway (so
	# clear() looks harmless/defensive) - empirically, clearing the list
	# clamps every polygon's material_index back to 0 as a data-integrity
	# side effect, and appending the 2 real materials afterward does NOT
	# retroactively fix already-clamped indices. Found by a real "only 1
	# glTF primitive exported despite 244/1380 polygons correctly split at
	# the bmesh/bpy.Mesh level" bug - see DECISIONS_NEEDED.md.
	structural_mat = new_material(name + "_structural_mat", structural_color, structural_metallic, structural_roughness)
	armor_mat = new_material(name + "_armor_mat", armor_color, armor_metallic, armor_roughness)
	obj.data.materials.append(structural_mat)
	obj.data.materials.append(armor_mat)


def export_glb(obj, filepath):
	bpy.ops.object.select_all(action='DESELECT')
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.export_scene.gltf(
		filepath=filepath,
		use_selection=True,
		export_format='GLB',
		export_yup=True,
		export_apply=True
	)
	print("Exported: " + filepath)


def export_and_cleanup(obj, out_dir, filename):
	path = os.path.join(out_dir, filename + ".glb")
	export_glb(obj, path)
	mesh_data = obj.data
	bpy.data.objects.remove(obj, do_unlink=True)
	if mesh_data and mesh_data.users == 0:
		bpy.data.meshes.remove(mesh_data)


# ---------------------------------------------------------------------------
# Geometric Polish Pass (Section 1) - shared tiered bevel + non-linear taper.
# Bevel width is keyed to a per-mesh reference dimension R rather than ever
# being a fixed world value, so the same three-tier vocabulary reads
# consistently on a tiny greeble or a whole hull. R excludes hull length on
# purpose - that's the axis under the heaviest runtime hull_scale stretch,
# so nose-to-tail stretching should never dilate bevel width.
# ---------------------------------------------------------------------------

def hull_reference_dim(size_x, size_y):
	"""R = min(width, height) - the design doc's reference dimension for
	keying bevel width and taper proportions."""
	return min(size_x, size_y)


def tiered_bevel_width(R, tier, pct=None, segments=None):
	"""Returns (width, segments) for an edge-role tier:
	  1 = primary structural silhouette edges (6-9% of R, 2 segments)
	  2 = secondary edges - hatch frames, ring corners (3-4% of R, 1 segment)
	  3 = cosmetic greeble/bolt-box edges (1-1.5% of R + a small fixed
	      floor, since pure percentage would vanish on tiny parts)
	`pct`/`segments` let a caller tune within (or deliberately just outside)
	a tier's band for per-archetype character - e.g. a heavy hull reading
	chunkier at the wide end of tier 1, an interceptor reading sharper at
	the narrow end. An absolute world-unit floor keeps every tier visible/
	non-z-fighting even at very small R."""
	if tier == 1:
		default_pct, default_segments = 0.075, 2
	elif tier == 2:
		default_pct, default_segments = 0.035, 1
	else:
		default_pct, default_segments = 0.0125, 1
	width = R * (pct if pct is not None else default_pct)
	if tier == 3:
		width = max(width, 0.012)
	segs = segments if segments is not None else default_segments
	return max(width, 0.01), segs


def bevel_sharp_edges(bm, verts, R, tier=1, angle_deg=20.0, max_face_frac=0.3, pct=None, segments=None,
		preserve_axis=None, preserve_thresh=0.95):
	"""Bevels only the genuinely sharp edges among `verts`, selected by
	dihedral angle - so a multi-slice taper loft's many near-coplanar
	edges are left alone (a blanket bevel would chew into the curve
	itself) while the real structural transitions (belly-to-deck, nose
	tip, spine ridge) get the tiered treatment. Works on any convex-hull-
	derived shape without hand-picking edge lists per hull.

	`preserve_axis` (0/1/2 for raw-Blender X/Y/Z) skips any edge touching
	a face whose normal is nearly aligned with that axis - e.g. a wall
	segment's flat end-cap faces, which must stay untouched so adjacent
	tiled segments still line up edge-to-edge."""
	width, segments = tiered_bevel_width(R, tier, pct=pct, segments=segments)
	width = min(width, R * max_face_frac)
	vert_set = set(verts)
	angle_thresh = math.radians(angle_deg)
	edges = []
	for e in bm.edges:
		if not (e.verts[0] in vert_set and e.verts[1] in vert_set):
			continue
		if len(e.link_faces) != 2:
			continue
		if preserve_axis is not None:
			skip = False
			for f in e.link_faces:
				if abs(f.normal[preserve_axis]) >= preserve_thresh:
					skip = True
					break
			if skip:
				continue
		if e.calc_face_angle() >= angle_thresh:
			edges.append(e)
	if edges:
		# A global R-based width can still self-intersect/spike near a
		# tapered tip (a pointed hull bow, a hull nose) where local edges
		# are much shorter than R - a real bug found on heavy_cruiser_hull
		# (see DECISIONS_NEEDED.md). Clamp to a safe fraction of the
		# SHORTEST selected edge's own length too, not just global R.
		min_edge_len = min(e.calc_length() for e in edges)
		width = min(width, min_edge_len * 0.4)
		bmesh.ops.bevel(bm, geom=edges, offset=width, segments=segments, affect='EDGES')
	return edges


def eased_taper(t):
	"""Smoothstep ease (0..1) so taper cross-sections blend rather than
	kink linearly from one slice to the next."""
	t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
	return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------------------
# Geometric Polish Pass (Section 1, Tier 2) - waist-inset and deck-line step.
# Both are real concave/raised surface details, which a pure convex_hull
# can't represent just by adding more points to its input cloud (any point
# "inside" the hull of its neighbors is simply ignored). Rather than pull in
# Blender's boolean modifier (new machinery, real non-manifold/perf risk),
# both are done as bisect_plane (clean loop cuts, no geometry removed) +
# a selective vertex shift within the cut band - bmesh-only, consistent
# with how the rest of this file already builds geometry.
#
# NOTE ON AXES: these operate directly on existing bm.verts (raw Blender
# coordinates), unlike most helpers above which take Godot-space args and
# call GV()/GS() internally. Per that convention: raw Blender X = Godot X
# (width, unchanged), raw Blender Y = Godot Z (length), raw Blender Z =
# Godot Y (height).
# ---------------------------------------------------------------------------

def add_waist_inset(bm, hx, hy, hz, depth_frac=0.06, height_frac=0.5, band_frac=0.1):
	"""Shallow horizontal recessed band cut into the hull's SIDE skin only
	(not the top deck/bottom belly, and not the spine) - natural sponson-
	mount nesting per the design doc. height_frac is the band's center as
	a fraction of hull height; depth_frac/band_frac are fractions of
	hx/hy for the inset depth and band thickness."""
	band_z0 = -hy + 2.0 * hy * height_frac - hy * band_frac
	band_z1 = -hy + 2.0 * hy * height_frac + hy * band_frac
	for plane_z in (band_z0, band_z1):
		bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
			plane_co=(0, 0, plane_z), plane_no=(0, 0, 1), clear_inner=False, clear_outer=False)
	depth = hx * depth_frac
	for v in bm.verts:
		if band_z0 - 1e-4 <= v.co.z <= band_z1 + 1e-4:
			if v.co.x > hx * 0.3:
				v.co.x -= depth
			elif v.co.x < -hx * 0.3:
				v.co.x += depth


def add_deck_line_step(bm, hx, hy, hz, height_frac=0.08, z_frac=(0.6, 0.95)):
	"""Raises a secondary volume across part of the top deck's length
	(rear portion by default, clear of the spine ridge's own Z position)
	- real mount real estate per the design doc. z_frac is the raised
	region's Z extent as a fraction of hull length."""
	z0 = -hz + hz * 2.0 * z_frac[0]
	z1 = -hz + hz * 2.0 * z_frac[1]
	for plane_y in (z0, z1):
		bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
			plane_co=(0, plane_y, 0), plane_no=(0, 1, 0), clear_inner=False, clear_outer=False)
	raise_h = hy * height_frac
	for v in bm.verts:
		if z0 - 1e-4 <= v.co.y <= z1 + 1e-4 and v.co.z > hy * 0.3:
			v.co.z += raise_h


def add_panel_line_groove(bm, hx, hy, hz, R, frac, depth_frac=0.015, width_frac=0.025, axis='z'):
	"""A single shallow inset seam line running across the top deck at a
	proportional position along `axis` - real geometry via bisect+push-in,
	not a texture, matching the design doc's 'inset face along a line,
	push resulting strip in along normal.' depth_frac/width_frac are
	fractions of R (not hull length) per the doc's 'depth ~1-2% R, width
	~2-3% R' - grooves stay a consistently fine detail-scale feature
	regardless of how long the hull is.

	axis='z' (default): a band running across the width at a Z position
	  (0=nose, 1=tail) - the original chordwise deck-line use.
	axis='x': a SPANWISE band running along the length at an X position
	  (0=centreline, 1=wingtip) - implies real spars/ribs on a swept
	  wing planform (flying_wing_hull) instead of fuselage panel lines."""
	if axis == 'z':
		center = -hz + hz * 2.0 * frac
		band_half = R * width_frac * 0.5
		lo, hi = center - band_half, center + band_half
		for plane_pos in (lo, hi):
			bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
				plane_co=(0, plane_pos, 0), plane_no=(0, 1, 0), clear_inner=False, clear_outer=False)
		push_in = R * depth_frac
		for v in bm.verts:
			if lo - 1e-4 <= v.co.y <= hi + 1e-4 and v.co.z > hy * 0.3:
				v.co.z -= push_in
	else:
		center = -hx + hx * 2.0 * frac
		band_half = R * width_frac * 0.5
		lo, hi = center - band_half, center + band_half
		for plane_pos in (lo, hi):
			bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
				plane_co=(plane_pos, 0, 0), plane_no=(1, 0, 0), clear_inner=False, clear_outer=False)
		push_in = R * depth_frac
		for v in bm.verts:
			if lo - 1e-4 <= v.co.x <= hi + 1e-4 and v.co.z > hy * 0.3:
				v.co.z -= push_in


def add_speed_line_chamfer(bm, hx, hy, hz, angle_deg=35.0, z_frac_center=0.4, depth_frac=0.06, band_frac=0.1):
	"""Tier 3 bespoke feature, interceptor_hull only: a single diagonal
	chamfer facet cut across each flank, rising toward the tail - a real
	styling cut (not a rounded edge-smooth) evoking the diagonal speed
	lines on a fast jet or sports car, distinct from every other hull's
	shared tiered-bevel vocabulary. Same bisect+selective-vertex-shift
	technique as add_waist_inset above, except the cutting plane is tilted
	between the length and height axes instead of purely axis-aligned, so
	the resulting cut line runs diagonally across the flat flank face."""
	angle = math.radians(angle_deg)
	plane_no_v = mathutils.Vector((0.0, math.sin(angle), math.cos(angle))).normalized()
	base_point = mathutils.Vector((0.0, -hz + 2.0 * hz * z_frac_center, 0.0))
	band_half = hz * band_frac
	for sign in (-1.0, 1.0):
		plane_co = base_point + plane_no_v * (sign * band_half)
		bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
			plane_co=(plane_co.x, plane_co.y, plane_co.z), plane_no=(plane_no_v.x, plane_no_v.y, plane_no_v.z),
			clear_inner=False, clear_outer=False)
	depth = hx * depth_frac
	for v in bm.verts:
		d = (v.co - base_point).dot(plane_no_v)
		if -band_half - 1e-4 <= d <= band_half + 1e-4:
			if v.co.x > hx * 0.3:
				v.co.x -= depth
			elif v.co.x < -hx * 0.3:
				v.co.x += depth


def taper_profile(t, nose_frac, front_flare, rear_flare, nose_region=0.35, rear_region=0.8):
	"""Non-linear width-scale multiplier along hull length: t=0 at the nose
	(front, -Z) .. t=1 at the tail (rear, +Z). Narrows aggressively across
	just the front `nose_region` fraction of length (the design doc's
	'more aggressive near nose'), holds steady across the mid-hull waist,
	then eases into the rear flare over the tail's last stretch."""
	region = max(nose_frac, nose_region)
	if t < region:
		tip = front_flare * (1.0 - nose_frac) if nose_frac > 0.01 else front_flare
		return tip + (1.0 - tip) * eased_taper(t / max(region, 0.001))
	if t < rear_region:
		return 1.0
	return 1.0 + (rear_flare - 1.0) * eased_taper((t - rear_region) / (1.0 - rear_region))


# ---------------------------------------------------------------------------
# Greeble primitives - all operate on a caller-supplied bm using GODOT-space
# center/size, so calling code never has to think about the Blender swap.
# ---------------------------------------------------------------------------

def add_box(bm, center, size, rot_axis=None, rot_angle=0.0, bevel=0.0):
	ret = bmesh.ops.create_cube(bm, size=1.0)
	verts = ret['verts']
	bmesh.ops.scale(bm, verts=verts, vec=GS(*size))
	if rot_axis and rot_angle:
		bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=rot_matrix(rot_axis, rot_angle))
	bmesh.ops.translate(bm, verts=verts, vec=GV(*center))
	if bevel > 0.0:
		edges = [e for e in bm.edges if all(v in verts for v in e.verts)]
		if edges:
			bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=1, affect='EDGES')
	return verts


def add_cyl_y(bm, center, radius, height, segments=12, radius2=None):
	"""Vertical (Godot-Y-axis) cylinder/cone centered at `center`."""
	r2 = radius2 if radius2 is not None else radius
	ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
		radius1=radius, radius2=r2, depth=height)
	bmesh.ops.translate(bm, verts=ret['verts'], vec=GV(*center))
	return ret['verts']


def add_cyl_axis(bm, center, radius, length, godot_axis, segments=10, radius2=None):
	"""Cylinder lying along a horizontal Godot axis ('x' or 'z'), centered at `center`."""
	r2 = radius2 if radius2 is not None else radius
	ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
		radius1=radius, radius2=r2, depth=length)
	bmesh.ops.rotate(bm, verts=ret['verts'], cent=(0, 0, 0), matrix=rot_matrix(godot_axis, math.pi / 2.0))
	bmesh.ops.translate(bm, verts=ret['verts'], vec=GV(*center))
	return ret['verts']


def add_ring(bm, center, major_radius, minor_radius, major_segments=20, minor_segments=8):
	"""A horizontal torus/ring (Godot-Y-axis normal), swept around `center`."""
	before = set(bm.verts)
	ret = bmesh.ops.create_circle(bm, cap_ends=True, radius=minor_radius, segments=minor_segments)
	bmesh.ops.rotate(bm, verts=ret['verts'], cent=(0, 0, 0), matrix=mathutils.Matrix.Rotation(math.pi / 2.0, 3, 'Y'))
	bmesh.ops.translate(bm, verts=ret['verts'], vec=(major_radius, 0, 0))
	geom = list(ret['verts'])
	geom += [e for v in ret['verts'] for e in v.link_edges]
	geom += [f for v in ret['verts'] for f in v.link_faces]
	geom = list(set(geom))
	bmesh.ops.spin(bm, geom=geom, cent=(0, 0, 0), axis=(0, 0, 1),
		angle=math.radians(360), steps=major_segments, use_duplicate=False)
	new_verts = [v for v in bm.verts if v not in before]
	if center != (0, 0, 0):
		bmesh.ops.translate(bm, verts=new_verts, vec=GV(*center))
	return new_verts


# ---------------------------------------------------------------------------
# Greeble "kits" - reusable clusters of detail merged straight into a bm.
# ---------------------------------------------------------------------------

def greeble_rivet_row(bm, start, end, count, radius=0.025, height=0.02, axis='y'):
	for i in range(count):
		t = (i / (count - 1)) if count > 1 else 0.5
		c = tuple(start[k] + (end[k] - start[k]) * t for k in range(3))
		if axis == 'y':
			add_cyl_y(bm, c, radius, height, segments=7)
		else:
			add_cyl_axis(bm, c, radius, height, axis, segments=7)


def greeble_vent(bm, center, size, slats=4):
	add_box(bm, center, size, bevel=0.01)
	slat_w = size[0] / (slats * 2.2)
	for i in range(slats):
		t = (i + 0.5) / slats - 0.5
		c = (center[0] + t * size[0] * 0.8, center[1], center[2])
		add_box(bm, c, (slat_w, size[1] * 1.2, size[2] * 0.85))


def greeble_louver_panel(bm, hy, center, size, R, slats=4, recess_frac=0.05):
	"""Engine-deck louvers as real recessed geometry (HULL_MASSING_SPEC.md)
	instead of a proud greeble_vent box: crossed bisect bands (the same
	bisect+shift technique as add_panel_line_groove, but bounded in BOTH
	length AND width instead of running the full hull width) carve a
	rectangular pocket, the interior is pushed down, then angled slat
	add_boxes sit at the recessed floor depth. Must be called on the
	silhouette BEFORE the tier-1 bevel pass (like every other bisect+shift
	feature), not from a hull's `greebles` callback which only runs after.
	center/size are Godot-space, matching greeble_vent's own signature.
	`hy` gates the vertical shift to the upper hull only (same `v.co.z >
	hy*0.3` convention add_deck_line_step/add_panel_line_groove already use),
	so this can safely be called without accidentally denting the belly."""
	cx, cy, cz = GV(*center)
	half_w, half_l = size[0] / 2.0, size[2] / 2.0
	x0, x1 = cx - half_w, cx + half_w
	y0, y1 = cy - half_l, cy + half_l
	for plane_x in (x0, x1):
		bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
			plane_co=(plane_x, 0, 0), plane_no=(1, 0, 0), clear_inner=False, clear_outer=False)
	for plane_y in (y0, y1):
		bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
			plane_co=(0, plane_y, 0), plane_no=(0, 1, 0), clear_inner=False, clear_outer=False)
	recess = R * recess_frac
	for v in bm.verts:
		if x0 - 1e-4 <= v.co.x <= x1 + 1e-4 and y0 - 1e-4 <= v.co.y <= y1 + 1e-4 and v.co.z > hy * 0.3:
			v.co.z -= recess

	slat_w = size[0] / (slats * 2.2)
	floor_y = center[1] - recess
	for i in range(slats):
		t = (i + 0.5) / slats - 0.5
		c = (center[0] + t * size[0] * 0.8, floor_y, center[2])
		add_box(bm, c, (slat_w, size[1] * 0.5, size[2] * 0.85), rot_axis='x', rot_angle=0.3)


def _bisect_z_band(bm, z0, z1):
	for plane_z in (z0, z1):
		bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
			plane_co=(0, 0, plane_z), plane_no=(0, 0, 1), clear_inner=False, clear_outer=False)


def _bisect_x_band_and_recess(bm, x0, x1, z0, z1, recess, wall_gate):
	for plane_x in (x0, x1):
		bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
			plane_co=(plane_x, 0, 0), plane_no=(1, 0, 0), clear_inner=False, clear_outer=False)
	for v in bm.verts:
		if x0 - 1e-4 <= v.co.x <= x1 + 1e-4 and z0 - 1e-4 <= v.co.z <= z1 + 1e-4 and v.co.y > wall_gate:
			v.co.y -= recess


def add_recessed_embrasure(bm, center, size, R, depth_frac=0.06, taper_width_frac=0.55, wall_gate=0.0):
	"""A recessed, splayed firing embrasure cut into an outward-facing
	(+Z) wall - the vertical-wall counterpart to greeble_louver_panel's
	horizontal deck pocket. Same bisect+shift technique (technique #2),
	just bounding width/height instead of width/depth, and pushing the
	interior INWARD along Z instead of down along Y. Two nested cuts (an
	outer wide pocket, then a narrower inner slit pushed further in)
	approximate a real casemate opening that narrows toward the firing
	position - "splayed wider on the outside" - without needing a
	continuous taper loft. Must be called on the silhouette BEFORE the
	tier-1 bevel pass, like every other bisect+shift feature.
	center/size (width, height) are Godot-space, matching greeble_vent's
	signature. `wall_gate` restricts the inward push to verts on this
	wall's outward side (an absolute Godot-Z threshold) so the cut
	doesn't also carve into a wall on the opposite side of the hull.
	For MULTIPLE embrasures sharing the same height band, use
	add_recessed_embrasure_row instead - calling this once per slit at
	an identical height re-bisects the same Z planes N times, which was
	found (via direct bmesh inspection on a 5-slit wall) to produce
	hundreds of degenerate zero-area faces."""
	cx, cy, cz = GV(*center)
	half_w, half_h = size[0] / 2.0, size[1] / 2.0
	_bisect_z_band(bm, cz - half_h, cz + half_h)
	_bisect_z_band(bm, cz - half_h * taper_width_frac, cz + half_h * taper_width_frac)
	_bisect_x_band_and_recess(bm, cx - half_w, cx + half_w, cz - half_h, cz + half_h,
		R * depth_frac, wall_gate)
	hw2, hh2 = half_w * taper_width_frac, half_h * taper_width_frac
	_bisect_x_band_and_recess(bm, cx - hw2, cx + hw2, cz - hh2, cz + hh2,
		R * depth_frac * 1.8, wall_gate)


def add_recessed_embrasure_row(bm, x_centers, y_level, size, R, depth_frac=0.06,
		taper_width_frac=0.55, wall_gate=0.0):
	"""Multiple embrasures at different X positions sharing one height
	band (build_wall_hull's arrow-slit row) - shares the height-bounding
	Z bisect across the whole row (cut once) instead of add_recessed_
	embrasure's per-call Z bisect (which would re-cut the identical
	location once per slit). Each slit's width (X) bisect still happens
	per-slit since those positions are always distinct, never coincident.
	x_centers/y_level/size are Godot-space, same convention as
	add_recessed_embrasure."""
	half_h = size[1] / 2.0
	half_h2 = half_h * taper_width_frac
	z0, z1 = y_level - half_h, y_level + half_h
	z0i, z1i = y_level - half_h2, y_level + half_h2
	_bisect_z_band(bm, z0, z1)
	_bisect_z_band(bm, z0i, z1i)
	half_w = size[0] / 2.0
	half_w2 = half_w * taper_width_frac
	for cx in x_centers:
		_bisect_x_band_and_recess(bm, cx - half_w, cx + half_w, z0, z1, R * depth_frac, wall_gate)
		_bisect_x_band_and_recess(bm, cx - half_w2, cx + half_w2, z0i, z1i,
			R * depth_frac * 1.8, wall_gate)


def greeble_headlight_pair(bm, hx, y_level, front_z, radius=0.09):
	for side in (-1, 1):
		add_cyl_axis(bm, (side * hx * 0.55, y_level, front_z), radius, 0.09, 'z', segments=10)


def greeble_exhaust_stack(bm, center, radius=0.08, height=0.35):
	add_cyl_y(bm, center, radius, height, segments=10)
	add_cyl_y(bm, (center[0], center[1] + height * 0.5 + 0.02, center[2]), radius * 1.2, 0.04, segments=10)


def greeble_antenna(bm, base, height=0.55, radius=0.018):
	add_cyl_y(bm, (base[0], base[1] + height / 2.0, base[2]), radius, height, segments=6)
	add_cyl_y(bm, (base[0], base[1], base[2]), radius * 2.2, 0.03, segments=8)


def greeble_hatch(bm, center, size, rim=0.03):
	add_box(bm, center, size, bevel=0.008)
	add_box(bm, (center[0], center[1] + size[1] * 0.5 + 0.008, center[2]),
		(size[0] - rim, 0.015, size[2] - rim))


def greeble_faired_canopy(bm, center, size, segments=12, rings=8):
	"""A real cockpit/canopy VOLUME - a squashed uvsphere fused directly
	into the hull's own bmesh (technique #1, same "second convex-hull-like
	shell left interpenetrating" approach as build_afv_hull's tub/upper
	split), replacing a proud add_box canopy bump. `size` is a (x, y, z)
	half-extent tuple, keyed the same way build_dome's squash param is -
	each axis independently, so a caller can clamp height to a fraction
	of hy and let width/length follow hx/hz (per HULL_MASSING_SPEC.md's
	interceptor_hull note: an unclamped squash ratio can invert under an
	extreme non-uniform hull_scale stretch and read as a bubble)."""
	ret = bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=1.0)
	bmesh.ops.scale(bm, verts=ret['verts'], vec=GS(size[0], size[1], size[2]))
	bmesh.ops.translate(bm, verts=ret['verts'], vec=GV(*center))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


def greeble_corner_gusset(bm, x_sign, hx, hy, z_pos, size=(0.32, 0.28, 0.45)):
	add_box(bm, (x_sign * (hx - size[0] * 0.35), -hy * 0.35, z_pos), size, bevel=0.02)


def greeble_toolbox(bm, center, size=(0.5, 0.28, 0.32)):
	add_box(bm, center, size, bevel=0.015)
	add_box(bm, (center[0], center[1] + size[1] * 0.5, center[2]), (size[0] * 0.9, 0.03, size[2] * 0.9))


def greeble_spotlight(bm, center, radius=0.11):
	add_cyl_axis(bm, center, radius, 0.14, 'z', segments=10)
	add_box(bm, (center[0], center[1] - radius * 0.9, center[2] - 0.05), (0.05, 0.16, 0.05))


def greeble_bolt_ring(bm, center, radius, count=8, bolt_radius=0.025, axis='y'):
	for i in range(count):
		angle = i * (2.0 * math.pi / count)
		if axis == 'y':
			pos = (center[0] + math.cos(angle) * radius, center[1], center[2] + math.sin(angle) * radius)
			add_cyl_y(bm, pos, bolt_radius, 0.02, segments=6)
		else:
			pos = (center[0] + math.cos(angle) * radius, center[1] + math.sin(angle) * radius, center[2])
			add_cyl_axis(bm, pos, bolt_radius, 0.02, 'z', segments=6)


def greeble_cooling_fins(bm, center, count, span, radius, thickness=0.012, axis='z'):
	for i in range(count):
		t = (i / (count - 1)) if count > 1 else 0.5
		off = (t - 0.5) * span
		if axis == 'z':
			pos = (center[0], center[1], center[2] + off)
			add_box(bm, pos, (radius * 2.1, radius * 2.1, thickness))
		else:
			pos = (center[0], center[1] + off, center[2])
			add_box(bm, pos, (radius * 2.1, thickness, radius * 2.1))


# ---------------------------------------------------------------------------
# Part builders - small reusable kit pieces referenced by visual_builder.gd.
# Cylinders/cones are authored with their length along Godot Z (forward),
# matching how they're mounted on weapons (barrels point along local -Z).
# ---------------------------------------------------------------------------

def build_barrel(name, length=1.0, radius=0.1, muzzle_radius=None, segments=16,
		fins=0, color=(0.12, 0.12, 0.13), steps=3):
	"""Barrel along Godot +Y, base at origin (y=0..length) - matches the
	existing runtime convention (Godot's own CylinderMesh default axis),
	so weapon assembly code keeps applying its existing PI/2 X rotation to
	point barrels forward, and existing caliber(X)/length(Y) tweak scaling
	on this child index keeps working unchanged.

	Section 3 of the design doc: modules compute their OWN reference
	dimension R from their own bounding box (here, diameter - a barrel's
	long axis is exactly the one caliber/length tweaks stretch, so it's
	excluded the same way hull length is). The body is now a stepped-
	diameter loft (discrete radius steps from breech to muzzle) instead
	of one smooth cone - reads as a real machined part, not a plain rod."""
	bm = bmesh.new()
	r2 = muzzle_radius if muzzle_radius is not None else radius
	R = 2.0 * max(radius, r2)
	step_len = length / steps
	all_verts = []
	for i in range(steps):
		t = i / float(max(steps - 1, 1))
		r = radius + (r2 - radius) * eased_taper(t)
		all_verts += add_cyl_y(bm, (0, step_len * (i + 0.5), 0), r, step_len, segments=segments)
	# Muzzle brake ring fused on the tip
	all_verts += add_cyl_y(bm, (0, length * 0.94, 0), r2 * 1.35, length * 0.1, segments=segments)
	bmesh.ops.remove_doubles(bm, verts=all_verts, dist=0.001)
	bevel_sharp_edges(bm, list(bm.verts), R, tier=2)
	if fins > 0:
		greeble_cooling_fins(bm, (0, length * 0.35, 0), fins, length * 0.45, radius * 1.15, axis='y')
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.85, roughness=0.3)
	return obj


def build_cylinder_part(name, radius=0.15, height=0.15, segments=20, bevel=True,
		bolts=True, color=(0.35, 0.35, 0.38)):
	"""Squat drum along Godot Y (up), base at origin - ammo drums, canisters,
	fuel tanks, turret base plates, muzzle brakes. Turret bodies get a
	tier-1 bevel per Section 3 (panel-line insets are Tier 2, deferred)."""
	bm = bmesh.new()
	verts = add_cyl_y(bm, (0, height / 2.0, 0), radius, height, segments=segments)
	if bevel:
		bevel_sharp_edges(bm, verts, radius * 2.0, tier=1, pct=0.06)
	if bolts:
		greeble_bolt_ring(bm, (0, height * 0.9, 0), radius * 0.82, count=max(6, segments // 2), axis='y')
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color)
	return obj


def build_dome(name, radius=0.15, squash=0.6, segments=16, rings=10,
		color=(0.85, 0.85, 0.85)):
	bm = bmesh.new()
	ret = bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
	bmesh.ops.scale(bm, verts=ret['verts'], vec=GS(1.0, squash, 1.0))
	bmesh.ops.translate(bm, verts=ret['verts'], vec=GV(0, radius * squash * 0.15, 0))
	# Base collar ring
	add_cyl_y(bm, (0, 0.02, 0), radius * 1.05, 0.04, segments=segments)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.1, roughness=0.15)
	return obj


def build_missile_body(name, length=1.0, radius=0.08, nose_frac=0.25, segments=14,
		fins=4, color=(0.9, 0.9, 0.9)):
	"""Missile body + nose cone along Godot +Y, base (tail) at origin -
	matches the existing runtime PI/2 X rotation convention."""
	bm = bmesh.new()
	body_len = length * (1.0 - nose_frac)
	nose_len = length * nose_frac
	add_cyl_y(bm, (0, body_len / 2.0, 0), radius, body_len, segments=segments)
	add_cyl_y(bm, (0, body_len + nose_len / 2.0, 0), radius, nose_len, segments=segments, radius2=0.0)
	# Rear stabilizer fins, fanned around the tail end
	fin_len = radius * 2.4
	for i in range(fins):
		angle = i * (2.0 * math.pi / fins)
		add_box(bm, (0, radius * 0.5, 0),
			(0.012, radius * 1.6, fin_len), rot_axis='y', rot_angle=angle)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.3, roughness=0.4)
	return obj


def build_pintle_mount(name, width=0.34, height=0.22, depth=0.22, wall=0.045,
		color=(0.2, 0.2, 0.22)):
	"""Small U-shaped yoke bracket: base plate + two side arms. Mounting
	hardware gets the LIGHTEST touch of anything in the roster per
	Section 3 - tier-3 bevel only, no boolean greeble beyond the
	existing bolt ring."""
	bm = bmesh.new()
	mount_bevel, _ = tiered_bevel_width(hull_reference_dim(width, height), tier=3)
	add_box(bm, (0, wall / 2.0, 0), (width, wall, depth), bevel=mount_bevel)
	for side in (-1, 1):
		add_box(bm, (side * (width / 2.0 - wall / 2.0), height / 2.0, 0), (wall, height, depth), bevel=mount_bevel)
	greeble_bolt_ring(bm, (0, wall * 0.5, 0), width * 0.32, count=4, axis='y')
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.6, roughness=0.5)
	return obj


def build_box_part(name, size=(0.5, 0.3, 0.4), bevel_amt=None, bolts=True,
		color=(0.3, 0.3, 0.33)):
	"""Beveled box - turret bases, launcher frames, weapon housings. A
	turret body gets a tier-1 bevel by default (panel-line insets are
	Tier 2, deferred); pass bevel_amt explicitly to override."""
	bm = bmesh.new()
	if bevel_amt is None:
		bevel_amt, _ = tiered_bevel_width(hull_reference_dim(size[0], size[1]), tier=1, pct=0.06)
	add_box(bm, (0, size[1] / 2.0, 0), size, bevel=bevel_amt)
	if bolts:
		for x_sign in (-1, 1):
			for z_sign in (-1, 1):
				pos = (x_sign * size[0] * 0.4, size[1] * 0.92, z_sign * size[2] * 0.4)
				add_cyl_y(bm, pos, 0.02, 0.015, segments=6)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color)
	return obj


def build_howitzer_breech(name, width=0.9, height=0.5, depth=0.55, color=(0.28, 0.28, 0.3)):
	"""Chunky breech block with twin recoil-buffer cylinders on top."""
	bm = bmesh.new()
	add_box(bm, (0, height / 2.0, 0), (width, height, depth), bevel=0.03)
	for side in (-1, 1):
		add_cyl_axis(bm, (side * width * 0.28, height * 0.85, -depth * 0.05), 0.09, depth * 1.3, 'z', segments=12)
	greeble_bolt_ring(bm, (0, height * 0.95, depth * 0.3), width * 0.3, count=6, axis='y')
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.6, roughness=0.5)
	return obj


def build_basic_cannon_solid(name, color=(0.28, 0.28, 0.32)):
	"""Simplified 37 mm Gun M3 on an open pintle mount (single solid mesh)."""
	bm = bmesh.new()

	# 1. Open Pintle Base Socket & Yoke Carriage
	add_box(bm, (0, 0.04, 0), (0.36, 0.08, 0.32), bevel=0.015)
	for side in (-1, 1):
		add_box(bm, (side * 0.16, 0.2, 0), (0.05, 0.24, 0.22), bevel=0.015)
	greeble_bolt_ring(bm, (0, 0.04, 0), 0.14, count=6, axis='y')

	# 2. Side Elevation Handwheel (left yoke)
	add_cyl_axis(bm, (-0.2, 0.22, 0), 0.07, 0.03, 'x', segments=12)

	# 3. Vertical Sliding-Block Breech Housing (at trunnion height Y = 0.22)
	trunnion_y = 0.22
	add_box(bm, (0, trunnion_y, 0.05), (0.2, 0.22, 0.36), bevel=0.02)
	greeble_bolt_ring(bm, (0, trunnion_y + 0.1, 0.1), 0.06, count=4, axis='y')

	# 4. Parallel Under-Barrel Hydraulic Recoil Cylinder Buffer
	recoil_len = 0.45
	add_cyl_axis(bm, (0, trunnion_y - 0.07, -recoil_len / 2.0 + 0.05), 0.05, recoil_len, 'z', segments=16)

	# 5. Slender 37mm L/56 Main Gun Barrel (Extending forward along -Z)
	barrel_len = 1.25
	add_cyl_axis(bm, (0, trunnion_y, -barrel_len / 2.0 - 0.05), 0.06, barrel_len, 'z', segments=20)
	add_cyl_axis(bm, (0, trunnion_y, -barrel_len - 0.05), 0.07, 0.06, 'z', segments=20)

	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.65, roughness=0.4)
	return obj


def build_rotary_jacket(name, radius=0.22, height=0.5, barrels=6, color=(0.2, 0.2, 0.21)):
	"""Cooling jacket ring around a rotary-cannon barrel cluster, along Godot +Y."""
	bm = bmesh.new()
	add_cyl_y(bm, (0, height * 0.5, 0), radius, height * 0.3, segments=20)
	add_cyl_y(bm, (0, height * 0.95, 0), radius * 1.08, height * 0.12, segments=20)
	greeble_cooling_fins(bm, (0, height * 0.55, 0), 5, height * 0.5, radius, axis='y')
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.75, roughness=0.35)
	return obj


def build_rail_array(name, length=1.6, gap=0.16, rail_h=0.12, color=(0.15, 0.15, 0.15)):
	"""Twin magnetic rail assembly with connecting spars, for the railgun."""
	bm = bmesh.new()
	for side in (-1, 1):
		add_box(bm, (side * gap, rail_h / 2.0, length / 2.0), (0.06, rail_h, length), bevel=0.01)
	for i in range(4):
		t = (i + 0.5) / 4.0
		add_box(bm, (0, rail_h * 0.5, length * t), (gap * 2.0 + 0.08, 0.03, 0.03))
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.7, roughness=0.25)
	return obj


def build_flak_breech(name, width=0.5, height=0.32, depth=0.4, color=(0.18, 0.18, 0.18)):
	bm = bmesh.new()
	add_box(bm, (0, height / 2.0, 0), (width, height, depth), bevel=0.02)
	greeble_bolt_ring(bm, (0, height * 0.9, 0), width * 0.32, count=6, axis='y')
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.65, roughness=0.4)
	return obj


def build_wheel(name, radius=0.45, width=0.35, spokes=6, color=(0.08, 0.08, 0.08), groove_depth=0.07):
	"""Wheel + hub, built Y-vertical (radius in X/Z, thickness along Y) -
	matches the existing runtime convention where locomotion code applies
	rotation.z = PI/2 at runtime to stand it up with the axle along X.

	R (module's own reference dimension, per Section 3) is the tire
	diameter - width is the axle axis, excluded the same way a barrel's
	length is. The tire is now 3 stacked segments so a real inset groove
	ring sits at the tire/rim boundary, and its outer edges get a
	stronger tier-1 bevel; the hub gets a radial lug-nut bolt ring."""
	bm = bmesh.new()
	R = radius * 2.0
	seg_w = width / 3.0
	tire_verts = []
	tire_verts += add_cyl_y(bm, (0, seg_w * 0.5, 0), radius, seg_w, segments=22)
	tire_verts += add_cyl_y(bm, (0, seg_w * 1.5, 0), radius * (1.0 - groove_depth), seg_w, segments=22)
	tire_verts += add_cyl_y(bm, (0, seg_w * 2.5, 0), radius, seg_w, segments=22)
	bmesh.ops.remove_doubles(bm, verts=tire_verts, dist=0.001)
	bevel_sharp_edges(bm, list(bm.verts), R, tier=1, pct=0.05)

	add_cyl_y(bm, (0, width * 0.53, 0), radius * 0.42, width * 1.06, segments=16)
	greeble_bolt_ring(bm, (0, width * 1.0, 0), radius * 0.22, count=6, bolt_radius=radius * 0.035, axis='y')
	for i in range(spokes):
		angle = i * (2.0 * math.pi / spokes)
		pos = (math.cos(angle) * radius * 0.55, width / 2.0, math.sin(angle) * radius * 0.55)
		add_box(bm, pos, (radius * 0.5, width * 0.9, 0.05), rot_axis='y', rot_angle=angle)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.2, roughness=0.7)
	return obj


def build_leg_segment(name, length=0.5, radius_top=0.12, radius_bottom=0.08, color=(0.3, 0.3, 0.32)):
	"""Armored leg segment along Godot Y, base(wide) at origin. The
	stepped-diameter taper per segment is already structurally present
	via radius_top/radius_bottom (and stacking two of these - thigh then
	shin - narrows the whole leg toward the foot); this pass adds the
	joint housing the doc asks for - a separate boolean-added collar at
	the wide (hip) end, individually beveled, rather than a smooth taper
	reading as one uninterrupted cone."""
	bm = bmesh.new()
	R = 2.0 * max(radius_top, radius_bottom)
	seg_verts = add_cyl_y(bm, (0, length / 2.0, 0), radius_top, length, segments=12, radius2=radius_bottom)
	bevel_sharp_edges(bm, seg_verts, R, tier=2)
	housing_h = length * 0.12
	add_cyl_y(bm, (0, housing_h * 0.5, 0), radius_top * 1.18, housing_h, segments=12, radius2=radius_top * 1.1)
	greeble_bolt_ring(bm, (0, length * 0.05, 0), radius_top * 0.85, count=6, axis='y')
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.55, roughness=0.4)
	return obj


def build_hover_ring(name, major_radius=0.5, minor_radius=0.1, color=(0.2, 0.6, 0.9)):
	bm = bmesh.new()
	add_ring(bm, (0, 0, 0), major_radius, minor_radius, major_segments=24, minor_segments=8)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.4, roughness=0.3)
	return obj


def build_tread_plate(name, width=1.0, length=1.0, links=6, color=(0.16, 0.16, 0.17)):
	"""Tracked-tread belt block with raised link ridges along its length -
	length is the axis the belt repeats/tiles along (the tread's own
	analogue of a hull's stretched axis), so R excludes it the same way."""
	bm = bmesh.new()
	R = hull_reference_dim(width, 0.3)
	base_bevel, _ = tiered_bevel_width(R, tier=2)
	ridge_bevel, _ = tiered_bevel_width(R, tier=3)
	add_box(bm, (0, 0.15, 0), (width, 0.3, length), bevel=base_bevel)
	for i in range(links):
		t = (i + 0.5) / links - 0.5
		add_box(bm, (0, 0.31, t * length), (width * 1.02, 0.04, length / links * 0.55), bevel=ridge_bevel)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.4, roughness=0.6)
	return obj


def build_screw_drum(name, length=1.6, shaft_radius=0.13, fin_reach=0.16, turns=3.0,
		color=(0.35, 0.32, 0.28)):
	"""Helical auger/screw drum for amphibious screw-drive locomotion (real
	historical screw-propelled vehicles - Soviet ZIL screw-drive trucks, the
	Fordson 'Snow Devil') - a tapered-cap core shaft with a continuous
	helical fin approximated by many short radial blade segments advancing
	in both angle and length together, along Godot +Z (matches the
	runtime mounting convention: the drum's own length lies parallel to the
	vehicle's travel direction, one drum per side)."""
	bm = bmesh.new()
	add_cyl_axis(bm, (0, 0, 0), shaft_radius, length, 'z', segments=14)
	add_cyl_axis(bm, (0, 0, -length * 0.5 - length * 0.05), 0.02, length * 0.1, 'z', segments=14, radius2=shaft_radius)
	add_cyl_axis(bm, (0, 0, length * 0.5 + length * 0.05), shaft_radius, length * 0.1, 'z', segments=14, radius2=0.02)

	segments = 40
	r_mid = shaft_radius + fin_reach / 2.0
	for i in range(segments):
		t = i / float(segments)
		z = -length * 0.5 + length * 0.1 + t * length * 0.8
		angle = t * turns * 2.0 * math.pi
		pos = (math.cos(angle) * r_mid, math.sin(angle) * r_mid, z)
		add_box(bm, pos, (fin_reach, 0.045, (length * 0.8 / segments) * 2.4), rot_axis='z', rot_angle=angle)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.65, roughness=0.55)
	return obj


def build_accessory(name, kind, color, **kwargs):
	"""Standalone small greeble accessories - also usable directly as weapon
	sub-parts (headlight cluster, exhaust, antenna, hatch, vent, toolbox)."""
	bm = bmesh.new()
	if kind == "exhaust":
		greeble_exhaust_stack(bm, (0, kwargs.get("height", 0.35) / 2.0, 0),
			radius=kwargs.get("radius", 0.08), height=kwargs.get("height", 0.35))
	elif kind == "antenna":
		greeble_antenna(bm, (0, 0, 0), height=kwargs.get("height", 0.55), radius=kwargs.get("radius", 0.018))
	elif kind == "vent":
		greeble_vent(bm, (0, kwargs.get("size", (0.4, 0.1, 0.25))[1] / 2.0, 0), kwargs.get("size", (0.4, 0.1, 0.25)))
	elif kind == "hatch":
		greeble_hatch(bm, (0, kwargs.get("size", (0.6, 0.06, 0.6))[1] / 2.0, 0), kwargs.get("size", (0.6, 0.06, 0.6)))
	elif kind == "toolbox":
		greeble_toolbox(bm, (0, kwargs.get("size", (0.5, 0.28, 0.32))[1] / 2.0, 0), kwargs.get("size", (0.5, 0.28, 0.32)))
	elif kind == "spotlight":
		greeble_spotlight(bm, (0, 0, 0), radius=kwargs.get("radius", 0.11))
	elif kind == "sensor_mast":
		add_cyl_y(bm, (0, kwargs.get("height", 1.0) / 2.0, 0), 0.05, kwargs.get("height", 1.0), segments=10, radius2=0.03)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=kwargs.get("metallic", 0.5), roughness=kwargs.get("roughness", 0.5))
	return obj


# ---------------------------------------------------------------------------
# Hull chassis builder - convex hull from a hand-placed "keel" point cloud,
# with fused-on greebles for detail. Robust (convex_hull is always
# manifold) and lets a handful of numeric parameters produce meaningfully
# different silhouettes.
# ---------------------------------------------------------------------------

def build_wedge_hull(name, size_x, size_y, size_z, nose_frac=0.0, spine_w=0.5, spine_h=1.1,
		rear_flare=0.9, front_flare=1.0, color=(0.55, 0.56, 0.58), greebles=None, taper_slices=7,
		nose_region=0.35, height_taper=0.0, bevel_pct=None, bevel_segments=None, bevel_angle_deg=20.0,
		waist_inset=0.0, waist_height_frac=0.5, deck_line=0.0, deck_line_z_frac=(0.6, 0.95),
		panel_line_fracs=None, speed_line_chamfer=False, armor_front_frac=0.4):
	"""height_taper (0..1): brings the deck down toward the nose too, for
	archetypes wanting a dart/wedge silhouette rather than just narrowing
	in width (interceptor_hull's "extreme taper in width AND height").
	bevel_pct/bevel_segments let each archetype sit at a different point
	within (or just outside) the tier-1 band - see Section 2 of the
	design doc: light reads narrow/subtle, heavy reads wide/chunky,
	interceptor reads narrow-and-sharp."""
	hx, hy, hz = size_x / 2.0, size_y / 2.0, size_z / 2.0
	R = hull_reference_dim(size_x, size_y)
	bm = bmesh.new()
	pts = []
	# Flat belly rectangle, unchanged/full-width - the taper below only
	# reshapes the top-deck silhouette, matching the original wedge look.
	pts += [(-hx, -hy, -hz), (hx, -hy, -hz), (-hx, -hy, hz), (hx, -hy, hz)]

	# Top deck: a real multi-slice loft along Z with the non-linear
	# (eased, nose-aggressive) taper curve instead of a single hard
	# front/rear cross-section jump.
	for i in range(taper_slices):
		t = i / float(taper_slices - 1)
		z = -hz + t * size_z
		scale = taper_profile(t, nose_frac, front_flare, rear_flare, nose_region=nose_region)
		deck_y = hy
		if height_taper > 0.0:
			h_scale = taper_profile(t, nose_frac, 1.0 - height_taper, 1.0, nose_region=nose_region)
			deck_y = hy * h_scale
		pts.append((-hx * scale, deck_y, z))
		pts.append((hx * scale, deck_y, z))
	if nose_frac > 0.01:
		nose_y = hy * 0.6 * (1.0 - height_taper) if height_taper > 0.0 else hy * 0.6
		pts.append((0.0, nose_y, -hz))

	pts += [(-hx * spine_w, hy * spine_h, hz * 0.1), (hx * spine_w, hy * spine_h, hz * 0.1)]
	pts += [(-hx * spine_w, hy * spine_h, -hz * 0.3), (hx * spine_w, hy * spine_h, -hz * 0.3)]

	verts = [bm.verts.new(GV(*p)) for p in pts]
	bmesh.ops.convex_hull(bm, input=verts)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

	# Tier 2: waist-inset / deck-line step - pure silhouette shaping,
	# applied AFTER the taper loft but BEFORE the bevel (which needs to
	# smooth their new cut edges too) and well before greebles, per the
	# design doc's mount-zone-aware ordering.
	if waist_inset > 0.0:
		add_waist_inset(bm, hx, hy, hz, depth_frac=waist_inset, height_frac=waist_height_frac)
	if deck_line > 0.0:
		add_deck_line_step(bm, hx, hy, hz, height_frac=deck_line, z_frac=deck_line_z_frac)
	if panel_line_fracs:
		for z_frac in panel_line_fracs:
			add_panel_line_groove(bm, hx, hy, hz, R, z_frac)
	if speed_line_chamfer:
		add_speed_line_chamfer(bm, hx, hy, hz)

	# Tier-1 bevel on the hull's own real structural edges (belly-to-deck
	# transition, nose tip, spine ridge, and any new waist/deck-line cuts)
	# - applied BEFORE greebles are fused on so it only ever touches the
	# primary silhouette. Uses the CURRENT vert set, not the original
	# convex-hull input, since bisect_plane above may have added verts.
	bevel_sharp_edges(bm, list(bm.verts), R, tier=1, angle_deg=bevel_angle_deg, pct=bevel_pct, segments=bevel_segments)

	# Hard-armor region: the nose taper's front arc, same frontal_armor_
	# predicate() technique as the AFV/ship hulls - a wedge hull's own
	# extreme nose taper (interceptor_hull's whole identity) makes the
	# front region naturally small relative to the long tapered top deck
	# and flat belly, so this stays a minority of area without needing a
	# smaller front_frac than the boxier AFV hulls.
	armor_frac = mark_armor_faces(bm, frontal_armor_predicate(hz, front_frac=armor_front_frac))
	print("  [armor split] %s: %.1f%% of surface area tagged hard-armor" % (name, armor_frac * 100.0))

	if greebles:
		greebles(bm, hx, hy, hz)

	obj = make_object_from_bmesh(bm, name)
	finalize_dual(obj, name, structural_color=color, armor_color=tuple(min(1.0, c * 1.15) for c in color))
	return obj


def build_afv_hull(name, size_x, size_y, size_z, nose_frac=0.0, tub_frac=0.55, upper_w=0.8,
		glacis_len_frac=0.3, fender_frac=1.0, fender_height_frac=0.12,
		spine_w=0.5, spine_h=1.1, color=(0.55, 0.56, 0.58), greebles=None,
		bevel_pct=None, bevel_segments=None, turret_ring=False, louver_panel=None,
		waist_inset=0.0, waist_height_frac=0.5, deck_line=0.0, deck_line_z_frac=(0.6, 0.95),
		panel_line_fracs=None, armor_front_frac=0.5):
	"""Ground AFV hull built from three genuinely separate, interpenetrating
	volumes instead of one tapered loft - a `bmesh.ops.convex_hull()` over a
	single point cloud can never produce a re-entrant silhouette (any point
	"inside" the hull of its neighbours is discarded), so a real lower-hull-
	tub-plus-separate-upper-glacis relationship is structurally impossible
	with build_wedge_hull's single-loft approach no matter how the taper/
	bevel parameters are tuned. This builder uses the same proven no-
	boolean technique build_tower_hull (per-tier convex hulls) and
	build_sponson_hull (fused blisters) already rely on: multiple convex
	hulls fused into the same bmesh, left deliberately interpenetrating
	(never welded - welding is where non-manifold geometry and bevel
	spikes come from). See HULL_MASSING_SPEC.md for the full design
	rationale and per-hull-type parameter reasoning.

	Volume A (tub): full-width slab, flat belly, light nose taper only -
	  the glacis slope lives entirely in Volume B, not here.
	Volume B (upper structure): narrower, a SEPARATE convex hull left
	  interpenetrating the tub. Its point cloud is just 4 distinct (Z, Y)
	  stations (nose-bottom / deck-front / deck-rear / rear-bottom), which
	  is enough for a convex hull to produce a real sloped-glacis ->
	  flat-deck -> vertical-rear cross-section with no lofting needed.
	Volume C (fenders): flat fused boxes filling the gap between the
	  tub's full width and the upper structure's narrower footprint - the
	  "over the tracks" read, and the best sponson-embed side-mount
	  real estate in the roster.

	tub_frac: tub roof height as a fraction of total height.
	upper_w: upper structure half-width as a fraction of hx.
	glacis_len_frac: how far back from the nose the glacis rises to meet
	  the flat deck - smaller = steeper/shorter glacis.
	fender_frac: fender outer edge as a fraction of hx (1.0 = flush with
	  the tub's own full width; set to upper_w or below to skip fenders).
	louver_panel: optional dict {"z_frac":f (position along length as a
	  multiple of hz, e.g. 0.72 = toward the rear), "width_frac"/"depth_frac"
	  (size as fractions of hx/hz), "slats":n, "recess_frac":f} - a
	  recessed engine-deck vent grate, applied to the silhouette before
	  the tier-1 bevel (see greeble_louver_panel)."""
	hx, hy, hz = size_x / 2.0, size_y / 2.0, size_z / 2.0
	R = hull_reference_dim(size_x, size_y)
	bm = bmesh.new()

	tub_top_y = -hy + 2.0 * hy * tub_frac

	# Volume A: lower hull tub.
	nose_x_scale = 1.0 - nose_frac * 0.3
	tub_pts = [
		(-hx, -hy, -hz), (hx, -hy, -hz), (-hx, -hy, hz), (hx, -hy, hz),
		(-hx * nose_x_scale, tub_top_y, -hz), (hx * nose_x_scale, tub_top_y, -hz),
		(-hx, tub_top_y, hz), (hx, tub_top_y, hz),
	]
	tub_verts = [bm.verts.new(GV(*p)) for p in tub_pts]
	bmesh.ops.convex_hull(bm, input=tub_verts)

	# Volume B: upper structure (glacis + casemate/engine deck) - a
	# separate convex hull, deliberately left interpenetrating Volume A.
	uw = hx * upper_w
	glacis_deck_z = -hz + size_z * glacis_len_frac
	upper_pts = [
		(-uw, tub_top_y, -hz), (uw, tub_top_y, -hz),
		(-uw, hy, glacis_deck_z), (uw, hy, glacis_deck_z),
		(-uw, hy, hz), (uw, hy, hz),
		(-uw, tub_top_y, hz), (uw, tub_top_y, hz),
	]
	upper_verts = [bm.verts.new(GV(*p)) for p in upper_pts]
	bmesh.ops.convex_hull(bm, input=upper_verts)

	# Spine ridge along the deck (mount rail), same convention as the
	# wedge-hull family's own spine.
	spine_pts = [
		(-hx * spine_w, hy * spine_h, hz * 0.1), (hx * spine_w, hy * spine_h, hz * 0.1),
		(-hx * spine_w, hy * spine_h, -hz * 0.3), (hx * spine_w, hy * spine_h, -hz * 0.3),
	]
	spine_verts = [bm.verts.new(GV(*p)) for p in spine_pts]
	bmesh.ops.convex_hull(bm, input=spine_verts)

	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

	# Volume C: flat fender/sponson shelves at the tub-roof seam.
	fender_outer = hx * fender_frac
	if fender_outer > uw + 0.02:
		fender_reach = fender_outer - uw
		fender_h = hy * fender_height_frac
		for side in (-1, 1):
			add_box(bm, (side * (uw + fender_reach * 0.5), tub_top_y + fender_h * 0.3, 0),
				(fender_reach, fender_h, hz * 1.98), bevel=0.02)

	if waist_inset > 0.0:
		add_waist_inset(bm, hx, hy, hz, depth_frac=waist_inset, height_frac=waist_height_frac)
	if deck_line > 0.0:
		add_deck_line_step(bm, hx, hy, hz, height_frac=deck_line, z_frac=deck_line_z_frac)
	if panel_line_fracs:
		for z_frac in panel_line_fracs:
			add_panel_line_groove(bm, hx, hy, hz, R, z_frac)
	if louver_panel:
		lv_center = (0, hy, hz * louver_panel.get("z_frac", 0.72))
		lv_size = (hx * louver_panel.get("width_frac", 0.85), 0.1, hz * louver_panel.get("depth_frac", 0.3))
		greeble_louver_panel(bm, hy, lv_center, lv_size, R,
			slats=louver_panel.get("slats", 4), recess_frac=louver_panel.get("recess_frac", 0.05))
	if turret_ring:
		add_cyl_y(bm, (0, hy * 1.05, hz * 0.1), min(hx, hz) * 0.32, hy * 0.12, segments=16)

	# Tier-1 bevel on the CURRENT vert set (picks up A/B/C's real seams -
	# tub roof, glacis crease, fender edges, spine, plus any bisect+shift
	# cuts above) - same dihedral-angle selection every other hull uses,
	# no hand-picked edge lists needed even with 3 fused volumes.
	bevel_sharp_edges(bm, list(bm.verts), R, tier=1, pct=bevel_pct, segments=bevel_segments)

	# Hard-armor region (2026-07-17, Approach A multi-region rollout - see
	# DECISIONS_NEEDED.md): the frontal glacis (Volume B's sloped nose-to-
	# deck face) plus the tub's own nose-taper corner facets - the real
	# highest-threat frontal arc on an AFV, per Chris's own "frontal
	# glacis, corner facets" framing. Everything else (top deck, sides/
	# fenders/side-skirts, rear, belly) stays structural/matte. Geometric
	# criterion, not hand-picked faces: any CURRENT face whose normal
	# faces sufficiently toward the nose (-Z in Godot terms, raw Blender
	# -Y - see godot_forward_component()) - this naturally stays a minority
	# of total area for an elongated hull without needing per-hull area
	# bookkeeping, and correctly excludes the turret ring (its cylinder
	# wall faces point radially outward in every direction, not just
	# forward) even though that geometry already exists in bm by this
	# point. Called BEFORE greebles so hatches/vents/antennae default to
	# structural fixtures, not armor plate.
	armor_frac = mark_armor_faces(bm, frontal_armor_predicate(hz, front_frac=armor_front_frac))
	print("  [armor split] %s: %.1f%% of surface area tagged hard-armor" % (name, armor_frac * 100.0))

	if greebles:
		greebles(bm, hx, hy, hz)

	obj = make_object_from_bmesh(bm, name)
	finalize_dual(obj, name, structural_color=color, armor_color=tuple(min(1.0, c * 1.15) for c in color))
	return obj


def build_bunker_hull(name, size_x, size_y, size_z, sides=8, taper=0.72,
		color=(0.45, 0.45, 0.4), greebles=None, embrasure=None, armor_threshold=0.2):
	"""Low static defensive bunker: tapered polygonal frustum + domed cap.
	The taper itself (top narrower than base) already gives the battered/
	inward-sloping wall read the design doc asks for - no new geometry
	needed there, just a bevel.

	embrasure: optional dict {"center":(x,y,z), "size":(w,h), "depth_frac":f}
	  - a real recessed, splayed firing slit (add_recessed_embrasure)
	  carved into the front wall before the bevel pass, replacing a proud
	  greeble_vent box."""
	hx, hy, hz = size_x / 2.0, size_y / 2.0, size_z / 2.0
	R = hull_reference_dim(size_x, size_y)
	bm = bmesh.new()
	base_r = max(hx, hz)
	top_r = base_r * taper
	base_pts = []
	top_pts = []
	for i in range(sides):
		angle = i * (2.0 * math.pi / sides)
		base_pts.append((math.cos(angle) * base_r * (hx / base_r), -hy, math.sin(angle) * base_r * (hz / base_r)))
		top_pts.append((math.cos(angle) * top_r * (hx / base_r), hy * 0.7, math.sin(angle) * top_r * (hz / base_r)))
	all_pts = base_pts + top_pts
	verts = [bm.verts.new(GV(*p)) for p in all_pts]
	bmesh.ops.convex_hull(bm, input=verts)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

	if embrasure:
		add_recessed_embrasure(bm, embrasure["center"], embrasure["size"], R,
			depth_frac=embrasure.get("depth_frac", 0.06), wall_gate=hz * 0.15)

	# Heavier, low-segment-count bevel - reads as blocky cast concrete
	# rather than the "milled/cast metal" facet count used on vehicle
	# hulls. Runs on the CURRENT vert set (not just the original
	# silhouette list) so it also smooths the embrasure cut's own edges.
	bevel_sharp_edges(bm, list(bm.verts), R, tier=1, pct=0.09, segments=1)

	# Hard-armor region: the embrasure-facing wall (Godot +Z, where the
	# firing slit itself sits, per the embrasure dict's own "center" Z
	# coordinate convention every caller uses) plus its immediate
	# neighboring facets - unlike a vehicle's frontal glacis or a flat
	# defensive wall, an octagonal frustum has no single dominant "front"
	# facet, so a looser threshold catches the 2-3 facets nearest +Z
	# instead of just one, reading as a real reinforced firing position
	# rather than a single oddly-isolated armored panel. Called before the
	# roof dome so the cap stays structural (real bunker domes are cast
	# concrete, not applied armor plate).
	armor_frac = mark_armor_faces(bm, outward_face_predicate(threshold=armor_threshold))
	print("  [armor split] %s: %.1f%% of surface area tagged hard-armor" % (name, armor_frac * 100.0))

	# Domed roof cap
	dome_verts = bmesh.ops.create_uvsphere(bm, u_segments=sides, v_segments=6, radius=top_r * 0.9)['verts']
	bmesh.ops.scale(bm, verts=dome_verts, vec=GS(1.0, 0.45, 1.0))
	bmesh.ops.translate(bm, verts=dome_verts, vec=GV(0, hy * 0.7, 0))

	if greebles:
		greebles(bm, hx, hy, hz)

	obj = make_object_from_bmesh(bm, name)
	finalize_dual(obj, name, structural_color=color, armor_color=tuple(min(1.0, c * 1.15) for c in color))
	return obj


def build_wall_hull(name, size_x, size_y, size_z, merlons=5, color=(0.42, 0.4, 0.36), greebles=None,
		arrow_slit_count=0, armor_threshold=0.4):
	"""Long, low defensive rampart: a battered (wider-at-base) wall face
	topped with alternating battlement merlons - a wall segment, not a
	bunker or tower, meant to read as long and thin rather than squat.

	arrow_slit_count: carves this many real recessed, splayed arrow slits
	  (add_recessed_embrasure, shared with pillbox_foundation) into the
	  +Z wall face before the bevel, replacing what used to be proud
	  add_box slits in the greebles callback. Positions stay well clear
	  of the +/-X end caps (see the bevel's own preserve_axis=0 comment
	  below) - end-cap tiling must not be touched by any new feature."""
	hx, hy, hz = size_x / 2.0, size_y / 2.0, size_z / 2.0
	R = hull_reference_dim(size_x, size_y)
	bm = bmesh.new()

	base_pts = [
		(-hx * 1.05, -hy, -hz * 1.1), (hx * 1.05, -hy, -hz * 1.1),
		(-hx * 1.05, -hy, hz * 1.1), (hx * 1.05, -hy, hz * 1.1),
		(-hx, hy * 0.55, -hz), (hx, hy * 0.55, -hz),
		(-hx, hy * 0.55, hz), (hx, hy * 0.55, hz),
	]
	verts = [bm.verts.new(GV(*p)) for p in base_pts]
	bmesh.ops.convex_hull(bm, input=verts)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

	if arrow_slit_count > 0:
		# All slits share the same height band, so add_recessed_embrasure_row
		# (not N separate add_recessed_embrasure calls) - re-bisecting an
		# identical height plane once per slit was found, via direct bmesh
		# inspection, to produce hundreds of degenerate zero-area faces.
		slit_xs = [((i + 0.5) / arrow_slit_count - 0.5) * hx * 1.7 for i in range(arrow_slit_count)]
		add_recessed_embrasure_row(bm, slit_xs, hy * 0.05, (R * 0.08, hy * 0.45), R,
			depth_frac=0.05, wall_gate=0.0)

	# Bevel the batter/top transition, but preserve_axis=0 keeps the two
	# flat end-cap faces (raw Blender +/-X, this wall's long axis) fully
	# untouched - those cross-sections must stay identical and flat so
	# adjacent wall segments still tile edge-to-edge with no visible seam.
	# Runs on the CURRENT vert set so it also smooths the arrow slits'
	# own cut edges (the slit positions are already well clear of the
	# preserved end caps, so this doesn't risk the tiling guarantee).
	bevel_sharp_edges(bm, list(bm.verts), R, tier=1, pct=0.06, preserve_axis=0)

	# Hard-armor region: the outward (Godot +Z, arrow-slit-bearing) wall
	# face - the side facing attackers, vs. the sheltered inward face/top/
	# end-caps staying structural masonry. Called before the merlons so the
	# battlements read as lighter capstone atop the hardened wall face, not
	# armor plate themselves.
	armor_frac = mark_armor_faces(bm, outward_face_predicate(threshold=armor_threshold))
	print("  [armor split] %s: %.1f%% of surface area tagged hard-armor" % (name, armor_frac * 100.0))

	# Battlements: alternating merlon teeth along the top edge, evenly
	# spaced with gaps (crenels) between them for the classic wall silhouette.
	# Bespoke Tier 3 detail: each merlon is built as two flanking half-
	# blocks with a narrow gap between them (a real arrow slit) instead of
	# one solid box - built as two separate primitives, not a boolean cut,
	# matching this file's established no-boolean convention (see
	# add_waist_inset's own comment on why booleans were ruled out).
	merlon_w = (size_x * 0.94) / (merlons * 2 - 1)
	slit_w = merlon_w * 0.16
	half_w = (merlon_w * 0.9 - slit_w) / 2.0
	for i in range(merlons):
		mx = -hx * 0.94 + merlon_w * (2 * i + 0.5)
		for side in (-1, 1):
			add_box(bm, (mx + side * (half_w + slit_w) / 2.0, hy * 0.55 + hy * 0.24, 0),
				(half_w, hy * 0.24, hz * 0.8), bevel=0.02)

	if greebles:
		greebles(bm, hx, hy, hz)

	obj = make_object_from_bmesh(bm, name)
	finalize_dual(obj, name, structural_color=color, armor_color=tuple(min(1.0, c * 1.15) for c in color))
	return obj


def build_ship_hull(name, size_x, size_y, size_z, bow_frac=0.35, color=(0.35, 0.38, 0.4), greebles=None,
		deadrise=0.3, sheer=0.1, flare=0.0, stations=9, bevel_pct=None, bevel_segments=None,
		superstructure_tiers=1, forecastle=False, quarterdeck=False, armor_front_frac=0.55):
	"""Naval hull: pointed bow, flat transom stern, a real V-shaped deadrise
	cross-section (via a per-station loft, not a boolean cut), sheer
	(deck line rising toward the bow), optional topside flare above the
	waterline, and a raised bridge superstructure.

	deadrise: keel drop as a fraction of local beam (0=flat-bottomed,
	  higher=sharper V) - small_boat wants this highest, heavy_cruiser
	  lowest.
	sheer: how much the deck rises toward the bow (0=dead flat deck).
	flare: extra outward bell above the main deck edge, above the
	  waterline - heavy_cruiser's "pronounced outward flare."
	Both the bow taper and sheer reuse taper_profile()'s eased nose-
	aggressive curve (bow = "nose" in the wedge-hull sense) so the entry
	curves rather than kinking at a single hard bow cross-section.

	superstructure_tiers: stacks this many fused boxes (technique #1) of
	  decreasing footprint above the deck instead of one flat bridge block -
	  foredeck house -> bridge -> open bridge, generalizing what used to be
	  a single "bridge box glued onto the hull". 1 (default) reproduces the
	  old single-box bridge exactly.
	forecastle: adds a short raised-foredeck box near the bow (the classic
	  freeboard step).
	quarterdeck: adds a lower stern deck step for a layered-deck read."""
	hx, hy, hz = size_x / 2.0, size_y / 2.0, size_z / 2.0
	R = hull_reference_dim(size_x, size_y)
	bm = bmesh.new()

	pts = []
	for i in range(stations):
		t = i / float(stations - 1)
		z = -hz + t * size_z
		beam_scale = taper_profile(t, bow_frac, 0.04, 1.0, nose_region=max(bow_frac, 0.3))
		sheer_scale = taper_profile(t, 0.0, 1.0 + sheer, 1.0, nose_region=max(bow_frac, 0.3))
		beam = hx * beam_scale
		deck_y = hy * sheer_scale
		keel_y = deck_y - beam * deadrise if beam > 0.001 else deck_y
		pts.append((-beam, deck_y, z))
		pts.append((beam, deck_y, z))
		pts.append((0.0, keel_y, z))
		# Gated on beam_scale (not just beam > 0.001): the flare's elevation
		# offset is a FIXED hy*0.15, not scaled with local beam, so adding
		# it right at the pointed bow tip (where beam is tiny but nonzero)
		# created a wildly disproportionate spike - a real bug caught by
		# actually re-verifying screenshots after fixing the Godot import
		# cache issue (see DECISIONS_NEEDED.md). Only flare past the
		# steepest part of the bow taper, where the hull has real beam.
		if flare > 0.0 and beam_scale > 0.5:
			flare_beam = beam * (1.0 + flare)
			flare_y = deck_y + hy * 0.15
			pts.append((-flare_beam, flare_y, z))
			pts.append((flare_beam, flare_y, z))

	verts = [bm.verts.new(GV(*p)) for p in pts]
	bmesh.ops.convex_hull(bm, input=verts)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

	bevel_sharp_edges(bm, verts, R, tier=1, pct=bevel_pct, segments=bevel_segments)

	# Hard-armor region: the bow belt - a real warship's most exposed
	# ramming/torpedo-arc surface, and (per the same reasoning as the AFV
	# hulls' frontal glacis) naturally a minority of total hull area for
	# an elongated hull. Excludes the keel/bottom (never visible, a
	# wasted area cost). Called BEFORE the bridge/forecastle/quarterdeck
	# additions so those stay structural deck fixtures, not armor plate -
	# a bridge superstructure isn't armor on a real ship either.
	armor_frac = mark_armor_faces(bm, frontal_armor_predicate(hz, front_frac=armor_front_frac))
	print("  [armor split] %s: %.1f%% of surface area tagged hard-armor" % (name, armor_frac * 100.0))

	# Bridge superstructure, offset toward the stern - a stack of
	# `superstructure_tiers` fused boxes of decreasing footprint
	# (technique #1, same as build_tower_hull's per-tier hulls), each
	# overlapping the one below it so they read as fused rather than
	# floating. tiers=1 reproduces the old single-box bridge exactly.
	tier_y, tier_hy, tier_hx, tier_hz = hy * 1.3, hy * 0.35, hx * 0.42, hz * 0.26
	for _tier_i in range(superstructure_tiers):
		add_box(bm, (0, tier_y, hz * 0.35), (tier_hx, tier_hy, tier_hz), bevel=0.03)
		tier_y += tier_hy * 1.6
		tier_hx *= 0.78
		tier_hy *= 0.85
		tier_hz *= 0.78

	if forecastle:
		add_box(bm, (0, hy * (1.0 + sheer * 0.6), -hz * 0.62), (hx * 0.7, hy * 0.16, hz * 0.16), bevel=0.02)
	if quarterdeck:
		add_box(bm, (0, -hy * 0.15, hz * 0.72), (hx * 0.9, hy * 0.18, hz * 0.22), bevel=0.02)

	if greebles:
		greebles(bm, hx, hy, hz)

	obj = make_object_from_bmesh(bm, name)
	finalize_dual(obj, name, structural_color=color, armor_color=tuple(min(1.0, c * 1.15) for c in color))
	return obj


def build_flying_wing_hull(name, size_x, size_y, size_z, sweep=0.55, color=(0.5, 0.52, 0.56), greebles=None,
		bevel_pct=0.085, bevel_segments=2, armor_front_frac=0.4):
	"""Blended-wing-body hull: a swept flying-wing planform with no
	distinct fuselage/wing break - a shallow dorsal blend ridge instead of
	the wedge hulls' raised spine, cockpit and body smoothly faired into
	the wing rather than sitting on top of it. The leading-edge thinning
	taper the design doc asks for is already structurally implicit here -
	the dorsal blend shoulders sit at +/-0.4*hx, short of the full-span
	wingtips at +/-hx, so the convex hull already tapers the wing's own
	thickness down to a single point at the tips rather than a constant-
	thickness slab. Tier 1's own lever is the bevel - wide/max-segment,
	per the doc's explicit call for the wing-root-to-body junction."""
	hx, hy, hz = size_x / 2.0, size_y / 2.0, size_z / 2.0
	R = hull_reference_dim(size_x, size_y)
	bm = bmesh.new()

	pts = [
		(0.0, -hy * 0.3, -hz),                                    # nose apex
		(-hx, -hy * 0.3, hz * sweep), (hx, -hy * 0.3, hz * sweep),  # wingtips, swept back
		(-hx * 0.45, -hy * 0.3, hz), (hx * 0.45, -hy * 0.3, hz),    # trailing edge corners
		(0.0, hy, -hz * 0.35),                                     # dorsal blend apex near nose
		(-hx * 0.4, hy * 0.75, hz * 0.25), (hx * 0.4, hy * 0.75, hz * 0.25),  # blend shoulders
		(0.0, hy * 0.45, hz * 0.85),                               # tail blend fade-out
	]
	verts = [bm.verts.new(GV(*p)) for p in pts]
	bmesh.ops.convex_hull(bm, input=verts)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

	# Spanwise panel-line grooves (spars/ribs) - the axis='x' variant of
	# the shared groove helper (add_panel_line_groove normally cuts
	# chordwise bands across a fuselage's length; here the cut runs along
	# the span instead), two symmetric ribs per wing. Applied before the
	# bevel so the tiered bevel still smooths the cut's own edges, same
	# ordering every other hull's bisect+shift details use.
	for x_frac in (0.3, 0.4, 0.6, 0.7):
		add_panel_line_groove(bm, hx, hy, hz, R, x_frac, axis='x')

	# Bevel on the CURRENT vert set (not the original silhouette-only
	# list) so it picks up the groove cuts' own new edges too - same
	# reasoning as build_afv_hull's bevel call.
	bevel_sharp_edges(bm, list(bm.verts), R, tier=1, pct=bevel_pct, segments=bevel_segments)

	# Hard-armor region: the nose apex and leading-edge region - same
	# frontal-arc reasoning as every other vehicle hull.
	armor_frac = mark_armor_faces(bm, frontal_armor_predicate(hz, front_frac=armor_front_frac))
	print("  [armor split] %s: %.1f%% of surface area tagged hard-armor" % (name, armor_frac * 100.0))

	if greebles:
		greebles(bm, hx, hy, hz)

	obj = make_object_from_bmesh(bm, name)
	finalize_dual(obj, name, structural_color=color, armor_color=tuple(min(1.0, c * 1.15) for c in color))
	return obj


def build_sponson_hull(name, size_x, size_y, size_z, sponson_bulge=1.3, sponson_span=0.4,
		sponson_height=0.65, color=(0.38, 0.36, 0.32), greebles=None):
	"""Ground hull with built-in sponson stubs baked directly into the
	silhouette: a slab-sided tapered core hull with two distinct box-like
	sponson blisters fused onto the sides at a mid-body band, protruding
	past the core's flat sides - a real stepped stub, not just a smooth
	taper - rather than sponsons being separately-applied mount hardware."""
	hx, hy, hz = size_x / 2.0, size_y / 2.0, size_z / 2.0
	bm = bmesh.new()
	core_x = hx * 0.78

	pts = [
		(-core_x, -hy, -hz), (core_x, -hy, -hz), (-core_x, -hy, hz), (core_x, -hy, hz),
		(-core_x * 0.85, hy, -hz * 0.9), (core_x * 0.85, hy, -hz * 0.9),
		(-core_x * 0.85, hy, hz * 0.9), (core_x * 0.85, hy, hz * 0.9),
	]
	verts = [bm.verts.new(GV(*p)) for p in pts]
	bmesh.ops.convex_hull(bm, input=verts)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

	sp_z = hz * sponson_span
	sp_x = hx * sponson_bulge
	sp_reach = sp_x - core_x
	for side in (-1, 1):
		add_box(bm, (side * (core_x + sp_reach * 0.5), -hy * (1.0 - sponson_height * 0.5), 0),
			(sp_reach, hy * sponson_height, sp_z * 2.0), bevel=0.04)

	if greebles:
		greebles(bm, hx, hy, hz)

	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=color, metallic=0.55, roughness=0.5)
	return obj


def build_fuselage_hull(name, size_x, size_y, size_z, nose_frac=0.16, tail_frac=0.24,
		wing_span_frac=1.0, wing_chord_frac=0.3, wing_pos_frac=0.05,
		color=(0.6, 0.6, 0.62), greebles=None, bevel_pct=None, bevel_segments=None, armor_front_frac=0.45):
	"""Traditional plane: a slender tapered fuselage tube along Z (nose cone
	forward, tail taper aft) with a separate flat wing slab crossing at
	mid-body and tail control surfaces - a genuine fuselage/wing break,
	unlike flying_wing_hull's single blended-wing-body convex hull with no
	distinct fuselage at all."""
	hx, hy, hz = size_x / 2.0, size_y / 2.0, size_z / 2.0
	R = hull_reference_dim(size_x, size_y)
	body_r = min(hx, hy) * 0.62
	bm = bmesh.new()

	nose_len = size_z * nose_frac
	tail_len = size_z * tail_frac
	body_len = size_z - nose_len - tail_len
	nose_z0 = -hz
	body_z0 = nose_z0 + nose_len
	tail_z0 = body_z0 + body_len

	body_verts = add_cyl_axis(bm, (0, 0, body_z0 + body_len / 2.0), body_r, body_len, 'z', segments=14)
	nose_verts = add_cyl_axis(bm, (0, 0, nose_z0 + nose_len / 2.0), 0.02, nose_len, 'z', segments=14, radius2=body_r)
	tail_verts = add_cyl_axis(bm, (0, 0, tail_z0 + tail_len / 2.0), body_r, tail_len, 'z', segments=14, radius2=body_r * 0.22)

	# The nose/body/tail cone segments are built as separate primitives
	# whose end-caps coincide in space but aren't topologically joined -
	# weld the coincident ring verts into one continuous mesh first, so
	# there's a real shared edge at each join for the tiered bevel to
	# smooth (previously masked only by shade_smooth, not real geometry).
	fuselage_verts = body_verts + nose_verts + tail_verts
	bmesh.ops.remove_doubles(bm, verts=fuselage_verts, dist=0.001)
	fuselage_verts = list(bm.verts)
	bevel_sharp_edges(bm, fuselage_verts, R, tier=1, pct=bevel_pct, segments=bevel_segments)

	# Hard-armor region: nose cone + forward body tube - real warplanes
	# armor the engine/pilot compartment up front, same "frontal arc"
	# reasoning as every other vehicle hull. Called before wings/fairings/
	# formers/tail so those stay lightweight structural skin, not armor.
	armor_frac = mark_armor_faces(bm, frontal_armor_predicate(hz, front_frac=armor_front_frac))
	print("  [armor split] %s: %.1f%% of surface area tagged hard-armor" % (name, armor_frac * 100.0))

	# Wings: a flat slab crossing the body near mid-fuselage - the defining
	# "attached wing" break this hull exists to demonstrate.
	wing_z = -hz * wing_pos_frac
	add_box(bm, (0, 0, wing_z), (size_x * wing_span_frac, hy * 0.16, size_z * wing_chord_frac), bevel=0.03)

	# Wing-root fairing: today the wing slab crosses the tube with a hard
	# intersection - a small fused fillet block at each root (technique
	# #1, no boolean) bridges the tube's own surface into the wing root
	# so the join reads as engineered rather than two shapes clipping.
	for side in (-1, 1):
		add_box(bm, (side * body_r * 0.85, -hy * 0.08, wing_z),
			(body_r * 0.4, hy * 0.14, size_z * wing_chord_frac * 0.55), bevel=0.03)

	# Circumferential formers/ribs along the body tube - same thin-ring
	# technique the airship envelope's own seam rings already use
	# (add_cyl_axis around the hull's long axis), just applied to the
	# fuselage tube instead of an ellipsoid envelope.
	for i in range(4):
		t = (i + 0.5) / 4.0
		add_cyl_axis(bm, (0, 0, body_z0 + t * body_len), body_r * 1.02, 0.02, 'z', segments=14)

	# Dorsal hardpoint pad: the tube's real top surface sits at body_r,
	# not at the AABB top facet (hy) - since body_r = min(hx,hy)*0.62 is
	# always well short of hy, a top-mounted pintle placed at the facet
	# would float above the round tube with a visible gap (the same class
	# of bug the naval/airship hulls hit with underside mounts). A flat
	# raised pad bridging body_r up toward hy gives a real mount surface
	# instead of needing a second, hull-specific mount-offset fix.
	add_box(bm, (0, (body_r + hy * 0.95) * 0.5, 0),
		(body_r * 0.5, (hy * 0.95 - body_r) * 0.5, size_z * 0.12), bevel=0.02)

	# Tail control surfaces: vertical fin + horizontal tailplane
	add_box(bm, (0, hy * 0.5, tail_z0 + tail_len * 0.55), (0.05, hy * 0.85, size_z * 0.1), bevel=0.02)
	add_box(bm, (0, 0, tail_z0 + tail_len * 0.5), (size_x * 0.55, hy * 0.1, size_z * 0.09), bevel=0.02)

	if greebles:
		greebles(bm, hx, hy, hz)

	obj = make_object_from_bmesh(bm, name)
	finalize_dual(obj, name, structural_color=color, armor_color=tuple(min(1.0, c * 1.15) for c in color))
	return obj


def build_airship_hull(name, size_x, size_y, size_z, tail_taper=0.35,
		color=(0.72, 0.7, 0.6), greebles=None, armor_front_frac=0.45):
	"""Rigid airship: a stretched teardrop/cigar gasbag envelope (blunt nose,
	tapered tail) with a gondola slung underneath on struts and a 4-way tail
	fin cross - the only hull silhouette in the roster implying buoyant lift
	rather than an engine actively fighting gravity (see buoyant_envelope's
	own catalog comment in module_catalog.gd for the gameplay consequence).

	Tier 3 bespoke feature: the envelope's cross-section (u_segments=8,
	down from a smooth-ellipsoid 18) is now genuinely faceted rather than
	a round curve - a real rigid-frame airship's skin is paneled over a
	polygonal girder frame, not a perfect balloon. 8 facets puts the
	dihedral angle between adjacent panels at 45 degrees, safely above
	finalize()'s 35-degree auto-smooth threshold, so the facets read as
	real flat panels instead of being smoothed back into a curve;
	v_segments (lengthwise rings) stays high so the teardrop taper along
	the length still reads smooth - only the AROUND-the-tube cross-section
	is faceted. This is a genuine topology change, not a bevel/taper
	tuning one, which is why it sat apart from the rest of the shared
	tiered-bevel work as its own separate Tier 3 item."""
	hx, hy, hz = size_x / 2.0, size_y / 2.0, size_z / 2.0
	R = hull_reference_dim(size_x, size_y)
	gon_bevel, _ = tiered_bevel_width(R, tier=2)
	fin_bevel, _ = tiered_bevel_width(R, tier=3)
	bm = bmesh.new()

	ret = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=12, radius=1.0)
	verts = ret['verts']
	bmesh.ops.scale(bm, verts=verts, vec=GS(hx, hy, hz))
	# Taper the tail half (raw Blender +Y = Godot +Z, per GV/GS convention)
	# narrower for a teardrop silhouette rather than a plain ellipsoid.
	for v in verts:
		if v.co.y > 0:
			t = v.co.y / hz
			shrink = 1.0 - t * tail_taper
			v.co.x *= shrink
			v.co.z *= shrink
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

	# Hard-armor region: the blunt nose - same frontal-arc reasoning as
	# every other vehicle hull, called before the gondola/fins/keel
	# additions so those stay lightweight structural fixtures, not part
	# of the envelope's own armor plating. This shape never gets a
	# bevel_sharp_edges() call (the uvsphere is already smooth), so
	# recalc_face_normals() above is needed first - the taper loop directly
	# mutates vertex coordinates without keeping face normals in sync.
	armor_frac = mark_armor_faces(bm, frontal_armor_predicate(hz, front_frac=armor_front_frac))
	print("  [armor split] %s: %.1f%% of surface area tagged hard-armor" % (name, armor_frac * 100.0))

	# Gondola slung underneath on struts, biased toward the nose for balance.
	gon_w, gon_h, gon_l = hx * 0.5, hy * 0.35, hz * 0.6
	add_box(bm, (0, -hy * 0.85, -hz * 0.15), (gon_w, gon_h, gon_l), bevel=gon_bevel)
	for side in (-1, 1):
		for z_frac in (-0.35, 0.25):
			add_cyl_y(bm, (side * gon_w * 0.35, -hy * 0.6, z_frac * hz * 0.3), 0.03, hy * 0.7, segments=6)

	# Tail fin cross near the tail taper.
	fin_z = hz * 0.75
	fin_span = min(hx, hy) * 0.9
	add_box(bm, (0, fin_span * 0.5, fin_z), (0.04, fin_span, hz * 0.18), bevel=fin_bevel)
	add_box(bm, (0, -fin_span * 0.5, fin_z), (0.04, fin_span, hz * 0.18), bevel=fin_bevel)
	add_box(bm, (fin_span * 0.5, 0, fin_z), (fin_span, 0.04, hz * 0.18), bevel=fin_bevel)
	add_box(bm, (-fin_span * 0.5, 0, fin_z), (fin_span, 0.04, hz * 0.18), bevel=fin_bevel)

	# Longitudinal keel girders - 3 thin fused battens (technique #1,
	# fused primitives left interpenetrating the envelope, same as every
	# other hull's non-welded volumes) running most of the length along
	# the belly, above the gondola. Thickness keyed to R, length to hz,
	# per HULL_MASSING_SPEC.md's stretch-safety rules. Together with the
	# existing ring seams (greebles) and the faceted envelope panels,
	# this is the move that reads as a real girder-frame Zeppelin rather
	# than a faceted balloon.
	batten_size = R * 0.035
	for x_off in (-hx * 0.32, 0.0, hx * 0.32):
		add_box(bm, (x_off, -hy * 0.68, 0), (batten_size, batten_size, hz * 1.75), bevel=0.01)

	if greebles:
		greebles(bm, hx, hy, hz)

	obj = make_object_from_bmesh(bm, name)
	# Canvas/aluminum-skin envelope reads wrong with the ground vehicles'
	# metallic paint - flatter, less reflective finish instead. (Preview-
	# only, same as every other hull's finalize_dual() color args - the
	# real runtime material is always the shared faction shader regardless
	# of hull type, unaffected by this.)
	finalize_dual(obj, name, structural_color=color, armor_color=tuple(min(1.0, c * 1.15) for c in color),
		structural_metallic=0.1, structural_roughness=0.6, armor_metallic=0.3, armor_roughness=0.45)
	return obj


def build_tower_hull(name, size_x, size_y, size_z, tiers=3, color=(0.5, 0.48, 0.44), greebles=None, armor_base_frac=0.06):
	"""Tall stepped defensive tower: tiers stacked wide-to-narrow."""
	hx, hy, hz = size_x / 2.0, size_y / 2.0, size_z / 2.0
	R = hull_reference_dim(size_x, size_y)
	bm = bmesh.new()
	tier_h = (size_y) / tiers
	all_verts = []
	for t in range(tiers):
		shrink = 1.0 - (t * 0.22)
		y0 = -hy + t * tier_h
		y1 = y0 + tier_h * (1.05 if t < tiers - 1 else 1.0)
		tx, tz = hx * shrink, hz * shrink
		pts = [
			(-tx, y0, -tz), (tx, y0, -tz), (-tx, y0, tz), (tx, y0, tz),
			(-tx, y1, -tz), (tx, y1, -tz), (-tx, y1, tz), (tx, y1, tz),
		]
		verts = [bm.verts.new(GV(*p)) for p in pts]
		bmesh.ops.convex_hull(bm, input=verts)
		all_verts += verts

	# Slight outward-flared base skirt - a shallow wider collar right at
	# the foundation, before any bevel touches the main stepped body.
	skirt_h = tier_h * 0.16
	skirt_verts = [bm.verts.new(GV(*p)) for p in [
		(-hx * 1.1, -hy - skirt_h, -hz * 1.1), (hx * 1.1, -hy - skirt_h, -hz * 1.1),
		(-hx * 1.1, -hy - skirt_h, hz * 1.1), (hx * 1.1, -hy - skirt_h, hz * 1.1),
		(-hx, -hy, -hz), (hx, -hy, -hz), (-hx, -hy, hz), (hx, -hy, hz),
	]]
	bmesh.ops.convex_hull(bm, input=skirt_verts)
	all_verts += skirt_verts

	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

	# Tier-1 bevel across the stepped body's real structural edges
	# (tier-to-tier shrink steps, skirt flare) - before railings/antenna
	# are fused on so only the primary silhouette is touched.
	bevel_sharp_edges(bm, all_verts, R, tier=1)

	# Hard-armor region: the base/lower tiers, NOT a frontal arc - a tower
	# has no distinct front/back (each tier is roughly rotationally
	# symmetric), so real castle-defense logic applies instead: the
	# ground-level tiers facing direct assault are hardened, upper tiers
	# are lighter structural stonework. Called before the machicolation
	# ring/railings/antenna/spotlights so those stay lightweight rooftop
	# fixtures, not armor plate.
	armor_frac = mark_armor_faces(bm, vertical_armor_predicate(hy, base_frac=armor_base_frac))
	print("  [armor split] %s: %.1f%% of surface area tagged hard-armor" % (name, armor_frac * 100.0))

	# Bespoke Tier 3 feature: a corbelled machicolation ring - a real
	# castle-defense projecting gallery, supported on angled brackets,
	# sitting at the step between the second-to-last and top tier so the
	# top tier reads as bridging out past its own (narrower) footprint on
	# a shelf, rather than just another plain stepped-pyramid shrink. Sized
	# to the tier BELOW the shelf (wider than the top tier it supports),
	# which is what makes the overhang actually visible from outside.
	if tiers >= 2:
		# Sized to the tier TWO steps below the shelf (clamped to the base
		# tier's own full footprint) - matching the tier directly below it
		# (an earlier version's off-by-one) left zero overhang, since the
		# shelf would then sit exactly flush with the very edge it was
		# meant to project past.
		shelf_shrink = 1.0 - (max(tiers - 3, 0) * 0.22)
		shelf_tx, shelf_tz = hx * shelf_shrink, hz * shelf_shrink
		shelf_y = -hy + (tiers - 1) * tier_h
		shelf_th = tier_h * 0.09
		add_box(bm, (0, shelf_y, -shelf_tz + shelf_th * 0.5), (shelf_tx * 2.0, shelf_th, shelf_th), bevel=0.015)
		add_box(bm, (0, shelf_y, shelf_tz - shelf_th * 0.5), (shelf_tx * 2.0, shelf_th, shelf_th), bevel=0.015)
		add_box(bm, (-shelf_tx + shelf_th * 0.5, shelf_y, 0), (shelf_th, shelf_th, shelf_tz * 2.0), bevel=0.015)
		add_box(bm, (shelf_tx - shelf_th * 0.5, shelf_y, 0), (shelf_th, shelf_th, shelf_tz * 2.0), bevel=0.015)
		for i in range(8):
			angle = i * (math.pi / 4.0)
			cx, cz = math.cos(angle) * shelf_tx * 0.92, math.sin(angle) * shelf_tz * 0.92
			add_box(bm, (cx, shelf_y - shelf_th * 1.6, cz), (0.12, shelf_th * 1.4, 0.12),
				rot_axis='x', rot_angle=0.6)

	# Rooftop platform railing posts
	top_shrink = 1.0 - ((tiers - 1) * 0.22)
	rx, rz = hx * top_shrink * 0.9, hz * top_shrink * 0.9
	for i in range(4):
		angle = i * (math.pi / 2.0) + math.pi / 4.0
		pos = (math.cos(angle) * rx, hy * 0.85, math.sin(angle) * rz)
		add_cyl_y(bm, pos, 0.03, 0.35, segments=6)
	greeble_antenna(bm, (0, hy, 0), height=0.7, radius=0.025)
	for side in (-1, 1):
		greeble_spotlight(bm, (side * rx * 0.7, hy * 0.75, -rz * 0.7), radius=0.09)

	if greebles:
		greebles(bm, hx, hy, hz)

	obj = make_object_from_bmesh(bm, name)
	finalize_dual(obj, name, structural_color=color, armor_color=tuple(min(1.0, c * 1.15) for c in color))
	return obj


# ---------------------------------------------------------------------------
# Generate: reusable parts
# ---------------------------------------------------------------------------

def generate_parts():
	print("--- Building parts library ---")

	export_and_cleanup(build_barrel("barrel_thin", length=1.0, radius=0.06, muzzle_radius=0.05), PARTS_DIR, "barrel_thin")
	export_and_cleanup(build_barrel("barrel_standard", length=1.0, radius=0.1, muzzle_radius=0.09), PARTS_DIR, "barrel_standard")
	export_and_cleanup(build_barrel("barrel_heavy", length=1.0, radius=0.16, muzzle_radius=0.22, fins=3), PARTS_DIR, "barrel_heavy")
	export_and_cleanup(build_barrel("barrel_taper_wide", length=1.0, radius=0.08, muzzle_radius=0.1), PARTS_DIR, "barrel_taper_wide")

	export_and_cleanup(build_cylinder_part("turret_base_round", radius=0.4, height=0.35, color=(0.32, 0.32, 0.35)), PARTS_DIR, "turret_base_round")
	export_and_cleanup(build_box_part("turret_base_box", size=(1.0, 0.5, 0.7), color=(0.32, 0.32, 0.35)), PARTS_DIR, "turret_base_box")

	export_and_cleanup(build_cylinder_part("ammo_drum", radius=0.5, height=0.4, color=(0.22, 0.24, 0.2)), PARTS_DIR, "ammo_drum")
	export_and_cleanup(build_cylinder_part("canister_small", radius=0.4, height=1.0, color=(0.5, 0.15, 0.12)), PARTS_DIR, "canister_small")
	export_and_cleanup(build_cylinder_part("fuel_tank", radius=0.5, height=1.0, color=(0.4, 0.1, 0.1)), PARTS_DIR, "fuel_tank")

	export_and_cleanup(build_dome("sensor_dome", radius=0.5, squash=0.65, color=(0.9, 0.92, 0.95)), PARTS_DIR, "sensor_dome")
	export_and_cleanup(build_dome("focal_lens", radius=0.5, squash=0.8, color=(1.0, 0.3, 0.3)), PARTS_DIR, "focal_lens")

	export_and_cleanup(build_missile_body("missile_body", length=1.0, radius=0.1, color=(0.92, 0.92, 0.9)), PARTS_DIR, "missile_body")
	export_and_cleanup(build_pintle_mount("pintle_mount", color=(0.18, 0.18, 0.2)), PARTS_DIR, "pintle_mount")
	export_and_cleanup(build_cylinder_part("muzzle_brake", radius=0.5, height=0.5, segments=10, color=(0.15, 0.15, 0.16)), PARTS_DIR, "muzzle_brake")

	export_and_cleanup(build_howitzer_breech("howitzer_breech", color=(0.28, 0.28, 0.3)), PARTS_DIR, "howitzer_breech")
	export_and_cleanup(build_basic_cannon_solid("basic_cannon", color=(0.28, 0.28, 0.32)), PARTS_DIR, "basic_cannon")
	export_and_cleanup(build_rotary_jacket("rotary_jacket", color=(0.2, 0.2, 0.21)), PARTS_DIR, "rotary_jacket")
	export_and_cleanup(build_rail_array("rail_array", color=(0.15, 0.15, 0.15)), PARTS_DIR, "rail_array")
	export_and_cleanup(build_flak_breech("flak_breech", color=(0.18, 0.18, 0.18)), PARTS_DIR, "flak_breech")

	export_and_cleanup(build_wheel("wheel_hub", color=(0.08, 0.08, 0.08)), PARTS_DIR, "wheel_hub")
	export_and_cleanup(build_leg_segment("leg_thigh", length=0.55, radius_top=0.13, radius_bottom=0.09, color=(0.3, 0.3, 0.32)), PARTS_DIR, "leg_thigh")
	export_and_cleanup(build_leg_segment("leg_shin", length=0.5, radius_top=0.09, radius_bottom=0.06, color=(0.16, 0.16, 0.17)), PARTS_DIR, "leg_shin")
	export_and_cleanup(build_hover_ring("hover_ring", major_radius=0.5, minor_radius=0.1, color=(0.2, 0.6, 0.9)), PARTS_DIR, "hover_ring")
	export_and_cleanup(build_hover_ring("antigrav_ring", major_radius=0.5, minor_radius=0.07, color=(0.3, 0.5, 1.0)), PARTS_DIR, "antigrav_ring")
	export_and_cleanup(build_tread_plate("tread_plate", color=(0.16, 0.16, 0.17)), PARTS_DIR, "tread_plate")
	export_and_cleanup(build_screw_drum("screw_drum", color=(0.35, 0.32, 0.28)), PARTS_DIR, "screw_drum")

	export_and_cleanup(build_accessory("headlight_cluster", "spotlight", (0.9, 0.9, 0.75), radius=0.07, metallic=0.3, roughness=0.2), PARTS_DIR, "headlight_cluster")
	export_and_cleanup(build_accessory("exhaust_stack", "exhaust", (0.15, 0.15, 0.15), height=0.35, metallic=0.7, roughness=0.5), PARTS_DIR, "exhaust_stack")
	export_and_cleanup(build_accessory("antenna_whip", "antenna", (0.12, 0.12, 0.12), height=0.6, metallic=0.6, roughness=0.4), PARTS_DIR, "antenna_whip")
	export_and_cleanup(build_accessory("vent_grille", "vent", (0.14, 0.14, 0.15), size=(0.4, 0.08, 0.25), metallic=0.55, roughness=0.5), PARTS_DIR, "vent_grille")
	export_and_cleanup(build_accessory("roof_hatch", "hatch", (0.38, 0.38, 0.4), size=(0.6, 0.06, 0.6), metallic=0.6, roughness=0.45), PARTS_DIR, "roof_hatch")
	export_and_cleanup(build_accessory("tool_box", "toolbox", (0.28, 0.32, 0.24), size=(0.5, 0.28, 0.32), metallic=0.3, roughness=0.6), PARTS_DIR, "tool_box")
	export_and_cleanup(build_accessory("sensor_mast", "sensor_mast", (0.15, 0.15, 0.15), height=1.0, metallic=0.6, roughness=0.4), PARTS_DIR, "sensor_mast")

	print("--- Parts library done ---")


# ---------------------------------------------------------------------------
# Generate: hull chassis (size = catalog "size" Vector3, matched exactly)
# ---------------------------------------------------------------------------

def _light_hull_greebles(bm, hx, hy, hz):
	greeble_headlight_pair(bm, hx, -hy * 0.2, -hz * 0.96, radius=0.08)
	greeble_antenna(bm, (hx * 0.5, hy * 1.0, hz * 0.3), height=0.22)
	greeble_vent(bm, (hx * 0.92, hy * 0.1, hz * 0.1), (0.1, 0.3, 0.5), slats=3)
	greeble_vent(bm, (-hx * 0.92, hy * 0.1, hz * 0.1), (0.1, 0.3, 0.5), slats=3)


def _medium_hull_greebles(bm, hx, hy, hz):
	greeble_headlight_pair(bm, hx, -hy * 0.15, -hz * 0.97, radius=0.1)
	greeble_hatch(bm, (0, hy * 1.05, hz * 0.1), (0.7, 0.06, 0.6))
	greeble_toolbox(bm, (hx * 0.7, -hy * 0.55, hz * 0.5))
	greeble_exhaust_stack(bm, (-hx * 0.75, hy * 0.6, hz * 0.85), radius=0.09, height=0.4)
	greeble_exhaust_stack(bm, (-hx * 0.55, hy * 0.6, hz * 0.85), radius=0.09, height=0.32)
	greeble_corner_gusset(bm, -1, hx, hy, -hz * 0.85)
	greeble_corner_gusset(bm, 1, hx, hy, -hz * 0.85)
	greeble_rivet_row(bm, (-hx * 0.9, hy * 0.9, -hz * 0.6), (-hx * 0.9, hy * 0.9, hz * 0.6), 6)
	greeble_rivet_row(bm, (hx * 0.9, hy * 0.9, -hz * 0.6), (hx * 0.9, hy * 0.9, hz * 0.6), 6)


def _heavy_hull_greebles(bm, hx, hy, hz):
	greeble_headlight_pair(bm, hx * 0.8, -hy * 0.1, -hz * 0.97, radius=0.13)
	greeble_hatch(bm, (0, hy * 1.08, 0), (1.0, 0.08, 0.9))
	add_cyl_y(bm, (0, hy * 1.15, 0), 0.45, 0.22, segments=14)  # commander cupola
	for x_sign in (-1, 1):
		for z_frac in (-0.75, 0.6):
			greeble_corner_gusset(bm, x_sign, hx, hy, hz * z_frac, size=(0.5, 0.42, 0.7))
	greeble_exhaust_stack(bm, (-hx * 0.7, hy * 0.65, hz * 0.9), radius=0.12, height=0.5)
	greeble_exhaust_stack(bm, (-hx * 0.45, hy * 0.65, hz * 0.9), radius=0.12, height=0.42)
	greeble_rivet_row(bm, (-hx * 0.95, hy * 0.85, -hz * 0.8), (-hx * 0.95, hy * 0.85, hz * 0.8), 8)
	greeble_rivet_row(bm, (hx * 0.95, hy * 0.85, -hz * 0.8), (hx * 0.95, hy * 0.85, hz * 0.8), 8)
	greeble_toolbox(bm, (hx * 0.75, -hy * 0.6, -hz * 0.3), size=(0.6, 0.32, 0.4))


def _interceptor_hull_greebles(bm, hx, hy, hz):
	# Sleek - fewer greebles, a small faired canopy (a real cockpit
	# volume, technique #1 - see greeble_faired_canopy) + tail fins +
	# intakes. Height clamped to hy, width/length to hx/hz per
	# HULL_MASSING_SPEC.md's interceptor_hull stretch-safety note - keeps
	# the dome from inverting its squash ratio under an extreme
	# independent hull_scale.y stretch. Set slightly forward of centre
	# and low/blended rather than the old proud add_box bump.
	greeble_faired_canopy(bm, (0, hy * 0.78, -hz * 0.1), (hx * 0.32, hy * 0.24, hz * 0.42))
	greeble_vent(bm, (hx * 0.85, 0, hz * 0.3), (0.08, 0.3, 0.6), slats=4)
	greeble_vent(bm, (-hx * 0.85, 0, hz * 0.3), (0.08, 0.3, 0.6), slats=4)
	for side in (-1, 1):
		add_box(bm, (side * hx * 0.5, hy * 0.3, hz * 0.92), (0.04, hy * 0.5, 0.3), rot_axis='x', rot_angle=0.3)
	greeble_antenna(bm, (0, hy * 1.05, -hz * 0.2), height=0.18)


def _assault_hull_greebles(bm, hx, hy, hz):
	greeble_headlight_pair(bm, hx * 0.75, -hy * 0.1, -hz * 0.97, radius=0.11)
	# Applique armor plates - tier-2 bevel (Section 3: "armor plates:
	# beveled/angled edges, tier-2") plus a vertical rivet line near the
	# exposed outward face; the back/mount-contact face against the hull
	# stays flat since the rivets only run along the outward-facing edge.
	plate_bevel, _ = tiered_bevel_width(hull_reference_dim(hx * 2, hy * 2), tier=2)
	for x_sign in (-1, 1):
		for z_frac in (-0.5, 0.0, 0.5):
			plate_x, plate_z = x_sign * hx * 0.98, hz * z_frac
			add_box(bm, (plate_x, hy * 0.1, plate_z), (0.1, hy * 1.1, hz * 0.28), bevel=plate_bevel)
			greeble_rivet_row(bm, (plate_x + x_sign * 0.06, hy * 0.1 - hy * 0.48, plate_z),
				(plate_x + x_sign * 0.06, hy * 0.1 + hy * 0.48, plate_z), 4, radius=0.018, axis='x')
	add_cyl_y(bm, (0, hy * 1.1, hz * 0.1), 0.5, 0.14, segments=16)  # turret ring
	greeble_hatch(bm, (0, hy * 1.15, hz * 0.1), (0.55, 0.05, 0.5))
	# Front dozer-style plate, sized to span the tub's full nose height
	# (assumes tub_frac=0.55, matching the build_afv_hull call below, so
	# tub_top_y = -hy + 2*hy*0.55 = 0.1*hy) so it fuses visually into the
	# tub/glacis seam instead of floating in front of the hull as a
	# separate bump - "one thick layered frontal assembly" per
	# HULL_MASSING_SPEC.md's assault_hull section.
	add_box(bm, (0, -hy * 0.45, -hz * 1.02), (hx * 1.3, hy * 1.05, 0.15), bevel=0.03)
	greeble_exhaust_stack(bm, (-hx * 0.6, hy * 0.55, hz * 0.9), radius=0.1, height=0.4)


def _pillbox_greebles(bm, hx, hy, hz):
	for i in range(8):
		angle = i * (2.0 * math.pi / 8.0) + math.pi / 8.0
		pos = (math.cos(angle) * hx * 0.95, -hy * 0.75, math.sin(angle) * hz * 0.95)
		add_box(bm, pos, (0.35, 0.35, 0.35), bevel=0.05)  # sandbag corner fillets
	# The firing embrasure itself is now a real recessed, splayed cut in
	# the silhouette (build_bunker_hull's `embrasure` param, carved before
	# the bevel) - a proud greeble_vent box here would double up on the
	# same location. Just the shallow casemate hood lintel above it.
	add_box(bm, (0, hy * 0.63, hz * 0.87), (0.56, 0.06, 0.14), bevel=0.02)
	greeble_antenna(bm, (hx * 0.3, hy * 1.15, hz * 0.3), height=0.5)
	greeble_rivet_row(bm, (-hx * 0.85, -hy * 0.2, hz * 0.85), (hx * 0.85, -hy * 0.2, hz * 0.85), 5)


def _tower_greebles(bm, hx, hy, hz):
	pass  # railing posts / spotlights / antenna already added in build_tower_hull


def _ship_hull_greebles(bm, hx, hy, hz):
	for side in (-1, 1):
		for i in range(4):
			t = (i + 0.5) / 4.0 - 0.5
			pos = (side * hx * 0.98, hy * 0.15, t * hz * 1.3)
			add_cyl_axis(bm, pos, 0.06, 0.05, 'x', segments=10)
	greeble_antenna(bm, (0, hy * 1.65, hz * 0.35), height=0.6)
	greeble_vent(bm, (0, hy * 1.05, -hz * 0.1), (0.3, 0.12, 0.5), slats=3)

	# Bespoke Tier 3 naval identity: naval_hull was the one ship hull with
	# no silhouette feature of its own beyond the shared bridge block -
	# small_boat_hull and heavy_cruiser_hull each already read distinctly
	# via their own greebles. A single raked funnel (just aft of the
	# bridge, slight outward flare at the cap) plus a foremast (just
	# forward of the bridge) is the classic mast-bridge-funnel silhouette
	# real mid-size warships read by, at real "massing" scale rather than
	# small surface detail.
	add_cyl_y(bm, (0, hy * 1.55, hz * 0.55), 0.22, hy * 1.1, segments=12, radius2=0.26)
	add_cyl_y(bm, (0, hy * 1.85, hz * 0.05), 0.045, hy * 1.7, segments=8)


def _small_boat_greebles(bm, hx, hy, hz):
	# Sparse - a fast patrol boat, not a warship draped in gear.
	greeble_antenna(bm, (0, hy * 1.5, hz * 0.4), height=0.4)
	greeble_spotlight(bm, (0, hy * 1.15, -hz * 0.5), radius=0.08)
	for side in (-1, 1):
		add_cyl_axis(bm, (side * hx * 0.97, hy * 0.1, hz * 0.5), 0.05, 0.04, 'x', segments=8)


def _heavy_cruiser_greebles(bm, hx, hy, hz):
	# A real warship silhouette: layered superstructure (now real base
	# massing via build_ship_hull's superstructure_tiers, not a hand-added
	# greeble box - the old "upper bridge deck" add_box here duplicated
	# what the tier stack now produces, so it was removed rather than
	# double-layering the same structure), twin funnels, gun deck
	# greebles, portholes - deliberately busier than naval_hull.
	greeble_exhaust_stack(bm, (-hx * 0.12, hy * 1.35, hz * 0.55), radius=0.18, height=0.7)
	greeble_exhaust_stack(bm, (hx * 0.12, hy * 1.35, hz * 0.55), radius=0.18, height=0.7)
	add_box(bm, (0, hy * 1.02, -hz * 0.55), (hx * 0.35, hy * 0.22, hz * 0.3), bevel=0.03)  # foredeck turret housing
	for side in (-1, 1):
		for i in range(6):
			t = (i + 0.5) / 6.0 - 0.5
			pos = (side * hx * 0.98, hy * 0.3, t * hz * 1.5)
			add_cyl_axis(bm, pos, 0.07, 0.05, 'x', segments=10)
	greeble_antenna(bm, (0, hy * 1.85, hz * 0.15), height=0.7)
	greeble_rivet_row(bm, (-hx * 0.9, hy * 1.0, -hz * 0.9), (-hx * 0.9, hy * 1.0, hz * 0.9), 8)
	greeble_rivet_row(bm, (hx * 0.9, hy * 1.0, -hz * 0.9), (hx * 0.9, hy * 1.0, hz * 0.9), 8)


def _fuselage_hull_greebles(bm, hx, hy, hz):
	# Real cockpit volume (see greeble_faired_canopy, introduced for
	# interceptor_hull's identical need) instead of a proud box bump -
	# height clamped to hy alone per the same extreme-stretch note.
	greeble_faired_canopy(bm, (0, hy * 0.28, -hz * 0.55), (hx * 0.16, hy * 0.14, hz * 0.28))
	greeble_vent(bm, (hx * 0.28, 0, -hz * 0.05), (0.1, 0.22, 0.3), slats=3)
	greeble_vent(bm, (-hx * 0.28, 0, -hz * 0.05), (0.1, 0.22, 0.3), slats=3)
	greeble_antenna(bm, (0, hy * 0.55, hz * 0.5), height=0.2)
	greeble_rivet_row(bm, (0, hy * 0.3, -hz * 0.75), (0, hy * 0.3, hz * 0.55), 8, axis='y')


def _airship_hull_greebles(bm, hx, hy, hz):
	greeble_antenna(bm, (0, hy * 0.3, -hz * 0.85), height=0.35)
	# Riding-off panel seams along the envelope, evenly spaced rings.
	for i in range(4):
		t = (i + 0.5) / 4.0 - 0.5
		add_cyl_axis(bm, (0, 0, t * hz * 1.2), min(hx, hy) * 1.01, 0.02, 'z', segments=18)


def _flying_wing_hull_greebles(bm, hx, hy, hz):
	# Faired canopy blister (greeble_faired_canopy, shared with
	# interceptor_hull/fuselage_hull) blended into the dorsal ridge
	# instead of a proud box bump - low/wide, height clamped to hy alone.
	greeble_faired_canopy(bm, (0, hy * 0.92, -hz * 0.3), (hx * 0.17, hy * 0.1, hz * 0.28))
	for side in (-1, 1):
		greeble_vent(bm, (side * hx * 0.55, hy * 0.5, hz * 0.6), (0.1, 0.25, 0.4), slats=3)
	greeble_antenna(bm, (0, hy * 0.9, hz * 0.6), height=0.16)


def _sponson_hull_greebles(bm, hx, hy, hz):
	greeble_headlight_pair(bm, hx * 0.55, -hy * 0.6, -hz * 0.97, radius=0.1)
	sp_z = hz * 0.4
	for side in (-1, 1):
		greeble_hatch(bm, (side * hx * 0.85, hy * 0.1, sp_z), (0.4, 0.05, 0.35))
	greeble_hatch(bm, (0, hy * 1.02, 0), (0.6, 0.06, 0.55))
	greeble_rivet_row(bm, (-hx * 0.9, -hy * 0.3, -hz * 0.85), (-hx * 0.9, -hy * 0.3, hz * 0.85), 6)
	greeble_rivet_row(bm, (hx * 0.9, -hy * 0.3, -hz * 0.85), (hx * 0.9, -hy * 0.3, hz * 0.85), 6)


def _wall_greebles(bm, hx, hy, hz):
	# Arrow slits are now a real recessed cut in the silhouette
	# (build_wall_hull's arrow_slit_count param, carved before the
	# bevel) instead of a proud add_box here - see HULL_MASSING_SPEC.md.
	greeble_rivet_row(bm, (-hx * 0.92, -hy * 0.75, hz * 0.98), (hx * 0.92, -hy * 0.75, hz * 0.98), 10)
	greeble_antenna(bm, (hx * 0.85, hy * 0.9, 0), height=0.4)


def generate_hulls():
	print("--- Building hull library ---")

	export_and_cleanup(build_afv_hull("light_hull", 3.0, 1.0, 4.0,
		nose_frac=0.6, tub_frac=0.45, upper_w=0.82, glacis_len_frac=0.35,
		spine_w=0.35, spine_h=1.08, fender_height_frac=0.05,
		bevel_pct=0.06,
		color=(0.72, 0.73, 0.75), greebles=_light_hull_greebles), HULLS_DIR, "light_hull")

	export_and_cleanup(build_afv_hull("medium_hull", 4.0, 1.0, 6.0,
		nose_frac=0.25, tub_frac=0.55, upper_w=0.78, glacis_len_frac=0.3,
		spine_w=0.6, spine_h=1.15, turret_ring=True,
		louver_panel={"z_frac": 0.72, "width_frac": 0.85, "depth_frac": 0.3, "slats": 5},
		waist_inset=0.0, deck_line=0.0,
		panel_line_fracs=[0.28], armor_front_frac=0.55,
		color=(0.5, 0.5, 0.52), greebles=_medium_hull_greebles), HULLS_DIR, "medium_hull")

	export_and_cleanup(build_afv_hull("heavy_hull", 6.0, 1.5, 8.0,
		nose_frac=0.08, tub_frac=0.6, upper_w=0.9, glacis_len_frac=0.22,
		spine_w=0.75, spine_h=1.2, turret_ring=True,
		louver_panel={"z_frac": 0.75, "width_frac": 0.85, "depth_frac": 0.28, "slats": 6},
		bevel_pct=0.09, bevel_segments=3,
		color=(0.32, 0.32, 0.34), greebles=_heavy_hull_greebles), HULLS_DIR, "heavy_hull")

	export_and_cleanup(build_wedge_hull("interceptor_hull", 2.4, 0.8, 3.2,
		nose_frac=0.95, spine_w=0.22, spine_h=1.05, rear_flare=0.75, front_flare=0.3,
		nose_region=0.22, height_taper=0.45, bevel_pct=0.05, bevel_segments=1,
		speed_line_chamfer=True,
		color=(0.55, 0.65, 0.78), greebles=_interceptor_hull_greebles), HULLS_DIR, "interceptor_hull")

	export_and_cleanup(build_afv_hull("assault_hull", 5.0, 1.3, 7.0,
		nose_frac=0.3, tub_frac=0.55, upper_w=0.82, glacis_len_frac=0.32,
		spine_w=0.7, spine_h=1.22,
		bevel_pct=0.085, bevel_segments=3,
		color=(0.4, 0.32, 0.28), greebles=_assault_hull_greebles), HULLS_DIR, "assault_hull")

	export_and_cleanup(build_bunker_hull("pillbox_foundation", 3.0, 1.2, 3.0,
		sides=8, taper=0.7,
		embrasure={"center": (0, 0.33, 1.35), "size": (0.5, 0.15), "depth_frac": 0.08},  # hy*0.55, hz*0.9
		color=(0.45, 0.45, 0.4), greebles=_pillbox_greebles), HULLS_DIR, "pillbox_foundation")

	export_and_cleanup(build_tower_hull("tower_foundation", 3.0, 4.0, 3.0,
		tiers=3, color=(0.5, 0.48, 0.44), greebles=_tower_greebles), HULLS_DIR, "tower_foundation")

	export_and_cleanup(build_wall_hull("fortress_wall_foundation", 6.0, 2.2, 1.3,
		merlons=5, arrow_slit_count=5,
		color=(0.42, 0.4, 0.36), greebles=_wall_greebles), HULLS_DIR, "fortress_wall_foundation")

	export_and_cleanup(build_ship_hull("naval_hull", 3.5, 1.6, 9.0,
		bow_frac=0.35, deadrise=0.3, sheer=0.08, flare=0.0, bevel_pct=0.07,
		superstructure_tiers=3, forecastle=True,
		color=(0.35, 0.38, 0.4), greebles=_ship_hull_greebles), HULLS_DIR, "naval_hull")

	export_and_cleanup(build_flying_wing_hull("flying_wing_hull", 5.0, 0.7, 3.6,
		sweep=0.55, color=(0.5, 0.52, 0.56), greebles=_flying_wing_hull_greebles), HULLS_DIR, "flying_wing_hull")

	export_and_cleanup(build_afv_hull("sponson_hull", 6.5, 1.6, 7.5,
		nose_frac=0.1, tub_frac=0.5, upper_w=0.7, glacis_len_frac=0.3,
		fender_frac=1.15, fender_height_frac=0.38,
		spine_w=0.6, spine_h=1.1,
		color=(0.38, 0.36, 0.32), greebles=_sponson_hull_greebles), HULLS_DIR, "sponson_hull")

	export_and_cleanup(build_ship_hull("small_boat_hull", 2.0, 1.0, 5.0,
		bow_frac=0.5, deadrise=0.55, sheer=0.15, flare=0.0, bevel_pct=0.06, bevel_segments=1,
		superstructure_tiers=1,  # one small pilothouse only - identity is sparseness, see HULL_MASSING_SPEC.md
		color=(0.4, 0.42, 0.44), greebles=_small_boat_greebles), HULLS_DIR, "small_boat_hull")

	export_and_cleanup(build_ship_hull("heavy_cruiser_hull", 4.4, 1.9, 10.5,
		bow_frac=0.28, deadrise=0.12, sheer=0.22, flare=0.35, bevel_pct=0.09, bevel_segments=3,
		superstructure_tiers=4, quarterdeck=True,
		color=(0.3, 0.32, 0.34), greebles=_heavy_cruiser_greebles), HULLS_DIR, "heavy_cruiser_hull")

	export_and_cleanup(build_fuselage_hull("fuselage_hull", 4.2, 1.2, 6.2,
		color=(0.6, 0.6, 0.62), greebles=_fuselage_hull_greebles), HULLS_DIR, "fuselage_hull")

	export_and_cleanup(build_airship_hull("airship_hull", 4.0, 3.0, 9.5,
		tail_taper=0.4, color=(0.72, 0.7, 0.6), greebles=_airship_hull_greebles), HULLS_DIR, "airship_hull")

	print("--- Hull library done ---")


clear_scene()
generate_parts()
# generate_hulls()  # Protected: hulls remain unmodified
print("=== Mesh generation complete ===")
