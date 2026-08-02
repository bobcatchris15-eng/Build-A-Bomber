extends RefCounted
class_name HullProjection
# Surface projection for decals and greeble cards.
#
# hull_decals.gd and hull_greebles.gd used to place every card at a hardcoded
# fraction of the hull's *declared catalog size* - Vector3(x * 0.32, y * 0.62,
# z * 0.46) and friends. That was wrong three separate ways, which is why the
# decals visibly floated off the hull:
#
#   1. The catalog size is a design-time bounding box, not the baked mesh's
#      real extents. Since the hull roster moved to the CSG/SDF bake pipeline,
#      a hull is routinely narrower, lower, or more tapered than its declared
#      box - so a card pinned to the box hangs in mid-air.
#   2. ModuleCatalog.get_hull_mesh_fit() recentres a hull's geometry on the
#      hull origin, so the roof is at +0.5 * size.y. The decal code used
#      0.62 * size.y, i.e. deliberately 12% of the hull's height ABOVE the
#      roof. The comment called that "a real margin" against z-fighting, but
#      it is a large visible gap at hull scale, not a depth-bias epsilon.
#   3. Even with exact extents, a fixed fraction of an AABB only touches the
#      surface on a literal box. On a sloped glacis, a curved airship, or a
#      flying wing, it is inside the hull or well outside it, and the card's
#      rotation (a hardcoded Euler) does not match the surface it is
#      supposedly stuck to.
#
# So instead of guessing a point, this raycasts the hull's REAL triangles and
# returns the actual surface hit plus its normal. A caller says "put this
# roughly here on the roof" in normalized box coordinates and gets back a
# point genuinely on the skin, oriented to it.
#
# Deliberately pure math (Moller-Trumbore against Mesh.get_faces()) rather
# than PhysicsDirectSpaceState raycasts:
#   - decals are applied during hull construction, before the node is in the
#     tree and before any physics step has run, so a space-state query would
#     have nothing to hit;
#   - it works headless, which the roster/test tooling needs;
#   - it does not depend on hull_surface.gd's collider existing or being on
#     the layer this happens to query.

# Small outward push so an exactly-on-surface quad does not z-fight the hull.
# Scaled to the hull so it stays visually invisible on a 2-unit scout and on a
# 12-unit airship alike, with an absolute floor for tiny props.
const OFFSET_FRACTION: float = 0.0025
const OFFSET_MIN: float = 0.002

# Containers whose own geometry must never be treated as hull surface -
# otherwise a rebuild would project the new decals onto the previous pass's
# decal quads.
# "ArmorGreebles" added when armor_greebles.gd landed: it runs BEFORE
# hull_decals in both call sites, so without the exclusion every decal
# projected onto the energy shield's ellipsoid (a big mesh enclosing the whole
# hull) and onto the rivet field, instead of onto the hull skin.
# "RunningGear" joins the list now that the chassis actually has geometry: it is
# a structural frame bolted UNDER the hull, not hull skin, so rivets should not
# grow out of its cross-members and unit markings should not project onto its
# belly plate - the same reasoning that excludes placed modules.
const EXCLUDED_NODES := ["HullDecals", "HullGreebles", "ArmorGreebles", "RunningGear"]

# The meta every PLACED MODULE carries (set by module_placer.gd and
# blueprint_manager.gd before they parent it to the hull). Modules are children
# of the hull node, so without this check a hull that already has a turret on it
# reports the turret's barrel as hull surface: decals project onto gun mantlets
# and rivets grow out of missile pods. A module is a thing bolted TO the skin,
# never part of it.
#
# Keyed on the meta rather than on node names because module nodes are named
# per-instance, and rather than on a group because these run during
# construction, before the node is necessarily in the tree.
const MODULE_META := "module_data"

const RAY_EPS: float = 0.000001


# Gathers every visible hull triangle in `host`'s local space.
#
# Returns {"tris": PackedVector3Array (flat, 3 verts per tri), "aabb": AABB}.
# An empty tris array is a legitimate result (a host with no mesh yet) and
# callers fall back to plain AABB placement.
static func build_surface(host: Node3D) -> Dictionary:
	var tris := PackedVector3Array()
	_gather(host, host, Transform3D.IDENTITY, tris)
	var aabb := AABB()
	var first := true
	for v in tris:
		if first:
			aabb = AABB(v, Vector3.ZERO)
			first = false
		else:
			aabb = aabb.expand(v)
	return {"tris": tris, "aabb": aabb}


static func _gather(node: Node, host: Node3D, xform: Transform3D, tris: PackedVector3Array) -> void:
	if node != host:
		if node.name in EXCLUDED_NODES:
			return
		if node.has_meta(MODULE_META):
			return
		if node is Node3D:
			var n3d := node as Node3D
			# An invisible MeshInstance3D is either the never-drawn physics
			# duplicate module_placer.gd/blueprint_manager.gd add alongside the
			# visual mesh, or something genuinely hidden. Neither is surface
			# the player can see a decal sitting on, and counting the physics
			# duplicate would double every triangle.
			if not n3d.visible:
				return
			xform = xform * n3d.transform
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh:
			var faces := mesh.get_faces()
			for v in faces:
				tris.append(xform * v)
	for child in node.get_children():
		_gather(child, host, xform, tris)


# Casts a ray and returns the FIRST surface hit along it.
#
# Returns {"hit": bool, "position": Vector3, "normal": Vector3}. The normal is
# geometric (from the winding) and flipped to face back toward the ray origin,
# so a decal always ends up on the side the caster came from even if a hull's
# winding is locally inverted.
static func raycast(surface: Dictionary, from: Vector3, dir: Vector3) -> Dictionary:
	var miss := {"hit": false, "position": from, "normal": -dir}
	var tris: PackedVector3Array = surface.get("tris", PackedVector3Array())
	if tris.size() < 3 or dir.length_squared() <= 0.0:
		return miss
	var d := dir.normalized()
	var best_t := INF
	var best_n := Vector3.ZERO
	var i := 0
	while i + 2 < tris.size():
		var a := tris[i]
		var e1 := tris[i + 1] - a
		var e2 := tris[i + 2] - a
		var pv := d.cross(e2)
		var det := e1.dot(pv)
		# Two-sided: a hull's winding is not guaranteed locally consistent, and
		# rejecting backfaces here would punch holes in the projection.
		if absf(det) > RAY_EPS:
			var inv_det := 1.0 / det
			var tv := from - a
			var u := tv.dot(pv) * inv_det
			if u >= 0.0 and u <= 1.0:
				var qv := tv.cross(e1)
				var v := d.dot(qv) * inv_det
				if v >= 0.0 and u + v <= 1.0:
					var t := e2.dot(qv) * inv_det
					if t > RAY_EPS and t < best_t:
						best_t = t
						best_n = e1.cross(e2)
		i += 3
	if best_t == INF:
		return miss
	var n := best_n.normalized() if best_n.length_squared() > 0.0 else -d
	if n.dot(d) > 0.0:
		n = -n
	return {"hit": true, "position": from + d * best_t, "normal": n}


# The main entry point. Places a card on the hull skin near a requested spot.
#
# `anchor` is in normalized surface-AABB coordinates (0..1 per axis), so a
# caller describes intent - "centred, a bit forward, on the roof" is
# Vector3(0.5, 1.0, 0.6) - without knowing the hull's real dimensions.
# `axis` is the face to approach from, e.g. Vector3.UP for the roof or
# Vector3.RIGHT for the starboard flank. The ray starts outside the AABB on
# that side and travels inward, so it lands on the outer skin rather than an
# interior wall.
#
# Returns {"hit": bool, "position": Vector3, "normal": Vector3, "basis":
# Basis} where `basis` orients a QuadMesh (which faces local +Z) flat against
# the surface, and `position` already carries the anti-z-fighting offset.
static func project(surface: Dictionary, anchor: Vector3, axis: Vector3) -> Dictionary:
	var aabb: AABB = surface.get("aabb", AABB())
	var size: Vector3 = aabb.size
	var a := axis.normalized()

	# Start clear of the AABB along the approach axis, and clamp the two
	# tangential coordinates inside it so a ray aimed at a corner still has
	# hull in front of it.
	var start := aabb.position + Vector3(
		size.x * clampf(anchor.x, 0.0, 1.0),
		size.y * clampf(anchor.y, 0.0, 1.0),
		size.z * clampf(anchor.z, 0.0, 1.0))
	var reach: float = size.length() + 1.0
	start += a * reach

	var axis_i := _dominant(a)
	# How far a hit may sit below the bounding box face along the approach axis
	# and still count as "the outer skin". A hull's real surface is a slope or a
	# curve, so some depth is normal (heavy_hull's raked rear deck is 23% in);
	# 4 units into a 7-unit hull is not.
	var depth_limit: float = size[axis_i] * 0.3
	var hit := raycast(surface, start, -a)

	# Two failure modes to recover from, both of which the old hardcoded
	# placement simply had no concept of:
	#
	#   MISS - the anchor sits over a genuine void. The flying wing has no hull
	#   at all at 68% span, so the ray hits nothing (measured 1.03 units of
	#   float when this fell back to the bounding box face).
	#
	#   TOO DEEP - the anchor sits over an OPENING. transport_hull's tailgate
	#   only exists up to 50% height; above that it is an open cargo bed, so a
	#   ray aimed at 78% travels 4 units into the vehicle and lands on the
	#   cab's rear bulkhead. That is a real, correctly-oriented surface, which
	#   is exactly why a plain "did it hit?" test accepts it - and it would put
	#   a hazard stripe deep inside the cargo bay.
	#
	# Both are handled by walking the anchor toward the hull's centre until a
	# ray lands on something shallow, keeping the shallowest candidate seen as
	# the fallback. The decal ends up slightly inboard of where it was asked
	# for, which beats mid-air or buried.
	if (not hit["hit"]) or _depth(hit, aabb, size, a, axis_i) > depth_limit:
		var best := hit if hit["hit"] else {}
		var best_depth: float = _depth(hit, aabb, size, a, axis_i) if hit["hit"] else INF
		var centre := Vector3(0.5, 0.5, 0.5)
		for step in range(1, 9):
			var t: float = float(step) / 9.0
			var pulled: Vector3 = anchor.lerp(centre, t)
			# Keep the approach-axis coordinate pinned - pulling it inward would
			# start the ray inside the hull.
			pulled[axis_i] = anchor[axis_i]
			var retry_start := aabb.position + Vector3(
				size.x * clampf(pulled.x, 0.0, 1.0),
				size.y * clampf(pulled.y, 0.0, 1.0),
				size.z * clampf(pulled.z, 0.0, 1.0)) + a * reach
			var retry := raycast(surface, retry_start, -a)
			if not retry["hit"]:
				continue
			var d: float = _depth(retry, aabb, size, a, axis_i)
			if d < best_depth:
				best_depth = d
				best = retry
			if d <= depth_limit:
				break
		if not best.is_empty():
			hit = best

	var pos: Vector3
	var normal: Vector3
	if hit["hit"]:
		pos = hit["position"]
		normal = hit["normal"]
	else:
		# No triangle along that ray (a hull with a genuine hole there, or a
		# host with no mesh at all). Fall back to the AABB's own face, which is
		# the old behaviour minus the spurious hover.
		normal = a
		pos = aabb.position + Vector3(
			size.x * clampf(anchor.x, 0.0, 1.0),
			size.y * clampf(anchor.y, 0.0, 1.0),
			size.z * clampf(anchor.z, 0.0, 1.0))
		# Snap the approach axis' component to the AABB face.
		var face_val: float = aabb.position[_dominant(a)] + (size[_dominant(a)] if a[_dominant(a)] > 0.0 else 0.0)
		pos[_dominant(a)] = face_val

	var offset: float = maxf(size.length() * OFFSET_FRACTION, OFFSET_MIN)
	return {
		"hit": hit["hit"],
		"position": pos + normal * offset,
		"normal": normal,
		"basis": basis_for_normal(normal),
	}


# A conforming decal mesh: a subdivided sheet whose every vertex is
# individually projected onto the hull, so it DRAPES over the real surface
# instead of being a single flat card tangent at one point.
#
# A single quad is fine for a small decal, but hull_greebles.gd's camo netting
# is nearly hull-sized, and one flat quad tangent to a curved airship or a
# stepped flank stands off at a visibly wrong angle at its far corners - it
# reads as a rigid billboard stuck on at a perpendicular, not as netting thrown
# over the hull. Subdividing and projecting each vertex is what makes it drape.
#
# `anchor` is the sheet's CENTRE in normalized surface-AABB coordinates,
# `extent_a`/`extent_b` are its world-space dimensions along the two tangent
# axes of `axis`, and UVs span 0..1 across the whole sheet so an existing
# cutout texture maps unchanged.
#
# Cells whose corners do not all land on hull are dropped, so a sheet thrown
# across the flying wing's cut-away tail stops at the edge of the real
# geometry rather than bridging the gap.
static func conforming_sheet(surface: Dictionary, anchor: Vector3, axis: Vector3,
		extent_a: float, extent_b: float, subdiv: int = 8) -> ArrayMesh:
	var aabb: AABB = surface.get("aabb", AABB())
	var size: Vector3 = aabb.size
	var a := axis.normalized()
	var frame := basis_for_normal(a)
	var ta: Vector3 = frame.x
	var tb: Vector3 = frame.y
	var reach: float = size.length() + 1.0
	var centre := aabb.position + Vector3(
		size.x * clampf(anchor.x, 0.0, 1.0),
		size.y * clampf(anchor.y, 0.0, 1.0),
		size.z * clampf(anchor.z, 0.0, 1.0))
	var offset: float = maxf(size.length() * OFFSET_FRACTION, OFFSET_MIN)

	# With no geometry at all (a bare host, or a hull whose MeshInstance3D does
	# not exist yet) the sheet degenerates to a flat one on the fallback AABB
	# face. It has nothing to conform TO, but it must still produce a mesh -
	# returning null there would silently drop the greeble entirely.
	var no_geo: bool = (surface.get("tris", PackedVector3Array()) as PackedVector3Array).size() < 3
	var face := centre
	if no_geo:
		var d := _dominant(a)
		face[d] = aabb.position[d] + (size[d] if a[d] > 0.0 else 0.0)

	var n := maxi(subdiv, 1)
	var pts := []
	var ok := []
	for i in range(n + 1):
		for j in range(n + 1):
			var u := float(i) / float(n)
			var v := float(j) / float(n)
			var tangential := ta * ((u - 0.5) * extent_a) + tb * ((v - 0.5) * extent_b)
			if no_geo:
				pts.append(face + tangential + a * offset)
				ok.append(true)
				continue
			var start := centre + tangential + a * reach
			var hit := raycast(surface, start, -a)
			if hit["hit"]:
				pts.append((hit["position"] as Vector3) + (hit["normal"] as Vector3) * offset)
				ok.append(true)
			else:
				pts.append(Vector3.ZERO)
				ok.append(false)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var emitted := 0
	for i in range(n):
		for j in range(n):
			var i00 := i * (n + 1) + j
			var i10 := (i + 1) * (n + 1) + j
			var i01 := i * (n + 1) + j + 1
			var i11 := (i + 1) * (n + 1) + j + 1
			if not (ok[i00] and ok[i10] and ok[i01] and ok[i11]):
				continue
			var u0 := float(i) / float(n)
			var u1 := float(i + 1) / float(n)
			var v0 := float(j) / float(n)
			var v1 := float(j + 1) / float(n)
			_sheet_tri(st, pts[i00], pts[i10], pts[i11], Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1))
			_sheet_tri(st, pts[i00], pts[i11], pts[i01], Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1))
			emitted += 2
	if emitted == 0:
		return null
	st.generate_normals()
	return st.commit()


static func _sheet_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	st.set_uv(ua); st.add_vertex(a)
	st.set_uv(ub); st.add_vertex(b)
	st.set_uv(uc); st.add_vertex(c)


# Non-uniform scale compensation.
#
# A decal container is a child of its host, so it inherits the host's scale.
# building.gd attaches decals straight to a mesh instance it has stretched
# per-axis onto the building's footprint (scale like (1.4, 0.8, 1.1)), which
# squashed every circular badge into an ellipse and skewed the stencil digits.
# Giving the container the inverse scale cancels that exactly, so cards render
# in the host's own units regardless of how the host was fitted.
#
# Returns the inverse scale to put on the container, plus the forward scale a
# host-space target position must be multiplied by to survive the round trip.
static func attach_compensation(host: Node3D) -> Dictionary:
	var s := host.scale if host else Vector3.ONE
	var inv := Vector3(
		1.0 / s.x if absf(s.x) > 0.000001 else 1.0,
		1.0 / s.y if absf(s.y) > 0.000001 else 1.0,
		1.0 / s.z if absf(s.z) > 0.000001 else 1.0)
	return {"container_scale": inv, "position_scale": Vector3(1.0 / inv.x, 1.0 / inv.y, 1.0 / inv.z)}


# How far a hit sits below the bounding box face along the approach axis.
static func _depth(hit: Dictionary, aabb: AABB, size: Vector3, a: Vector3, axis_i: int) -> float:
	var face: float = aabb.position[axis_i] + (size[axis_i] if a[axis_i] > 0.0 else 0.0)
	return absf(face - (hit["position"] as Vector3)[axis_i])


static func _dominant(v: Vector3) -> int:
	var ax := absf(v.x)
	var ay := absf(v.y)
	var az := absf(v.z)
	if ax >= ay and ax >= az:
		return 0
	return 1 if ay >= az else 2


# Builds an orthonormal basis whose local +Z is `normal`, i.e. a QuadMesh's
# facing direction. The up-reference is picked away from the normal so a roof
# decal (normal == UP, where UP would be degenerate) still gets a stable
# rotation instead of a NaN basis.
static func basis_for_normal(normal: Vector3) -> Basis:
	var z := normal.normalized()
	if z.length_squared() <= 0.0:
		return Basis.IDENTITY
	var up := Vector3.UP
	if absf(z.dot(up)) > 0.99:
		# Facing straight up or down: orient the card's own "up" along the
		# hull's forward axis so roof decals read consistently nose-to-tail
		# rather than spinning with float noise.
		up = Vector3.FORWARD
	var x := up.cross(z)
	if x.length_squared() <= 0.0:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


# Basis for a card that STANDS OFF the surface rather than lying flat on it -
# hull_greebles.gd's scrap antennas, which are supposed to break the
# silhouette. Local +Y runs along the surface normal (so the card grows out of
# the hull) and local +Z faces sideways, so it is visible from an RTS camera
# orbiting the unit rather than edge-on.
#
# Not for anything gravity- or world-aligned: a banner hangs down and a tailfin
# stands up regardless of the panel they are mounted to, so those use their
# masthead/mount POINT from project() and their own world-space orientation.
static func basis_standing(normal: Vector3, facing_hint: Vector3 = Vector3.RIGHT) -> Basis:
	var y := normal.normalized()
	if y.length_squared() <= 0.0:
		return Basis.IDENTITY
	var hint := facing_hint
	if absf(y.dot(hint.normalized())) > 0.99:
		hint = Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
	var x := y.cross(hint).normalized()
	if x.length_squared() <= 0.0:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	return Basis(x, y, z)
