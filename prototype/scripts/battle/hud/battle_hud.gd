class_name BattleHUD
extends Control
# Slimmed-down BattleHUD - delegates chrome to CommandConsole.
# Keeps only minimap logic for headless test pixel assertions.

const Tokens = preload("res://scripts/ui_tokens.gd")
const ResourceCatalogScript = preload("res://scripts/battle/economy/resource_catalog.gd")
const TerrainBuilder = preload("res://scripts/terrain_builder.gd")
const LiveryScript = preload("res://scripts/livery.gd")
const WorldScaleScript = preload("res://scripts/world_scale.gd")
const CommandConsoleScript = preload("res://scripts/battle/hud/command_console.gd")
const MinimapOverlayScript = preload("res://scripts/battle/hud/minimap_overlay.gd")

# Minimap constants (kept for test compatibility)
const CELL := 2.0
const UI_SIZE := 180.0
const BLIP_RADIUS := 1
const WATER_COLOR := Color(0.15, 0.32, 0.55)
const MINIMAP_UNEXPLORED_ALPHA := 1.0
const MINIMAP_EXPLORED_ALPHA := 0.42
const SURFACE_COLORS := {
	"marsh": Color(0.30, 0.36, 0.24),
	"snow_mud": Color(0.55, 0.58, 0.60),
	"sand": Color(0.62, 0.56, 0.38),
	"gravel": Color(0.48, 0.46, 0.44),
	"forest": Color(0.16, 0.28, 0.16),
	"ice": Color(0.75, 0.85, 0.92),
}
const VIEW_INDICATOR_COLOR := Color(0.95, 0.95, 0.98)

var _director: Node = null
var _local_team: int = 0

# Minimap state (for tests that read minimap_image())
var _half: float = 80.0
var _world_scale: float = 1.0
var _dim: int = 0
var _static_image: Image = null
var _image: Image = null
var _texture: ImageTexture = null
var _fog_image: Image = null
var _fog_version: int = -1

# PR-B (2026-08-19). Minimap refresh rate cap.
var _MINIMAP_REFRESH_PERIOD_MS := 200
var _last_minimap_refresh_ms: int = -1

var command_console: CommandConsole
var minimap_overlay: MinimapOverlay

func _init() -> void:
	command_console = CommandConsoleScript.new()
	command_console.name = "CommandConsole"
	add_child(command_console)

	minimap_overlay = MinimapOverlayScript.new()
	minimap_overlay.name = "MinimapOverlay"
	add_child(minimap_overlay)

func setup(director: Node, local_team: int, current_map: Dictionary) -> void:
	_director = director
	_local_team = local_team
	_half = current_map.get("map_half_extents", 80.0)
	_world_scale = WorldScaleScript.for_map(current_map)

	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fit_to_viewport()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(fit_to_viewport):
		vp.size_changed.connect(fit_to_viewport)

	# Build minimap (for test pixel assertions)
	_bake_minimap(current_map)
	_build_minimap()

	# Delegate all chrome to CommandConsole
	command_console.setup(director, local_team, current_map)
	minimap_overlay.setup(current_map)

func fit_to_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	position = Vector2.ZERO
	size = vp.get_visible_rect().size

# --- Minimap (kept for test compatibility) ---

func _bake_minimap(current_map: Dictionary) -> void:
	var cell := CELL * _world_scale
	_dim = maxi(1, int(ceil((_half * 2.0) / cell)))
	var raw = current_map.get("ground_color", Color(0.2, 0.25, 0.2))
	var ground_color: Color = raw if raw is Color else Color(raw[0], raw[1], raw[2])
	_static_image = Image.create(_dim, _dim, false, Image.FORMAT_RGBA8)
	for gz in range(_dim):
		var wz := -_half + (gz + 0.5) * cell
		for gx in range(_dim):
			var wx := -_half + (gx + 0.5) * cell
			var color: Color
			if TerrainBuilder.is_water_at(current_map, wx, wz):
				color = WATER_COLOR
			else:
				var surf := TerrainBuilder.get_surface_type_at(current_map, Vector3(wx, 0, wz))
				color = SURFACE_COLORS.get(surf, ground_color)
			_static_image.set_pixel(gx, gz, color)
	_image = _static_image.duplicate()
	_texture = ImageTexture.create_from_image(_image)

func _build_minimap() -> void:
	# MinimapOverlay handles the visible minimap; this builds the backing texture for tests
	pass

func _composite_fog() -> void:
	var vision = _director.vision if _director != null and "vision" in _director else null
	if vision == null:
		return
	if "reveal_all" in vision and vision.reveal_all:
		return
	var src: Image = vision.shroud_image()
	if src == null or src.get_width() == 0:
		return

	var version: int = vision.shroud_version
	if _fog_image == null or _fog_version != version:
		_fog_version = version
		var shaded := src.duplicate()
		for y in range(shaded.get_height()):
			for x in range(shaded.get_width()):
				var a: float = shaded.get_pixel(x, y).a
				var out: float = 0.0
				if a >= 0.99:
					out = MINIMAP_UNEXPLORED_ALPHA
				elif a > 0.01:
					out = MINIMAP_EXPLORED_ALPHA
				shaded.set_pixel(x, y, Color(0.0, 0.0, 0.0, out))
		if shaded.get_width() != _dim or shaded.get_height() != _dim:
			shaded.resize(_dim, _dim, Image.INTERPOLATE_BILINEAR)
		_fog_image = shaded

	_image.blend_rect(_fog_image, Rect2i(Vector2i.ZERO, Vector2i(_dim, _dim)), Vector2i.ZERO)

func _refresh_minimap() -> void:
	if _texture == null:
		return
	_image.blit_rect(_static_image, Rect2i(Vector2i.ZERO, Vector2i(_dim, _dim)), Vector2i.ZERO)
	_composite_fog()

	for r in get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(r):
			continue
		var rc: Color = ResourceCatalogScript.color(str(r.get("resource_type")))
		_blip(r.global_position.x, r.global_position.z, rc)

	for c in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(c) or c.is_dead:
			continue
		var team: int = c.get_meta("team") if c.has_meta("team") else -1
		if team != _local_team and "fog_hidden" in c and c.fog_hidden:
			continue
		_blip(c.global_position.x, c.global_position.z,
			LiveryScript.zone_color(_faction_of(c), "hull_upper"))

	_draw_view_indicator()
	_texture.update(_image)

func _blip(world_x: float, world_z: float, color: Color) -> void:
	var c := world_to_cell(world_x, world_z)
	for dz in range(-BLIP_RADIUS, BLIP_RADIUS + 1):
		var gz := c.y + dz
		if gz < 0 or gz >= _dim:
			continue
		for dx in range(-BLIP_RADIUS, BLIP_RADIUS + 1):
			var gx := c.x + dx
			if gx < 0 or gx >= _dim:
				continue
			_image.set_pixel(gx, gz, color)

func world_to_cell(x: float, z: float) -> Vector2i:
	var cell := CELL * _world_scale
	return Vector2i(
		clampi(int(floor((x + _half) / cell)), 0, _dim - 1),
		clampi(int(floor((z + _half) / cell)), 0, _dim - 1))

# The image, for tests to read pixels back out of.
func minimap_image() -> Image:
	return _image

func _draw_view_indicator() -> void:
	if _director == null or not ("camera" in _director):
		return
	var cam = _director.camera
	if not is_instance_valid(cam) or not (cam is Camera3D) or not cam.is_inside_tree():
		return
	var vp_size: Vector2 = cam.get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return
	var corners: Array = []
	for p in [Vector2(0, 0), Vector2(vp_size.x, 0), Vector2(vp_size.x, vp_size.y), Vector2(0, vp_size.y)]:
		var origin: Vector3 = cam.project_ray_origin(p)
		var dir: Vector3 = cam.project_ray_normal(p)
		if dir.y >= -0.001:
			return
		var t: float = -origin.y / dir.y
		corners.append(origin + dir * t)
	for i in range(corners.size()):
		_draw_map_line(corners[i], corners[(i + 1) % corners.size()])

func _draw_map_line(a: Vector3, b: Vector3) -> void:
	var from := world_to_cell(a.x, a.z)
	var to := world_to_cell(b.x, b.z)
	var steps: int = maxi(absi(to.x - from.x), absi(to.y - from.y))
	if steps <= 0:
		_image.set_pixel(from.x, from.y, VIEW_INDICATOR_COLOR)
		return
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var gx: int = clampi(int(round(lerpf(from.x, to.x, t))), 0, _dim - 1)
		var gz: int = clampi(int(round(lerpf(from.y, to.y, t))), 0, _dim - 1)
		_image.set_pixel(gx, gz, VIEW_INDICATOR_COLOR)

func _faction_of(c) -> String:
	if "faction" in c and c.faction != "":
		return c.faction
	if "hull_node" in c and is_instance_valid(c.hull_node) and c.hull_node.has_meta("faction"):
		return c.hull_node.get_meta("faction")
	return LiveryScript.PLAYER_ID

# Per-tick refresh (called by match_director)
func refresh() -> void:
	# PR-B (2026-08-19). Cap the per-tick minimap work to 5 Hz. The
	# compositing itself is gated on shroud_version, but the surrounding
	# blit_rect + blip loops run unconditionally and the per-frame
	# update_texture call to ImageTexture was the visible 10 ms cost.
	# Capping the whole refresh is simpler and more aggressive - the
	# minimap is a 180px swatch, nobody sees 30 Hz updates.
	var now_ms := Time.get_ticks_msec()
	if _last_minimap_refresh_ms >= 0 and now_ms - _last_minimap_refresh_ms < _MINIMAP_REFRESH_PERIOD_MS:
		return
	_last_minimap_refresh_ms = now_ms
	_refresh_minimap()
	# CommandConsole handles its own updates via signals
