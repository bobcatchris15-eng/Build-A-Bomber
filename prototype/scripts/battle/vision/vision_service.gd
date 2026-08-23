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

# SKIRMISH_PERF_TROUBLESHOOTING.md §12.6. Vision scans on a timer, not per frame.
# Visibility changing 2x a second is imperceptible and the scan is O(viewers x targets)
# per team. Was 0.3 s (= 3.33 Hz); doubled to 0.6 s (= 1.67 Hz) because the §12.1
# capture's `vision` section went 21 ms mean -> 56 ms mean after the cull landed
# and stopped hiding behind 4-7 fps render frames. Halving the per-second
# cost directly halves the per-second vision budget. The cache TTL (§_LOS_CACHE_TTL_MS
# below) was sized 2.5x against the OLD TICK_INTERVAL (0.75s / 0.3s = ~2.5 ticks);
# against the new interval it is now 1.25x, which is still warm across one
# TICK_INTERVAL and improves the hit rate rather than degrading it.
const TICK_INTERVAL := 0.6

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

# PR-4 (2026-08-19). LOS result cache.
#
# The 22:54:40 capture: 25 ms mean per tick, 665 ticks. The dominant cost
# is the per-(viewer, target) LOS raycast in _is_spotted(), and the same
# pair re-tests hundreds of times in a row for the same answer - a unit
# that LOS checks at frame N is in the same place at frame N+30. Caching
# the result for `_LOS_CACHE_TTL_MS` cuts the raycast count by roughly
# `TTL / TICK_INTERVAL` = 0.75 seconds / 0.3 = ~2.5x on the existing
# 3.33 Hz TICK_INTERVAL, and more on the in-between ticks where the
# cache stays warm across multiple TICK_INTERVALs.
#
# The cache is invalidated wholesale on structure events (`invalidate_los_cache`,
# called from match_director on _place_structure / _on_structure_died) and
# expires naturally on TTL. The cell granularity (`_LOS_CELL_SIZE`) is
# deliberately coarser than GRID_CELL: a unit that moved 2 m between
# cache writes still has the same cell, so the cache hit rate stays
# high during normal movement.
#
# TTL must be >= TICK_INTERVAL (750ms vs 300ms). The previous value of
# 250ms expired BEFORE the next tick, making the cache a no-op and
# re-raycasting every viewer×target pair every tick — the exact problem
# the cache was meant to solve. 750ms = 2.5× TICK_INTERVAL; a pair
# tested at tick N is still warm at tick N+1 and N+2.
const _LOS_CACHE_TTL_MS := 750
const _LOS_CELL_SIZE := 4.0
var _los_cache: Dictionary = {}
# Bumped on structure events. Included in the cache key so any entry written
# before the bump misses the next lookup - the wholesale clear that follows
# in `invalidate_los_cache` is just a defensive backup.
var _los_geom_version: int = 0

# SKIRMISH_PERF_TROUBLESHOOTING.md §12.6. Shroud resolution and the two dimmed
# states. Unexplored is opaque; explored is partly lifted and never returns to
# full black once seen.
#
# §12.6 made this 6.0 m (was 4.0 m). The 4 m resolution was a screen-space fog
# convention from the era when the shroud was a flat plane and needed fine
# subdivision to avoid the "stair-step" edge as a unit walked a vision boundary.
# Since §11 the shroud is a fullscreen depth-buffer pass (see the SHROUD IS
# SCREEN-SPACE block below), so the per-cell resolution no longer drives edge
# appearance; the cells are only the buckets the visibility logic writes into.
# Coarsening to 6 m drops per-viewer cell count from 729 to ~441 (a viewer with
# 50 m vision covers a 13x13 box at 4 m vs 9x9 at 6 m), saving ~40% of the
# _update_shroud scan. The shroud image is 120x120 -> 80x80 on lake_crossing;
# the minimap re-samples it (its own texture, see hud_minimap.gd) so the
# change is invisible to the player.
const GRID_CELL := 6.0
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


# PR-4 (2026-08-19). Wholesale cache invalidation. Called by match_director
# whenever the world geometry that LOS could care about changes - structure
# placement, structure death, anything that adds or removes a static occluder.
# Bumping the version also makes every pre-existing key miss, so the clear
# is belt-and-suspenders; the lookup loop never sees stale data either way.
func invalidate_los_cache() -> void:
	_los_geom_version += 1
	_los_cache.clear()
	# SKIRMISH_PERF_TROUBLESHOOTING.md §12.6. The shroud fast path is keyed
	# on viewer position; a structure event can change which cells are
	# visible even with no viewer moving. Forcing the count to -1 makes
	# the next _inputs_unchanged check fail and the cell scan to run once.
	_last_constructs_count = -1


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


func _pos_of(n: Node) -> Vector3:
	if not is_instance_valid(n):
		return Vector3.ZERO
	if n is Node3D:
		return n.global_position if n.is_inside_tree() else n.position
	return Vector3.ZERO


func _forward_of(n: Node) -> Vector3:
	if not is_instance_valid(n) or not (n is Node3D):
		return Vector3.FORWARD
	var b: Basis = n.global_transform.basis if n.is_inside_tree() else n.transform.basis
	return -b.z.normalized()


func _get_prop(o: Object, prop: String, default_val = null):
	if o == null or not is_instance_valid(o):
		return default_val
	var v = o.get(prop)
	if v != null:
		return v
	if o.has_meta(prop):
		return o.get_meta(prop)
	return default_val


func _is_spotted(c, viewers: Array, beacons: Array, was_visible: bool) -> bool:
	var c_flying: bool = bool(_get_prop(c, "is_flying", false))
	var c_moving: bool = false
	var vel = _get_prop(c, "velocity")
	if vel is Vector3:
		c_moving = vel.length() > 0.2
	elif bool(_get_prop(c, "is_moving", false)):
		c_moving = true

	var c_pos := _pos_of(c)

	for o in viewers:
		if not is_instance_valid(o):
			continue

		var o_pos := _pos_of(o)

		# 1. Seismic Sensing: Non-line-of-sight ground vibration sensing
		var seismic: float = float(_get_prop(o, "seismic_range", 0.0))
		if seismic > 0.0 and not c_flying and c_moving:
			var reach_seis := seismic * HIDE_RANGE_MULT if was_visible else seismic
			if c_pos.distance_to(o_pos) <= reach_seis:
				return true

		# 2. Check Directional Radar Sensors (focused sector reach)
		var dir_sensors = _get_prop(o, "directional_sensors")
		if dir_sensors is Array and not dir_sensors.is_empty():
			var fwd := _forward_of(o)
			var fwd_2d := Vector2(fwd.x, fwd.z).normalized()
			for ds in dir_sensors:
				var ds_range: float = float(ds.get("range", 0.0))
				var ds_arc_rad: float = float(ds.get("arc_rad", PI / 3.0))
				var ds_reach := ds_range * HIDE_RANGE_MULT if was_visible else ds_range
				var to_c: Vector3 = c_pos - o_pos
				var dist: float = to_c.length()
				if dist <= ds_reach and dist > 0.001:
					var to_c_2d := Vector2(to_c.x, to_c.z).normalized()
					var dot_val := clampf(fwd_2d.dot(to_c_2d), -1.0, 1.0)
					var angle := acos(dot_val)
					if angle <= ds_arc_rad * 0.5:
						var o_flying: bool = bool(_get_prop(o, "is_flying", false))
						if o_flying or c_flying:
							return true
						var has_thermal: bool = bool(_get_prop(o, "has_thermal_sight", false)) or \
							(is_instance_valid(o.get("hull_node")) and o.hull_node.has_meta("has_thermal_sight") and o.hull_node.get_meta("has_thermal_sight"))
						if _check_los_cached(o, c, has_thermal):
							return true

		# 3. Standard Omni Vision (and Thermal FLIR Sight)
		var vision := effective_vision(o)
		if vision > 0.0:
			if is_instance_valid(o.get("hull_node")) and o.hull_node.has_meta("has_fire_control_radar") \
					and o.hull_node.get_meta("has_fire_control_radar"):
				vision = maxf(vision, float(o.hull_node.get_meta("fire_control_max_range", vision)))
			var reach := vision * HIDE_RANGE_MULT if was_visible else vision
			if c_pos.distance_to(o_pos) <= reach:
				var o_flying: bool = bool(_get_prop(o, "is_flying", false))
				if o_flying or c_flying:
					return true
				var has_thermal: bool = bool(_get_prop(o, "has_thermal_sight", false)) or \
					(is_instance_valid(o.get("hull_node")) and o.hull_node.has_meta("has_thermal_sight") and o.hull_node.get_meta("has_thermal_sight"))
				if _check_los_cached(o, c, has_thermal):
					return true

	for b in beacons:
		if c_pos.distance_to(b.pos) <= b.radius:
			return true
	return false


func _check_los_cached(o: Node, c: Node, has_thermal: bool) -> bool:
	var o_pos := _pos_of(o)
	var c_pos := _pos_of(c)
	var key := "%d:%d:%d:%d:%d:%d:%d:%d" % [
		_los_geom_version,
		o.get_instance_id(), c.get_instance_id(),
		int(floor(o_pos.x / _LOS_CELL_SIZE)),
		int(floor(o_pos.z / _LOS_CELL_SIZE)),
		int(floor(c_pos.x / _LOS_CELL_SIZE)),
		int(floor(c_pos.z / _LOS_CELL_SIZE)),
		1 if has_thermal else 0,
	]
	var now := Time.get_ticks_msec()
	if _los_cache.has(key):
		var entry: Dictionary = _los_cache[key]
		if entry.expires_at > now:
			return entry.result
	var visible: bool = _has_line_of_sight(o_pos, c_pos, has_thermal)
	_los_cache[key] = {"result": visible, "expires_at": now + _LOS_CACHE_TTL_MS}
	return visible


func _has_line_of_sight(from_pos: Vector3, to_pos: Vector3, ignore_smoke: bool = false) -> bool:
	if _controller == null or not _controller.is_inside_tree():
		return true
	var space: PhysicsDirectSpaceState3D = _controller.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		from_pos + Vector3(0, EYE_HEIGHT, 0),
		to_pos + Vector3(0, EYE_HEIGHT, 0))
	var mask: int = BattleLayers.TERRAIN
	if not ignore_smoke:
		mask += SmokeVolumeScript.SMOKE_COLLISION_LAYER
	query.collision_mask = mask
	query.collide_with_areas = not ignore_smoke
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
# moved this tick rather than with the size of the map. SKIRMISH_PERF_TROUBLESHOOTING.md
# §12.6: the cell-scan IS skipped when the input is identical to last tick (the
# _inputs_unchanged check below), so the cost scales with how much vision MOVED
# THIS TICK rather than with N viewers x cells x sqrt. Both lines of defence are
# needed: the early-exit at the top avoids the scan; the `changed` flag at the
# bottom guards the set_pixel writes.
func _update_shroud(local_constructs: Array, beacons: Array) -> void:
	if _texture == null:
		return
	if _inputs_unchanged(local_constructs, beacons):
		return
	var viewers: Array = []
	var topographic_scanners: Array = []
	for o in local_constructs:
		if not is_instance_valid(o):
			continue
		var v := effective_vision(o)
		var o_pos := _pos_of(o)
		if v > 0.0:
			viewers.append({"pos": o_pos, "vision": v, "type": "omni"})
		var dir_sensors = _get_prop(o, "directional_sensors")
		if dir_sensors is Array:
			var fwd := _forward_of(o)
			var fwd_2d := Vector2(fwd.x, fwd.z).normalized()
			for ds in dir_sensors:
				var ds_r: float = float(ds.get("range", 0.0))
				var ds_arc: float = float(ds.get("arc_rad", PI / 3.0))
				if ds_r > 0.0:
					viewers.append({
						"pos": o_pos,
						"vision": ds_r,
						"type": "directional",
						"fwd": fwd_2d,
						"arc_rad": ds_arc,
					})
		var topo_r: float = float(_get_prop(o, "topographic_range", 0.0))
		if topo_r > 0.0:
			topographic_scanners.append({"pos": o_pos, "radius": topo_r})

	for b in beacons:
		viewers.append({"pos": b.pos, "vision": b.radius, "type": "omni"})

	var now_visible: Dictionary = {}
	var cell_size := _cell_size()
	for o in viewers:
		var vision: float = o.vision
		var centre: Vector3 = o.pos
		var cell_radius := int(ceil(vision / cell_size)) + 1
		var c0 := _world_to_cell(centre.x, centre.z)
		var is_dir: bool = o.get("type", "omni") == "directional"
		var fwd_2d: Vector2 = o.get("fwd", Vector2.ZERO)
		var arc_rad: float = o.get("arc_rad", TAU)

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
				var d_vec := Vector2(wx - centre.x, wz - centre.z)
				if d_vec.length() <= vision:
					if is_dir and d_vec.length() > 0.001:
						var angle := acos(clampf(fwd_2d.dot(d_vec.normalized()), -1.0, 1.0))
						if angle > arc_rad * 0.5:
							continue
					now_visible[Vector2i(gx, gz)] = true

	var changed := false
	for cell in now_visible:
		if not _prev_cells.has(cell):
			_image.set_pixel(cell.x, cell.y, Color(0, 0, 0, 0.0))
			changed = true
	for cell in _prev_cells:
		if not now_visible.has(cell):
			# Back to EXPLORED, not to unexplored. Somewhere you have been stays known.
			_image.set_pixel(cell.x, cell.y, Color(0, 0, 0, EXPLORED_ALPHA))
			changed = true

	# Topographic survey mapping (reveals terrain contours without tactical unit spotting)
	for topo in topographic_scanners:
		var t_pos: Vector3 = topo.pos
		var t_rad: float = topo.radius
		var cell_radius := int(ceil(t_rad / cell_size)) + 1
		var c0 := _world_to_cell(t_pos.x, t_pos.z)
		for dz in range(-cell_radius, cell_radius + 1):
			var gz := c0.y + dz
			if gz < 0 or gz >= _dim:
				continue
			for dx in range(-cell_radius, cell_radius + 1):
				var gx := c0.x + dx
				if gx < 0 or gx >= _dim:
					continue
				var cell_coord := Vector2i(gx, gz)
				if now_visible.has(cell_coord):
					continue
				var wx := -_half + (gx + 0.5) * cell_size
				var wz := -_half + (gz + 0.5) * cell_size
				if Vector2(wx - t_pos.x, wz - t_pos.z).length() <= t_rad:
					var cur_col = _image.get_pixel(gx, gz)
					if cur_col.a >= UNEXPLORED_ALPHA - 0.01:
						_image.set_pixel(gx, gz, Color(0, 0, 0, EXPLORED_ALPHA))
						changed = true

	_prev_cells = now_visible
	if changed:
		_texture.update(_image)
		# Bumped only on a real change so readers that keep a derived copy (the
		# minimap builds a re-shaded one) can skip rebuilding on the many ticks
		# where nothing moved far enough to uncover a new cell.
		shroud_version += 1
	# Cache the just-computed input for next tick's fast-path compare.
	_last_constructs_count = local_constructs.size()
	_last_beacons_count = beacons.size()
	_last_constructs_fingerprint.clear()
	for c in local_constructs:
		if is_instance_valid(c):
			_last_constructs_fingerprint.append({"pos": _pos_of(c), "fwd": _forward_of(c)})


# SKIRMISH_PERF_TROUBLESHOOTING.md §12.6. Input fingerprint for the _update_shroud
# fast path. Stores a quantized (x, z) per viewer at 0.5 m resolution, orientation,
# and the beacon count.
var _last_constructs_count: int = -1
var _last_beacons_count: int = -1
var _last_constructs_fingerprint: Array = []


func _inputs_unchanged(local_constructs: Array, beacons: Array) -> bool:
	if local_constructs.size() != _last_constructs_count:
		return false
	if beacons.size() != _last_beacons_count:
		return false
	for i in range(local_constructs.size()):
		var c: Node = local_constructs[i]
		if not is_instance_valid(c):
			return false
		var p: Vector3 = _pos_of(c)
		var prev_entry = _last_constructs_fingerprint[i]
		var prev_p: Vector3 = prev_entry["pos"] if prev_entry is Dictionary else prev_entry
		if int(p.x * 2.0) != int(prev_p.x * 2.0):
			return false
		if int(p.z * 2.0) != int(prev_p.z * 2.0):
			return false
		if prev_entry is Dictionary:
			var cur_fwd: Vector3 = _forward_of(c)
			var prev_fwd: Vector3 = prev_entry.get("fwd", Vector3.FORWARD)
			if int(cur_fwd.x * 4.0) != int(prev_fwd.x * 4.0) or int(cur_fwd.z * 4.0) != int(prev_fwd.z * 4.0):
				return false
	return true
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
