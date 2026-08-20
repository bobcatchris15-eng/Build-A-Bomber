# CSGMeshBaker - exact polygonal CSG bake for constructed hulls.
# (use via preload, e.g. const CSGMeshBaker = preload("res://scripts/csg_mesh_baker.gd"))
#
# The alternative to scripts/sdf_mesh_baker.gd, and the right tool when the hull
# is meant to read as a MANUFACTURED object: flat armour panels, dead-straight
# edges, exact 45-degree chamfers.
#
# ── Why this exists ──────────────────────────────────────────────────────
#
# The SDF path samples a distance field on a voxel grid and contours it. That
# makes every flat panel only as flat as the lattice allows: a panel is exact
# only where its plane happens to align with a grid plane, and everywhere else
# each cell carries its own sub-voxel error. Cell-to-cell variation in that error
# IS the sawtooth, and it is structural, not a tuning problem - measured across
# three rounds of tuning, the boxy hulls plateaued at 3-9% of their shared edges
# sitting at a "should be coplanar but isn't" angle, and buying accuracy with
# resolution costs triangles cubically (the roster reached 27,000 triangles and
# still was not crisp).
#
# This baker never samples anything. Every primitive in the kit is a convex
# polyhedron (or a small union of them), so the hull is a union of convex solids,
# and the union's boundary can be computed exactly:
#
#   for every face F of every convex piece P:
#       remove the parts of F that lie inside any OTHER piece
#       whatever survives is on the outside of the union
#
# The surviving polygons are exactly planar because they are pieces of the
# primitives' own faces - not approximations of them. Output is a few hundred
# triangles instead of a few thousand.
#
# ── Subtracting a convex solid from a polygon ────────────────────────────
#
# F minus the interior of Q, where Q is the intersection of half-spaces h_1..h_n,
# decomposes into n convex pieces without any general polygon-boolean machinery:
#
#   F \ Q  =  U over i of  ( F  ∩ h_1 ∩ .. ∩ h_(i-1)  ∩  outside(h_i) )
#
# i.e. walk Q's planes, peel off the part of what remains that is outside the
# current plane (that part can never be inside Q), and carry the rest forward.
# Whatever is left after all n planes is inside Q and gets discarded. Each peeled
# piece is convex, so a fan triangulation is valid.
#
# No class_name / no `extends` - same convention as sdf_mesh_baker.gd,
# hull_loader.gd and mesh_asset_loader.gd (class_name globals aren't reliable in
# scripts run headless before the .godot cache exists).

const SDFMeshBaker = preload("res://scripts/sdf_mesh_baker.gd")

# Primitive type ids, mirroring hull_builder.gd's PrimitiveType. Duplicated for
# the same reason sdf_mesh_baker.gd duplicates them - hull_builder.gd is a Node3D
# bound to a scene full of @onready UI references.
const TYPE_BOX := 0
const TYPE_SPHERE := 1
const TYPE_CYLINDER := 2
const TYPE_WEDGE := 3
const TYPE_CONE := 4
const TYPE_TORUS := 5
const TYPE_SLOPE := 6
const TYPE_FRUSTUM := 7
const TYPE_CHAMFER_BOX := 8
const TYPE_HALF_CYLINDER := 9
const TYPE_HEMISPHERE := 10
const TYPE_CAPSULE := 11
const TYPE_I_BEAM := 12
const TYPE_L_BEAM := 13
const TYPE_HEX_PRISM := 14
const TYPE_PYRAMID := 15
const TYPE_FENDER := 16
const TYPE_CANOPY := 17
const TYPE_RING := 18
const TYPE_INNER_CORNER := 19
const TYPE_OUTER_CORNER := 20

# Geometric tolerance. Coordinates here are hull-space metres (hulls run ~2-16
# units), so 1e-5 is comfortably below any authored feature yet far above float
# noise in the clipping arithmetic.
const EPS := 0.00001

# Degenerate polygons below this area are dropped rather than emitted as slivers.
const MIN_FACE_AREA := 0.000001


# ── Public API ────────────────────────────────────────────────────────────

# primitives: same array shape sdf_mesh_baker.gd takes - dictionaries with
#   type / position / rotation / scale.
# facets: how many segments a curved primitive is approximated with. Curved
#   shapes have no exact polyhedral form, so they become convex prisms/domes at
#   this segment count. Planar primitives ignore it entirely and are exact.
# chamfer_pct: chamfer size for CHAMFER_BOX, as a percentage of its smallest
#   half-extent. Matches sdf_mesh_baker.gd's 15% default.
static func bake(primitives: Array, facets: int = 12, chamfer_pct: float = 15.0) -> ArrayMesh:
	if primitives.is_empty():
		return null

	# Every primitive becomes one or more convex pieces. A piece is an Array of
	# Planes with OUTWARD normals, so "inside" is every distance <= 0.
	var pieces: Array = []
	var piece_owner: Array = []  # index of the primitive each piece came from
	for i in range(primitives.size()):
		for piece in _primitive_to_pieces(primitives[i], facets, chamfer_pct):
			if piece.size() >= 4:
				pieces.append(piece)
				piece_owner.append(i)
	if pieces.is_empty():
		return null

	# Scene extent, used to size the starting quad each face is carved out of.
	var extent := _scene_extent(primitives)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var emitted := 0

	for pi in range(pieces.size()):
		var planes: Array = pieces[pi]
		for fi in range(planes.size()):
			var face: PackedVector3Array = _face_polygon(planes, fi, extent)
			if face.size() < 3:
				continue
			var plane: Plane = planes[fi]

			# Carve away everything covered by another piece.
			var parts: Array = [face]
			for qi in range(pieces.size()):
				if qi == pi:
					continue
				if parts.is_empty():
					break
				var next_parts: Array = []
				for part in parts:
					next_parts.append_array(_subtract_piece(part, pieces[qi], plane, pi, qi))
				parts = next_parts

			for part in parts:
				emitted += _emit_polygon(st, part, plane.normal)

	if emitted == 0:
		return null
	return st.commit()


# ── Union boundary ────────────────────────────────────────────────────────

# Returns the parts of `poly` that are NOT inside piece `q`.
#
# `poly_plane`, `pi` and `qi` exist only to resolve the coplanar case, which is
# common and matters: two stacked boxes share a face plane, and naive "inside"
# testing either deletes that surface from both (a hole) or keeps it on both
# (z-fighting duplicates).
static func _subtract_piece(poly: PackedVector3Array, q: Array,
		poly_plane: Plane, pi: int, qi: int) -> Array:
	# Is the polygon coplanar with one of q's faces?
	var cop := -1
	var same_facing := false
	for i in range(q.size()):
		if _polygon_on_plane(poly, q[i]):
			cop = i
			same_facing = poly_plane.normal.dot((q[i] as Plane).normal) > 0.0
			break

	if cop >= 0:
		# CRITICAL: being coplanar with one of q's planes does NOT mean the
		# polygon is on q's surface. It only means it lies in the same infinite
		# plane. The overlap is the part of the polygon that is also within q's
		# OTHER half-spaces; everything else is nowhere near q and must survive
		# untouched.
		#
		# Deciding on coplanarity alone deleted whole faces. A RING is built from
		# `seg` sector blocks stacked around the annulus, and every block's top
		# face shares the ring's top plane - so the tie-break threw away the top
		# and bottom faces of all but the first block, even though the blocks
		# occupy disjoint angular sectors and never overlap. The ring lost 33% of
		# its volume, which is what dragged heavy_hull and medium_hull ~10% under
		# their true volume.
		var others: Array = []
		for i in range(q.size()):
			if i != cop:
				others.append(q[i])
		if others.is_empty():
			return [poly]
		if same_facing and qi > pi:
			# Same-facing shared surface, and this piece is the designated owner:
			# emit all of it, including the shared part. The other piece will drop
			# its copy when it runs this test, so the surface appears exactly once.
			return [poly]
		# Either q owns the shared region (lowest index wins, deterministically),
		# or the normals oppose and the shared region is interior to the union.
		# Both mean: keep everything except the overlap.
		return _peel_outside(poly, others)

	return _peel_outside(poly, q)


# The parts of `poly` lying outside the convex intersection of `planes`.
#
# F \ Q = U over i of ( F ∩ h_1 ∩ .. ∩ h_(i-1) ∩ outside(h_i) ) - peel off the
# part outside the current plane (it can never be inside Q), carry the rest
# forward. Whatever survives every plane is inside Q and is discarded.
static func _peel_outside(poly: PackedVector3Array, planes: Array) -> Array:
	var out: Array = []
	var rem: PackedVector3Array = poly
	for h in planes:
		var outside: PackedVector3Array = _clip(rem, h, false)
		if outside.size() >= 3 and _polygon_area(outside) > MIN_FACE_AREA:
			out.append(outside)
		rem = _clip(rem, h, true)
		if rem.size() < 3:
			return out  # nothing left inside the intersection
	return out


# Sutherland-Hodgman clip of a polygon by a plane.
# keep_inside: keep distance <= 0 (the solid side). Otherwise keep distance >= 0.
static func _clip(poly: PackedVector3Array, plane: Plane, keep_inside: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := poly.size()
	if n == 0:
		return out
	var sign := 1.0 if keep_inside else -1.0
	for i in range(n):
		var a: Vector3 = poly[i]
		var b: Vector3 = poly[(i + 1) % n]
		# da/db < 0 means "on the side we are keeping".
		var da: float = sign * plane.distance_to(a)
		var db: float = sign * plane.distance_to(b)
		var a_in: bool = da <= EPS
		var b_in: bool = db <= EPS
		if a_in:
			out.append(a)
		if a_in != b_in:
			var denom: float = da - db
			if absf(denom) > 1e-12:
				var t: float = da / denom
				if t > 0.0 and t < 1.0:
					out.append(a.lerp(b, t))
	return out


# ── Faces of a convex piece ───────────────────────────────────────────────

# The polygon of face `fi`: start with a quad on that plane big enough to cover
# the whole assembly, then clip it by every other plane of the piece. What
# remains is exactly that face.
static func _face_polygon(planes: Array, fi: int, extent: float) -> PackedVector3Array:
	var plane: Plane = planes[fi]
	var n: Vector3 = plane.normal
	# Any two vectors spanning the plane.
	var u: Vector3 = Vector3(0, 0, 1).cross(n)
	if u.length_squared() < 0.001:
		u = Vector3(1, 0, 0).cross(n)
	u = u.normalized()
	var v: Vector3 = n.cross(u).normalized()
	var origin: Vector3 = n * plane.d
	var r: float = extent
	# Wound so the polygon's own normal agrees with the plane normal.
	var quad := PackedVector3Array([
		origin - u * r - v * r,
		origin + u * r - v * r,
		origin + u * r + v * r,
		origin - u * r + v * r,
	])
	if (quad[1] - quad[0]).cross(quad[2] - quad[0]).dot(n) > 0.0:
		quad.reverse()  # swapped logic for clockwise

	var poly := quad
	for j in range(planes.size()):
		if j == fi:
			continue
		poly = _clip(poly, planes[j], true)
		if poly.size() < 3:
			return PackedVector3Array()
	return poly


static func _polygon_on_plane(poly: PackedVector3Array, plane: Plane) -> bool:
	for p in poly:
		if absf(plane.distance_to(p)) > EPS * 10.0:
			return false
	return true


static func _polygon_area(poly: PackedVector3Array) -> float:
	if poly.size() < 3:
		return 0.0
	var acc := Vector3.ZERO
	for i in range(1, poly.size() - 1):
		acc += (poly[i] - poly[0]).cross(poly[i + 1] - poly[0])
	return acc.length() * 0.5


# Fan-triangulates a convex polygon. Returns the triangle count.
static func _emit_polygon(st: SurfaceTool, poly: PackedVector3Array, normal: Vector3) -> int:
	if poly.size() < 3 or _polygon_area(poly) <= MIN_FACE_AREA:
		return 0
	var count := 0
	for i in range(1, poly.size() - 1):
		var a: Vector3 = poly[0]
		var b: Vector3 = poly[i]
		var c: Vector3 = poly[i + 1]
		if (b - a).cross(c - a).length_squared() < 1e-14:
			continue
		# Flat per-face normal from the exact plane - this is what gives hard
		# edges with no shading gradient across a panel.
		st.set_normal(normal)
		st.add_vertex(a)
		st.set_normal(normal)
		st.add_vertex(b)
		st.set_normal(normal)
		st.add_vertex(c)
		count += 1
	return count


static func _scene_extent(primitives: Array) -> float:
	var m := 1.0
	for prim in primitives:
		var pos: Vector3 = prim.position
		var s: Vector3 = (prim.scale as Vector3).abs()
		m = max(m, pos.length() + s.length())
	return m * 2.0


# ── Primitive -> convex pieces ────────────────────────────────────────────

static func _primitive_to_pieces(prim: Dictionary, facets: int, chamfer_pct: float) -> Array:
	var basis := Basis.from_euler(prim.rotation)
	var pos: Vector3 = prim.position
	var h: Vector3 = (prim.scale as Vector3).abs() * 0.5
	h = Vector3(max(h.x, EPS), max(h.y, EPS), max(h.z, EPS))
	var seg: int = maxi(facets, 4)

	match int(prim.type):
		TYPE_BOX:
			return [_box(pos, basis, h)]
		TYPE_CHAMFER_BOX:
			return [_chamfer_box(pos, basis, h, chamfer_pct)]
		TYPE_SLOPE:
			return [_slope(pos, basis, h)]
		TYPE_WEDGE:
			return [_wedge(pos, basis, h)]
		TYPE_FRUSTUM:
			return [_frustum(pos, basis, h, 0.5)]
		TYPE_PYRAMID:
			return [_frustum(pos, basis, h, 0.0)]
		TYPE_I_BEAM:
			# Non-convex: a union of three boxes, exactly as _sdf_i_beam builds it.
			var ft: float = h.x * 0.3
			var wt: float = h.y * 0.3
			return [
				_box(pos + basis * Vector3(0, h.y - ft, 0), basis, Vector3(h.x, ft, h.z)),
				_box(pos + basis * Vector3(0, -(h.y - ft), 0), basis, Vector3(h.x, ft, h.z)),
				_box(pos, basis, Vector3(wt, h.y, h.z)),
			]
		TYPE_L_BEAM:
			var t: float = min(h.x, h.y) * 0.35
			return [
				_box(pos + basis * Vector3(-(h.x - t), 0, 0), basis, Vector3(t, h.y, h.z)),
				_box(pos + basis * Vector3(0, -(h.y - t), 0), basis, Vector3(h.x, t, h.z)),
			]
		TYPE_HEX_PRISM:
			return [_ngon_prism(pos, basis, h, 6, Vector3.AXIS_Z)]
		TYPE_CYLINDER:
			return [_ngon_prism(pos, basis, h, seg, Vector3.AXIS_Y)]
		TYPE_HALF_CYLINDER:
			return [_half_cylinder(pos, basis, h, seg)]
		TYPE_CONE:
			return [_cone(pos, basis, h, seg)]
		TYPE_SPHERE:
			return [_ellipsoid(pos, basis, h, seg, false)]
		TYPE_HEMISPHERE, TYPE_CANOPY:
			return [_ellipsoid(pos, basis, h, seg, true)]
		TYPE_CAPSULE:
			# Approximated as a stadium-section prism: a cylinder with the caps
			# faceted in, which is convex and close enough at these sizes.
			return [_ellipsoid(pos, basis, h, seg, false)]
		TYPE_RING, TYPE_TORUS, TYPE_FENDER:
			return _annulus(pos, basis, h, seg, int(prim.type))
		TYPE_INNER_CORNER:
			return [_inner_corner(pos, basis, h)]
		TYPE_OUTER_CORNER:
			return [_outer_corner(pos, basis, h)]
		_:
			return [_box(pos, basis, h)]


static func _plane_from(normal_local: Vector3, point_local: Vector3, pos: Vector3, basis: Basis) -> Plane:
	var n: Vector3 = (basis * normal_local).normalized()
	var p: Vector3 = pos + basis * point_local
	return Plane(n, n.dot(p))


static func _box(pos: Vector3, basis: Basis, h: Vector3) -> Array:
	return [
		_plane_from(Vector3(1, 0, 0), Vector3(h.x, 0, 0), pos, basis),
		_plane_from(Vector3(-1, 0, 0), Vector3(-h.x, 0, 0), pos, basis),
		_plane_from(Vector3(0, 1, 0), Vector3(0, h.y, 0), pos, basis),
		_plane_from(Vector3(0, -1, 0), Vector3(0, -h.y, 0), pos, basis),
		_plane_from(Vector3(0, 0, 1), Vector3(0, 0, h.z), pos, basis),
		_plane_from(Vector3(0, 0, -1), Vector3(0, 0, -h.z), pos, basis),
	]


static func _inner_corner(pos: Vector3, basis: Basis, h: Vector3) -> Array:
	return [
		_plane_from(Vector3(0, 1, 0), Vector3(0, h.y, 0), pos, basis),
		_plane_from(Vector3(0, -1, 0), Vector3(0, -h.y, 0), pos, basis),
		_plane_from(Vector3(-1, 0, 0), Vector3(-h.x, 0, 0), pos, basis),
		_plane_from(Vector3(0, 0, -1), Vector3(0, 0, -h.z), pos, basis),
		_plane_from(Vector3(1.0 / h.x, 0.0, 1.0 / h.z), Vector3(h.x, 0, -h.z), pos, basis),
	]


static func _outer_corner(pos: Vector3, basis: Basis, h: Vector3) -> Array:
	return [
		_plane_from(Vector3(0, 1, 0), Vector3(0, h.y, 0), pos, basis),
		_plane_from(Vector3(0, -1, 0), Vector3(0, -h.y, 0), pos, basis),
		_plane_from(Vector3(1, 0, 0), Vector3(h.x, 0, 0), pos, basis),
		_plane_from(Vector3(0, 0, 1), Vector3(0, 0, h.z), pos, basis),
		_plane_from(Vector3(-1.0 / h.x, 0.0, -1.0 / h.z), Vector3(h.x, 0, -h.z), pos, basis),
	]


# Box plus 45-degree cuts across all 12 edges - the exact chamfered box, matching
# sdf_mesh_baker.gd's _sdf_chamfer_box. The 8 corner facets emerge where three
# edge cuts meet; no extra planes needed.
static func _chamfer_box(pos: Vector3, basis: Basis, h: Vector3, chamfer_pct: float) -> Array:
	var c: float = min(h.x, min(h.y, h.z)) * clampf(chamfer_pct, 0.0, 90.0) / 100.0
	var planes: Array = _box(pos, basis, h)
	if c <= EPS:
		return planes
	var pairs := [[0, 1], [1, 2], [0, 2]]  # (x,y), (y,z), (x,z)
	for pair in pairs:
		var a: int = pair[0]
		var b: int = pair[1]
		for sa in [-1.0, 1.0]:
			for sb in [-1.0, 1.0]:
				var nl := Vector3.ZERO
				nl[a] = sa
				nl[b] = sb
				# Cut passes through the point where the chamfer meets each face.
				var pl := Vector3.ZERO
				pl[a] = sa * (h[a] - c)
				pl[b] = sb * h[b]
				planes.append(_plane_from(nl, pl, pos, basis))
	return planes


# Single 45-degree cut through the top-front edge (+Y, -Z), scaled relative to
# the half-extents exactly as sdf_mesh_baker.gd's _sdf_slope does.
static func _slope(pos: Vector3, basis: Basis, h: Vector3) -> Array:
	var planes: Array = _box(pos, basis, h)
	var nl := Vector3(0.0, 1.0 / h.y, -1.0 / h.z)
	var pl := Vector3(0.0, h.y, -0.3 * h.z)
	planes.append(_plane_from(nl, pl, pos, basis))
	return planes


# Full-height at -Z tapering to zero height at +Z - matches _sdf_wedge.
static func _wedge(pos: Vector3, basis: Basis, h: Vector3) -> Array:
	return [
		_plane_from(Vector3(1, 0, 0), Vector3(h.x, 0, 0), pos, basis),
		_plane_from(Vector3(-1, 0, 0), Vector3(-h.x, 0, 0), pos, basis),
		_plane_from(Vector3(0, -1, 0), Vector3(0, -h.y, 0), pos, basis),
		_plane_from(Vector3(0, 0, 1), Vector3(0, 0, h.z), pos, basis),
		_plane_from(Vector3(0, 0, -1), Vector3(0, 0, -h.z), pos, basis),
		_plane_from(Vector3(0.0, 1.0, h.y / h.z), Vector3(0, h.y, -h.z), pos, basis),
	]


# Box tapered from h at -Y to h*top_scale at +Y. top_scale 0 gives the pyramid.
static func _frustum(pos: Vector3, basis: Basis, h: Vector3, top_scale: float) -> Array:
	var planes: Array = [
		_plane_from(Vector3(0, 1, 0), Vector3(0, h.y, 0), pos, basis),
		_plane_from(Vector3(0, -1, 0), Vector3(0, -h.y, 0), pos, basis),
	]
	# Each side plane contains that side's bottom edge and its (narrower) top
	# edge. In the (axis, y) plane the side runs from (s*half, -h.y) to
	# (s*half*top_scale, +h.y), so the outward normal is that edge rotated a
	# quarter turn: (2*h.y, half*(1 - top_scale)) scaled by the side's sign.
	for axis in [0, 2]:
		for s in [-1.0, 1.0]:
			var half: float = h[axis]
			var nl := Vector3.ZERO
			nl[axis] = s * 2.0 * h.y
			nl.y = half * (1.0 - top_scale)
			var pl := Vector3.ZERO
			pl[axis] = s * half
			pl.y = -h.y
			planes.append(_plane_from(nl, pl, pos, basis))
	return planes


# Regular n-gon cross-section extruded along `axis`, inscribed in the primitive's
# box so a non-uniform scale gives an elliptical cross-section rather than
# collapsing to the narrowest radius.
static func _ngon_prism(pos: Vector3, basis: Basis, h: Vector3, sides: int, axis: int) -> Array:
	var a0: int = (axis + 1) % 3
	var a1: int = (axis + 2) % 3
	var planes: Array = [
		_plane_from(_axis_vec(axis, 1.0), _axis_vec(axis, h[axis]), pos, basis),
		_plane_from(_axis_vec(axis, -1.0), _axis_vec(axis, -h[axis]), pos, basis),
	]
	for i in range(sides):
		var ang: float = TAU * (float(i) + 0.5) / float(sides)
		var cx: float = cos(ang)
		var cy: float = sin(ang)
		# Point on the inscribed ellipse, and the ellipse's normal there.
		var pl := Vector3.ZERO
		pl[a0] = cx * h[a0]
		pl[a1] = cy * h[a1]
		var nl := Vector3.ZERO
		nl[a0] = cx / h[a0]
		nl[a1] = cy / h[a1]
		planes.append(_plane_from(nl, pl, pos, basis))
	return planes


static func _axis_vec(axis: int, v: float) -> Vector3:
	var out := Vector3.ZERO
	out[axis] = v
	return out


# Flat-bottomed half-round trough extruded along Z (matches _sdf_half_cylinder).
static func _half_cylinder(pos: Vector3, basis: Basis, h: Vector3, seg: int) -> Array:
	var planes: Array = [
		_plane_from(Vector3(0, 0, 1), Vector3(0, 0, h.z), pos, basis),
		_plane_from(Vector3(0, 0, -1), Vector3(0, 0, -h.z), pos, basis),
		_plane_from(Vector3(0, -1, 0), Vector3(0, -h.y, 0), pos, basis),
	]
	var half_seg: int = maxi(seg / 2, 2)
	for i in range(half_seg):
		var ang: float = PI * (float(i) + 0.5) / float(half_seg)
		var cx: float = cos(ang)
		var cy: float = sin(ang)
		var pl := Vector3(cx * h.x, -h.y + cy * (2.0 * h.y), 0)
		var nl := Vector3(cx / h.x, cy / (2.0 * h.y), 0)
		planes.append(_plane_from(nl, pl, pos, basis))
	return planes


# Cone with apex at +Y, base at -Y (matches _sdf_cone).
static func _cone(pos: Vector3, basis: Basis, h: Vector3, seg: int) -> Array:
	var planes: Array = [
		_plane_from(Vector3(0, -1, 0), Vector3(0, -h.y, 0), pos, basis),
	]
	for i in range(seg):
		var ang: float = TAU * (float(i) + 0.5) / float(seg)
		var cx: float = cos(ang)
		var cz: float = sin(ang)
		# Plane through the base rim point and the apex.
		var rim := Vector3(cx * h.x, -h.y, cz * h.z)
		var radial := Vector3(cx / h.x, 0.0, cz / h.z).normalized()
		var to_apex := Vector3(0, h.y, 0) - rim
		var tangent := Vector3(-cz * h.x, 0.0, cx * h.z)
		var nl := tangent.cross(to_apex).normalized()
		if nl.dot(radial) < 0.0:
			nl = -nl
		planes.append(_plane_from(nl, rim, pos, basis))
	return planes


# Faceted ellipsoid, or the upper half of one for dome/canopy types. Latitude
# rings x longitude segments, each facet contributing one tangent plane.
static func _ellipsoid(pos: Vector3, basis: Basis, h: Vector3, seg: int, dome: bool) -> Array:
	var planes: Array = []
	# Dome sits on the primitive's floor with its apex at the ceiling, matching
	# sdf_mesh_baker.gd's _sdf_dome.
	var centre_y: float = -h.y if dome else 0.0
	var ry: float = (h.y * 2.0) if dome else h.y
	if dome:
		planes.append(_plane_from(Vector3(0, -1, 0), Vector3(0, -h.y, 0), pos, basis))
	var lat_count: int = maxi(seg / 2, 3)
	var lat_lo: float = 0.0 if dome else -PI * 0.5
	for li in range(lat_count):
		var t0: float = float(li) + 0.5
		var lat: float = lat_lo + (PI * 0.5 - lat_lo) * (t0 / float(lat_count)) if dome \
			else (-PI * 0.5 + PI * (t0 / float(lat_count)))
		var cy: float = sin(lat)
		var cr: float = cos(lat)
		for si in range(seg):
			var ang: float = TAU * (float(si) + 0.5) / float(seg)
			var cx: float = cos(ang) * cr
			var cz: float = sin(ang) * cr
			var pl := Vector3(cx * h.x, centre_y + cy * ry, cz * h.z)
			var nl := Vector3(cx / h.x, cy / ry, cz / h.z)
			if nl.length_squared() < 1e-12:
				continue
			planes.append(_plane_from(nl, pl, pos, basis))
	return planes


# Ring / torus / fender are NOT convex - they have a hole. Decomposed into `seg`
# convex blocks swept around the annulus, which is exact for RING (a square-
# section washer) and a good faceting of the round-section TORUS and the
# half-arch FENDER.
static func _annulus(pos: Vector3, basis: Basis, h: Vector3, seg: int, type: int) -> Array:
	var r_out: float
	var r_in: float
	var half_h: float
	match type:
		TYPE_RING:
			r_out = min(h.x, h.z)
			r_in = r_out * 0.6
			half_h = h.y
		TYPE_TORUS:
			var r_major: float = min(h.x, h.z) * 0.8
			var r_minor: float = min(h.x, min(h.y, h.z)) * 0.2
			r_out = r_major + r_minor
			r_in = max(r_major - r_minor, EPS)
			half_h = r_minor
		_:  # TYPE_FENDER - half arch, upper half only
			var fr: float = min(h.x, h.z)
			var ft: float = min(h.y, h.z) * 0.3
			r_out = fr + ft
			r_in = max(fr - ft, EPS)
			half_h = ft

	var full: bool = type != TYPE_FENDER
	var count: int = seg if full else maxi(seg / 2, 3)
	var span: float = TAU if full else PI
	var out: Array = []
	for i in range(count):
		var a0: float = span * float(i) / float(count)
		var a1: float = span * float(i + 1) / float(count)
		var p00 := Vector3(cos(a0) * r_in, 0, sin(a0) * r_in)
		var p01 := Vector3(cos(a0) * r_out, 0, sin(a0) * r_out)
		var p10 := Vector3(cos(a1) * r_in, 0, sin(a1) * r_in)
		var p11 := Vector3(cos(a1) * r_out, 0, sin(a1) * r_out)
		# Convex block: top/bottom, the two radial cut planes, and inner/outer.
		var planes: Array = [
			_plane_from(Vector3(0, 1, 0), Vector3(0, half_h, 0), pos, basis),
			_plane_from(Vector3(0, -1, 0), Vector3(0, -half_h, 0), pos, basis),
		]
		# Radial side at a0 (outward normal points back, away from the sector).
		var n0 := Vector3(sin(a0), 0, -cos(a0))
		var n1 := Vector3(-sin(a1), 0, cos(a1))
		planes.append(_plane_from(n0, p00, pos, basis))
		planes.append(_plane_from(n1, p10, pos, basis))
		# Outer chord plane through the two outer corners.
		var outward := ((p01 + p11) * 0.5).normalized()
		planes.append(_plane_from(outward, p01, pos, basis))
		# Inner chord plane, facing inward (towards the hole).
		var inward := -((p00 + p10) * 0.5).normalized()
		planes.append(_plane_from(inward, p00, pos, basis))
		out.append(planes)
	return out
