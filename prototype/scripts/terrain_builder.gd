extends Node
class_name TerrainBuilder
# Turns a MapCatalog map Dictionary into: baked NavigationServer3D ground/
# water maps, decorative terrain meshes (water planes, rock-cluster
# obstacles, elevation plateaus+ramps), and pure query functions
# (terrain_height_at / is_position_blocked) that skirmish.gd and
# battle_unit.gd consult for Y-positioning, buildability, and (indirectly,
# via real Y coordinates) vision/combat elevation bonuses.
#
# Ground navmesh technique: generalizes the old single-lake "4 quad bands
# around one rectangular hole" into an arbitrary-hole grid - the 160x160
# (or whatever map_half_extents says) area is walked in GRID_CELL-sized
# quads, and any cell overlapping a water/obstacle/elevation-zone/ramp
# footprint is simply omitted. Elevation zones then add back a plateau-top
# quad (at y=height) and one sloped ramp quad bridging ground level to the
# plateau, all on the SAME ground_nav_map - NavigationServer3D happily
# routes across a slope as long as it's under NavigationMesh's default
# ~45-degree max-slope bake limit (RAMP_RUN_PER_HEIGHT is chosen to stay
# well under that, see its own comment).
#
# Deliberately NOT physically-collidable ramps/plateaus (no rotated
# CollisionShape3D, no CharacterBody3D stair-stepping risk) - elevation
# Y-positioning is instead driven by terrain_height_at(), a pure analytic
# function battle_unit.gd/skirmish.gd call every tick to snap a unit/
# building's Y, decoupled entirely from physics. This was a deliberate
# scope choice over real 3D collision - see DECISIONS_NEEDED.md.

const GRID_CELL: float = 4.0
# Ramp run (horizontal distance) per unit of rise. 1.5 -> slope angle
# atan(1/1.5) ~= 33.7 degrees, comfortably under both Godot's default
# NavigationMesh max-slope bake limit (45 deg) and CharacterBody3D's
# default floor_max_angle (45 deg) - not that either matters for the
# analytic height-snap approach, but keeping the ramp geometrically
# plausible as an actual walkable slope, not just a navmesh technicality.
const RAMP_RUN_PER_HEIGHT: float = 1.5
# The coarse flat-ground grid skips a whole GRID_CELL if it even partially
# overlaps a hole (water/obstacle/ramp footprint) - correct for avoiding
# false-walkable slivers, but it means a hole boundary that doesn't fall
# exactly on a grid line gets rounded UP TO a full cell short of the flat
# grid's actual walkable edge. A first fix (pad the ramp's ground-facing
# sides by a flat RAMP_PAD offset) turned out to be insufficient: an
# unaligned PADDED edge has exactly the same problem the unpadded edge
# did, just shifted outward by one cell - confirmed by a probe script
# still failing to route onto the plateau after adding the naive pad.
# The real fix is to SNAP every ground-facing ramp boundary onto an actual
# grid line (_snap_floor/_snap_ceil below) and use that identical snapped
# value for both the navmesh hole AND the apron quad's edge - so the two
# pieces of geometry share an exact coincident boundary no matter where
# the ramp sits, the same way the original lake's hand-computed exact
# bands always did.
const RAMP_PAD: float = GRID_CELL

static func _snap_floor(coord: float, half: float) -> float:
	return -half + floor((coord - (-half)) / GRID_CELL) * GRID_CELL

static func _snap_ceil(coord: float, half: float) -> float:
	return -half + ceil((coord - (-half)) / GRID_CELL) * GRID_CELL

# --- Geometry helpers ---

static func _rect_from(center: Vector3, half_extents: Vector2) -> Dictionary:
	return {"x0": center.x - half_extents.x, "x1": center.x + half_extents.x,
		"z0": center.z - half_extents.y, "z1": center.z + half_extents.y}

static func _rect_overlaps(cx0: float, cx1: float, cz0: float, cz1: float, rect: Dictionary) -> bool:
	return cx0 < rect.x1 and cx1 > rect.x0 and cz0 < rect.z1 and cz1 > rect.z0

static func _point_in_rect(pos: Vector3, rect: Dictionary) -> bool:
	return pos.x >= rect.x0 and pos.x <= rect.x1 and pos.z >= rect.z0 and pos.z <= rect.z1

# One ramp per elevation zone, on the given side. Returns the axis it runs
# along, its true (unpadded) inner (plateau-level, y=height) / outer
# (ground-level, y=0) coordinate along that axis - used for the sloped
# quad's shape and the height-interpolation formula - plus a grid-SNAPPED
# x0/x1/z0/z1 rect (see RAMP_PAD/_snap_floor/_snap_ceil) used for the
# navmesh hole, the visual mesh's width, and the height/buildability
# containment queries. `half` is the map's map_half_extents - the grid's
# origin, needed to snap onto the same lines _build_ground_faces() uses.
static func _ramp_geometry(zone: Dictionary, half: float) -> Dictionary:
	var c: Vector3 = zone.center
	var he: Vector2 = zone.half_extents
	var h: float = zone.height
	var rw: float = zone.get("ramp_width", 6.0)
	var depth: float = h * RAMP_RUN_PER_HEIGHT
	var side: String = zone.get("ramp_side", "south")
	match side:
		"north":
			var true_outer = c.z + he.y + depth
			return {"axis": "z", "inner": c.z + he.y, "outer": true_outer,
				"x0": _snap_floor(c.x - rw / 2.0 - RAMP_PAD, half), "x1": _snap_ceil(c.x + rw / 2.0 + RAMP_PAD, half),
				"z0": c.z + he.y, "z1": _snap_ceil(true_outer + RAMP_PAD, half)}
		"east":
			var true_outer = c.x + he.x + depth
			return {"axis": "x", "inner": c.x + he.x, "outer": true_outer,
				"z0": _snap_floor(c.z - rw / 2.0 - RAMP_PAD, half), "z1": _snap_ceil(c.z + rw / 2.0 + RAMP_PAD, half),
				"x0": c.x + he.x, "x1": _snap_ceil(true_outer + RAMP_PAD, half)}
		"west":
			var true_outer = c.x - he.x - depth
			return {"axis": "x", "inner": c.x - he.x, "outer": true_outer,
				"z0": _snap_floor(c.z - rw / 2.0 - RAMP_PAD, half), "z1": _snap_ceil(c.z + rw / 2.0 + RAMP_PAD, half),
				"x0": _snap_floor(true_outer - RAMP_PAD, half), "x1": c.x - he.x}
		_: # "south" (also the default for an unrecognized side)
			var true_outer = c.z - he.y - depth
			return {"axis": "z", "inner": c.z - he.y, "outer": true_outer,
				"x0": _snap_floor(c.x - rw / 2.0 - RAMP_PAD, half), "x1": _snap_ceil(c.x + rw / 2.0 + RAMP_PAD, half),
				"z0": _snap_floor(true_outer - RAMP_PAD, half), "z1": c.z - he.y}

# The ramp's navmesh geometry as two quads: the true sloped section (inner
# to outer, height h to 0) plus a flat "apron" from outer out to the
# padded far boundary - see RAMP_PAD for why the apron exists.
#
# Winding matters here in a way it doesn't for the rest of this file: an
# empirical probe found that Recast's baking silently drops a triangle
# whose winding doesn't match its (undocumented, but consistently
# reproduced) walkable-surface convention - not a slope/height/agent-
# parameter issue, a plain backface-style rejection. The existing grid/
# lake/plateau quads all sweep low-to-high along whichever axis varies
# (x0->x1, z0->z1), which happens to already match that convention. A
# "south" or "west" ramp's outer edge is at a SMALLER coordinate than its
# inner edge, which reverses that sweep and silently baked to zero
# polygons (confirmed with an isolated single-quad repro) until `flip`
# swaps the two width corners back to the matching winding.
static func _ramp_quads(rg: Dictionary, h: float) -> Array:
	var quads = []
	var flip = rg.outer < rg.inner
	if rg.axis == "z":
		var apron_far = rg.z1 if rg.outer > rg.inner else rg.z0
		var xa = rg.x1 if flip else rg.x0
		var xb = rg.x0 if flip else rg.x1
		quads.append([Vector3(xa, h, rg.inner), Vector3(xb, h, rg.inner), Vector3(xb, 0, rg.outer), Vector3(xa, 0, rg.outer)])
		quads.append([Vector3(xa, 0, rg.outer), Vector3(xb, 0, rg.outer), Vector3(xb, 0, apron_far), Vector3(xa, 0, apron_far)])
	else:
		var apron_far = rg.x1 if rg.outer > rg.inner else rg.x0
		var za = rg.z0 if flip else rg.z1
		var zb = rg.z1 if flip else rg.z0
		quads.append([Vector3(rg.inner, h, za), Vector3(rg.inner, h, zb), Vector3(rg.outer, 0, zb), Vector3(rg.outer, 0, za)])
		quads.append([Vector3(rg.outer, 0, za), Vector3(rg.outer, 0, zb), Vector3(apron_far, 0, zb), Vector3(apron_far, 0, za)])
	return quads

static func _add_nav_quad(verts: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3):
	verts.append(a); verts.append(b); verts.append(c)
	verts.append(a); verts.append(c); verts.append(d)

static func _collect_holes(map_def: Dictionary, half: float) -> Array:
	var holes = []
	for w in map_def.get("water_areas", []):
		holes.append(_rect_from(w.center, w.half_extents))
	for o in map_def.get("obstacles", []):
		holes.append(_rect_from(o.center, o.half_extents))
	for e in map_def.get("elevation_zones", []):
		holes.append(_rect_from(e.center, e.half_extents))
		var rg = _ramp_geometry(e, half)
		holes.append({"x0": rg.x0, "x1": rg.x1, "z0": rg.z0, "z1": rg.z1})
	return holes

# --- Navmesh source geometry ---

static func _build_ground_faces(map_def: Dictionary) -> PackedVector3Array:
	var verts = PackedVector3Array()
	var half: float = map_def.get("map_half_extents", 80.0)
	var holes = _collect_holes(map_def, half)

	var x = -half
	while x < half:
		var x1 = min(x + GRID_CELL, half)
		var z = -half
		while z < half:
			var z1 = min(z + GRID_CELL, half)
			var blocked = false
			for h in holes:
				if _rect_overlaps(x, x1, z, z1, h):
					blocked = true
					break
			if not blocked:
				_add_nav_quad(verts, Vector3(x, 0, z), Vector3(x1, 0, z), Vector3(x1, 0, z1), Vector3(x, 0, z1))
			z = z1
		x = x1

	for e in map_def.get("elevation_zones", []):
		var c: Vector3 = e.center
		var he: Vector2 = e.half_extents
		var h: float = e.height
		_add_nav_quad(verts,
			Vector3(c.x - he.x, h, c.z - he.y), Vector3(c.x + he.x, h, c.z - he.y),
			Vector3(c.x + he.x, h, c.z + he.y), Vector3(c.x - he.x, h, c.z + he.y))
		var rg = _ramp_geometry(e, half)
		for q in _ramp_quads(rg, h):
			_add_nav_quad(verts, q[0], q[1], q[2], q[3])
	return verts

static func build_navmeshes(map_def: Dictionary) -> Dictionary:
	var ground_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(ground_map, true)
	var water_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(water_map, true)

	var ground_verts = _build_ground_faces(map_def)
	var ground_nav_mesh = NavigationMesh.new()
	var ground_source = NavigationMeshSourceGeometryData3D.new()
	ground_source.add_faces(ground_verts, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(ground_nav_mesh, ground_source)
	var ground_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(ground_region, ground_map)
	NavigationServer3D.region_set_navigation_mesh(ground_region, ground_nav_mesh)

	var water_verts = PackedVector3Array()
	for w in map_def.get("water_areas", []):
		var rect = _rect_from(w.center, w.half_extents)
		_add_nav_quad(water_verts, Vector3(rect.x0, 0, rect.z0), Vector3(rect.x1, 0, rect.z0),
			Vector3(rect.x1, 0, rect.z1), Vector3(rect.x0, 0, rect.z1))
	var water_region: RID = RID()
	if water_verts.size() > 0:
		var water_nav_mesh = NavigationMesh.new()
		var water_source = NavigationMeshSourceGeometryData3D.new()
		water_source.add_faces(water_verts, Transform3D.IDENTITY)
		NavigationServer3D.bake_from_source_geometry_data(water_nav_mesh, water_source)
		water_region = NavigationServer3D.region_create()
		NavigationServer3D.region_set_map(water_region, water_map)
		NavigationServer3D.region_set_navigation_mesh(water_region, water_nav_mesh)

	return {"ground_map": ground_map, "water_map": water_map, "ground_region": ground_region, "water_region": water_region}

# --- Visuals ---

static func spawn_visuals(map_def: Dictionary, parent: Node3D):
	var half: float = map_def.get("map_half_extents", 80.0)
	for w in map_def.get("water_areas", []):
		_spawn_water_plane(w, parent)
	for o in map_def.get("obstacles", []):
		_spawn_obstacle(o, parent)
	for e in map_def.get("elevation_zones", []):
		_spawn_elevation_zone(e, parent, half)

static func _spawn_water_plane(water: Dictionary, parent: Node3D):
	var mesh_inst = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(water.half_extents.x * 2.0, water.half_extents.y * 2.0)
	mesh_inst.mesh = plane
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.35, 0.55, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.25, 0.4)
	mesh_inst.material_override = mat
	parent.add_child(mesh_inst)
	mesh_inst.global_position = Vector3(water.center.x, 0.05, water.center.z)

static func _spawn_obstacle(obstacle: Dictionary, parent: Node3D):
	# A rough rock cluster filling the footprint - primitive meshes, not a
	# new Blender asset (avoids the fragile import pipeline for pure
	# decoration). Seeded from position so a given map's obstacles always
	# look the same run to run (deterministic for screenshot verification).
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(obstacle.center)
	for i in range(5):
		var rock = MeshInstance3D.new()
		var box = BoxMesh.new()
		var size = Vector3(rng.randf_range(1.2, 2.4), rng.randf_range(1.0, 2.2), rng.randf_range(1.2, 2.4))
		box.size = size
		rock.mesh = box
		var mat = StandardMaterial3D.new()
		var shade = rng.randf_range(0.35, 0.5)
		mat.albedo_color = Color(shade, shade * 0.95, shade * 0.9)
		mat.roughness = 0.95
		rock.material_override = mat
		parent.add_child(rock)
		var ox = rng.randf_range(-obstacle.half_extents.x * 0.7, obstacle.half_extents.x * 0.7)
		var oz = rng.randf_range(-obstacle.half_extents.y * 0.7, obstacle.half_extents.y * 0.7)
		rock.global_position = Vector3(obstacle.center.x + ox, size.y / 2.0, obstacle.center.z + oz)
		rock.rotation.y = rng.randf_range(0, TAU)

	# Real collision (same "Ground only" layer as the flat terrain) so units
	# physically can't clip through even if steering pushes them off-path,
	# and the build-placement raycast can't resolve a spot inside the
	# footprint to a flat position either - belt-and-suspenders on top of
	# the navmesh hole and the explicit is_position_blocked() reject.
	var body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(obstacle.half_extents.x * 2.0, 3.0, obstacle.half_extents.y * 2.0)
	shape.shape = box_shape
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = Vector3(obstacle.center.x, 1.5, obstacle.center.z)

static func _spawn_elevation_zone(zone: Dictionary, parent: Node3D, half: float):
	var c: Vector3 = zone.center
	var he: Vector2 = zone.half_extents
	var h: float = zone.height

	var plateau = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(he.x * 2.0, h, he.y * 2.0)
	plateau.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.38, 0.3)
	mat.roughness = 0.85
	plateau.material_override = mat
	parent.add_child(plateau)
	plateau.global_position = Vector3(c.x, h / 2.0, c.z)

	# Ramp visual: just the true sloped quad (not the flat navmesh-only
	# apron beyond it, which is already flush with the surrounding ground
	# and needs no distinct visual) - built from the same corners the
	# navmesh uses, so what a player sees lines up with where units walk.
	var rg = _ramp_geometry(zone, half)
	var slope_quad = _ramp_quads(rg, h)[0]
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.add_vertex(slope_quad[0]); st.add_vertex(slope_quad[1]); st.add_vertex(slope_quad[2])
	st.add_vertex(slope_quad[0]); st.add_vertex(slope_quad[2]); st.add_vertex(slope_quad[3])
	st.generate_normals()
	var ramp_mesh_inst = MeshInstance3D.new()
	ramp_mesh_inst.mesh = st.commit()
	var ramp_mat = StandardMaterial3D.new()
	ramp_mat.albedo_color = Color(0.38, 0.35, 0.28)
	ramp_mat.roughness = 0.9
	ramp_mesh_inst.material_override = ramp_mat
	parent.add_child(ramp_mesh_inst)

# --- Queries (pure functions, no Node dependency - callable from tests
# directly against a MapCatalog dictionary) ---

# The single source of truth for "what Y should something at this XZ sit
# at" - consulted for building placement, unit spawn positions, and every
# moving ground unit's per-tick Y snap. Because it's the ONLY place Y gets
# set for elevated terrain, vision (fog-of-war distance check) and combat
# (damage_resolver's hit_origin/defender Y comparison) automatically react
# to real elevation differences without needing their own map awareness -
# they just compare whatever Y values units/buildings already carry.
static func terrain_height_at(map_def: Dictionary, pos: Vector3) -> float:
	var half: float = map_def.get("map_half_extents", 80.0)
	for e in map_def.get("elevation_zones", []):
		if _point_in_rect(pos, _rect_from(e.center, e.half_extents)):
			return e.height
		var rg = _ramp_geometry(e, half)
		var ramp_rect = {"x0": rg.x0, "x1": rg.x1, "z0": rg.z0, "z1": rg.z1}
		if _point_in_rect(pos, ramp_rect):
			var coord = pos.z if rg.axis == "z" else pos.x
			var span = rg.outer - rg.inner
			var t = 1.0
			if span != 0.0:
				t = 1.0 - clamp((coord - rg.inner) / span, 0.0, 1.0)
			return e.height * clamp(t, 0.0, 1.0)
	return 0.0

# Water, obstacles, and ramp slopes are all "can't stand/build here" -
# a plateau's flat TOP is deliberately excluded (legitimate, valuable
# buildable high ground - the whole point of holding it).
static func is_position_blocked(map_def: Dictionary, pos: Vector3) -> bool:
	var half: float = map_def.get("map_half_extents", 80.0)
	for w in map_def.get("water_areas", []):
		if _point_in_rect(pos, _rect_from(w.center, w.half_extents)):
			return true
	for o in map_def.get("obstacles", []):
		if _point_in_rect(pos, _rect_from(o.center, o.half_extents)):
			return true
	for e in map_def.get("elevation_zones", []):
		var rg = _ramp_geometry(e, half)
		var ramp_rect = {"x0": rg.x0, "x1": rg.x1, "z0": rg.z0, "z1": rg.z1}
		if _point_in_rect(pos, ramp_rect):
			return true
	return false
