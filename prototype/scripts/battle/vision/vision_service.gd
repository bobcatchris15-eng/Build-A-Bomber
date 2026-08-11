class_name VisionService
extends RefCounted

const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
# Who can see what, and the grey sheet drawn over what they cannot.
#
# PORTED, NOT REDESIGNED. The old implementation (skirmish.gd:735-1017) is good
# and its comments record real bugs found the hard way - boundary flicker, the
# wallhack a shroud-only fog allows, the asymmetry a single fog_hidden flag
# creates once weapons out-range vision. All of that survives; what changes is
# that it lives in a service the director delegates to rather than in 280 lines
# of the match controller.
#
# The research pass proposed a SubViewport mask instead. That is a downgrade
# here: a viewport mask is a two-state answer, and this is a three-state system -
# unexplored, explored-but-not-currently-seen, and visible. Losing the middle
# state would mean a base you scouted an hour ago vanishes the moment you look
# away, which is worse than the cost it saves.
#
# TWO SEPARATE QUESTIONS, deliberately answered differently:
#
#   GAMEPLAY visibility (is_visible_to_team) uses a real line-of-sight raycast,
#   because without one a unit behind a ridge can be targeted through it - a
#   wallhack the player can see happening.
#
#   The VISUAL shroud does not raycast. It is cosmetic ground dimming, and a ray
#   per grid cell per construct per tick would be thousands of casts for an
#   effect nobody can distinguish from a plain radius.

const LiveryScript = preload("res://scripts/livery.gd")
const SmokeVolumeScript = preload("res://scripts/smoke_volume.gd")
const WorldScaleScript = preload("res://scripts/world_scale.gd")

# Vision scans on a timer, not per frame. Visibility changing 3x a second is
# imperceptible and the scan is O(viewers x targets) per team.
const TICK_INTERVAL := 0.3

# Height the LOS ray is cast at, so a unit in a shallow dip is not blindfolded by
# the lip of it.
#
# CORE_DESIGN_LANGUAGE.md §3.2: deliberately NOT scaled - this is an offset
# above a UNIT's own origin, and units are unit-space, fixed regardless of
# world_scale (the whole "environment scales, units don't" premise).
const EYE_HEIGHT := 1.5

# Higher ground sees further, capped so a mountain is not an all-seeing eye.
#
# CORE_DESIGN_LANGUAGE.md §3.2: these ARE world_scale=1.0 baselines -
# effective_vision() below scales them, unlike EYE_HEIGHT above. The
# elevation they read (terrain_height_at()) is real terrain Y, which
# already grows with world_scale (ground noise amplitude - Chunk 9 - and
# any heightmap's terrain.height_scale, both FIELD_SPEC-flagged). Left
# unscaled, a hill authored to just reach ELEVATION_CAP at world_scale=1
# would tower 16x higher at world_scale=16 while the cap stayed put, so
# the SAME relative hilltop would trip the cap at a small fraction of its
# climb instead of at the top - elevation bonus would stop meaning "you're
# on high ground" and start meaning "you're on ANY ground with the
# faintest slope." ELEVATION_CAP scales WITH world_scale (same relative
# hill still caps the bonus at the same relative height) and
# ELEVATION_BONUS_PER_UNIT scales INVERSELY (so the maximum total bonus at
# the cap - a balance number, not a distance - stays identical regardless
# of scale).
const ELEVATION_BONUS_PER_UNIT := 0.02
const ELEVATION_CAP := 12.0

# Reveal happens at plain vision range; something ALREADY visible only drops out
# past this multiple of it. The gap is a dead zone: without it a construct
# sitting exactly on the boundary flickers in and out every single tick as
# millimetre position deltas cross one threshold.
const HIDE_RANGE_MULT := 1.15

# Shroud resolution and the two dimmed states. Unexplored is opaque; explored is
# partly lifted and never returns to full black once seen.
const GRID_CELL := 4.0
# Playtest: "the VISION needs to be brighter in comparison to the non-visible
# parts of the explored map." Currently-visible ground is alpha 0 - fully clear,
# and already as bright as the terrain itself gets - so the contrast has to come
# from the other end: explored-but-not-currently-visible is dimmed harder.
# Raised 0.55 -> 0.74, which keeps remembered terrain legible (that is the whole
# point of explored state persisting) while making the lit, actively-seen area
# read as unmistakably the live one.
const EXPLORED_ALPHA := 0.74
const UNEXPLORED_ALPHA := 1.0
# Clearance above the terrain AT EACH POINT, not above the map maximum.
#
# The shroud used to be a flat plane, which forced it to sit above the highest
# ground anywhere on the map or hilltops would render through it. That worked
# while maps were nearly flat. With real hills and ravines it means the fog
# floats far above the floor of every low-lying area - a ceiling over the map
# rather than a layer on the ground - which is what the playtest reported. The
# mesh now follows height_at() and needs only a hair of local clearance, so
# max_height() is no longer involved in placing it at all.
const SHROUD_CLEARANCE := 1.0
# Grid spacing for the shroud mesh, in world units before world_scale. The
# ground mesh's own 3-unit grid would be ~1.8M verts across an 840 half-extent
# map, and the shroud does not need it: it is following the same low-frequency
# relief the ground noise produces, not rendering detail.
const SHROUD_MESH_RESOLUTION := 3.0

const SHROUD_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

varying vec3 world_pos;

uniform sampler2D shroud_tex : hint_default_black, filter_linear;
uniform float map_half = 80.0;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (world_pos.xz + vec2(map_half)) / (2.0 * map_half);
	vec4 c = texture(shroud_tex, uv);
	ALBEDO = vec3(0.015, 0.015, 0.02);
	ALPHA = c.a;
}
"""

var _controller: Node = null
var _local_team: int = 0
var reveal_all: bool = false

# viewing team -> { instance_id: true }. One set per team rather than one flag
# per construct: a single flag can only describe ONE side's knowledge, which left
# the AI with no visibility gate at all while the player had one. Vision is a
# TEAM property - if a scout sees it, the artillery on the far side of the map
# may shoot it - so it needs a per-team answer.
var _team_visible: Dictionary = {}

var _beacons: Array = []

var _half: float = 80.0
var _dim: int = 0
var _image: Image = null
var _texture: ImageTexture = null
var _prev_cells: Dictionary = {}
# CORE_DESIGN_LANGUAGE.md §3.2: scales the shroud grid cell (below) and the
# elevation-bonus constants (effective_vision()) - see GRID_CELL and
# ELEVATION_CAP's own comments for why each needs it.
var _world_scale: float = 1.0


func setup(controller: Node, local_team: int, map_half_extents: float, world_scale: float = 1.0) -> void:
	_controller = controller
	_local_team = local_team
	_half = map_half_extents
	_world_scale = world_scale
	# Same self-bounding fix as flow_field.gd's BASE_CELL_SIZE: left flat,
	# the shroud IMAGE would grow O(world_scale^2) as _half grows with it -
	# the "77MB fog image" the plan's own cost table warns about. Scaling
	# the cell alongside _half keeps _dim (and image memory) roughly
	# constant regardless of world_scale.
	_dim = maxi(1, int(ceil((_half * 2.0) / _cell_size())))
	_image = Image.create(_dim, _dim, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0, 0, 0, UNEXPLORED_ALPHA))
	_texture = ImageTexture.create_from_image(_image)


# The shroud plane. Returned rather than self-parented so the director owns the
# scene tree and this owns the rules.
func build_shroud() -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.name = "FogShroud"
	inst.mesh = _shroud_mesh()
	var shader := Shader.new()
	shader.code = SHROUD_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("shroud_tex", _texture)
	mat.set_shader_parameter("map_half", _half)
	inst.material_override = mat
	return inst


# A shroud that lies ON the terrain. Falls back to the old flat plane at a
# fixed clearance when there is no map to sample - a test stub or a controller
# without current_map - rather than to nothing, same degrade contract the rest
# of the terrain code uses.
func _shroud_mesh() -> Mesh:
	var map_def: Dictionary = {}
	if _controller != null and "current_map" in _controller:
		map_def = _controller.current_map
	if map_def.is_empty():
		var plane := PlaneMesh.new()
		plane.size = Vector2(_half * 2.0, _half * 2.0)
		return plane
	return TerrainBuilderScript.build_conforming_overlay_mesh(
		map_def, _half, SHROUD_CLEARANCE, SHROUD_MESH_RESOLUTION * _world_scale)


# --- Queries -----------------------------------------------------------------

# How far `o` can see from where it is standing. Flying units skip the elevation
# bonus - they are already up, and stacking altitude on altitude is double-
# counting the same advantage.
func effective_vision(o) -> float:
	var vision: float = o.vision_range if "vision_range" in o else 0.0
	if "is_flying" in o and o.is_flying:
		return vision
	var elevation := 0.0
	if _controller != null and _controller.has_method("terrain_height_at"):
		elevation = _controller.terrain_height_at(o.global_position)
	var cap := ELEVATION_CAP * _world_scale
	var bonus_per_unit := ELEVATION_BONUS_PER_UNIT / _world_scale
	return vision * (1.0 + minf(elevation, cap) * bonus_per_unit)


# Can `viewing_team` see `c` right now?
#
# FAILS OPEN before the first scan. A closed default would make every weapon in
# the game refuse to fire until the first fog tick landed - a far louder and more
# confusing failure than one tick of over-sharing on a map nobody has moved on.
const DebugSettingsScript = preload("res://scripts/debug_settings.gd")

func _reveal_all_cheat() -> bool:
	var ds = DebugSettingsScript.get_active()
	return ds != null and ds.reveal_all_fog


func is_visible_to_team(c, viewing_team: int) -> bool:
	if c == null or not is_instance_valid(c):
		return false
	if reveal_all or _reveal_all_cheat():
		return true
	var c_team: int = c.get_meta("team") if c.has_meta("team") else -1
	if c_team == viewing_team:
		return true
	if not _team_visible.has(viewing_team):
		return true
	return _team_visible[viewing_team].has(c.get_instance_id())


# Illumination ammo and sensor beacons. A flare is simply a stationary observer
# owned by the team that fired it, so it folds into the same scan rather than
# getting a parallel visibility path.
#
# Deliberately no line-of-sight requirement: a flare lights an area from above,
# which is the entire reason you fire one over a ridge you cannot see behind.
func reveal_area(for_team: int, pos: Vector3, radius: float, duration: float) -> void:
	_beacons.append({
		"pos": pos, "radius": radius, "team": for_team,
		"expires_at": Time.get_ticks_msec() + int(duration * 1000.0),
	})


func _live_beacons(viewing_team: int) -> Array:
	var now := Time.get_ticks_msec()
	var mine: Array = []
	var kept: Array = []
	for b in _beacons:
		if b.expires_at <= now:
			continue
		kept.append(b)
		if b.team == viewing_team:
			mine.append(b)
	_beacons = kept
	return mine


# --- The scan ----------------------------------------------------------------

func tick() -> void:
	var by_team: Dictionary = {}
	for c in _all_constructs():
		var t: int = c.get_meta("team") if c.has_meta("team") else -1
		if not by_team.has(t):
			by_team[t] = []
		by_team[t].append(c)

	var next: Dictionary = {}
	for viewing_team in by_team:
		var viewers: Array = []
		var targets: Array = []
		for t in by_team:
			if t == viewing_team:
				viewers += by_team[t]
			else:
				targets += by_team[t]
		var beacons := _live_beacons(viewing_team)
		var previous: Dictionary = _team_visible.get(viewing_team, {})
		var seen: Dictionary = {}
		for c in targets:
			if not is_instance_valid(c):
				continue
			# Hysteresis needs THIS team's own previous answer. For a non-local
			# team that cannot come off a shared flag, which is the second reason
			# visibility is stored per team.
			var was_visible: bool = previous.has(c.get_instance_id())
			if reveal_all or _is_spotted(c, viewers, beacons, was_visible):
				seen[c.get_instance_id()] = true
		next[viewing_team] = seen
	_team_visible = next

	# The local team's answer additionally drives rendering.
	var local_seen: Dictionary = _team_visible.get(_local_team, {})
	var local_constructs: Array = []
	for c in _all_constructs():
		var t: int = c.get_meta("team") if c.has_meta("team") else -1
		if t == _local_team:
			local_constructs.append(c)
		elif c.has_method("set_fog_visible"):
			c.set_fog_visible(reveal_all or local_seen.has(c.get_instance_id()))
	_update_shroud(local_constructs, _live_beacons(_local_team))


func _is_spotted(c, viewers: Array, beacons: Array, was_visible: bool) -> bool:
	var c_flying: bool = "is_flying" in c and c.is_flying
	# The Bayou Irregulars' camouflage passive scaled every observer's range
	# against the thing being looked at. Faction passives are gone (see
	# livery.gd); spotting range is now the viewer's alone.
	for o in viewers:
		if not is_instance_valid(o):
			continue
		var vision := effective_vision(o)
		# NO VISION MEANS NO VISION. Without this, the `distance <= reach` test
		# below reads 0 <= 0 as true, so a construct with its sensors stripped -
		# or one that never had any - still spots anything sharing its exact
		# position. Degenerate in a real match, but it is the kind of edge that
		# turns into a phantom reveal the moment two things stack.
		if vision <= 0.0:
			continue
		# A fire-control radar lets a unit designate out to its weapons' reach
		# rather than only as far as its own eyes.
		if is_instance_valid(o.get("hull_node")) and o.hull_node.has_meta("has_fire_control_radar") \
				and o.hull_node.get_meta("has_fire_control_radar"):
			vision = maxf(vision, float(o.hull_node.get_meta("fire_control_max_range", vision)))
		var reach := vision * HIDE_RANGE_MULT if was_visible else vision
		if c.global_position.distance_to(o.global_position) > reach:
			continue
		# Airborne on either end skips the terrain ray - a plane is above the
		# ridge the ray would hit, and so is anything looking at one.
		var o_flying: bool = "is_flying" in o and o.is_flying
		if o_flying or c_flying or _has_line_of_sight(o.global_position, c.global_position):
			return true
	for b in beacons:
		if c.global_position.distance_to(b.pos) <= b.radius:
			return true
	return false


func _has_line_of_sight(from_pos: Vector3, to_pos: Vector3) -> bool:
	if _controller == null or not _controller.is_inside_tree():
		return true
	var space: PhysicsDirectSpaceState3D = _controller.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		from_pos + Vector3(0, EYE_HEIGHT, 0),
		to_pos + Vector3(0, EYE_HEIGHT, 0))
	# Terrain and smoke, never other units - a unit does not block sight past it.
	# Smoke denies SCOUTING as well as fire: a screen that hid you from being shot
	# at but not from being seen would be a strange half-measure. Areas are off by
	# default in a ray query, so smoke has to be opted into explicitly.
	query.collision_mask = BattleLayers.TERRAIN + SmokeVolumeScript.SMOKE_COLLISION_LAYER
	query.collide_with_areas = true
	return space.intersect_ray(query).is_empty()


func _faction_of(c) -> String:
	if "faction" in c and c.faction != "":
		return c.faction
	if "hull_node" in c and is_instance_valid(c.hull_node) and c.hull_node.has_meta("faction"):
		return c.hull_node.get_meta("faction")
	return LiveryScript.PLAYER_ID


func _all_constructs() -> Array:
	if _controller == null or not _controller.is_inside_tree():
		return []
	var out: Array = []
	for c in _controller.get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(c):
			continue
		# `damageable` is a TREE-WIDE group and this service does not own who joins
		# it. Reading .is_dead off whatever is in there crashed the whole scan the
		# moment something joined without one - which is not hypothetical: it is
		# how the vision suite first failed, on a node another suite had left
		# behind. A construct that cannot say whether it is alive is not a thing
		# vision has an opinion about, so it is skipped rather than assumed.
		if not ("is_dead" in c) or c.is_dead:
			continue
		if not c.has_meta("team"):
			continue
		out.append(c)
	return out


# --- Shroud ------------------------------------------------------------------

# The resolved (world_scale-scaled) shroud cell size, matching setup()'s
# own _dim computation. Every spatial use of GRID_CELL must go through this,
# not the raw constant - a mismatch between how the shroud IMAGE is sized
# and how world positions are mapped INTO it produces exactly the "strange
# patches exposed and not exposed" bug this comment is here to prevent a
# repeat of (GRID_CELL was scaled here in setup() but not in the three
# other places that convert world position to a cell index, so vision
# writes landed in different cells than the shroud reader expected).
func _cell_size() -> float:
	return GRID_CELL * _world_scale

func _world_to_cell(x: float, z: float) -> Vector2i:
	var cell := _cell_size()
	return Vector2i(int(floor((x + _half) / cell)), int(floor((z + _half) / cell)))


# Only cells that CHANGE STATE are written, so cost scales with how much vision
# moved this tick rather than with the size of the map.
func _update_shroud(local_constructs: Array, beacons: Array) -> void:
	if _texture == null:
		return
	var viewers: Array = []
	for o in local_constructs:
		if not is_instance_valid(o):
			continue
		var v := effective_vision(o)
		if v > 0.0:
			viewers.append({"pos": o.global_position, "vision": v})
	for b in beacons:
		viewers.append({"pos": b.pos, "vision": b.radius})

	var now_visible: Dictionary = {}
	var cell_size := _cell_size()
	for o in viewers:
		var vision: float = o.vision
		var centre: Vector3 = o.pos
		var cell_radius := int(ceil(vision / cell_size)) + 1
		var c0 := _world_to_cell(centre.x, centre.z)
		for dz in range(-cell_radius, cell_radius + 1):
			var gz := c0.y + dz
			if gz < 0 or gz >= _dim:
				continue
			for dx in range(-cell_radius, cell_radius + 1):
				var gx := c0.x + dx
				if gx < 0 or gx >= _dim:
					continue
				var wx := -_half + (gx + 0.5) * cell_size
				var wz := -_half + (gz + 0.5) * cell_size
				if Vector2(wx - centre.x, wz - centre.z).length() <= vision:
					now_visible[Vector2i(gx, gz)] = true

	var changed := false
	for cell in now_visible:
		if not _prev_cells.has(cell):
			_image.set_pixel(cell.x, cell.y, Color(0, 0, 0, 0.0))
			changed = true
	for cell in _prev_cells:
		if not now_visible.has(cell):
			# Back to EXPLORED, not to unexplored. Somewhere you have been stays
			# known.
			_image.set_pixel(cell.x, cell.y, Color(0, 0, 0, EXPLORED_ALPHA))
			changed = true
	_prev_cells = now_visible
	if changed:
		_texture.update(_image)


# Whether a map cell has ever been seen. Exposed for the minimap, which draws
# terrain only where the player has been.
func cell_explored(x: float, z: float) -> bool:
	if _reveal_all_cheat():
		return true
	if _image == null:
		return false
	var cell := _world_to_cell(x, z)
	if cell.x < 0 or cell.x >= _dim or cell.y < 0 or cell.y >= _dim:
		return false
	return _image.get_pixel(cell.x, cell.y).a < UNEXPLORED_ALPHA
