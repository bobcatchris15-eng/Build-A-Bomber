class_name BattleHUD
extends Control
# The always-on match readouts: resources, power, and the minimap.
#
# COMPOSITION ONLY. Every piece of chrome here is an existing ui_* widget or a
# theme variation from bomber_theme.tres. The old HUD was ~700 lines inside
# skirmish.gd building its own panels, and that is exactly the accretion this
# rebuild exists to undo - so this file arranges things and reads services, and
# owns no styling of its own beyond layout.
#
# The production queues are NOT here. production_hud.gd already owns them, with
# its dock and its radial ring, and a second thing drawing queue state would be
# two views of one truth that can disagree.
#
# THE MINIMAP IS A REAL Image, NOT A SubViewport. Headless never rasterizes a
# viewport, so a render-to-texture minimap cannot be asserted on in a test - and
# this one is asserted on, by reading pixels back. The old implementation made
# the same call for the same reason and it is carried over deliberately.

const Tokens = preload("res://scripts/ui_tokens.gd")
const ResourceCatalogScript = preload("res://scripts/battle/economy/resource_catalog.gd")
const TerrainBuilder = preload("res://scripts/terrain_builder.gd")
const LiveryScript = preload("res://scripts/livery.gd")
const WorldScaleScript = preload("res://scripts/world_scale.gd")
const CommandCardScript = preload("res://scripts/ui/command_card.gd")
const SpecPlacardScript = preload("res://scripts/ui/spec_placard.gd")
const EdgeMarkerScript = preload("res://scripts/ui/edge_marker.gd")

# Coarser than the fog grid on purpose: a minimap needs a recognisable
# silhouette, not per-vision-tick precision.
#
# CORE_DESIGN_LANGUAGE.md §3.2: world_scale=1.0 BASELINE - _bake_minimap()
# scales it by the map's resolved world_scale, same self-bounding reasoning
# as vision_service.gd's GRID_CELL (Chunk 16). The minimap is a fixed
# UI_SIZE on screen regardless of map size, so its underlying resolution
# should stay roughly constant too - left flat, a 16x-larger map would bake
# an image with 256x the pixels for no visible benefit.
# Lowered 8.0 -> 2.0 after playtest ("the minimap absolutely needs more
# resolution"). At 8.0 with world_scale 4 the minimap baked one pixel per 32
# world units - an 840 half-extent map came out ~52 pixels wide and was then
# stretched over a 180-pixel UI element, which is why it read as blocky. At 2.0
# the same map bakes ~210 pixels, so the texture is roughly 1:1 with the widget
# rather than being magnified 3.5x.
#
# This does NOT undo the self-bounding property above: the cell still scales
# with world_scale while _half scales with it too, so the baked dimension stays
# roughly constant as the world grows. It just picks a better constant. At
# ~210x210 RGB8 the image is ~130KB, which is not a budget worth defending
# against a legibility complaint.
const CELL := 2.0
const UI_SIZE := 180.0
const BLIP_RADIUS := 1

const WATER_COLOR := Color(0.15, 0.32, 0.55)

# Fog on the minimap is RE-SHADED, not copied straight from the world shroud.
#
# The world shroud dims explored-but-not-currently-seen ground to 26% of its
# colour (vision_service.gd's EXPLORED_ALPHA 0.74). That reads fine across a
# lit 3D scene, but the minimap is a 180px swatch of flat colour, and at 26%
# the difference between water, sand and marsh collapses - which would cost the
# player the map silhouette across most of the board, since most of the board
# is explored-but-unseen at any given moment. The distinction actually needed
# here is revealed vs not, so that is where the contrast is spent: never-seen
# goes fully black, explored stays legible, currently-seen is untouched.
const MINIMAP_UNEXPLORED_ALPHA := 1.0
const MINIMAP_EXPLORED_ALPHA := 0.42

# One flat colour per surface - a swatch, not a material. Echoes the per-surface
# tints the terrain generator uses so the minimap reads as the same map.
const SURFACE_COLORS := {
	"marsh": Color(0.30, 0.36, 0.24),
	"snow_mud": Color(0.55, 0.58, 0.60),
	"sand": Color(0.62, 0.56, 0.38),
	"gravel": Color(0.48, 0.46, 0.44),
	"forest": Color(0.16, 0.28, 0.16),
	"ice": Color(0.75, 0.85, 0.92),
}

var _director: Node = null
var _local_team: int = 0

var _resource_label: Label = null
var _power_bar: ProgressBar = null
var _power_label: Label = null
var _status_label: Label = null

var _half: float = 80.0
var _world_scale: float = 1.0
var _dim: int = 0
var _static_image: Image = null
var _image: Image = null
var _texture: ImageTexture = null
# The re-shaded fog layer, cached against vision.shroud_version - see
# _composite_fog().
var _fog_image: Image = null
var _fog_version: int = -1
var minimap_rect: TextureRect = null
var command_card: Control = null
var placard: Control = null
var edge_marker: Control = null


func setup(director: Node, local_team: int, current_map: Dictionary) -> void:
	_director = director
	_local_team = local_team
	_half = current_map.get("map_half_extents", 80.0)
	_world_scale = WorldScaleScript.for_map(current_map)
	# TOP_LEFT plus an explicit size, NOT FULL_RECT - see ProductionHUD.setup().
	# This HUD's parent is a CanvasLayer, which is not a Control and has no rect
	# for anchors to be fractions of, so FULL_RECT collapses the node to (0, 0)
	# and the top-RIGHT minimap renders at the far left on top of everything else.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fit_to_viewport()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(fit_to_viewport):
		vp.size_changed.connect(fit_to_viewport)

	_build_top_strip()
	_bake_minimap(current_map)
	_build_minimap()
	_build_command_card()
	
	edge_marker = EdgeMarkerScript.new()
	add_child(edge_marker)
	edge_marker.setup(_director)


func fit_to_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	position = Vector2.ZERO
	size = vp.get_visible_rect().size


# --- Top strip ---------------------------------------------------------------
#
# Offset from the very top edge rather than flush against it, so the readouts
# float over the battlefield instead of framing it - the research pass called
# this out and it matches what the UI style guide already asks for.
# Named so match_director can stack the key bindings BELOW the strip instead of
# guessing an offset that silently drifts the moment this changes.
const TOP_STRIP_HEIGHT := 56.0

func _build_top_strip() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "HUDPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_top = Tokens.SPACE_SM
	panel.offset_bottom = Tokens.SPACE_SM + TOP_STRIP_HEIGHT
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.SPACE_LG)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	_resource_label = Label.new()
	_resource_label.text = "METAL 0    CRYSTAL 0"
	row.add_child(_resource_label)

	_power_label = Label.new()
	_power_label.theme_type_variation = "HintLabel"
	_power_label.text = "POWER"
	row.add_child(_power_label)

	_power_bar = ProgressBar.new()
	_power_bar.custom_minimum_size = Vector2(160, 14)
	_power_bar.show_percentage = false
	_power_bar.max_value = 1.0
	row.add_child(_power_bar)

	_status_label = Label.new()
	_status_label.theme_type_variation = "HintLabel"
	row.add_child(_status_label)


# --- Minimap -----------------------------------------------------------------

# Terrain colours are baked ONCE. Every tick copies this and blits live blips on
# top, which is cheap because the image is small - repainting terrain per tick
# would be the expensive part and it never changes.
func _bake_minimap(current_map: Dictionary) -> void:
	var cell := CELL * _world_scale
	_dim = maxi(1, int(ceil((_half * 2.0) / cell)))
	# Map JSON carries this as a real Color once MapCatalog has parsed it, but the
	# raw form is a [r, g, b] array - accept either rather than assuming which
	# side of the parse this dictionary came from.
	var raw = current_map.get("ground_color", Color(0.2, 0.25, 0.2))
	var ground_color: Color = raw if raw is Color else Color(raw[0], raw[1], raw[2])
	# RGBA8, not RGB8: _refresh_minimap() composites the fog with
	# Image.blend_rect(), which hard-fails on a format mismatch between source
	# and destination (core/io/image.cpp's `format != p_src->format`) rather
	# than converting - and it fails by pushing an error and doing NOTHING, so
	# an RGB8 minimap would silently render with no fog at all. The alpha
	# channel itself is unused here; every pixel written below is opaque.
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
	minimap_rect = TextureRect.new()
	minimap_rect.texture = _texture
	minimap_rect.custom_minimum_size = Vector2(UI_SIZE, UI_SIZE)
	minimap_rect.size = Vector2(UI_SIZE, UI_SIZE)
	minimap_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	minimap_rect.stretch_mode = TextureRect.STRETCH_SCALE
	minimap_rect.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap_rect.offset_left = -(UI_SIZE + Tokens.SPACE_MD)
	minimap_rect.offset_top = Tokens.SPACE_MD + 64
	minimap_rect.offset_right = -Tokens.SPACE_MD
	minimap_rect.offset_bottom = Tokens.SPACE_MD + 64 + UI_SIZE
	minimap_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	minimap_rect.gui_input.connect(_on_minimap_input)
	add_child(minimap_rect)


func _build_command_card() -> void:
	command_card = CommandCardScript.new()
	command_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	command_card.offset_right = -Tokens.SPACE_MD
	command_card.offset_bottom = -Tokens.SPACE_MD
	add_child(command_card)
	command_card.setup(_director)
	
	placard = SpecPlacardScript.new()
	placard.level = SpecPlacardScript.Level.BATTLE
	placard.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	placard.offset_right = -Tokens.SPACE_MD - 180 # adjacent to command card
	placard.offset_bottom = -Tokens.SPACE_MD
	add_child(placard)
	
	_director.selection.selection_changed.connect(_on_selection_changed)

func _on_selection_changed(selected: Array) -> void:
	if selected.is_empty():
		placard.visible = false
		return
	var primary = selected[0]
	if not is_instance_valid(primary) or primary.is_dead:
		placard.visible = false
		return
	var blueprint = primary.get_meta("blueprint") if primary.has_meta("blueprint") else {}
	var design_name = primary.get_meta("design_name") if primary.has_meta("design_name") else "Unit"
	var title = design_name
	if selected.size() > 1:
		title += " (+%d)" % (selected.size() - 1)
	placard.from_blueprint(title, "", blueprint, primary.get_meta("design_stats") if primary.has_meta("design_stats") else {})
	placard.visible = true


func world_to_cell(x: float, z: float) -> Vector2i:
	var cell := CELL * _world_scale
	return Vector2i(
		clampi(int(floor((x + _half) / cell)), 0, _dim - 1),
		clampi(int(floor((z + _half) / cell)), 0, _dim - 1))


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


func _composite_fog() -> void:
	var vision = _director.vision if _director != null and "vision" in _director else null
	if vision == null:
		return
	# Cheat/debug reveal shows the whole map, same as the world view.
	if "reveal_all" in vision and vision.reveal_all:
		return
	var src: Image = vision.shroud_image()
	if src == null or src.get_width() == 0:
		return

	# The re-shade is per-pixel, so it runs only when the fog actually moved -
	# hence shroud_version. On the ticks where nothing was uncovered (most of
	# them) this is just the blend below, which is a single C++ call.
	var version: int = vision.shroud_version
	if _fog_image == null or _fog_version != version:
		_fog_version = version
		# Re-shade at the SOURCE resolution, which is coarser than the minimap
		# (the vision grid is 4 world units per cell against the minimap's 2),
		# so the per-pixel loop is roughly a quarter the size. Resizing after
		# the remap also lets the interpolation soften the cell edges.
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


# The image, for tests to read pixels back out of.
func minimap_image() -> Image:
	return _image


func _on_minimap_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var uv: Vector2 = event.position / UI_SIZE
	var world := Vector2(-_half + uv.x * _half * 2.0, -_half + uv.y * _half * 2.0)
	var camera: Camera3D = _director.camera
	if camera != null:
		# The camera is a fixed overhead rig with no separate pan target, so its
		# X/Z is its ground focus. Height and angle are left alone.
		camera.global_position.x = world.x
		camera.global_position.z = world.y


# --- Per-tick ----------------------------------------------------------------

func refresh() -> void:
	_refresh_resources()
	_refresh_minimap()
	_refresh_placard()

func _refresh_placard() -> void:
	if not placard.visible or _director.selection.selected.is_empty():
		return
	var primary = _director.selection.selected[0]
	if not is_instance_valid(primary) or primary.is_dead:
		return
	var vals := {}
	
	if "health" in primary and "max_health" in primary:
		var hp = clampf(float(primary.health) / float(primary.max_health), 0.0, 1.0)
		vals["health"] = "%d%%" % int(hp * 100)
		
	if "current_order_name" in primary:
		vals["order"] = str(primary.current_order_name)
	elif "current_order" in primary and primary.current_order != null:
		if "name" in primary.current_order:
			vals["order"] = primary.current_order.name
		else:
			vals["order"] = str(primary.current_order)
	else:
		vals["order"] = "IDLE"
		
	if "stance" in primary:
		vals["stance"] = str(primary.stance)
		
	placard.update_values(vals)


func _refresh_resources() -> void:
	var economy = _director.economy
	if economy == null:
		return
	# ONE NUMBER. The readout used to show METAL and CRYSTAL side by side, which
	# was two numbers the player had to mentally combine to answer the only
	# question they were asking - can I afford that. Income is alongside it
	# because cash-on-hand alone is misleading under drip-fed production: sitting
	# at zero while earning 30 a second and sitting at zero with dead harvesters
	# look identical otherwise.
	_resource_label.text = "%d cr    +%.0f/s" % [
		int(economy.credits(_local_team)), economy.income_rate(_local_team)]

	var capacity: float = economy.power_capacity(_local_team)
	var draw: float = economy.power_draw(_local_team)
	_power_bar.value = 0.0 if capacity <= 0.0 else clampf(draw / capacity, 0.0, 1.0)
	if economy.is_low_power(_local_team):
		_power_label.text = "LOW POWER"
		_status_label.text = "Production slowed - build more power"
	else:
		_power_label.text = "POWER"
		_status_label.text = ""


func _refresh_minimap() -> void:
	if _texture == null:
		return
	_image.blit_rect(_static_image, Rect2i(Vector2i.ZERO, Vector2i(_dim, _dim)), Vector2i.ZERO)
	# BEFORE the blips, deliberately. Fog shades the TERRAIN; the blips drawn
	# after it stay at full brightness, which keeps the existing rule that a
	# resource node is map knowledge rather than something you have to hold
	# ground to keep seeing. Compositing the other way round would quietly
	# reverse that.
	_composite_fog()

	# Resource nodes are map knowledge, not scouting-gated, so they are always
	# drawn - the same rule resource_node.gd already follows everywhere else.
	for r in get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(r):
			continue
		# Per-type colour straight off the catalog, so lumber and oil are
		# distinguishable on the minimap rather than all reading as ore.
		var rc: Color = ResourceCatalogScript.color(str(r.get("resource_type")))
		_blip(r.global_position.x, r.global_position.z, rc)

	for c in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(c) or c.is_dead:
			continue
		var team: int = c.get_meta("team") if c.has_meta("team") else -1
		# An enemy blip shows only while CURRENTLY scouted - no persistent memory,
		# the same one-directional rule the rest of the fog uses. Structures keep
		# their own ever-seen memory for the world view, but the minimap
		# deliberately does not, or it becomes a free map of the enemy base.
		if team != _local_team and "fog_hidden" in c and c.fog_hidden:
			continue
		_blip(c.global_position.x, c.global_position.z,
			LiveryScript.zone_color(_faction_of(c), "hull_upper"))

	_draw_view_indicator()

	_texture.update(_image)


# Playtest: the minimap needs a "current view" indicator. Drawn LAST so it sits
# on top of the blips rather than being overwritten by them.
#
# The footprint comes from the real camera by raycasting its four viewport
# corners onto the ground plane, so the box is genuinely what is on screen at
# the current height and tilt rather than a guess reconstructed from camera
# height. Every step is guarded: a controller without a camera, a camera not in
# a viewport, or a corner ray pointing at or above the horizon (which has no
# ground intersection at all) each skip the indicator rather than erroring or
# drawing a box stretching to infinity.
const VIEW_INDICATOR_COLOR := Color(0.95, 0.95, 0.98)

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
		# Looking level or upward: this corner never meets the ground.
		if dir.y >= -0.001:
			return
		var t: float = -origin.y / dir.y
		corners.append(origin + dir * t)
	for i in range(corners.size()):
		_draw_map_line(corners[i], corners[(i + 1) % corners.size()])


# A world-space segment onto the minimap image, sampled at enough steps that a
# long edge stays continuous instead of dotted.
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
