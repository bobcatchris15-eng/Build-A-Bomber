class_name VisionService
extends RefCounted

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
# THE SHROUD IS SCREEN-SPACE, and this is its third design. The history is
# worth keeping because each step failed for a reason the next one had to fix:
#
#   1. A flat plane. Had to sit above the HIGHEST ground anywhere on the map or
#      hilltops rendered through it. Fine while maps were nearly flat.
#   2. A mesh conforming to height_at() at a small local clearance, because (1)
#      left the fog floating like a ceiling over every low-lying area once maps
#      had real hills and ravines.
#
# (2) fixed the terrain, but a sheet lying ON the ground can only ever hide the
# ground. Anything TALLER than its clearance punches straight through, and the
# terrain layer is now full of exactly that: trees, boulders, rock spires,
# cliff facades, buildings, resource nodes. The playtest report - fog "only
# covers the base ground" - is that geometry, not a bug in the sheet.
#
# Raising the sheet cannot fix it. Any clearance high enough to cover the
# tallest prop is a ceiling again, and the cure re-introduces (1).
#
# So the fog is no longer geometry in the world at all. It is a fullscreen pass
# that reads the depth buffer, reconstructs each pixel's world position, and
# looks that up in the same shroud texture as before. Whatever is nearest the
# camera at that pixel gets fogged, at any height - ground, a tree's canopy, a
# cliff face, a unit - because the test is "where is this pixel in the world",
# not "is this pixel under the sheet".
#
# Two consequences worth knowing:
#   - The conforming mesh, and with it the per-map shroud mesh build, is gone.
#     One quad replaces a grid that spanned the entire map.
#   - Sky pixels are skipped (nothing was drawn there to fog), so the horizon
#     stays clear instead of the fog climbing up it.
const SHROUD_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

// repeat_disable matters: a pixel off the edge of the map produces a UV
// outside 0..1, and with repeat on that wraps to fog from the opposite side.
uniform sampler2D shroud_tex : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float map_half = 80.0;
uniform vec3 fog_color = vec3(0.015, 0.015, 0.02);

void vertex() {
	// Drive clip space directly so the quad covers the viewport wherever the
	// instance happens to sit in the scene tree. QuadMesh spans -0.5..0.5, so
	// x2 fills -1..1. z = 1.0 is the near plane under Godot's reverse-Z, which
	// with depth_test_disabled just guarantees it is never clipped away.
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	// Both extremes are rejected on purpose, rather than just the far plane.
	// One of them IS the far plane - the sky, where nothing was drawn and
	// fogging would paint a grey wall up the horizon - but WHICH one depends
	// on whether the renderer is using reverse-Z, and that is a detail of the
	// engine build rather than something this shader should encode. Nothing
	// legitimately renders exactly at the near plane either, so discarding
	// both is correct under either convention.
	if (d <= 0.000001 || d >= 0.999999) {
		discard;
	}
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, d);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	vec2 uv = (world.xz + vec2(map_half)) / (2.0 * map_half);
	// Off the edge of the map there is no fog state to read.
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		discard;
	}
	ALBEDO = fog_color;
	ALPHA = texture(shroud_tex, uv).a;
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

# Increments whenever the shroud image actually changes. See _update_shroud().
var shroud_version: int = 0

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
	inst.mesh = QuadMesh.new()
	# The vertex shader writes POSITION directly, so this instance's transform
	# never reaches the rasterizer - but the CULLER still uses its AABB, and a
	# unit quad parked at the origin is culled the moment the camera looks away
	# from it, taking the whole fog pass with it. An AABB larger than any map
	# keeps it permanently in frame.
	inst.custom_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = SHROUD_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("shroud_tex", _texture)
	mat.set_shader_parameter("map_half", _half)
	# Last of the transparent pass. Water and the shallow-water markers are
	# transparent too, and the fog has to land on top of them rather than
	# underneath.
	mat.render_priority = 127
	inst.material_override = mat
	return inst


# The live fog image: alpha 0 where currently seen, EXPLORED_ALPHA where seen
# before, UNEXPLORED_ALPHA where never seen. Exposed so the minimap can shade
# itself from the SAME source the world shroud uses, rather than keeping a
# second copy of the rules that could drift out of step with this one.
func shroud_image() -> Image:
	return _image


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
		# Bumped only on a real change so readers that keep a derived copy (the
		# minimap builds a re-shaded one) can skip rebuilding on the many ticks
		# where nothing moved far enough to uncover a new cell.
		shroud_version += 1


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
