extends RefCounted
class_name HullFacets
# Stable per-hull facet segmentation: which triangles of a hull mesh belong to
# the same FACE, decided once at bake time and looked up at runtime.
#
# WHY THIS IS BAKED AND NOT DERIVED AT PLACEMENT TIME
# ---------------------------------------------------------------------------
# module_placer used to work out "the facet you clicked" live, by flooding out
# from the clicked triangle across coplanar neighbours. Measured across 25 drop
# points on the same face, that is not a function of the FACE - it is a function
# of where the player happened to let go:
#
#   Rackham deck   2.68 x 3.50 .. 2.68 x 3.50   centre wander 0.00m
#   Brenntal deck  2.81 x 2.54 .. 2.81 x 3.46   centre wander 0.47m
#   Brenntal flank 0.51 x 2.54 .. 1.19 x 5.60   centre wander 1.17m
#   Kestrel deck   0.22 x 0.15 .. 3.20 x 5.30   centre wander 2.10m
#
# Boxy hulls were already stable; lofted ones were not, and the Kestrel could
# hand back anything from a postage stamp to the whole hull.
#
# The obvious repair - grow until a hard edge - does not work on this roster,
# and that is a property of the art, not of the algorithm. These hulls are
# SMOOTH LOFTS (see hull_forge.py's cross-section peaks), so there is no crease
# to stop at: on the Brenntal deck a 15-degree tolerance captures 6 triangles
# (2.81 x 0.27 x 2.53) and 30 degrees captures 36 that have already spilled over
# the deck edge and down both sides (3.60 x 1.13 x 4.21). Nothing in between
# means "the deck". Seeding the tolerance from the clicked triangle instead of a
# fixed axis does not help either, because on a curved face the seed's own
# normal moves with the drop point - that variant still left 1.3-5.5m of centre
# wander.
#
# So the segmentation is computed ONCE per hull, offline, where it can afford a
# global greedy partition with a canonical ordering instead of a local flood
# from an arbitrary seed. Runtime then only has to answer "which facet contains
# this triangle", which is a lookup and therefore identical for every drop point
# on that face - drop-independence becomes structural rather than tuned.
#
# Same precedent, and the same reasoning, as the baked convex decomposition in
# tools/bake_hull_roster.gd: derive it from the shipped mesh, store it next to
# the mesh, never make the game pay for it at runtime.

# --- Segmentation tuning ----------------------------------------------------

# Half-angle of the cone a triangle must stay inside to join a facet. Applied
# TWICE, against different references, and both are load-bearing:
#
#   * against the facet's running MEAN normal, which is what lets a facet follow
#     a gentle curve (a tumblehome flank is one face, not fourteen);
#   * against the facet's SEED normal, which is what stops it following that
#     curve all the way round the hull - without it, a chain of individually
#     shallow steps walks the deck facet onto the belly.
#
# TIGHTENED from 25/42 (Chris, 2026-08-17: armor "draping across everything per
# side"). At 42 degrees of seed drift a single facet may span 84 degrees, which
# is most of a quarter turn - so the Brenntal's "front" swallowed its glacis and
# its chin and a plate on the nose wrapped around onto surfaces the player
# thinks of as different faces. The cost of tightening is more facets per hull,
# which is the right trade: a face the player can point at is worth more than a
# face that is cheap to store.
const FACET_CONE_DEG := 14.0

# Still wider than the step cone, because it bounds TOTAL drift rather than
# local smoothness - a face may legitimately curve further overall than any one
# of its triangles does from its neighbour. 20 keeps a tumblehome flank whole
# while refusing to turn a corner.
const FACET_SEED_CONE_DEG := 20.0

# Facets smaller than this fraction of the hull's total surface area are merged
# into the neighbour whose normal is closest. Without it every mast mesa and
# barbette cap authored as a cross-section peak (hull_forge.py) becomes its own
# clickable facet, and a plate dropped on the Kestrel's spine fits the spine -
# which is technically correct and useless.
const MIN_FACET_AREA_FRACTION := 0.015

# Position quantisation for vertex adjacency. mesh_weld.gd's reasoning applies:
# a faceted hull's coincident corners carry different normals, so adjacency has
# to be decided on POSITION alone or nothing is adjacent to anything.
const WELD_QUANTUM := 10000.0

# --- Plate construction tuning ---------------------------------------------

# Corner normals are averaged only across neighbouring facet triangles within
# this angle of each other. It is what keeps a hull's CHAMFERS CRISP: past this
# angle the two sides of an edge keep their own normals, so the armor turns the
# corner instead of rolling over it. Averaging across everything makes a plate
# read as a soft layer laid on top of the hull rather than as part of it.
#
# Comfortably below the 25-degree segmentation cone, so a crease that is sharp
# enough to be visible is still well inside the same facet - this splits
# SHADING and displacement, not the facet itself.
const CREASE_SPLIT_DEG := 12.0

# How far the skin floats off the hull. This is a z-fighting epsilon and
# NOTHING ELSE - armor is a surface treatment here, so any value large enough to
# read as thickness is a bug, not a tuning choice.
const PLATE_LIFT_FRACTION := 0.0025
const PLATE_LIFT_MIN := 0.004

const SIDECAR_DIR := "res://assets/models/hulls"
const SIDECAR_KEY := "facets"

# The six canonical sides, and the outward direction each one means. Matches
# ModuleCatalog.classify_facet()'s convention exactly - forward is local -Z.
const SIDE_AXES := {
	"front": Vector3(0, 0, -1), "back": Vector3(0, 0, 1),
	"left": Vector3(-1, 0, 0), "right": Vector3(1, 0, 0),
	"top": Vector3(0, 1, 0), "bottom": Vector3(0, -1, 0),
}

# A facet belongs to a side's BRUSH SET if it faces that side by at least this
# much (cos 60 degrees).
#
# WHY A FACET GETS MORE THAN ONE SIDE. classify_facet() is winner-take-all on
# the dominant axis, which is right for "which way did this shot come from" but
# wrong for "what does the front of this hull consist of". A raked glacis has a
# normal more vertical than horizontal, so dominant-axis files it under `top`
# and the front of the vehicle ends up with NO facets at all. Measured on the
# shipped roster: 15 of 94 hulls had an empty `front` that way - including every
# Kestrel, whose whole identity is a steeply sloped nose - and 16 had some side
# empty. A side-first armor brush cannot work if the most important side is
# unpaintable.
#
# So membership is weighted by max(0, dot(normal, axis)), which is just the
# facet's PROJECTED area as seen from that side. A 50-degree glacis counts ~0.64
# toward the front and ~0.77 toward the top, and is paintable from either - the
# same plate really does stop both frontal and plunging fire, which is the thing
# compute_slope_multiplier() already models on the damage side.
#
# THE THRESHOLD IS LOW ON PURPOSE, and 0.5 was measurably wrong. Coverage for a
# side divides painted projected area by the projected area of the WHOLE hull
# from that direction - so a facet excluded from the brush set still sits in the
# denominator. At 0.5, painting a side covered a mean of 0.85 of it and as
# little as 0.13 (kestrel_medium_b's front): the player clicks a flank, and most
# of that flank stays bare. Measured across all 94 hulls x 6 sides:
#
#   threshold   mean coverage   sides under 70%   mean fraction of hull painted
#     0.50          0.85              101                  0.19
#     0.25          0.92               29                  0.22
#     0.05          0.98                1                  0.28
#     0.001         1.00                0                  0.38
#
# 0.05 is where coverage becomes essentially complete without the brush turning
# greedy - at 0.001 a side brush grabs up to 80% of some hulls, because every
# facet not actively facing away counts. Sides overlapping is expected and
# correct: a chine belongs to the flank AND the deck, and armoring either should
# armor it.
const BRUSH_SIDE_MIN_WEIGHT := 0.05

# hull_type_id -> {"tri_count": int, "map": PackedInt32Array} or {} for "looked
# and there is none". Cached because every mouse-move during a drag asks.
static var _map_cache: Dictionary = {}


# --- Bake side --------------------------------------------------------------

# Partitions `mesh` into facets. Returns {"map": PackedInt32Array (one facet id
# per triangle), "count": int, "tri_count": int}.
#
# Deterministic: triangles are seeded in descending area order with the triangle
# index as tiebreak, so the same mesh always yields the same partition. That is
# the whole point - a segmentation that varied between bakes would reintroduce
# exactly the instability it exists to remove.
static func segment(mesh: Mesh) -> Dictionary:
	var faces := mesh.get_faces()
	var tri_count := faces.size() / 3
	if tri_count <= 0:
		return {"map": PackedInt32Array(), "count": 0, "tri_count": 0}

	var flip := winding_sign(mesh)
	var normals := PackedVector3Array()
	var areas := PackedFloat32Array()
	normals.resize(tri_count)
	areas.resize(tri_count)
	var total_area := 0.0
	for i in range(tri_count):
		var v0 := faces[i * 3]
		var cross := (faces[i * 3 + 1] - v0).cross(faces[i * 3 + 2] - v0)
		var len2 := cross.length_squared()
		if len2 < 1e-16:
			normals[i] = Vector3.ZERO
			areas[i] = 0.0
			continue
		var l := sqrt(len2)
		normals[i] = (cross / l) * flip
		areas[i] = l * 0.5
		total_area += areas[i]

	var adjacency := _build_adjacency(faces, tri_count)

	# Canonical seeding order: biggest triangle first. A large triangle is far
	# more likely to sit in the middle of a real face than a sliver is, so the
	# facet a face ends up with is grown from its own interior rather than from
	# whichever edge triangle happened to come first in the vertex buffer.
	var order := []
	order.resize(tri_count)
	for i in range(tri_count):
		order[i] = i
	order.sort_custom(func(a, b):
		if is_equal_approx(areas[a], areas[b]):
			return a < b
		return areas[a] > areas[b])

	var facet_of := PackedInt32Array()
	facet_of.resize(tri_count)
	facet_of.fill(-1)
	var step_cos := cos(deg_to_rad(FACET_CONE_DEG))
	var seed_cos := cos(deg_to_rad(FACET_SEED_CONE_DEG))
	var facet_count := 0

	for seed in order:
		if facet_of[seed] != -1 or areas[seed] <= 0.0:
			continue
		var id := facet_count
		facet_count += 1
		var seed_n: Vector3 = normals[seed]
		var mean := seed_n * areas[seed]
		var mean_n := seed_n
		facet_of[seed] = id
		var queue := [seed]
		while not queue.is_empty():
			var cur: int = queue.pop_back()
			for nb in adjacency[cur]:
				if facet_of[nb] != -1 or areas[nb] <= 0.0:
					continue
				var nn: Vector3 = normals[nb]
				if nn.dot(mean_n) < step_cos or nn.dot(seed_n) < seed_cos:
					continue
				facet_of[nb] = id
				mean += nn * areas[nb]
				if mean.length_squared() > 1e-12:
					mean_n = mean.normalized()
				queue.append(nb)

	var merged := _merge_small_facets(facet_of, normals, areas, adjacency,
		facet_count, total_area, tri_count)
	var summary := _summarize(faces, merged["map"], normals, areas, merged["count"])
	return {"map": merged["map"], "count": merged["count"], "tri_count": tri_count,
		"winding": flip, "normal": summary["normal"], "centroid": summary["centroid"],
		"area": summary["area"], "total_area": total_area}


# Per-facet outward normal, centroid and area, in the mesh's own (unscaled)
# local space. Everything here is a by-product of sums the segmentation already
# computes and then discards - the alternative is re-walking every triangle at
# spawn time, once per unit, for numbers that cannot change without the mesh
# changing.
#
# Both accumulators are AREA-WEIGHTED. A facet's triangles vary wildly in size
# on a lofted hull, so an unweighted mean lets a fan of slivers at one corner
# outvote the large quads that actually define where the face points and where
# its middle is.
static func _summarize(faces: PackedVector3Array, facet_of: PackedInt32Array,
		normals: PackedVector3Array, areas: PackedFloat32Array,
		count: int) -> Dictionary:
	var f_normal := PackedVector3Array()
	var f_centroid := PackedVector3Array()
	var f_area := PackedFloat32Array()
	f_normal.resize(count)
	f_centroid.resize(count)
	f_area.resize(count)

	for i in range(facet_of.size()):
		var f := facet_of[i]
		if f < 0 or f >= count:
			continue
		var a := areas[i]
		if a <= 0.0:
			continue
		var tri_c := (faces[i * 3] + faces[i * 3 + 1] + faces[i * 3 + 2]) / 3.0
		f_normal[f] += normals[i] * a
		f_centroid[f] += tri_c * a
		f_area[f] += a

	for f in range(count):
		if f_area[f] > 0.0:
			f_centroid[f] = f_centroid[f] / f_area[f]
		f_normal[f] = f_normal[f].normalized() if f_normal[f].length_squared() > 1e-12 else Vector3.UP
	return {"normal": f_normal, "centroid": f_centroid, "area": f_area}


# +1 if the mesh's triangle winding already yields outward normals, -1 if it is
# inverted. Baked rather than recomputed at runtime so a facet's outward
# direction never has to be inferred from the click - see measure().
static func winding_sign(mesh: Mesh) -> float:
	return -1.0 if _signed_volume(mesh.get_faces()) < 0.0 else 1.0


# Rolls facets below MIN_FACET_AREA_FRACTION into the adjacent facet whose mean
# normal is closest, smallest first so a chain of slivers collapses inward
# rather than each one capturing the next. Facet ids are then compacted, so the
# stored map has no holes.
static func _merge_small_facets(facet_of: PackedInt32Array, normals: PackedVector3Array,
		areas: PackedFloat32Array, adjacency: Array, facet_count: int,
		total_area: float, tri_count: int) -> Dictionary:
	if facet_count <= 1 or total_area <= 0.0:
		return {"map": facet_of, "count": facet_count}

	var facet_area := PackedFloat32Array()
	var facet_normal := PackedVector3Array()
	facet_area.resize(facet_count)
	facet_normal.resize(facet_count)
	for i in range(tri_count):
		var f := facet_of[i]
		if f < 0:
			continue
		facet_area[f] += areas[i]
		facet_normal[f] += normals[i] * areas[i]

	var small := []
	for f in range(facet_count):
		if facet_area[f] < total_area * MIN_FACET_AREA_FRACTION:
			small.append(f)
	small.sort_custom(func(a, b): return facet_area[a] < facet_area[b])

	for f in small:
		if facet_area[f] <= 0.0:
			continue
		var my_n: Vector3 = facet_normal[f].normalized() if facet_normal[f].length_squared() > 1e-12 else Vector3.UP
		var best := -1
		var best_dot := -2.0
		for i in range(tri_count):
			if facet_of[i] != f:
				continue
			for nb in adjacency[i]:
				var other := facet_of[nb]
				if other == f or other < 0:
					continue
				var on: Vector3 = facet_normal[other]
				var d: float = my_n.dot(on.normalized()) if on.length_squared() > 1e-12 else -1.0
				if d > best_dot:
					best_dot = d
					best = other
		if best < 0:
			continue
		for i in range(tri_count):
			if facet_of[i] == f:
				facet_of[i] = best
		facet_normal[best] += facet_normal[f]
		facet_area[best] += facet_area[f]
		facet_area[f] = 0.0
		facet_normal[f] = Vector3.ZERO

	# Compact ids so the stored map is 0..n-1 with no gaps.
	var remap := {}
	var next := 0
	for i in range(tri_count):
		var f := facet_of[i]
		if f < 0:
			continue
		if not remap.has(f):
			remap[f] = next
			next += 1
		facet_of[i] = remap[f]
	return {"map": facet_of, "count": next}


static func _signed_volume(faces: PackedVector3Array) -> float:
	# The shipped roster is wound INWARD - measured, only 2/180 (Brenntal),
	# 14/204 (Kestrel) and 24/284 (Orrin) triangles point away from the mesh
	# centroid. That is consistent rather than random, which is what makes a
	# single global sign flip valid and lets everything downstream use a SIGNED
	# normal test. module_placer's old abs() existed because of this and cost it
	# the ability to tell a deck from a belly.
	var vol := 0.0
	for i in range(faces.size() / 3):
		vol += faces[i * 3].cross(faces[i * 3 + 1]).dot(faces[i * 3 + 2]) / 6.0
	return vol


static func _build_adjacency(faces: PackedVector3Array, tri_count: int) -> Array:
	var by_vertex := {}
	for i in range(tri_count):
		for k in range(3):
			var key := _vkey(faces[i * 3 + k])
			if not by_vertex.has(key):
				by_vertex[key] = []
			by_vertex[key].append(i)
	var adjacency := []
	adjacency.resize(tri_count)
	for i in range(tri_count):
		var seen := {}
		for k in range(3):
			for j in by_vertex[_vkey(faces[i * 3 + k])]:
				if j != i:
					seen[j] = true
		adjacency[i] = seen.keys()
	return adjacency


static func _vkey(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x * WELD_QUANTUM), roundi(v.y * WELD_QUANTUM), roundi(v.z * WELD_QUANTUM))


# --- Runtime side -----------------------------------------------------------

# Reads a hull's baked facet map, or {} when there is none. Cached per hull type.
static func load_map(hull_type_id: String) -> Dictionary:
	if hull_type_id == "":
		return {}
	if _map_cache.has(hull_type_id):
		return _map_cache[hull_type_id]
	var result := {}
	var path := "%s/%s.json" % [SIDECAR_DIR, hull_type_id]
	if FileAccess.file_exists(path):
		var text := FileAccess.get_file_as_string(path)
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary and parsed.has(SIDECAR_KEY):
			var block = parsed[SIDECAR_KEY]
			if block is Dictionary and block.has("map"):
				var raw = block["map"]
				var ints := PackedInt32Array()
				for v in raw:
					ints.append(int(v))
				result = {
					"tri_count": int(block.get("tri_count", ints.size())),
					"map": ints,
					# Defaulting to +1 keeps a sidecar baked before the winding
					# field existed loading rather than erroring; such a map
					# simply resolves outward the old way for meshes that are
					# already wound outward.
					"winding": float(block.get("winding", 1.0)),
				}
				# Per-facet geometry and the six-side grouping, added for the
				# armor paint model. Every one is OPTIONAL: a sidecar baked
				# before these existed still loads and simply reports no facet
				# summary, which callers treat the same as no map at all.
				result["facet_count"] = int(block.get("facet_count", 0))
				result["normal"] = _to_vec3_array(block.get("facet_normal", []))
				result["centroid"] = _to_vec3_array(block.get("facet_centroid", []))
				result["area"] = _to_float_array(block.get("facet_area", []))
				result["side"] = block.get("facet_side", [])
				result["side_weight"] = block.get("facet_side_weight", [])
				result["sides"] = block.get("sides", {})
				result["side_area"] = block.get("side_area", {})
				result["total_area"] = float(block.get("total_area", 0.0))
	_map_cache[hull_type_id] = result
	return result


static func _to_vec3_array(raw) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not (raw is Array):
		return out
	for v in raw:
		if v is Array and v.size() >= 3:
			out.append(Vector3(float(v[0]), float(v[1]), float(v[2])))
	return out


static func _to_float_array(raw) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if not (raw is Array):
		return out
	for v in raw:
		out.append(float(v))
	return out


static func clear_cache() -> void:
	_map_cache.clear()


# The facet measurement, from the baked map. Returns the same shape
# module_placer._measure_hull_facet always has - {"size", "center", "outline",
# "valid"} - so callers cannot tell which path produced it, and an empty result
# means "fall back to the live measurement".
#
# `local_pos`/`local_normal` are in HULL-local space, and the mesh instance's
# own transform is applied to the baked triangles here, so hull_scale, the fit
# rotation and any non-uniform stretch are all accounted for. That is also why
# only the SEGMENTATION is baked and never the outline: the outline depends on
# the transform the hull is currently wearing, the segmentation does not.
static func measure(mesh_inst: MeshInstance3D, hull_type_id: String, local_pos: Vector3,
		local_normal: Vector3, module_basis: Basis) -> Dictionary:
	var empty := {"size": Vector3.ZERO, "center": local_pos, "outline": PackedVector2Array(), "valid": false}
	if mesh_inst == null or mesh_inst.mesh == null:
		return empty
	var baked := load_map(hull_type_id)
	if baked.is_empty():
		return empty
	var faces := mesh_inst.mesh.get_faces()
	var tri_count := faces.size() / 3
	var map: PackedInt32Array = baked["map"]
	# GUARD. The map is indexed by triangle, so it is only meaningful against
	# the exact mesh it was baked from. A re-exported or re-imported .glb with a
	# different triangle count must fall back to the live measurement rather
	# than silently assigning plates to whatever facet now holds that index.
	if map.size() != tri_count or tri_count <= 0:
		return empty

	var xform := mesh_inst.transform
	var norm := local_normal.normalized()
	# Seed: the nearest triangle that actually faces the way the ray came from.
	var seed := -1
	var best := INF
	for i in range(tri_count):
		var v0: Vector3 = xform * faces[i * 3]
		var v1: Vector3 = xform * faces[i * 3 + 1]
		var v2: Vector3 = xform * faces[i * 3 + 2]
		var n := (v1 - v0).cross(v2 - v0)
		if n.length_squared() < 1e-12:
			continue
		# Winding is inverted on this roster, so agreement is tested with abs()
		# HERE and only here - picking the triangle under the cursor, where the
		# click normal already tells us which side we are on. The segmentation
		# itself used the global sign and needed no such thing.
		if absf(n.normalized().dot(norm)) < 0.5:
			continue
		var d: float = (((v0 + v1 + v2) / 3.0) - local_pos).length_squared()
		if d < best:
			best = d
			seed = i
	if seed < 0:
		return empty

	var facet_id := map[seed]

	# EVERYTHING BELOW IS DERIVED FROM THE FACET, NOT FROM THE CLICK - which is
	# the half of drop-independence that a stable segmentation alone does not
	# buy. The first version of this still took its tangent frame from
	# `module_basis` (built from the raycast hit normal) and anchored the centre
	# on `local_pos`. Both move with the drop point on a curved face, so the
	# same facet still measured differently from different drops even though the
	# triangle SET was identical - measured, every facet on the Brenntal came
	# back ambiguous. The facet's own mean normal and centroid do not move, so
	# they are what the frame and the anchor are built from now.
	#
	# `module_basis` survives only as the tie-breaker for the frame's in-plane
	# spin, and `local_normal` only to orient the mean normal outward.
	var mean_n := Vector3.ZERO
	var centroid := Vector3.ZERO
	var vert_count := 0
	var tri_verts := PackedVector3Array()
	for i in range(tri_count):
		if map[i] != facet_id:
			continue
		var v0: Vector3 = xform * faces[i * 3]
		var v1: Vector3 = xform * faces[i * 3 + 1]
		var v2: Vector3 = xform * faces[i * 3 + 2]
		# Cross product of the TRANSFORMED edges, so hull_scale and any
		# non-uniform stretch are already in it. Transforming a baked normal
		# instead would need the inverse-transpose and would be wrong here.
		var cr := (v1 - v0).cross(v2 - v0)
		mean_n += cr
		centroid += v0 + v1 + v2
		vert_count += 3
		tri_verts.append(v0)
		tri_verts.append(v1)
		tri_verts.append(v2)
	if vert_count < 3 or mean_n.length_squared() < 1e-12:
		return empty
	centroid /= float(vert_count)
	mean_n = mean_n.normalized()
	# Outward direction comes from the BAKED winding sign, not from the click.
	#
	# Using the click normal to settle the sign looks equivalent and is not: a
	# facet that wraps more than 90 degrees (the Orrin's tumblehome flank, the
	# Kestrel's blended chine) has drop points whose hit normal disagrees with
	# the facet's own mean, so the plate flipped depending on which end of the
	# facet was clicked. Measured, that was the last ambiguity left after the
	# frame and the anchor were made facet-derived. A mesh's winding is a
	# property of the mesh, so it belongs in the bake.
	#
	# `xform` can itself mirror (a negative-determinant hull fit), which flips
	# the handedness of every cross product computed above - so the baked sign
	# is corrected by the transform's determinant rather than trusted raw.
	var det_sign := signf(xform.basis.determinant())
	if det_sign == 0.0:
		det_sign = 1.0
	var outward: float = float(baked.get("winding", 1.0)) * det_sign
	if outward < 0.0:
		mean_n = -mean_n

	var frame := _tangent_frame(mean_n)
	var bx: Vector3 = frame.x
	var bz: Vector3 = frame.z
	var pts := PackedVector2Array()
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for v in tri_verts:
		var rel: Vector3 = v - centroid
		var px := rel.dot(bx)
		var pz := rel.dot(bz)
		min_x = minf(min_x, px)
		max_x = maxf(max_x, px)
		min_z = minf(min_z, pz)
		max_z = maxf(max_z, pz)
		pts.append(Vector2(px, pz))
	if pts.size() < 3 or (max_x - min_x) <= 0.1 or (max_z - min_z) <= 0.1:
		return empty

	var mid_x := (min_x + max_x) * 0.5
	var mid_z := (min_z + max_z) * 0.5
	var centred := PackedVector2Array()
	centred.resize(pts.size())
	for i in range(pts.size()):
		centred[i] = Vector2(pts[i].x - mid_x, pts[i].y - mid_z)
	var outline := Geometry2D.convex_hull(centred)
	return {
		"size": Vector3(max_x - min_x, 0.0, max_z - min_z),
		"center": centroid + bx * mid_x + bz * mid_z,
		"outline": outline if outline.size() >= 3 else PackedVector2Array(),
		"normal": mean_n,
		"basis": frame,
		"facet_id": facet_id,
		"valid": true,
	}


# Per-type surface pattern. Every armor type is the SAME thin shell of the
# facet - the type shows in how that shell is cut, not in anything added on top
# of it.
#
# This replaces an attempt to tile each type's authored .glb across the facet
# and displace its vertices onto the surface. It preserved the authored art
# exactly and was wrong anyway: slat_armor's authored form is a cage that STANDS
# OFF the hull, so wrapping it produced a bulky block hanging off the face
# rather than armor on it (Chris, 2026-08-17). The differentiating read at RTS
# zoom is the pattern - bars, tiles, plate - and a pattern costs no thickness.
#
#   period - pattern repeat in metres along the facet's tangent axes
#   duty   - fraction of each period that is solid (1.0 = no gaps at all)
#   axis   - 0 strips along U, 1 strips along V, 2 a grid in both
const SURFACE_PATTERNS := {
	# Plain plate: no cuts. Corner bolts and the like are the authored mesh's
	# business and are deliberately not reproduced here - a solid shell is the
	# honest read for "additional plate".
	"armor_plating": {"period": 0.0, "duty": 1.0, "axis": 0},
	# A cage of bars with real gaps between them. The gaps ARE the module: slat
	# armor works by catching a shaped charge early, and a slat plate with no
	# daylight through it is just plate.
	"slat_armor": {"period": 0.42, "duty": 0.52, "axis": 0},
	# Discrete panels with a visible seam between them.
	"spaced_composite": {"period": 0.85, "duty": 0.86, "axis": 2},
	# A fine mosaic - the smallest period here, because tiles only read as
	# tiles when there are many of them.
	"ablative_foam": {"period": 0.46, "duty": 0.88, "axis": 2},
}

# Builds the armor plate for a facet, in the MODULE's local frame (X/Z tangent,
# +Y the facet normal, origin at `center`).
#
# THE PLATE IS A SKIN, NOT A SLAB. It is the facet's own triangles lifted off
# the hull by a hair - just enough to clear z-fighting - and cut by the type's
# pattern. It adds no thickness, has no rim and has no underside, because armor
# here is a surface treatment on a face the player can see, not a box bolted to
# it (Chris, 2026-08-17).
#
# Three earlier versions are worth naming, because each was rejected for a
# different reason and it would be easy to re-derive any of them:
#
#   * A FLAT extruded polygon. Wrong on curvature - measured, only 3/10 facets
#     on the Brenntal are flat to within 5cm and the worst departs 2.30m, so a
#     flat plate is buried at the centre and floating at the rim.
#   * The type's AUTHORED MESH wrapped onto the surface. Faithful to the art and
#     still wrong: slat_armor's authored form is a cage that STANDS OFF the
#     hull, so wrapping it reproduced that standoff as a block hanging off the
#     face.
#   * A conformed SLAB with real thickness and a rim. Correct in shape, still
#     read as a thick blocky plate sitting on the hull rather than as armor on
#     its surface.
#
# CRISP EDGES ARE A PROPERTY OF THE NORMAL FIELD. The lift runs along corner
# normals averaged only across neighbours within CREASE_SPLIT_DEG, so a chamfer
# keeps a distinct normal each side and the skin turns the corner instead of
# rolling over it.
# MATERIAL RELIEF: the surface treatment that tells two materials apart.
#
# Colour cannot carry this. The player's livery repaints the whole vehicle, so
# an armor material identified by its tint is identified by nothing the moment
# anyone picks a different scheme. Relief survives livery, survives the faction
# shader, and reads at gameplay camera distance because it catches light.
#
# `cell` is the tile size in metres, `height` how far a tile stands proud (scaled
# by the facet's thickness), `stagger` offsets alternate rows like brickwork.
# Tiles are CUT, not displaced per-vertex: a facet can be two big triangles, so
# vertex displacement would have nothing to displace. Clipping into cells and
# lifting each cell as a unit gives flat tops and crisp steps at any facet size,
# reusing the same Sutherland-Hodgman clip the slat pattern already uses.
const MATERIAL_RELIEF := {
	# ALL ZERO, AND THAT IS THE ANSWER, not a stub.
	#
	# This cut real tiles into the skin and raised them. It worked exactly as
	# specified - triangle counts scaled with cell size, 57 flat vs 395 reactive
	# vs 2309 carbon - and rendered INVISIBLE. Only the tile TOPS were emitted,
	# so the result was a set of parallel quads at slightly different heights
	# with no vertical face anywhere for light to hit. A step you cannot see is
	# not a step. Emitting skirts round every tile would have fixed it and
	# multiplied the triangle count on something that rides on every unit in a
	# skirmish.
	#
	# The signature moved into the shader instead (shaders/armor_surface.gdshader),
	# where it costs no geometry and cannot have this failure mode. The machinery
	# below is kept because a per-material height field is still the right hook
	# if a material ever needs a genuine silhouette change rather than a surface
	# one - set a cell and a height and it comes back.
	"hardened_steel": {"cell": 0.0, "height": 0.0, "stagger": false},
	"reactive_armor": {"cell": 0.0, "height": 0.0, "stagger": true},
	"ablative_ceramic": {"cell": 0.0, "height": 0.0, "stagger": false},
	"carbon_fiber": {"cell": 0.0, "height": 0.0, "stagger": true},
	"titanium_plate": {"cell": 0.0, "height": 0.0, "stagger": false},
}


static func build_plate(mesh_inst: MeshInstance3D, hull_type_id: String, facet_id: int,
		type_id: String, cat_size: Vector3, center: Vector3, frame: Basis,
		material_id: String = "hardened_steel", thickness: float = 1.0) -> ArrayMesh:
	if mesh_inst == null or mesh_inst.mesh == null:
		return null
	var surface := _facet_surface(mesh_inst, hull_type_id, facet_id, center, frame)
	if surface.is_empty():
		return null
	var bounds: Rect2 = surface["bounds"]
	# Scaled to the facet so it stays invisible on a 2m scout panel and on a 12m
	# airship flank alike, with an absolute floor for tiny facets. Same reasoning
	# (and the same order of magnitude) as HullProjection's decal offset.
	var lift: float = maxf(bounds.size.length() * PLATE_LIFT_FRACTION, PLATE_LIFT_MIN)
	var pattern: Dictionary = SURFACE_PATTERNS.get(type_id, {"period": 0.0, "duty": 1.0, "axis": 0})
	var relief: Dictionary = MATERIAL_RELIEF.get(material_id, MATERIAL_RELIEF["hardened_steel"])
	return _skin(surface, lift, pattern, relief, thickness)


# The skin: the facet's triangles lifted by `lift` and cut by the pattern.
#
# Outer surface only - no underside and no rim. Both would be invisible (the
# skin is flush to the hull) and a rim is precisely what gives a plate a
# readable EDGE THICKNESS, which is the "thick blocky plate" read being removed.
#
# THE CUT IS AN ANALYTIC CLIP, NOT A DROPPED SUBDIVISION. The first version
# subdivided each facet triangle and discarded cells whose centre fell in a gap.
# Rendered, that produced a TRIANGULAR SAWTOOTH rather than bars: cell edges run
# along the subdivision, not along the pattern, so no cell boundary is ever a
# straight line across the facet. Clipping each triangle against the band's two
# parallel planes puts the cut exactly where the pattern says it is, at any
# facet size, with no subdivision to resolve.
static func _skin(surface: Dictionary, lift: float, pattern: Dictionary,
		relief: Dictionary = {}, thickness: float = 1.0) -> ArrayMesh:
	var tris: Array = surface["tris"]
	var normals: Array = surface["normals"]
	var bounds: Rect2 = surface["bounds"]
	var period := float(pattern.get("period", 0.0))
	var duty := float(pattern.get("duty", 1.0))
	var axis := int(pattern.get("axis", 0))
	var solid: bool = period <= 0.0 or duty >= 0.999

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var emitted := 0
	for t in range(tris.size()):
		var poly := []
		for k in range(3):
			poly.append({"p": tris[t][k], "n": normals[t][k]})
		if solid:
			emitted += _emit_relief(st, poly, lift, bounds, relief, thickness)
			continue
		var pieces := [poly]
		# Component 0 is the facet's U tangent, 2 its V tangent - the same axes
		# the pattern period is quoted in metres along.
		if axis == 0 or axis == 2:
			pieces = _cut_bands(pieces, 0, period, duty)
		if axis == 1 or axis == 2:
			pieces = _cut_bands(pieces, 2, period, duty)
		for pc in pieces:
			emitted += _emit_relief(st, pc, lift, bounds, relief, thickness)
	if emitted == 0:
		return null
	st.generate_normals()
	# Required by the armor shader's normal mapping; needs the UVs set above.
	st.generate_tangents()
	return st.commit()


# Clips every polygon to the SOLID part of each band it overlaps along `comp`,
# returning the surviving pieces. A band is [k*period, k*period + duty*period];
# the remainder of the period is the gap.
static func _cut_bands(pieces: Array, comp: int, period: float, duty: float) -> Array:
	var out := []
	var solid_width := period * duty
	for poly in pieces:
		if (poly as Array).size() < 3:
			continue
		var lo := INF
		var hi := -INF
		for v in poly:
			var c: float = (v["p"] as Vector3)[comp]
			lo = minf(lo, c)
			hi = maxf(hi, c)
		var first := int(floor(lo / period))
		var last := int(floor(hi / period))
		for k in range(first, last + 1):
			var band_lo := float(k) * period
			var clipped := _clip_slab(poly, comp, band_lo, band_lo + solid_width)
			if clipped.size() >= 3:
				out.append(clipped)
	return out


# Sutherland-Hodgman against the two parallel planes of a slab, interpolating
# the corner normal along with the position so the lift stays continuous across
# a cut edge.
static func _clip_slab(poly: Array, comp: int, lo: float, hi: float) -> Array:
	var a := _clip_half(poly, comp, lo, true)
	if a.size() < 3:
		return []
	return _clip_half(a, comp, hi, false)


static func _clip_half(poly: Array, comp: int, limit: float, keep_greater: bool) -> Array:
	var out := []
	var n := poly.size()
	for i in range(n):
		var cur: Dictionary = poly[i]
		var nxt: Dictionary = poly[(i + 1) % n]
		var cv: float = (cur["p"] as Vector3)[comp]
		var nv: float = (nxt["p"] as Vector3)[comp]
		var cur_in: bool = (cv >= limit) if keep_greater else (cv <= limit)
		var nxt_in: bool = (nv >= limit) if keep_greater else (nv <= limit)
		if cur_in:
			out.append(cur)
		if cur_in != nxt_in:
			var denom := nv - cv
			if absf(denom) < 1e-12:
				continue
			var s: float = (limit - cv) / denom
			out.append({
				"p": (cur["p"] as Vector3).lerp(nxt["p"], s),
				"n": ((cur["n"] as Vector3).lerp(nxt["n"], s)).normalized(),
			})
	return out


# Cuts a piece into relief cells and emits each raised as a unit, giving flat
# tops and a crisp step at every seam.
#
# THIS IS WHAT TELLS TWO MATERIALS APART. Colour cannot: the player's livery
# repaints the whole vehicle, so a material identified by its tint is identified
# by nothing as soon as anyone picks a scheme. Relief survives livery and the
# faction shader, and catches light at gameplay distance.
#
# The lift is per CELL, not per vertex, and that is the whole reason it works: a
# facet can be two large triangles, so there are no interior vertices to push -
# the tiles have to be CUT into existence. Reuses the same Sutherland-Hodgman
# slab clip the slat pattern uses, so seams land exactly on the grid at any
# facet size with no subdivision to resolve.
#
# A cell size of 0 means no relief and the piece is emitted whole. That is
# hardened_steel, deliberately flat, so every other material reads as a
# departure from a baseline the player has already seen.
static func _emit_relief(st: SurfaceTool, poly: Array, lift: float, bounds: Rect2,
		relief: Dictionary, thickness: float) -> int:
	var cell := float(relief.get("cell", 0.0))
	var height := float(relief.get("height", 0.0)) * maxf(0.35, thickness)
	if cell <= 0.0 or height <= 0.0:
		return _emit_poly(st, poly, lift, bounds)

	var stagger: bool = bool(relief.get("stagger", false))
	var lo := INF
	var hi := -INF
	for v in poly:
		var c: float = (v["p"] as Vector3).z
		lo = minf(lo, c)
		hi = maxf(hi, c)
	var first := int(floor(lo / cell))
	var last := int(floor(hi / cell))

	var count := 0
	for row in range(first, last + 1):
		var strip := _clip_slab(poly, 2, float(row) * cell, float(row + 1) * cell)
		if strip.size() < 3:
			continue
		# Brick offset: alternate rows shift half a cell along u.
		var shift: float = (cell * 0.5) if (stagger and (row % 2 != 0)) else 0.0
		var ulo := INF
		var uhi := -INF
		for v in strip:
			var u: float = (v["p"] as Vector3).x
			ulo = minf(ulo, u)
			uhi = maxf(uhi, u)
		var ufirst := int(floor((ulo - shift) / cell))
		var ulast := int(floor((uhi - shift) / cell))
		for col in range(ufirst, ulast + 1):
			var tile := _clip_slab(strip, 0, shift + float(col) * cell,
				shift + float(col + 1) * cell)
			if tile.size() < 3:
				continue
			# Two depths, checkerboarded, so the seams read as a GRID rather
			# than as one uniformly raised sheet - a uniform lift is invisible,
			# because it has no edge for the light to catch.
			var raised: bool = ((row + col) % 2) == 0
			var h: float = height if raised else height * 0.25
			count += _emit_poly(st, tile, lift + h, bounds)
	return count


# Fan-triangulates a convex piece and emits it lifted off the hull. Returns how
# many triangles were written.
static func _emit_poly(st: SurfaceTool, poly: Array, lift: float, bounds: Rect2) -> int:
	var n := poly.size()
	if n < 3:
		return 0
	var count := 0
	for i in range(1, n - 1):
		for idx in [0, i, i + 1]:
			var v: Dictionary = poly[idx]
			var p: Vector3 = (v["p"] as Vector3) + (v["n"] as Vector3) * lift
			st.set_uv(_shell_uv(p, bounds))
			st.add_vertex(p)
		count += 1
	return count


# The facet as a liftable surface, in module-local space: its triangles, their
# crease-split corner normals, and the tangential bounds used for UVs.
static func _facet_surface(mesh_inst: MeshInstance3D, hull_type_id: String, facet_id: int,
		center: Vector3, frame: Basis) -> Dictionary:
	var baked := load_map(hull_type_id)
	if baked.is_empty():
		return {}
	var faces := mesh_inst.mesh.get_faces()
	var tri_count := faces.size() / 3
	var map: PackedInt32Array = baked["map"]
	if map.size() != tri_count:
		return {}
	var xform := mesh_inst.transform
	var to_local := Transform3D(frame, center).affine_inverse()

	var tris := []
	var face_normals := []
	for i in range(tri_count):
		if map[i] != facet_id:
			continue
		var a: Vector3 = to_local * (xform * faces[i * 3])
		var b: Vector3 = to_local * (xform * faces[i * 3 + 1])
		var c: Vector3 = to_local * (xform * faces[i * 3 + 2])
		var cr := (b - a).cross(c - a)
		if cr.length_squared() < 1e-14:
			continue
		# Orient so the facet's outward side is +Y in module space, and so the
		# emitted triangle faces the camera. Done per triangle so a mirroring
		# hull transform cannot invert the skin.
		if cr.y < 0.0:
			var swap := b
			b = c
			c = swap
			cr = -cr
		tris.append([a, b, c])
		face_normals.append(cr.normalized())
	if tris.is_empty():
		return {}

	# Crease-split corner normals: average the face normals meeting at a vertex,
	# but only those within CREASE_SPLIT_DEG of THIS triangle's own normal.
	var by_vertex := {}
	for t in range(tris.size()):
		for k in range(3):
			var key := _vkey(tris[t][k])
			if not by_vertex.has(key):
				by_vertex[key] = []
			by_vertex[key].append(t)
	var crease := cos(deg_to_rad(CREASE_SPLIT_DEG))
	var corner_normals := []
	var min_u := INF
	var max_u := -INF
	var min_v := INF
	var max_v := -INF
	for t in range(tris.size()):
		var own: Vector3 = face_normals[t]
		var trio := []
		for k in range(3):
			var acc := Vector3.ZERO
			for other in by_vertex[_vkey(tris[t][k])]:
				var on: Vector3 = face_normals[other]
				if on.dot(own) >= crease:
					acc += on
			trio.append(acc.normalized() if acc.length_squared() > 1e-12 else own)
			var p: Vector3 = tris[t][k]
			min_u = minf(min_u, p.x); max_u = maxf(max_u, p.x)
			min_v = minf(min_v, p.z); max_v = maxf(max_v, p.z)
		corner_normals.append(trio)
	return {
		"tris": tris,
		"normals": corner_normals,
		"bounds": Rect2(min_u, min_v, max_u - min_u, max_v - min_v),
	}


# UVs in METRES of facet-local surface, not normalised 0..1.
#
# Normalised was wrong for the armor shader: it makes one UV unit mean "the
# width of this facet", so the same material tiled at a different density on
# every panel of the same vehicle - a small facet got the same number of blocks
# as a large one. In metres, a 0.5m reactive block is 0.5m everywhere, which is
# the only way a material can have a recognisable SCALE.
#
# `bounds` is retained so the offset stays stable as the facet moves, and so a
# facet straddling the origin does not get negative UVs on half of itself.
static func _shell_uv(p: Vector3, bounds: Rect2) -> Vector2:
	return Vector2(p.x - bounds.position.x, p.z - bounds.position.y)


# Orthonormal frame with +Y on the facet normal, and a PURE FUNCTION OF THAT
# NORMAL - no reference to the click, deliberately.
#
# Taking the in-plane spin from the caller's hit-normal basis was the last drop
# dependence left: on a curved facet the hit normal moves, so the frame span,
# and the measured bbox spun with it even after the facet set and the anchor
# were both stable. Since it reproduces module_placer._align_up_to() exactly,
# the module's own +Y still lands on the surface normal and every downstream
# convention (mirror flip, bottom-facet flip, yaw_offset) is unaffected.
# The centre and orientation of a baked facet, in HULL space - i.e. exactly the
# `center`/`frame` pair build_plate() wants, so a painted facet can be skinned
# from its id alone with no click and no measurement.
#
# measure() cannot serve this: it exists to answer "which facet did the player
# just point at" and needs a ray to do it. Painting already knows the answer.
static func facet_frame(hull_type_id: String, facet_id: int, xform: Transform3D) -> Dictionary:
	var baked := load_map(hull_type_id)
	var normals: PackedVector3Array = baked.get("normal", PackedVector3Array())
	var centroids: PackedVector3Array = baked.get("centroid", PackedVector3Array())
	if facet_id < 0 or facet_id >= normals.size() or facet_id >= centroids.size():
		return {"valid": false}
	# Normals take the inverse transpose, positions the transform itself.
	var n: Vector3 = (xform.basis.inverse().transposed() * normals[facet_id])
	if n.length_squared() < 1e-12:
		return {"valid": false}
	n = n.normalized()
	return {
		"valid": true,
		"center": xform * centroids[facet_id],
		"normal": n,
		"basis": _tangent_frame(n),
	}


static func _tangent_frame(n: Vector3) -> Basis:
	var target := n.normalized()
	if target.length_squared() < 0.5:
		return Basis.IDENTITY
	var d := Vector3.UP.dot(target)
	if d > 1.0 - 0.000001:
		return Basis.IDENTITY
	if d < -1.0 + 0.000001:
		return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, target))
