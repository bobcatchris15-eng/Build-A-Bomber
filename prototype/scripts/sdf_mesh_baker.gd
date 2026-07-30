# SDFMeshBaker (use via preload, e.g. const SDFMeshBaker = preload("res://scripts/sdf_mesh_baker.gd"))
# Turns a Hull Builder primitive assembly (see hull_builder.gd's `primitives`
# array) into a single fused ArrayMesh: each primitive becomes a signed
# distance field, all of them are folded together with a polynomial
# smooth-min (so overlapping shapes blend into one organic surface instead of
# staying as interpenetrating shells), and the result is polygonized with
# Marching Cubes (mc_tables.gd) on a voxel grid sized to the assembly's AABB.
#
# No class_name / no `extends` line, deliberately - same convention as
# hull_loader.gd and mesh_asset_loader.gd (class_name globals aren't reliable
# in scripts run headless before the .godot cache exists).
#
# Runs entirely synchronously in GDScript - this is an explicit "Baking..."
# step triggered from the Export button (see hull_builder.gd's
# _on_export_confirmed()), not a per-frame operation, so no threading is
# needed for a first pass.

const MCTables = preload("res://scripts/mc_tables.gd")
const DCTables = preload("res://scripts/dc_tables.gd")

# Must stay in sync with hull_builder.gd's PrimitiveType enum order -
# duplicated here rather than imported to avoid a preload cycle with
# hull_builder.gd's scene-heavy deps. The expanded-kit shapes (SLOPE onward)
# are analytic SDF approximations of the same unit geometry
# tools/blender/build_hull_primitives.py authors for the discrete editor
# preview mesh - see each _sdf_* function's own comment for how closely it
# tracks the authored shape's actual parameters.
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

# Primitive types whose surface normals are inherently curved (radial,
# spherical, toroidal). Vertices on these surfaces keep their natural SDF
# normals instead of being snapped to cardinal/chamfer targets.
const CURVED_PRIMITIVE_TYPES := [
	TYPE_SPHERE, TYPE_CYLINDER, TYPE_CONE, TYPE_TORUS,
	TYPE_HALF_CYLINDER, TYPE_HEMISPHERE, TYPE_CAPSULE,
	TYPE_FENDER, TYPE_CANOPY, TYPE_RING,
]

# Conservative unit-space half-extent shared by _compute_primitives_aabb() -
# every primitive type in hull_builder.gd is built at unit size (see its
# _build_mesh_for_type()); 0.6 covers all of them (box/sphere/cylinder/cone/
# wedge are exactly 0.5, the torus's outer_radius is 0.6) with a little
# headroom, since this AABB only sizes the voxel grid, not the final surface.
const _UNIT_BOUND := 0.6

# Large number for distance comparisons. Deliberately NOT named INF - a class
# const by that name shadows GDScript's global INF, and every `INF` in this
# file then silently means 1e9 instead of true infinity.
const _FAR_DIST := 1e9

# ── Plane-snap tunables ──────────────────────────────────────────────────
# Static so a probe script can sweep them; the defaults are the shipping values.
#
# snap_pad_voxels is the interesting one. Strict Dual Contouring keeps every
# vertex inside its own cell, and the first version of the plane snap honoured
# that. But it is over-cautious for THIS operation: snapping pulls many vertices
# onto a SHARED plane, which cannot change the mesh's connectivity, so it cannot
# open a hole - the quad-per-sign-change topology is decided before any snapping
# happens. Allowing a vertex to sit somewhat outside its cell lets far more of
# them reach their plane, which is what actually flattens the panels.
static var snap_tol_voxels := 0.75
static var snap_pad_voxels := 0.0
static var snap_surface_eps_voxels := 0.2

# (There used to be a non-static `rad_to_deg()` helper here shadowing the
# GDScript global of the same name, called from static functions. Removed - the
# built-in does the same thing and doesn't depend on an instance existing.)

# ── Grid sizing (shared) ─────────────────────────────────────────────────
#
# bake_dc()/bake_mc() and tools/bake_hull_roster.gd's sub-voxel feature check
# MUST agree on the voxel size, or the check lies. They used to compute it
# independently: the tool used AABB(pos - scale*0.5, scale) with no rotation
# and no margin, while the baker uses _UNIT_BOUND (0.6, not 0.5) per axis,
# applies each primitive's rotation basis, and then grows by the smoothness
# margin. On heavy_hull that made the tool report voxel 0.31 where the baker
# actually used ~0.39 - a 26% understatement, so the "WILL BE LOST" branch
# effectively never fired and thin features vanished silently (exactly the
# swept-wing hull's wing-loss failure the warning exists to prevent - that
# hull has since been retired from the roster, but the failure mode has not).
#
# Both now call these two functions. Do not reintroduce a local copy.

static func compute_bake_bounds(primitives: Array, smoothness: float) -> AABB:
	var bounds := _compute_primitives_aabb(primitives)
	var margin: float = max(smoothness * 2.5, 0.25)
	return bounds.grow(margin)

# Returns 0.0 if the assembly is degenerate (no extent to grid).
static func compute_voxel_size(primitives: Array, smoothness: float, resolution: int) -> float:
	if primitives.is_empty():
		return 0.0
	var size: Vector3 = compute_bake_bounds(primitives, smoothness).size
	var longest: float = max(size.x, max(size.y, size.z))
	if longest <= 0.001:
		return 0.0
	return longest / float(max(resolution, 4))

# Re-lays the sample lattice so it is exactly mirror-symmetric about x=0, and
# returns the corrected [origin_x, nx].
#
# This is the honest fix for the problem scene_sdf()'s abs(x) fold was hiding.
# nx comes from ceil(size.x / voxel), so the grid overshoots the bounds - and
# because the origin stays at bounds.position, the whole overshoot lands on the
# +X side. The lattice is therefore NOT symmetric about x=0, so a hand-mirrored
# pair of primitives gets sampled at different offsets on each side and Dual
# Contouring places visibly different vertices. Folding the field forced
# symmetry, but at the cost of duplicating one-sided features and opening seam
# gaps. Centring the lattice instead gets exact symmetry for mirrored input
# while leaving asymmetric input alone.
#
# Width is taken from whichever side reaches further from x=0, so a hull that
# sits entirely off-centre is still fully covered (never cropped), and nx is
# rounded up to even so a sample plane lands exactly on x=0.
static func _center_grid_x(bounds: AABB, voxel_size: float, nx: int, max_cells: int) -> Array:
	var reach: float = max(absf(bounds.position.x), absf(bounds.position.x + bounds.size.x))
	var needed: int = int(ceil(2.0 * reach / voxel_size))
	if needed % 2 == 1:
		needed += 1
	needed = clampi(max(needed, nx), 2, max_cells)
	if needed % 2 == 1:
		needed -= 1
	return [-(float(needed) * voxel_size) * 0.5, needed]

# ── Public API ────────────────────────────────────────────────────────────

# Unified bake entry point.
# method: "dc" (Dual Contouring - hard facets & sharp edges) or "mc" (Marching Cubes - smooth).
# fit_percent: 0..100+ (for DC: controls how tightly vertices hug the SDF isosurface, default 95).
# facet_angle_deg: angle threshold for coplanar face merging.
# crystallinity: 0.0 (constructed/axis-aligned plates & standard slope angles) .. 1.0 (unconstrained/crystalline facets).
# chamfer_edge_pct: 0.0% .. 25.0% (default 5.0% - weights edge zone for angled chamfers while locking main face bodies 100% cardinal).
# mirror_x: fold the field into the +X half. Off by default and rarely what you
#   want - it DELETES any primitive centred at negative X. See scene_sdf().
static func bake(primitives: Array, smoothness: float, resolution: int, method: String = "dc", fit_percent: float = 95.0, facet_angle_deg: float = 15.0, crystallinity: float = 0.0, chamfer_edge_pct: float = 5.0, mirror_x: bool = false) -> ArrayMesh:
	var m := method.to_lower()
	# "csg" bypasses the voxel grid entirely - see scripts/csg_mesh_baker.gd. It
	# is the method for manufactured hulls: exactly planar panels and hard edges,
	# no resolution/fit/crystallinity knobs because there is no sampling error to
	# tune. `resolution` is reused as the curved-primitive facet count so the
	# existing quality control still means something on this path.
	if m == "csg":
		var CSG = load("res://scripts/csg_mesh_baker.gd")
		return CSG.bake(primitives, maxi(int(round(float(resolution) / 3.0)), 6))
	if m == "mc":
		return bake_mc(primitives, smoothness, resolution, mirror_x)
	return bake_dc(primitives, smoothness, resolution, fit_percent, facet_angle_deg, crystallinity, chamfer_edge_pct, mirror_x)

# Legacy / Smooth Marching Cubes pipeline
static func bake_mc(primitives: Array, smoothness: float, resolution: int, mirror_x: bool = false) -> ArrayMesh:
	if primitives.is_empty():
		return null

	var bounds := compute_bake_bounds(primitives, smoothness)

	var size: Vector3 = bounds.size
	var longest: float = max(size.x, max(size.y, size.z))
	if longest <= 0.001:
		return null

	var res: int = max(resolution, 4)
	var voxel_size: float = longest / float(res)
	var nx: int = clampi(int(ceil(size.x / voxel_size)), 2, res * 2)
	var ny: int = clampi(int(ceil(size.y / voxel_size)), 2, res * 2)
	var nz: int = clampi(int(ceil(size.z / voxel_size)), 2, res * 2)

	var centered := _center_grid_x(bounds, voxel_size, nx, res * 2)
	bounds.position.x = centered[0]
	nx = centered[1]

	var dim_x := nx + 1
	var dim_y := ny + 1
	var dim_z := nz + 1

	var field := PackedFloat32Array()
	field.resize(dim_x * dim_y * dim_z)
	for iz in range(dim_z):
		for iy in range(dim_y):
			for ix in range(dim_x):
				var wp: Vector3 = bounds.position + Vector3(ix, iy, iz) * voxel_size
				field[_grid_index(ix, iy, iz, dim_x, dim_y)] = scene_sdf(wp, primitives, smoothness, mirror_x)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri_count := 0
	for iz in range(nz):
		for iy in range(ny):
			for ix in range(nx):
				tri_count += _march_cell(st, ix, iy, iz, dim_x, dim_y, field,
					bounds.position, voxel_size, primitives, smoothness, mirror_x)

	if tri_count == 0:
		return null

	return st.commit()

# Dual Contouring (DC) bake pipeline — sharp edges, QEF solver, hard facets.
static func bake_dc(primitives: Array, smoothness: float, resolution: int, fit_percent: float = 95.0, facet_angle_deg: float = 15.0, crystallinity: float = 0.0, chamfer_edge_pct: float = 5.0, mirror_x: bool = false) -> ArrayMesh:
	if primitives.is_empty():
		return null

	var bounds := compute_bake_bounds(primitives, smoothness)

	var size: Vector3 = bounds.size
	var longest: float = max(size.x, max(size.y, size.z))
	if longest <= 0.001:
		return null

	var res: int = max(resolution, 4)
	var voxel_size: float = longest / float(res)
	var nx: int = clampi(int(ceil(size.x / voxel_size)), 2, res * 2)
	var ny: int = clampi(int(ceil(size.y / voxel_size)), 2, res * 2)
	var nz: int = clampi(int(ceil(size.z / voxel_size)), 2, res * 2)

	var centered := _center_grid_x(bounds, voxel_size, nx, res * 2)
	bounds.position.x = centered[0]
	nx = centered[1]

	var dim_x := nx + 1
	var dim_y := ny + 1
	var dim_z := nz + 1

	var field := PackedFloat32Array()
	field.resize(dim_x * dim_y * dim_z)
	for iz in range(dim_z):
		for iy in range(dim_y):
			for ix in range(dim_x):
				var wp: Vector3 = bounds.position + Vector3(ix, iy, iz) * voxel_size
				field[_grid_index(ix, iy, iz, dim_x, dim_y)] = scene_sdf(wp, primitives, smoothness, mirror_x)

	var dual_vertices := {}

	for iz in range(nz):
		for iy in range(ny):
			for ix in range(nx):
				var cell_idx := _grid_index(ix, iy, iz, dim_x, dim_y)
				var intersections := []
				var normals := []
				var p_sum := Vector3.ZERO

				var cell_min := bounds.position + Vector3(ix, iy, iz) * voxel_size
				var cell_max := cell_min + Vector3(voxel_size, voxel_size, voxel_size)

				for e in range(12):
					var pair: Array = DCTables.EDGE_CORNERS[e]
					var off0: Vector3 = DCTables.CORNER_OFFSETS[pair[0]]
					var off1: Vector3 = DCTables.CORNER_OFFSETS[pair[1]]

					var v0: float = field[_grid_index(ix + int(off0.x), iy + int(off0.y), iz + int(off0.z), dim_x, dim_y)]
					var v1: float = field[_grid_index(ix + int(off1.x), iy + int(off1.y), iz + int(off1.z), dim_x, dim_y)]

					if (v0 < 0.0) != (v1 < 0.0):
						var p0 := cell_min + off0 * voxel_size
						var p1 := cell_min + off1 * voxel_size
						var t := 0.5
						if abs(v1 - v0) > 0.00001:
							t = clamp(v0 / (v0 - v1), 0.0, 1.0)
						var p_edge := p0.lerp(p1, t)
						var n_edge := _sdf_normal(p_edge, primitives, smoothness, mirror_x)
						n_edge = _snap_constructed_normal(n_edge, crystallinity, p_edge, primitives, chamfer_edge_pct, mirror_x)

						intersections.append(p_edge)
						normals.append(n_edge)
						p_sum += p_edge

				if not intersections.is_empty():
					var mass_point := p_sum / float(intersections.size())
					var vert := _solve_qef_3d(intersections, normals, mass_point, cell_min, cell_max)

					if fit_percent != 100.0:
						var sdf_val := scene_sdf(vert, primitives, smoothness, mirror_x)
						var norm := _sdf_normal(vert, primitives, smoothness, mirror_x)
						norm = _snap_constructed_normal(norm, crystallinity, vert, primitives, chamfer_edge_pct, mirror_x)
						var desired_offset := (100.0 - fit_percent) / 100.0 * voxel_size * 0.5
						vert = vert - norm * (sdf_val - desired_offset)
						vert = vert.clamp(cell_min, cell_max)

					# NOTE: vertices are aligned to the primitives' real face
					# planes in a final pass (_snap_to_primitive_planes) once
					# every cell has a vertex, not here.
					#
					# What used to be here was a "Constructed Orthogonal
					# Alignment" that rounded each coordinate onto an arbitrary
					# sub-voxel lattice - voxel*0.5 along the dominant axis,
					# voxel*0.25 tangentially. That lattice has no relationship
					# to where the box faces actually are, so neighbouring cells
					# rounded to DIFFERENT lattice steps and the shared edge
					# between them became a zigzag. It is the direct cause of the
					# sawtooth ribbons along the deck edges, and it injected up
					# to a quarter-voxel of jitter into lines that should be
					# dead straight. Snapping to the actual planes gets the hard
					# edges this was reaching for, without inventing a grid.
					dual_vertices[cell_idx] = vert

	if dual_vertices.is_empty():
		return null

	# ── Post-process: Flatten Cardinal Panels ────────────────────────────
	# Vertices whose SDF normal points along a cardinal axis (+X, -X, +Y,
	# -Y, +Z, -Z) should lie on identical planes. DC vertex jitter causes
	# visible stepping; cluster-averaging the dominant-axis coordinate
	# across nearby same-cardinal vertices eliminates it.
	if crystallinity < 0.5:
		_flatten_cardinal_panels(dual_vertices, primitives, smoothness, crystallinity, chamfer_edge_pct, voxel_size, mirror_x)
		# Runs AFTER flattening so exact planes win over averaged ones.
		_snap_to_primitive_planes(dual_vertices, primitives, smoothness, bounds,
			voxel_size, dim_x, dim_y, mirror_x)

	var triangles: Array = []

	for iz in range(nz):
		for iy in range(ny):
			for ix in range(nx):
				var origin_val := field[_grid_index(ix, iy, iz, dim_x, dim_y)]
				for axis in range(3):
					var next_x := ix + (1 if axis == 0 else 0)
					var next_y := iy + (1 if axis == 1 else 0)
					var next_z := iz + (1 if axis == 2 else 0)

					if next_x > nx or next_y > ny or next_z > nz:
						continue

					var next_val := field[_grid_index(next_x, next_y, next_z, dim_x, dim_y)]

					if (origin_val < 0.0) != (next_val < 0.0):
						var quad_cells: Array = DCTables.QUAD_CELL_OFFSETS[axis]
						var c_verts := []
						var valid := true
						for cell_off in quad_cells:
							var cx: int = ix + cell_off.x
							var cy: int = iy + cell_off.y
							var cz: int = iz + cell_off.z
							if cx < 0 or cy < 0 or cz < 0 or cx >= nx or cy >= ny or cz >= nz:
								valid = false
								break
							var c_idx := _grid_index(cx, cy, cz, dim_x, dim_y)
							if dual_vertices.has(c_idx):
								c_verts.append(dual_vertices[c_idx])
							else:
								valid = false
								break

						if valid and c_verts.size() == 4:
							var v0: Vector3 = c_verts[0]
							var v1: Vector3 = c_verts[1]
							var v2: Vector3 = c_verts[2]
							var v3: Vector3 = c_verts[3]

							if origin_val < 0.0:
								triangles.append([v0, v3, v2])
								triangles.append([v0, v2, v1])
							else:
								triangles.append([v0, v1, v2])
								triangles.append([v0, v2, v3])

	if triangles.is_empty():
		return null

	return _build_faceted_mesh(triangles, facet_angle_deg, crystallinity, primitives, chamfer_edge_pct, mirror_x, smoothness, voxel_size)

# QEF solver (3D Quadratic Error Function) using 3x3 matrix inverse.
static func _solve_qef_3d(pts: Array, normals: Array, mass_point: Vector3, cell_min: Vector3, cell_max: Vector3) -> Vector3:
	var n_count := pts.size()
	if n_count == 0:
		return (cell_min + cell_max) * 0.5

	var m00 := 0.0; var m01 := 0.0; var m02 := 0.0
	var m11 := 0.0; var m12 := 0.0; var m22 := 0.0
	var v_x := 0.0; var v_y := 0.0; var v_z := 0.0

	for i in range(n_count):
		var n: Vector3 = normals[i]
		var p: Vector3 = pts[i] - mass_point
		var dot_np: float = n.dot(p)

		m00 += n.x * n.x
		m01 += n.x * n.y
		m02 += n.x * n.z
		m11 += n.y * n.y
		m12 += n.y * n.z
		m22 += n.z * n.z

		v_x += n.x * dot_np
		v_y += n.y * dot_np
		v_z += n.z * dot_np

	var det := m00 * (m11 * m22 - m12 * m12) \
			 - m01 * (m01 * m22 - m12 * m02) \
			 + m02 * (m01 * m12 - m11 * m02)

	if abs(det) < 0.0001:
		return mass_point.clamp(cell_min, cell_max)

	var inv_det := 1.0 / det

	var i00 := (m11 * m22 - m12 * m12) * inv_det
	var i01 := (m02 * m12 - m01 * m22) * inv_det
	var i02 := (m01 * m12 - m02 * m11) * inv_det
	var i11 := (m00 * m22 - m02 * m02) * inv_det
	var i12 := (m01 * m02 - m00 * m12) * inv_det
	var i22 := (m00 * m11 - m01 * m01) * inv_det

	var dx := i00 * v_x + i01 * v_y + i02 * v_z
	var dy := i01 * v_x + i11 * v_y + i12 * v_z
	var dz := i02 * v_x + i12 * v_y + i22 * v_z

	var solution := mass_point + Vector3(dx, dy, dz)
	return solution.clamp(cell_min, cell_max)

# Quantizes / snaps normals to cardinal & standard chamfer / slope angles for
# constructed hulls. Vertices whose nearest primitive is a curved-silhouette
# type (ring, torus, sphere, cylinder, etc.) skip snapping entirely and keep
# their natural SDF normals. Box-derived types (box, wedge, slope, frustum,
# i-beam, etc.) snap to cardinal in the main face body and to chamfer targets
# in the perimeter edge zone.
static func _snap_constructed_normal(n: Vector3, crystallinity: float, point: Vector3 = Vector3.ZERO, primitives: Array = [], chamfer_edge_pct: float = 5.0, mirror_x: bool = false) -> Vector3:
	if crystallinity >= 1.0 or n.length_squared() < 1e-6:
		return n

	# ── Mirror-space agreement ───────────────────────────────────────────
	# When mirror_x is on, scene_sdf() evaluates the field at |x|, so the
	# surface in the -X half belongs to a primitive sitting in the +X half.
	# This function used to classify against the RAW point, so on the -X side
	# it found the wrong nearest primitive and ran edge-zone detection against
	# the wrong half-extents - producing faceting that was asymmetric on a mesh
	# the field guarantees is symmetric. Fold the point (and the normal's x,
	# which flips with it), snap in +X space, then unfold the result.
	var flipped := mirror_x and point.x < 0.0
	if flipped:
		point = Vector3(-point.x, point.y, point.z)
		n = Vector3(-n.x, n.y, n.z)
	var result := _snap_constructed_normal_folded(n, crystallinity, point, primitives, chamfer_edge_pct)
	if flipped:
		result = Vector3(-result.x, result.y, result.z)
	return result

# True when the point sits on a primitive whose surface is genuinely curved
# (ring, sphere, cylinder, dome, torus...), using the same nearest-primitive
# search and curvature threshold the normal snap uses.
#
# The normal snap already bypasses curved surfaces, but two OTHER passes were
# quantising them regardless: the sub-voxel coordinate snap and the cardinal
# panel flattener. Both key off "is this normal within 0.75 of an axis", which
# is true for big stretches of any curved surface - so the top and outer wall of
# heavy_hull's turret RING had its coordinates rounded onto a voxel*0.25 lattice
# and its panels averaged flat. A circle quantised onto a coarse lattice is
# exactly the "series of crystalline bumps" instead of a ring.
static func _is_on_curved_surface(point: Vector3, primitives: Array, mirror_x: bool = false) -> bool:
	if primitives.is_empty():
		return false
	var p := Vector3(absf(point.x), point.y, point.z) if mirror_x else point
	var nearest: Dictionary = primitives[0]
	var min_abs_dist: float = _FAR_DIST
	for prim in primitives:
		var d_abs: float = absf(primitive_sdf(p, prim))
		if d_abs < min_abs_dist:
			min_abs_dist = d_abs
			nearest = prim
	return _estimate_curvature(p, nearest, primitives, 0.0) > 15.0

# The body of the snap, evaluated strictly in +X space when mirror_x is on.
static func _snap_constructed_normal_folded(n: Vector3, crystallinity: float, point: Vector3, primitives: Array, chamfer_edge_pct: float) -> Vector3:
	# ── Find the nearest primitive ───────────────────────────────────────
	# Used for both curved-type bypass and edge-zone detection.
	var nearest_prim: Dictionary = primitives[0] if not primitives.is_empty() else {}
	var nearest_prim_type: int = nearest_prim.get("type", TYPE_BOX) if not primitives.is_empty() else TYPE_BOX
	if not primitives.is_empty():
		var min_abs_dist: float = _FAR_DIST
		for prim in primitives:
			var d_abs: float = abs(primitive_sdf(point, prim))
			if d_abs < min_abs_dist:
				min_abs_dist = d_abs
				nearest_prim = prim
				nearest_prim_type = prim.type

	# ── Curvature-aware normal snapping ──────────────────────────────────────
	# Rather than binary curved/constructed distinction, we now measure
	# local-space curvature and blend intelligently: high curvature preserves
	# natural SDF normals, low curvature enables snapping to cardinal/chamfer targets.

	# Calculate local-space curvature for intelligent decision making
	# smoothness is 0.0 because _snap_constructed_normal's callers don't thread
	# one through, and _estimate_curvature declares the parameter without ever
	# reading it (its curvature is analytic per primitive type). If that
	# function ever starts using smoothness, this call site has to be revisited.
	var curvature_deg: float = _estimate_curvature(point, nearest_prim, primitives, 0.0)

	# Curvature threshold (matches issue summary) - above this, preserve natural SDF normal
	var curvature_threshold_deg: float = 15.0

	if curvature_deg > curvature_threshold_deg:
		# HIGH CURVATURE - preserve SDF normal (ring, sphere, tight curves)
		return n

	# LOW CURVATURE - enable snapping to cardinal/chamfer targets
	# Cardinal targets (orthogonal vertical / horizontal surfaces)
	var cardinal_targets := [
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, -1, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1)
	]

	# Angled chamfer targets (45, 30, 60 degree bevels)
	var chamfer_targets := [
		Vector3(0.707107, 0.707107, 0), Vector3(-0.707107, 0.707107, 0),
		Vector3(0.707107, -0.707107, 0), Vector3(-0.707107, -0.707107, 0),
		Vector3(0.707107, 0, 0.707107), Vector3(-0.707107, 0, 0.707107),
		Vector3(0.707107, 0, -0.707107), Vector3(-0.707107, 0, -0.707107),
		Vector3(0, 0.707107, 0.707107), Vector3(0, -0.707107, 0.707107),
		Vector3(0, 0.707107, -0.707107), Vector3(0, -0.707107, -0.707107),

		Vector3(0, 0.5, 0.866025), Vector3(0, 0.5, -0.866025),
		Vector3(0, 0.866025, 0.5), Vector3(0, 0.866025, -0.5),
		Vector3(0, -0.5, 0.866025), Vector3(0, -0.5, -0.866025),
		Vector3(0, -0.866025, 0.5), Vector3(0, -0.866025, -0.5),
		Vector3(0.5, 0.866025, 0), Vector3(-0.5, 0.866025, 0),
		Vector3(0.866025, 0.5, 0), Vector3(-0.866025, 0.5, 0)
	]

	# Check if point is in main face body or near perimeter edge.
	# Only the NEAREST primitive matters - checking all primitives causes
	# every surface vertex to be misclassified as edge-zone (since a surface
	# point is trivially "outside the inner region" of distant primitives).
	# Additionally, only tangential axes (perpendicular to the face normal)
	# determine edge proximity - the face-normal axis is always at the
	# boundary by definition.
	var is_edge_zone := false
	if not primitives.is_empty() and chamfer_edge_pct > 0.0:
		var basis := Basis.from_euler(nearest_prim.rotation)
		var local: Vector3 = basis.inverse() * (point - nearest_prim.position)
		var half_extents: Vector3 = nearest_prim.scale * 0.5
		var margin_frac: float = chamfer_edge_pct / 100.0

		# Determine which face the point is on (closest face of this primitive)
		var abs_local := local.abs()
		var face_dists := [
			abs(abs_local.x - half_extents.x),  # X face
			abs(abs_local.y - half_extents.y),  # Y face
			abs(abs_local.z - half_extents.z)   # Z face
		]
		var face_axis: int = 0
		if face_dists[1] < face_dists[face_axis]: face_axis = 1
		if face_dists[2] < face_dists[face_axis]: face_axis = 2

		# Check tangential axes only (perpendicular to face normal)
		for a in range(3):
			if a == face_axis:
				continue
			var coord: float = abs_local[a]
			var extent: float = half_extents[a]
			var inner_extent: float = extent * (1.0 - margin_frac)
			if coord > inner_extent:
				is_edge_zone = true
				break

	# In main face body zone: force 100% hard cardinal (pure horizontal/vertical)
	if not is_edge_zone:
		var best_cardinal_dot := -1.0
		var best_cardinal := n
		for t in cardinal_targets:
			var d := n.dot(t)
			if d > best_cardinal_dot:
				best_cardinal_dot = d
				best_cardinal = t
		if best_cardinal_dot >= 0.5: # Within 60 degrees of cardinal
			return best_cardinal

	# In edge chamfer zone: evaluate both cardinal and angled chamfers
	var snap_threshold_deg: float = lerp(40.0, 0.0, clamp(crystallinity, 0.0, 1.0))
	if snap_threshold_deg <= 0.001:
		return n

	var cos_thresh := cos(deg_to_rad(snap_threshold_deg))
	var all_targets := cardinal_targets + chamfer_targets
	var best_dot := -1.0
	var best_target := n

	for target in all_targets:
		var d := n.dot(target)
		if d > best_dot:
			best_dot = d
			best_target = target

	if best_dot >= cos_thresh:
		return best_target

	return n

# Builds ArrayMesh from triangles with flat face normals for crisp faceting.
static func _build_faceted_mesh(triangles: Array, _facet_angle_deg: float, crystallinity: float = 0.0, primitives: Array = [], chamfer_edge_pct: float = 5.0, mirror_x: bool = false, smoothness: float = 0.0, voxel_size: float = 0.1) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for tri in triangles:
		var p0: Vector3 = tri[0]
		var p1: Vector3 = tri[1]
		var p2: Vector3 = tri[2]

		var n: Vector3 = (p1 - p0).cross(p2 - p0)
		if n.length_squared() < 1e-10:
			continue
		n = n.normalized()
		var center := (p0 + p1 + p2) / 3.0

		# Defensive winding fix, matching the one _march_cell() has always had
		# on the Marching Cubes path. Dual Contouring emits each quad's winding
		# from the sign of the field at the edge's origin corner, which does NOT
		# reliably produce outward-facing triangles: ~30% of every baked hull
		# came out wound inward (heavy_hull: 481 of 1632). Inward faces are
		# backface-culled, so they read as holes and dark patches, AND they are
		# invisible to placement raycasts, because create_trimesh_shape()'s
		# ConcavePolygonShape3D defaults to backface_collision = false. That is
		# the "large portions of the hull won't accept a module" symptom.
		#
		# Must happen BEFORE the normal snap: snapping an inward normal picks
		# the wrong cardinal target, so the lighting normal was wrong too.
		#
		# Decided against the SDF gradient, which is the same quantity the mesh's
		# shading normals are derived from - so "outward" here means the same
		# thing it means everywhere else in this file.
		#
		# The gradient is a central difference, and it vanishes in a couple of
		# places (inside a sub-voxel-thin feature, exactly on a union seam) where
		# _sdf_normal() would hand back its hard-coded Vector3.UP fallback and
		# make the test a coin flip. Only in that degenerate case, fall back to
		# sampling the field either side of the face: outside the solid the field
		# reads higher, so the higher side is the outside.
		#
		# Field-sampling was tried as the PRIMARY test and was clearly worse -
		# it disagreed with the gradient on up to 20 faces per hull, because at a
		# concave seam both probe points can sit inside solid material. Gradient
		# first, sampling only to break ties.
		var grad_raw := _sdf_gradient(center, primitives, smoothness, mirror_x)
		var flip := false
		if grad_raw.length_squared() > 1e-12:
			flip = n.dot(grad_raw) < 0.0
		else:
			var probe: float = max(voxel_size * 0.25, 0.001)
			flip = scene_sdf(center + n * probe, primitives, smoothness, mirror_x) \
				 < scene_sdf(center - n * probe, primitives, smoothness, mirror_x)
		if flip:
			var swap := p1
			p1 = p2
			p2 = swap
			n = -n

		n = _snap_constructed_normal(n, crystallinity, center, primitives, chamfer_edge_pct, mirror_x)

		st.set_normal(n)
		st.add_vertex(p0)
		st.set_normal(n)
		st.add_vertex(p1)
		st.set_normal(n)
		st.add_vertex(p2)

	return st.commit()


# ── Primitive Plane Snapping ─────────────────────────────────────────────

# Pulls each dual vertex onto the REAL face planes of the primitive it sits on,
# so a hull assembled from boxes and slopes reads as a constructed object:
# panels dead flat, edges dead straight, corners meeting exactly.
#
# Dual Contouring puts a vertex wherever the QEF fit lands inside each cell,
# which is near the surface but never exactly on it. Sub-voxel error that varies
# cell to cell is what makes a flat armour plate look faintly quilted and a
# straight edge look like a saw. The previous approach rounded coordinates onto
# an invented sub-voxel lattice, which traded that for a coarser, more regular
# sawtooth. A box's faces are at exactly +/-half_extent in its own local space,
# so there is no need to guess a grid: snap to the plane itself.
#
# Two guards keep this from tearing the mesh, both essential:
#
#  1. IN-CELL ONLY. A vertex is only moved to a plane that passes through its
#     own cell. Dual Contouring's manifold guarantee depends on each cell's
#     vertex staying inside that cell - push one out and the quads around it
#     fold over each other. Because a cell straddling a face plane is exactly
#     the cell that contains it, the right cells snap and no others.
#
#  2. STILL-ON-SURFACE. The candidate position is rejected unless it is still on
#     the union's isosurface. The nearest primitive's face plane is often BURIED
#     inside a neighbouring primitive (that's what a union does), and snapping to
#     a buried plane would drag the skin inward through solid material.
static func _snap_to_primitive_planes(dual_vertices: Dictionary, primitives: Array,
		smoothness: float, bounds: AABB, voxel_size: float,
		dim_x: int, dim_y: int, mirror_x: bool) -> void:
	if primitives.is_empty():
		return
	# How far a vertex will reach to find a plane.
	var tol: float = voxel_size * snap_tol_voxels
	# A candidate is "still on the surface" within this much of the isosurface.
	var surface_eps: float = voxel_size * snap_surface_eps_voxels
	# How far outside its own cell a vertex may be placed. Strict DC keeps every
	# vertex inside its cell; see snap_pad_voxels for why that is relaxed.
	var cell_pad: float = voxel_size * snap_pad_voxels + voxel_size * 0.001

	for cell_idx in dual_vertices:
		var vert: Vector3 = dual_vertices[cell_idx]
		if _is_on_curved_surface(vert, primitives, mirror_x):
			continue

		var ix: int = cell_idx % dim_x
		var iy: int = int(cell_idx / dim_x) % dim_y
		var iz: int = int(cell_idx / (dim_x * dim_y))
		var cell_min: Vector3 = bounds.position + Vector3(ix, iy, iz) * voxel_size
		var cell_max: Vector3 = cell_min + Vector3(voxel_size, voxel_size, voxel_size)

		# Fold for the nearest-primitive search when the field is folded, so the
		# -X half is matched against the primitive that actually shapes it.
		var probe := Vector3(absf(vert.x), vert.y, vert.z) if mirror_x else vert
		var nearest: Dictionary = primitives[0]
		var min_abs_dist: float = _FAR_DIST
		for prim in primitives:
			var d_abs: float = absf(primitive_sdf(probe, prim))
			if d_abs < min_abs_dist:
				min_abs_dist = d_abs
				nearest = prim
		# Only box-like primitives have flat faces to snap to.
		if nearest.type in CURVED_PRIMITIVE_TYPES:
			continue

		var basis := Basis.from_euler(nearest.rotation)
		var inv := basis.inverse()
		var half: Vector3 = nearest.scale.abs() * 0.5
		var local: Vector3 = inv * (probe - nearest.position)

		# Accept axes independently, then apply together - that is what makes an
		# edge (two planes) and a corner (three) land exactly, instead of only
		# ever resolving one face at a time.
		var snapped_local := local
		var changed := false
		for a in range(3):
			if half[a] <= 0.0001:
				continue
			var target: float = half[a] if local[a] >= 0.0 else -half[a]
			if absf(local[a] - target) > tol:
				continue
			var cand_local := snapped_local
			cand_local[a] = target
			var cand: Vector3 = nearest.position + basis * cand_local
			# Undo the fold to test against this vertex's own cell.
			if mirror_x and vert.x < 0.0:
				cand.x = -cand.x
			if cand[a] < cell_min[a] - cell_pad or cand[a] > cell_max[a] + cell_pad:
				continue
			if absf(scene_sdf(cand, primitives, smoothness, mirror_x)) > surface_eps:
				continue
			snapped_local = cand_local
			changed = true

		if not changed:
			continue
		var out: Vector3 = nearest.position + basis * snapped_local
		if mirror_x and vert.x < 0.0:
			out.x = -out.x
		dual_vertices[cell_idx] = out.clamp(
			cell_min - Vector3(cell_pad, cell_pad, cell_pad),
			cell_max + Vector3(cell_pad, cell_pad, cell_pad))

# ── Cardinal Panel Flattening ────────────────────────────────────────────

# Post-process dual vertices: for each cardinal normal direction (+/-X, +/-Y, +/-Z),
# cluster nearby vertices and project them onto a shared plane so that roofs, side
# walls, and floor panels are perfectly flat instead of exhibiting per-cell jitter.
static func _flatten_cardinal_panels(dual_vertices: Dictionary, primitives: Array, smoothness: float, crystallinity: float, chamfer_edge_pct: float, voxel_size: float, mirror_x: bool = false) -> void:
	if dual_vertices.is_empty():
		return

	# Classify every dual vertex by its dominant cardinal normal
	# 0=+X, 1=-X, 2=+Y, 3=-Y, 4=+Z, 5=-Z
	var cardinal_dirs := [
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, -1, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1)
	]
	# axis_index per cardinal: 0,0,1,1,2,2
	var cardinal_axis := [0, 0, 1, 1, 2, 2]

	var groups: Array = [[], [], [], [], [], []]  # one array of cell_ids per cardinal

	for cell_idx in dual_vertices:
		var v: Vector3 = dual_vertices[cell_idx]
		# Never flatten a curved surface into a plane - see _is_on_curved_surface.
		if _is_on_curved_surface(v, primitives, mirror_x):
			continue
		var n: Vector3 = _sdf_normal(v, primitives, smoothness, mirror_x)
		n = _snap_constructed_normal(n, crystallinity, v, primitives, chamfer_edge_pct, mirror_x)

		for ci in range(6):
			if n.dot(cardinal_dirs[ci]) > 0.9:
				groups[ci].append(cell_idx)
				break

	# For each cardinal group, cluster by position along the normal axis
	# and flatten each cluster to its average coordinate.
	for ci in range(6):
		var ids: Array = groups[ci]
		if ids.size() < 2:
			continue

		var ax: int = cardinal_axis[ci]
		# +1 for the outward-positive cardinal of this axis, -1 for its twin.
		var dir: float = cardinal_dirs[ci][ax]

		# Sort by coordinate * dir, i.e. inward-to-outward, NOT by raw ascending
		# coordinate. Mirroring maps the +X group onto the -X group with every
		# coordinate negated, so raw ascending order traverses the two groups in
		# opposite directions: they anchor their clusters at opposite ends and
		# split at non-mirrored boundaries, which made a perfectly symmetric
		# assembly (e.g. medium_hull, whose only off-centre primitives are an
		# exact +/-1.32 pair) bake asymmetrically. coord*dir is invariant under
		# the mirror, so both sides cluster identically.
		ids.sort_custom(func(a, b):
			return dual_vertices[a][ax] * dir < dual_vertices[b][ax] * dir
		)

		# Cluster: group vertices lying within 1.5 voxels along the axis.
		#
		# The gap test is against the cluster's ANCHOR (its first coordinate),
		# not against the immediately preceding vertex. Comparing to the
		# predecessor makes clustering transitive: a run of vertices each
		# within tolerance of the last chains into one cluster of unbounded
		# extent, which then gets flattened to a single averaged plane. That
		# silently ate genuine steps and ledges whenever the stair risers
		# happened to be spaced under 1.5 voxels apart.
		var tolerance: float = voxel_size * 1.5
		var clusters: Array = [[ids[0]]]
		var anchor_coord: float = dual_vertices[ids[0]][ax] * dir
		for i in range(1, ids.size()):
			var curr_coord: float = dual_vertices[ids[i]][ax] * dir
			if abs(curr_coord - anchor_coord) < tolerance:
				clusters[-1].append(ids[i])
			else:
				clusters.append([ids[i]])
				anchor_coord = curr_coord

		# Flatten each cluster to the average coordinate along the axis
		for cluster in clusters:
			if cluster.size() < 2:
				continue
			var avg_coord: float = 0.0
			for idx in cluster:
				avg_coord += dual_vertices[idx][ax]
			avg_coord /= float(cluster.size())

			for idx in cluster:
				var v: Vector3 = dual_vertices[idx]
				v[ax] = avg_coord
				dual_vertices[idx] = v


# ── Curvature estimation ───────────────────────────────────────────────────

static func _estimate_curvature(world_point: Vector3, nearest_prim: Dictionary, primitives: Array, smoothness: float) -> float:
	# Local-space curvature estimation for intelligent normal snapping
	# Measures curvature in primitive-local coordinates rather than world-space
	# to avoid artifacts with rotated or translated primitives.

	var basis := Basis.from_euler(nearest_prim.rotation)
	var local_point: Vector3 = basis.inverse() * (world_point - nearest_prim.position)
	var scale: Vector3 = Vector3(
		max(abs(nearest_prim.scale.x), 0.0001),
		max(abs(nearest_prim.scale.y), 0.0001),
		max(abs(nearest_prim.scale.z), 0.0001))
	var half_extents: Vector3 = scale * 0.5
	var prim_type: int = nearest_prim.type

	match prim_type:
		# Flat primitive: zero curvature
		TYPE_BOX, TYPE_WEDGE, TYPE_SLOPE, TYPE_FRUSTUM, TYPE_CHAMFER_BOX, TYPE_HALF_CYLINDER, TYPE_I_BEAM, TYPE_L_BEAM, TYPE_HEX_PRISM, TYPE_PYRAMID, TYPE_FENDER, TYPE_CANOPY:
			return 0.0

		# Perfectly curved primitives (constant curvature across surface)
		TYPE_SPHERE:
			# Sphere has constant positive curvature everywhere
			# Gaussian curvature K = 1/r^2, mean curvature H = 1/r
			# Convert to angular deviation: max normal deviation = arcsin(1/r)
			var r: float = min(half_extents.x, min(half_extents.y, half_extents.z))
			if r > 0.0001:
				# Maximum angular deviation from point vs sphere center
				var angle_rad: float = atan(sqrt(3.0) / r)
				return rad_to_deg(angle_rad)
			return 0.0

		TYPE_CYLINDER:
			# Cylinder has zero Gaussian curvature but principal curvature H = 1/r
			var r: float = min(half_extents.x, half_extents.z)
			if r > 0.0001:
				var angle_rad: float = atan(sqrt(3.0) / r)
				return rad_to_deg(angle_rad)
			return 0.0

		TYPE_CONE:
			# Cone curvature varies with position - at vertex it's infinite
			# At base it's 1/r, but we're approximating with mid-cylinder value
			var r: float = min(half_extents.x, half_extents.z)
			if r > 0.0001:
				var angle_rad: float = atan(sqrt(3.0) / r) * 0.7  # Moderate for cone
				return rad_to_deg(angle_rad)
			return 0.0

		TYPE_TORUS:
			# Torus has varying curvature (inner and outer radii)
			var r_major: float = min(half_extents.x, half_extents.z) * 0.8
			var r_minor: float = min(half_extents.x, min(half_extents.y, half_extents.z)) * 0.2
			if r_minor > 0.0001:
				# Focus on minor radius for local surface curvature
				var angle_rad: float = atan(sqrt(3.0) / r_minor)
				return rad_to_deg(angle_rad)
			return 0.0

		TYPE_HEMISPHERE:
			# Hemisphere inherits sphere curvature on dome surface
			var r: float = min(half_extents.x, min(half_extents.y, half_extents.z))
			if r > 0.0001:
				var angle_rad: float = atan(sqrt(3.0) / r) * 0.9  # Very curved
				return rad_to_deg(angle_rad)
			return 0.0

		TYPE_CAPSULE:
			# Capsule is curved cylinder with hemispherical ends
			var r: float = min(half_extents.x, half_extents.z)
			if r > 0.0001:
				var angle_rad: float = atan(sqrt(3.0) / r) * 0.8
				return rad_to_deg(angle_rad)
			return 0.0

		TYPE_RING:
			# Ring is a critical special case - has two curvatures:
			# 1. Major radius curvature (outer/inner radii): primary ring shape
			# 2. Minor radius curvature (tube thickness): secondary tube shape
			# For ring rendering we need major radius curvature since that
			# determines whether the ring appears as a smooth circle vs blocky.
			var r_out: float = min(half_extents.x, half_extents.z)
			var r_in: float = r_out * 0.6  # Per _sdf_ring in hash
			var r_tube: float = min(half_extents.y * 0.5, r_out - r_in) * 0.5

			# PRIMARY curvature (for ring appearance): use major radius
			# This determines whether we snap to cardinal or keep circle
			if r_out > 0.0001:
				var angle_rad: float = atan(sqrt(3.0) / r_out)
				return rad_to_deg(angle_rad)
			return 0.0

		# FALLBACK - default to zero curvature for unknown types
		_:
			return 0.0

	# ── SDF evaluation ───────────────────────────────────────────────────────

static func scene_sdf(world_point: Vector3, primitives: Array, smoothness: float, mirror_x: bool = false) -> float:
	if primitives.is_empty():
		return 1e9
	# Bilateral X-Symmetry Enforcement: fold world_point into the +X domain.
	#
	# This is now OPT-IN (mirror_x), defaulting OFF, because folding does not
	# merely tidy up symmetry - it SILENTLY DELETES GEOMETRY. The fold can only
	# ever produce sample points with x >= 0, so a primitive whose CENTRE sits
	# at negative x is never reached at all: its local coordinate would need a
	# negative sample x to evaluate inside. It does not get mirrored to the
	# other side, it vanishes.
	#
	# heavy_hull was losing two primitives to this: the port side-rail at
	# x=-1.82 (masked, because its starboard twin at +1.82 was mirrored back
	# over the port side and looked correct) and the unpaired HEMISPHERE cupola
	# at x=-0.7, which simply never appeared in any baked hull.
	#
	# Exact symmetry for hand-mirrored pairs now comes from _center_grid_x()
	# instead, which makes the sample lattice itself mirror-symmetric. That
	# achieves what the fold was reaching for without destroying anything.
	var sym_point := Vector3(abs(world_point.x), world_point.y, world_point.z) if mirror_x else world_point

	# Hard union: min() is associative, so array order cannot matter.
	if smoothness <= 0.0001:
		var d_hard: float = primitive_sdf(sym_point, primitives[0])
		for i in range(1, primitives.size()):
			d_hard = min(d_hard, primitive_sdf(sym_point, primitives[i]))
		return d_hard

	# Smooth union: fold in ARRAY ORDER. Do not "improve" this by sorting.
	#
	# smin() is not associative, so array order does affect the result, and that
	# does cost a little bilateral symmetry (airship_hull, the only hull with a
	# large smoothness, ends up with ~3% of its vertices lacking an exact mirror
	# partner). Sorting the distances first makes the fold order a function of
	# geometry alone and fixes that - and it also DESTROYS both smooth hulls.
	#
	# The reason is that a smooth union is load-bearing structure here, not a
	# finishing touch. airship_hull's primitives do not overlap: the envelope is
	# a chain of separate volumes that only becomes one connected surface because
	# each iterated smin() inflates the running result toward the next primitive,
	# compounding across the fold and bridging the gaps between them. Sorting
	# ascending blends the running minimum against ever more DISTANT values,
	# where smin(a, b, k) with b >> a just returns a - so the compounding stops,
	# the bridges vanish, and the hull falls apart into detached pieces (measured:
	# airship 2 components, and the since-retired flying wing 2 components + 24
	# boundary edges).
	#
	# A few percent of mirror asymmetry on one hull is a far better trade than an
	# airship in bits. If exact symmetry for smooth hulls is wanted later, the fix
	# is an order-independent blend that still compounds - exponential smooth-min,
	# -log(sum(exp(-k*d_i)))/k - not sorting this one.
	var d: float = primitive_sdf(sym_point, primitives[0])
	for i in range(1, primitives.size()):
		d = smin(d, primitive_sdf(sym_point, primitives[i]), smoothness)
	return d

# Polynomial smooth-min (Inigo Quilez). k <= 0 degenerates to a hard min, i.e.
# a plain CSG union with sharp seams - so Smoothness = 0 is a legitimate,
# supported choice, not a special case callers need to avoid.
static func smin(a: float, b: float, k: float) -> float:
	if k <= 0.0001:
		return min(a, b)
	var h: float = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerp(b, a, h) - k * h * (1.0 - h)

# Transforms world_point into the primitive's local space and evaluates
# exact scaled distances for crisp non-blobby CSG geometry.
static func primitive_sdf(world_point: Vector3, prim: Dictionary) -> float:
	var basis := Basis.from_euler(prim.rotation)
	var local: Vector3 = basis.inverse() * (world_point - prim.position)
	var scale: Vector3 = Vector3(
		max(abs(prim.scale.x), 0.0001),
		max(abs(prim.scale.y), 0.0001),
		max(abs(prim.scale.z), 0.0001))
	var half_extents: Vector3 = scale * 0.5
	return _scaled_sdf(local, half_extents, prim.type)

static func _scaled_sdf(p: Vector3, h: Vector3, type: int) -> float:
	match type:
		TYPE_BOX:
			return _sdf_box(p, h)
		TYPE_SPHERE:
			# Fills the primitive's box as an ellipsoid rather than collapsing to
			# a ball of the smallest half-extent - see _sdf_ellipsoid.
			return _sdf_ellipsoid(p, h)
		TYPE_CYLINDER:
			# Elliptical cross-section, so a cylinder stretched in one horizontal
			# axis stays stretched instead of shrinking to the narrower one.
			return _sdf_elliptic_cylinder(p, h.x, h.z, h.y)
		TYPE_WEDGE:
			return _sdf_wedge(p, h)
		TYPE_CONE:
			var r: float = min(h.x, h.z)
			return _sdf_cone(p, r, h.y)
		TYPE_TORUS:
			var r_major: float = min(h.x, h.z) * 0.8
			var r_minor: float = min(h.x, min(h.y, h.z)) * 0.2
			return _sdf_torus(p, r_major, r_minor)
		TYPE_SLOPE:
			return _sdf_slope(p, h)
		TYPE_FRUSTUM:
			return _sdf_frustum(p, h, 0.5)
		TYPE_CHAMFER_BOX:
			var chamfer_r: float = min(h.x, min(h.y, h.z)) * 0.15
			return _sdf_chamfer_box(p, h, chamfer_r)
		TYPE_HALF_CYLINDER:
			var r: float = min(h.x, h.z)
			return _sdf_half_cylinder(p, r, h.y)
		TYPE_HEMISPHERE:
			return _sdf_dome(p, h)
		TYPE_CAPSULE:
			var r: float = min(h.x, h.z)
			return _sdf_capsule(p, r, h.y - r)
		TYPE_I_BEAM:
			return _sdf_i_beam(p, h, h.x * 0.3, h.y * 0.3)
		TYPE_L_BEAM:
			return _sdf_l_beam(p, h, min(h.x, h.y) * 0.35)
		TYPE_HEX_PRISM:
			var r: float = min(h.x, h.z)
			return _sdf_hex_prism(p, r, h.y)
		TYPE_PYRAMID:
			return _sdf_frustum(p, h, 0.0)
		TYPE_FENDER:
			return _sdf_fender(p, min(h.x, h.z), min(h.y, h.z) * 0.3)
		TYPE_CANOPY:
			# A canopy is just a dome elongated along Z, which the ellipsoidal
			# dome expresses directly through its per-axis radii.
			return _sdf_dome(p, h)
		TYPE_RING:
			var r_out: float = min(h.x, h.z)
			var r_in: float = r_out * 0.6
			return _sdf_ring(p, r_out, r_in, h.y)
		_:
			return _sdf_box(p, h)

# Ellipsoid with independent per-axis radii (Inigo Quilez's standard bounded
# approximation - not an exact distance field, but accurate near the surface,
# which is all polygonisation needs).
#
# This exists because the sphere family used to collapse non-uniform scale to
# min(h.x, h.y, h.z) and return a PERFECT BALL of that radius. That is not an
# approximation of an ellipsoid, it is a different and far smaller shape, and it
# destroyed every hull built on a stretched sphere:
#
#   airship_hull's envelope is a SPHERE scaled 5.8 x 3.6 x 12.6 - a 12.6-long
#   gasbag. min() made it a ball of radius 1.8, so the envelope no longer
#   reached the gondola, tail or nose, and the hull baked as a small ball with
#   several boxes floating around it in mid-air. The retired flying wing hull's
#   5.6-long body sphere became a 0.7-radius pebble the same way.
static func _sdf_ellipsoid(p: Vector3, r: Vector3) -> float:
	var rr := Vector3(max(r.x, 0.0001), max(r.y, 0.0001), max(r.z, 0.0001))
	var k0: float = Vector3(p.x / rr.x, p.y / rr.y, p.z / rr.z).length()
	if k0 < 0.00001:
		return -min(rr.x, min(rr.y, rr.z))
	var k1: float = Vector3(p.x / (rr.x * rr.x), p.y / (rr.y * rr.y), p.z / (rr.z * rr.z)).length()
	if k1 < 0.000001:
		return k0 - 1.0
	return k0 * (k0 - 1.0) / k1

static func _sdf_box(p: Vector3, half_extents: Vector3) -> float:
	var q: Vector3 = p.abs() - half_extents
	var outside := Vector3(max(q.x, 0.0), max(q.y, 0.0), max(q.z, 0.0))
	return outside.length() + min(max(q.x, max(q.y, q.z)), 0.0)

# Axis-aligned along Y, matching Godot's CylinderMesh convention.
static func _sdf_cylinder(p: Vector3, radius: float, half_height: float) -> float:
	var d := Vector2(Vector2(p.x, p.z).length() - radius, abs(p.y) - half_height)
	var outside := Vector2(max(d.x, 0.0), max(d.y, 0.0))
	return outside.length() + min(max(d.x, d.y), 0.0)

# Capped cone, apex at +Y, base (radius base_radius) at -Y - matches
# hull_builder.gd's CONE (a CylinderMesh with top_radius = 0). An
# approximation (radius-vs-y isn't a true unit-gradient distance field) but
# accurate enough for MC + smooth-min purposes - the same tradeoff every
# SDF-modeling primitive library makes for cones.
static func _sdf_cone(p: Vector3, base_radius: float, half_height: float) -> float:
	var t: float = clamp((p.y + half_height) / (2.0 * half_height), 0.0, 1.0)
	var r_at_y: float = lerp(base_radius, 0.0, t)
	var d := Vector2(Vector2(p.x, p.z).length() - r_at_y, abs(p.y) - half_height)
	var outside := Vector2(max(d.x, 0.0), max(d.y, 0.0))
	return outside.length() + min(max(d.x, d.y), 0.0)

# Torus in the XZ plane (Y is the ring axis), matching Godot's TorusMesh.
static func _sdf_torus(p: Vector3, major_radius: float, minor_radius: float) -> float:
	var q := Vector2(Vector2(p.x, p.z).length() - major_radius, p.y)
	return q.length() - minor_radius

# Ramp/wedge: full height (he.y*2) at -Z, tapering linearly to zero height at
# +Z, full width in X - a glacis-plate style ramp. Built as the intersection
# of 6 half-spaces (the box's 5 axis-aligned faces minus the top, plus the
# sloped top plane), combined via max() - exact near the surface (what
# matters for MC), the standard technique for a convex half-space
# intersection SDF.
static func _sdf_wedge(p: Vector3, he: Vector3) -> float:
	var d1: float = p.x - he.x
	var d2: float = -p.x - he.x
	var d3: float = -p.y - he.y
	var d4: float = p.z - he.z
	var d5: float = -p.z - he.z

	var slope: float = he.y / he.z
	var top_raw: float = p.y - he.y + he.y * (p.z + he.z) / he.z
	var d6: float = top_raw / sqrt(1.0 + slope * slope)

	return max(d1, max(d2, max(d3, max(d4, max(d5, d6)))))

# Single 45-degree bevel through the top-front edge only (Godot +Y, -Z) -
# matches build_hull_primitives.py's build_slope(), whose bevel offset=0.35
# on a unit cube puts the cut plane through (y=0.5, z=-0.15) and
# (y=0.15, z=-0.5); same convex half-space-intersection technique as
# _sdf_wedge, just one extra shallow cut instead of a full-height ramp.
static func _sdf_slope(p: Vector3, he: Vector3) -> float:
	var d_box: float = _sdf_box(p, he)
	# The cut plane has to be expressed RELATIVE to the primitive's half-extents.
	#
	# It used to be the absolute plane (p.y - p.z - 0.65), which is correct only
	# at he = (0.5, 0.5, 0.5) - the unit cube the 0.35 bevel offset was measured
	# on. primitive_sdf() passes local coordinates at full world scale, so on any
	# other size the cut landed in the wrong place and the bevel came out at an
	# arbitrary angle: assault_hull scales its SLOPE to 2.8 x 1.6 x 2 and
	# light_hull to 2.3 x 1.05 x 1.45, so neither matched its own authored
	# preview mesh, and the glacis angle was whatever the scale happened to make
	# it. Normalising by he.y/he.z reproduces build_slope()'s proportions at
	# every size: the plane passes through (y, z) = (he.y, -0.3*he.z) and
	# (0.3*he.y, -he.z), which is 2y - 2z = 1.3 on the unit cube, i.e. exactly
	# the old constant.
	if he.y <= 0.0001 or he.z <= 0.0001:
		return d_box
	var f: float = p.y / he.y - p.z / he.z - 1.3
	var grad: float = sqrt(1.0 / (he.y * he.y) + 1.0 / (he.z * he.z))
	return max(d_box, f / grad)

# Box tapered from full half-extents at -Y to half-extents*top_scale at +Y -
# matches build_hull_primitives.py's build_frustum() (top_scale=0.5) and, at
# top_scale=0.0 (tapering all the way to a point), doubles as the pyramid
# SDF - same tapering-half-extent approximation _sdf_cone() already uses.
static func _sdf_frustum(p: Vector3, he: Vector3, top_scale: float) -> float:
	var t: float = clamp((p.y + he.y) / (2.0 * he.y), 0.0, 1.0)
	var hx: float = lerp(he.x, he.x * top_scale, t)
	var hz: float = lerp(he.z, he.z * top_scale, t)
	var qx: float = abs(p.x) - hx
	var qy: float = abs(p.y) - he.y
	var qz: float = abs(p.z) - hz
	var outside := Vector3(max(qx, 0.0), max(qy, 0.0), max(qz, 0.0))
	return outside.length() + min(max(qx, max(qy, qz)), 0.0)

# TRUE chamfered box: the box intersected with 45-degree planes across each of
# its 12 edges, giving flat bevel facets and hard edges either side of them.
#
# This used to be a ROUNDED box - _sdf_box(p, he - r) - r, Quilez's round-over
# construction. That is a fillet, not a chamfer: it replaces every edge with a
# smoothly curved quarter-round, which by definition has no hard edge anywhere on
# it. On assault_hull it was the single largest source of non-cardinal surface
# area, and it is exactly the "smooshed instead of constructed" look - the shape
# named CHAMFER_BOX was the one shape in the kit guaranteed to never produce a
# crisp edge. build_hull_primitives.py's build_chamfer_box() authors a real
# flat-bevel chamfer, so the SDF now matches the mesh the editor previews.
#
# Each cut is a half-space on the sum of two |coords| - the standard convex
# half-space-intersection technique already used by _sdf_wedge and _sdf_ring.
# The 8 corner facets fall out of the three edge cuts meeting, no extra term.
static func _sdf_chamfer_box(p: Vector3, he: Vector3, chamfer: float) -> float:
	var d: float = _sdf_box(p, he)
	var q: Vector3 = p.abs()
	var inv_sqrt2: float = 0.70710678
	d = max(d, (q.x + q.y - (he.x + he.y - chamfer)) * inv_sqrt2)
	d = max(d, (q.y + q.z - (he.y + he.z - chamfer)) * inv_sqrt2)
	d = max(d, (q.x + q.z - (he.x + he.z - chamfer)) * inv_sqrt2)
	return d

# Flat-bottomed half-round trough, extruded along Z - matches
# build_hull_primitives.py's build_half_cylinder(): a disc of the given
# radius centered at Y=-radius (so its flat diameter sits at the unit box's
# floor Y=-he.y and its crown reaches Y=0), intersected with the upper
# half-space, same max()-of-two-exact-SDFs technique as _sdf_wedge/_sdf_ring.
static func _sdf_half_cylinder(p: Vector3, radius: float, half_len: float) -> float:
	var d_round: float = Vector2(p.x, p.y + radius).length() - radius
	var d_flat: float = -p.y - radius
	var d2: float = max(d_round, d_flat)
	var dz: float = abs(p.z) - half_len
	var outside := Vector2(max(d2, 0.0), max(dz, 0.0))
	return outside.length() + min(max(d2, dz), 0.0)

# Flat-bottomed dome: a sphere of the given radius centered at Y=-radius
# (flat base at the unit box floor, apex at Y=0), intersected with the upper
# half-space - same technique as _sdf_half_cylinder, one dimension up.
# z_stretch=1.0 matches build_hull_primitives.py's build_hemisphere();
# z_stretch>1.0 (canopy) elongates the dome along Z the same way that
# script's build_canopy() does, via a non-uniform-scale approximation
# (same acceptable-approximation tradeoff primitive_sdf() already documents
# for non-uniform scale in general).
# Rewritten to take the half-extents directly. The old signature took a single
# radius plus a z_stretch factor, and every caller passed min(h...) for the
# radius - so a dome or canopy stretched in x or z shrank to its narrowest axis
# instead of filling its box (see _sdf_ellipsoid for the same bug on SPHERE).
#
# Base sits on the primitive's floor (y = -he.y) and the apex reaches its ceiling
# (y = +he.y), so the vertical radius is the full 2*he.y about a centre at the
# floor - matching build_hull_primitives.py's build_hemisphere()/build_canopy(),
# which both fill the unit cell.
static func _sdf_dome(p: Vector3, he: Vector3) -> float:
	var radii := Vector3(he.x, he.y * 2.0, he.z)
	var d_ellip: float = _sdf_ellipsoid(Vector3(p.x, p.y + he.y, p.z), radii)
	var d_flat: float = -p.y - he.y
	return max(d_ellip, d_flat)

# Cylinder with an elliptical cross-section, extruded along Y.
static func _sdf_elliptic_cylinder(p: Vector3, rx: float, rz: float, half_height: float) -> float:
	var ex: float = max(rx, 0.0001)
	var ez: float = max(rz, 0.0001)
	# Radial term scaled back into world units so it stays comparable with the
	# Y term (a raw normalised value would not be a distance).
	var k: float = Vector2(p.x / ex, p.z / ez).length()
	var d_radial: float = (k - 1.0) * min(ex, ez)
	var d_y: float = abs(p.y) - half_height
	var outside := Vector2(max(d_radial, 0.0), max(d_y, 0.0))
	return outside.length() + min(max(d_radial, d_y), 0.0)

# Capsule (cylinder + hemispherical caps) along Y - exact SDF, matches
# Godot's native CapsuleMesh built directly for this type in hull_builder.gd
# (no authored .glb - see AUTHORED_PRIMITIVE_SHAPES there).
static func _sdf_capsule(p: Vector3, radius: float, half_seg: float) -> float:
	var py: float = clamp(p.y, -half_seg, half_seg)
	return Vector3(p.x, p.y - py, p.z).length() - radius

# I-beam cross-section (top flange + bottom flange + web), extruded along Z -
# a hard union (min) of 3 boxes, matching build_hull_primitives.py's
# build_i_beam() 12-point outline. Hard seams are correct here (an I-beam
# reads as assembled structural stock, not a single smooth casting).
static func _sdf_i_beam(p: Vector3, he: Vector3, flange_thick: float, web_half_width: float) -> float:
	var top_flange: float = _sdf_box(p - Vector3(0, he.y - flange_thick, 0), Vector3(he.x, flange_thick, he.z))
	var bot_flange: float = _sdf_box(p - Vector3(0, -(he.y - flange_thick), 0), Vector3(he.x, flange_thick, he.z))
	var web: float = _sdf_box(p, Vector3(web_half_width, he.y, he.z))
	return min(top_flange, min(bot_flange, web))

# L-angle bracket cross-section (vertical leg + horizontal leg), extruded
# along Z - hard union of 2 boxes, matching build_hull_primitives.py's
# build_l_beam() 6-point outline.
static func _sdf_l_beam(p: Vector3, he: Vector3, thick: float) -> float:
	var vertical: float = _sdf_box(p - Vector3(-(he.x - thick), 0, 0), Vector3(thick, he.y, he.z))
	var horizontal: float = _sdf_box(p - Vector3(0, -(he.y - thick), 0), Vector3(he.x, thick, he.z))
	return min(vertical, horizontal)

# 2D regular-hexagon SDF (Inigo Quilez's standard formula) extruded along Z -
# matches a 6-radial-segment CylinderMesh, i.e. hull_builder.gd's native
# HEX_PRISM mesh (no authored asset - see AUTHORED_PRIMITIVE_SHAPES).
static func _sdf_hex_prism(p: Vector3, radius: float, half_len: float) -> float:
	var k := Vector3(-0.8660254, 0.5, 0.57735)
	var qx: float = abs(p.x)
	var qy: float = abs(p.y)
	var m: float = 2.0 * min(k.x * qx + k.y * qy, 0.0)
	qx -= m * k.x
	qy -= m * k.y
	qx -= clamp(qx, -k.z * radius, k.z * radius)
	qy -= radius
	var d2: float = Vector2(qx, qy).length() * sign(qy)
	var dz: float = abs(p.z) - half_len
	var outside := Vector2(max(d2, 0.0), max(dz, 0.0))
	return outside.length() + min(max(d2, dz), 0.0)

# Open half-torus arch (wheel-arch/mudguard read): a full torus SDF
# intersected with the upper half-space (Godot Y>=0), matching
# build_hull_primitives.py's build_fender() 0..pi arc sweep.
static func _sdf_fender(p: Vector3, major_radius: float, minor_radius: float) -> float:
	var d_torus: float = _sdf_torus(p, major_radius, minor_radius)
	var d_flat: float = -p.y
	return max(d_torus, d_flat)

# Flat annulus/washer (square cross-section, unlike TORUS's round
# cross-section), extruded along Y - matches build_hull_primitives.py's
# build_ring(): radial distance clamped between inner_radius and
# outer_radius (outside the ring = outside outer_radius OR inside
# inner_radius), combined with the Y-extent the same way _sdf_cylinder does.
static func _sdf_ring(p: Vector3, outer_radius: float, inner_radius: float, half_height: float) -> float:
	var radial: float = Vector2(p.x, p.z).length()
	var d2: float = max(radial - outer_radius, inner_radius - radial)
	var dy: float = abs(p.y) - half_height
	var outside := Vector2(max(d2, 0.0), max(dy, 0.0))
	return outside.length() + min(max(d2, dy), 0.0)

# Raw (un-normalised) central-difference gradient. Callers that need to know
# whether the gradient actually exists use this instead of _sdf_normal(), which
# hides a vanishing gradient behind a Vector3.UP fallback.
static func _sdf_gradient(p: Vector3, primitives: Array, smoothness: float, mirror_x: bool = false) -> Vector3:
	var eps := 0.01
	return Vector3(
		scene_sdf(p + Vector3(eps, 0, 0), primitives, smoothness, mirror_x) \
			- scene_sdf(p - Vector3(eps, 0, 0), primitives, smoothness, mirror_x),
		scene_sdf(p + Vector3(0, eps, 0), primitives, smoothness, mirror_x) \
			- scene_sdf(p - Vector3(0, eps, 0), primitives, smoothness, mirror_x),
		scene_sdf(p + Vector3(0, 0, eps), primitives, smoothness, mirror_x) \
			- scene_sdf(p - Vector3(0, 0, eps), primitives, smoothness, mirror_x))

static func _sdf_normal(p: Vector3, primitives: Array, smoothness: float, mirror_x: bool = false) -> Vector3:
	var eps := 0.01
	var dx: float = scene_sdf(p + Vector3(eps, 0, 0), primitives, smoothness, mirror_x) \
		- scene_sdf(p - Vector3(eps, 0, 0), primitives, smoothness, mirror_x)
	var dy: float = scene_sdf(p + Vector3(0, eps, 0), primitives, smoothness, mirror_x) \
		- scene_sdf(p - Vector3(0, eps, 0), primitives, smoothness, mirror_x)
	var dz: float = scene_sdf(p + Vector3(0, 0, eps), primitives, smoothness, mirror_x) \
		- scene_sdf(p - Vector3(0, 0, eps), primitives, smoothness, mirror_x)
	var n := Vector3(dx, dy, dz)
	if n.length_squared() < 0.0000001:
		return Vector3.UP
	return n.normalized()

# ── AABB ─────────────────────────────────────────────────────────────────

static func _compute_primitives_aabb(primitives: Array) -> AABB:
	var result := AABB()
	var first := true
	for prim in primitives:
		var basis := Basis.from_euler(prim.rotation)
		var he: Vector3 = prim.scale.abs() * _UNIT_BOUND
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var local_corner := Vector3(sx * he.x, sy * he.y, sz * he.z)
					var world_corner: Vector3 = prim.position + basis * local_corner
					if first:
						result = AABB(world_corner, Vector3.ZERO)
						first = false
					else:
						result = result.expand(world_corner)
	return result

# ── Marching Cubes ───────────────────────────────────────────────────────

static func _grid_index(ix: int, iy: int, iz: int, dim_x: int, dim_y: int) -> int:
	return ix + dim_x * (iy + dim_y * iz)

static func _march_cell(st: SurfaceTool, ix: int, iy: int, iz: int, dim_x: int, dim_y: int,
		field: PackedFloat32Array, origin: Vector3, voxel_size: float,
		primitives: Array, smoothness: float, mirror_x: bool = false) -> int:
	var corner_val := PackedFloat32Array()
	corner_val.resize(8)
	for c in range(8):
		var off: Vector3 = MCTables.CORNER_OFFSETS[c]
		var cx: int = ix + int(off.x)
		var cy: int = iy + int(off.y)
		var cz: int = iz + int(off.z)
		corner_val[c] = field[_grid_index(cx, cy, cz, dim_x, dim_y)]

	var cube_index := 0
	for c in range(8):
		if corner_val[c] < 0.0:
			cube_index |= (1 << c)

	var edge_mask: int = MCTables.EDGE_TABLE[cube_index]
	if edge_mask == 0:
		return 0

	var base := Vector3(ix, iy, iz)
	var edge_pos := {}
	for e in range(12):
		if (edge_mask & (1 << e)) != 0:
			var pair: Array = MCTables.EDGE_CORNERS[e]
			var c0: int = pair[0]
			var c1: int = pair[1]
			var p0: Vector3 = origin + (base + MCTables.CORNER_OFFSETS[c0]) * voxel_size
			var p1: Vector3 = origin + (base + MCTables.CORNER_OFFSETS[c1]) * voxel_size
			var v0: float = corner_val[c0]
			var v1: float = corner_val[c1]
			var t := 0.5
			if abs(v1 - v0) > 0.00001:
				t = clamp(v0 / (v0 - v1), 0.0, 1.0)
			edge_pos[e] = p0.lerp(p1, t)

	var tris: Array = MCTables.TRI_TABLE[cube_index]
	var count := 0
	var i := 0
	while i < tris.size() and tris[i] != -1:
		var pa: Vector3 = edge_pos[tris[i]]
		var pb: Vector3 = edge_pos[tris[i + 1]]
		var pc: Vector3 = edge_pos[tris[i + 2]]
		var na := _sdf_normal(pa, primitives, smoothness, mirror_x)
		var nb := _sdf_normal(pb, primitives, smoothness, mirror_x)
		var nc := _sdf_normal(pc, primitives, smoothness, mirror_x)

		# Defensive winding fix: force triangle winding to agree with the
		# outward SDF gradient regardless of the source table's assumed
		# convention, so a winding mismatch can't silently backface-cull the
		# whole bake into invisibility.
		var face_n: Vector3 = (pb - pa).cross(pc - pa)
		if face_n.dot(na + nb + nc) < 0.0:
			var tmp_p := pb
			pb = pc
			pc = tmp_p
			var tmp_n := nb
			nb = nc
			nc = tmp_n

		st.set_normal(na)
		st.add_vertex(pa)
		st.set_normal(nb)
		st.add_vertex(pb)
		st.set_normal(nc)
		st.add_vertex(pc)
		count += 1
		i += 3
	return count
