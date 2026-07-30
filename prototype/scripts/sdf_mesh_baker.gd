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

# Conservative unit-space half-extent shared by _compute_primitives_aabb() -
# every primitive type in hull_builder.gd is built at unit size (see its
# _build_mesh_for_type()); 0.6 covers all of them (box/sphere/cylinder/cone/
# wedge are exactly 0.5, the torus's outer_radius is 0.6) with a little
# headroom, since this AABB only sizes the voxel grid, not the final surface.
const _UNIT_BOUND := 0.6

# ── Public API ────────────────────────────────────────────────────────────

# Unified bake entry point.
# method: "dc" (Dual Contouring - hard facets & sharp edges) or "mc" (Marching Cubes - smooth).
# fit_percent: 0..100+ (for DC: controls how tightly vertices hug the SDF isosurface, default 95).
# facet_angle_deg: angle threshold for coplanar face merging.
# crystallinity: 0.0 (constructed/axis-aligned plates & standard slope angles) .. 1.0 (unconstrained/crystalline facets).
# chamfer_edge_pct: 0.0% .. 25.0% (default 5.0% - weights edge zone for angled chamfers while locking main face bodies 100% cardinal).
static func bake(primitives: Array, smoothness: float, resolution: int, method: String = "dc", fit_percent: float = 95.0, facet_angle_deg: float = 15.0, crystallinity: float = 0.0, chamfer_edge_pct: float = 5.0) -> ArrayMesh:
	if method.to_lower() == "mc":
		return bake_mc(primitives, smoothness, resolution)
	return bake_dc(primitives, smoothness, resolution, fit_percent, facet_angle_deg, crystallinity, chamfer_edge_pct)

# Legacy / Smooth Marching Cubes pipeline
static func bake_mc(primitives: Array, smoothness: float, resolution: int) -> ArrayMesh:
	if primitives.is_empty():
		return null

	var bounds := _compute_primitives_aabb(primitives)
	var margin: float = max(smoothness * 2.5, 0.25)
	bounds = bounds.grow(margin)

	var size: Vector3 = bounds.size
	var longest: float = max(size.x, max(size.y, size.z))
	if longest <= 0.001:
		return null

	var res: int = max(resolution, 4)
	var voxel_size: float = longest / float(res)
	var nx: int = clampi(int(ceil(size.x / voxel_size)), 2, res * 2)
	var ny: int = clampi(int(ceil(size.y / voxel_size)), 2, res * 2)
	var nz: int = clampi(int(ceil(size.z / voxel_size)), 2, res * 2)

	var dim_x := nx + 1
	var dim_y := ny + 1
	var dim_z := nz + 1

	var field := PackedFloat32Array()
	field.resize(dim_x * dim_y * dim_z)
	for iz in range(dim_z):
		for iy in range(dim_y):
			for ix in range(dim_x):
				var wp: Vector3 = bounds.position + Vector3(ix, iy, iz) * voxel_size
				field[_grid_index(ix, iy, iz, dim_x, dim_y)] = scene_sdf(wp, primitives, smoothness)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri_count := 0
	for iz in range(nz):
		for iy in range(ny):
			for ix in range(nx):
				tri_count += _march_cell(st, ix, iy, iz, dim_x, dim_y, field,
					bounds.position, voxel_size, primitives, smoothness)

	if tri_count == 0:
		return null

	return st.commit()

# Dual Contouring (DC) bake pipeline — sharp edges, QEF solver, hard facets.
static func bake_dc(primitives: Array, smoothness: float, resolution: int, fit_percent: float = 95.0, facet_angle_deg: float = 15.0, crystallinity: float = 0.0, chamfer_edge_pct: float = 5.0) -> ArrayMesh:
	if primitives.is_empty():
		return null

	var bounds := _compute_primitives_aabb(primitives)
	var margin: float = max(smoothness * 2.5, 0.25)
	bounds = bounds.grow(margin)

	var size: Vector3 = bounds.size
	var longest: float = max(size.x, max(size.y, size.z))
	if longest <= 0.001:
		return null

	var res: int = max(resolution, 4)
	var voxel_size: float = longest / float(res)
	var nx: int = clampi(int(ceil(size.x / voxel_size)), 2, res * 2)
	var ny: int = clampi(int(ceil(size.y / voxel_size)), 2, res * 2)
	var nz: int = clampi(int(ceil(size.z / voxel_size)), 2, res * 2)

	var dim_x := nx + 1
	var dim_y := ny + 1
	var dim_z := nz + 1

	var field := PackedFloat32Array()
	field.resize(dim_x * dim_y * dim_z)
	for iz in range(dim_z):
		for iy in range(dim_y):
			for ix in range(dim_x):
				var wp: Vector3 = bounds.position + Vector3(ix, iy, iz) * voxel_size
				field[_grid_index(ix, iy, iz, dim_x, dim_y)] = scene_sdf(wp, primitives, smoothness)

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
						var n_edge := _sdf_normal(p_edge, primitives, smoothness)
						n_edge = _snap_constructed_normal(n_edge, crystallinity, p_edge, primitives, chamfer_edge_pct)

						intersections.append(p_edge)
						normals.append(n_edge)
						p_sum += p_edge

				if not intersections.is_empty():
					var mass_point := p_sum / float(intersections.size())
					var vert := _solve_qef_3d(intersections, normals, mass_point, cell_min, cell_max)

					if fit_percent != 100.0:
						var sdf_val := scene_sdf(vert, primitives, smoothness)
						var norm := _sdf_normal(vert, primitives, smoothness)
						norm = _snap_constructed_normal(norm, crystallinity, vert, primitives, chamfer_edge_pct)
						var desired_offset := (100.0 - fit_percent) / 100.0 * voxel_size * 0.5
						vert = vert - norm * (sdf_val - desired_offset)
						vert = vert.clamp(cell_min, cell_max)

					# Constructed Orthogonal Alignment: for constructed hulls (crystallinity < 0.5),
					# snap vertex coordinates to discrete sub-voxel grid steps along dominant plane axes.
					if crystallinity < 0.5 and not normals.is_empty():
						var avg_n := Vector3.ZERO
						for n in normals:
							avg_n += n
						avg_n = avg_n.normalized()
						avg_n = _snap_constructed_normal(avg_n, crystallinity, vert, primitives, chamfer_edge_pct)

						var snap_step := voxel_size * 0.25
						if abs(avg_n.x) > 0.75:
							vert.x = round(vert.x / snap_step) * snap_step
						if abs(avg_n.y) > 0.75:
							vert.y = round(vert.y / snap_step) * snap_step
						if abs(avg_n.z) > 0.75:
							vert.z = round(vert.z / snap_step) * snap_step

					dual_vertices[cell_idx] = vert

	if dual_vertices.is_empty():
		return null

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

	return _build_faceted_mesh(triangles, facet_angle_deg, crystallinity)

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

# Quantizes / snaps normals to cardinal & standard chamfer / slope angles for constructed hulls.
# Weights main face body (inner > chamfer_edge_pct) 100% hard cardinal, reserving angled chamfers for perimeter edges.
static func _snap_constructed_normal(n: Vector3, crystallinity: float, point: Vector3 = Vector3.ZERO, primitives: Array = [], chamfer_edge_pct: float = 5.0) -> Vector3:
	if crystallinity >= 1.0 or n.length_squared() < 1e-6:
		return n

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

	# Check if point is in main face body or near perimeter edge
	var is_edge_zone := false
	if not primitives.is_empty() and chamfer_edge_pct > 0.0:
		for prim in primitives:
			var basis := Basis.from_euler(prim.rotation)
			var local: Vector3 = basis.inverse() * (point - prim.position)
			var half_extents: Vector3 = prim.scale * 0.5
			# Distance to outer face boundary normalized by size
			var margin_frac: float = chamfer_edge_pct / 100.0
			var q: Vector3 = local.abs() - half_extents * (1.0 - margin_frac)
			if q.x > 0.0 or q.y > 0.0 or q.z > 0.0:
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
		if best_cardinal_dot >= 0.707: # Within 45 degrees of cardinal
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
static func _build_faceted_mesh(triangles: Array, _facet_angle_deg: float, crystallinity: float = 0.0, primitives: Array = [], chamfer_edge_pct: float = 5.0) -> ArrayMesh:
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
		n = _snap_constructed_normal(n, crystallinity, center, primitives, chamfer_edge_pct)

		st.set_normal(n)
		st.add_vertex(p0)
		st.set_normal(n)
		st.add_vertex(p1)
		st.set_normal(n)
		st.add_vertex(p2)

	return st.commit()


# ── SDF evaluation ───────────────────────────────────────────────────────

static func scene_sdf(world_point: Vector3, primitives: Array, smoothness: float) -> float:
	if primitives.is_empty():
		return 1e9
	# Bilateral X-Symmetry Enforcement: fold world_point into +X domain
	var sym_point := Vector3(abs(world_point.x), world_point.y, world_point.z)
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
			var r: float = min(h.x, min(h.y, h.z))
			return p.length() - r
		TYPE_CYLINDER:
			var r: float = min(h.x, h.z)
			return _sdf_cylinder(p, r, h.y)
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
			var r: float = min(h.x, min(h.y, h.z))
			return _sdf_dome(p, r, h.y / r if r > 0.0001 else 1.0)
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
			var r: float = min(h.x, h.y)
			return _sdf_dome(p, r, h.z / r if r > 0.0001 else 1.35)
		TYPE_RING:
			var r_out: float = min(h.x, h.z)
			var r_in: float = r_out * 0.6
			return _sdf_ring(p, r_out, r_in, h.y)
		_:
			return _sdf_box(p, h)

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
	var d_cut: float = (p.y - p.z - 0.65) / sqrt(2.0)
	return max(d_box, d_cut)

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

# Rounded box (exact SDF, Quilez's standard "box minus radius, then grow
# back out by radius" construction) - matches build_hull_primitives.py's
# build_chamfer_box() bevel offset=0.12.
static func _sdf_chamfer_box(p: Vector3, he: Vector3, radius: float) -> float:
	var inner_he: Vector3 = he - Vector3(radius, radius, radius)
	return _sdf_box(p, inner_he) - radius

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
static func _sdf_dome(p: Vector3, radius: float, z_stretch: float) -> float:
	var q := Vector3(p.x, p.y + radius, p.z / z_stretch)
	var d_sphere: float = (q.length() - radius) * min(1.0, z_stretch)
	var d_flat: float = -p.y - radius
	return max(d_sphere, d_flat)

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

static func _sdf_normal(p: Vector3, primitives: Array, smoothness: float) -> Vector3:
	var eps := 0.01
	var dx: float = scene_sdf(p + Vector3(eps, 0, 0), primitives, smoothness) \
		- scene_sdf(p - Vector3(eps, 0, 0), primitives, smoothness)
	var dy: float = scene_sdf(p + Vector3(0, eps, 0), primitives, smoothness) \
		- scene_sdf(p - Vector3(0, eps, 0), primitives, smoothness)
	var dz: float = scene_sdf(p + Vector3(0, 0, eps), primitives, smoothness) \
		- scene_sdf(p - Vector3(0, 0, eps), primitives, smoothness)
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
		primitives: Array, smoothness: float) -> int:
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
		var na := _sdf_normal(pa, primitives, smoothness)
		var nb := _sdf_normal(pb, primitives, smoothness)
		var nc := _sdf_normal(pc, primitives, smoothness)

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
