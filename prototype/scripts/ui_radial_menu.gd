class_name UIRadialMenu
extends Control
# A radial action ring that opens on the selected part in the Design Lab.
#
# WHY A RING RATHER THAN A SIDEBAR. Acting on a selected module used to mean
# travelling to the right-hand rail, finding the right row among a dozen
# permanently-visible ones, and clicking it - with the player's eyes leaving
# the model they are editing every single time. The actions are few, fixed and
# mutually exclusive, which is the exact shape a radial menu is for: every
# option is the same distance from the cursor, and after a handful of uses the
# direction becomes muscle memory and the menu stops needing to be read at all.
#
# WHY IT IS DRAWN RATHER THAN ASSEMBLED FROM BUTTONS. This is an instrument
# dial - a machined bezel with an index ring and tick marks. A ring of themed
# Buttons reads as a ring of buttons no matter what StyleBox goes on them, and
# the sector geometry (a wedge, not a rectangle) cannot be expressed as a
# StyleBox at all. Drawing also makes hover and click share one code path:
# both just ask which sector the cursor is in, which is what makes flick
# selection work for free.
#
# TONE. Legends are stencilled equipment labels - ROTATE, MIRROR, DISCARD -
# not friendly verbs, and the hub reads out the part's designation like a
# panel legend. The interface treats a googly kitbashed contraption as
# certified hardware; see scripts/blueprint_namer.gd for the rule in full.
#
# INTERACTION:
#   * Opens centred on the part, and TRACKS it - the ring stays glued to the
#     module as the camera orbits, like the callouts do.
#   * The hub is a dead zone. Releasing there cancels, which is the standard
#     escape hatch for radial menus and the reason the hub has to be large
#     enough to hit without care.
#   * Hovering a sector lights it and names it in the hub.
#   * Esc closes. So does invoking anything.

const Tokens = preload("res://scripts/ui_tokens.gd")
const UIAnim = preload("res://scripts/ui_anim.gd")
const UIIcons = preload("res://scripts/ui_icons.gd")

signal action_invoked(action_id: String)
signal dismissed()

# Geometry, in pixels at 100% scale.
#
# HUB_RADIUS is deliberately generous. A small dead zone means a player who
# opens the ring and changes their mind has to aim to cancel, and aiming to
# cancel is the single most annoying thing a radial menu can ask for.
const HUB_RADIUS := 30.0
const RING_INNER := 38.0
const RING_OUTER := 84.0
# Padding beyond RING_OUTER for the legend text, which is drawn outside the
# ring so it never fights the tick marks for space.
const LABEL_GAP := 14.0
const CANVAS_PAD := 56.0

const TICK_COUNT := 48
const TICK_LEN_MINOR := 4.0
const TICK_LEN_MAJOR := 8.0

# How far the camera can get before the ring fades out. Matches
# TweakCallout.max_zoom_distance so the two annotation systems disappear
# together rather than one lingering after the other.
var max_zoom_distance: float = 40.0

# The part this ring is acting on. The ring frees itself if it goes away -
# a menu still floating over a deleted module is worse than no menu.
var target_node: Node3D = null

# Shown in the hub when nothing is hovered. The part's designation.
var subject_label: String = ""

var _actions: Array = []          # [{id, label, icon, enabled}]
var _hovered: int = -1
var _is_open: bool = false


func _init() -> void:
	# The ring draws well outside its own centre, so it needs real size.
	var span := (RING_OUTER + CANVAS_PAD) * 2.0
	custom_minimum_size = Vector2(span, span)
	size = custom_minimum_size
	pivot_offset = custom_minimum_size * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Position is set in terms of the ring's CENTRE by _center_on(); the
	# control's own origin is its top-left, so everything that positions this
	# node goes through that helper rather than setting position directly.


# Registers one wedge. Order is the order they appear, starting at the top and
# going clockwise - the reading order for a dial.
#
# `icon` is a key into UIIcons.ICON_PATHS, or "" for a text-only wedge.
func add_action(id: String, label: String, icon: String = "", enabled: bool = true) -> void:
	_actions.append({
		"id": id,
		"label": label.to_upper(),
		"icon": icon,
		"enabled": enabled,
	})
	queue_redraw()


func set_action_enabled(id: String, enabled: bool) -> void:
	for a in _actions:
		if a["id"] == id:
			a["enabled"] = enabled
	queue_redraw()


func is_open() -> bool:
	return _is_open


# Opens the ring centred on `screen_pos`.
func open_at(screen_pos: Vector2) -> void:
	_is_open = true
	_hovered = -1
	visible = true
	_center_on(screen_pos)
	UIAnim.ring_pop(self)
	queue_redraw()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_hovered = -1
	# Free rather than hide. The ring is rebuilt per selection (the action set
	# depends on the part type), so a hidden one left in the tree is just a
	# stale node waiting to be shown with the wrong buttons on it.
	dismissed.emit()
	queue_free()


func _center_on(screen_pos: Vector2) -> void:
	position = screen_pos - size * 0.5


func _ready() -> void:
	# Sit above the callouts. Both live on the same canvas and the ring is the
	# thing being actively aimed at.
	z_index = 10
	if target_node and is_instance_valid(target_node):
		var camera := get_viewport().get_camera_3d()
		if camera:
			_center_on(camera.unproject_position(target_node.global_position))


func _process(delta: float) -> void:
	if not _is_open:
		return

	# Track the part. Freeing on an invalid target mirrors TweakCallout's
	# behaviour - see its _process() for the same guard.
	if target_node != null and not is_instance_valid(target_node):
		close()
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null or target_node == null:
		return

	var pos_3d := target_node.global_position
	if camera.is_position_behind(pos_3d):
		modulate.a = 0.0
		return

	var dist := camera.global_position.distance_to(pos_3d)
	var want_alpha := 0.0 if dist > max_zoom_distance else 1.0
	modulate.a = lerp(modulate.a, want_alpha, 10.0 * delta)

	# Lerp rather than snap so a camera orbit drags the ring smoothly instead
	# of making it judder a frame behind the model.
	var target_pos := camera.unproject_position(pos_3d) - size * 0.5
	position = position.lerp(target_pos, 20.0 * delta)


# Only the annulus belongs to this control. Without this the ring's bounding
# square swallows clicks in its corners - which, at 280px across, is most of
# its area and would make the viewport behind it feel broken.
func _has_point(point: Vector2) -> bool:
	var r := point.distance_to(size * 0.5)
	return r <= RING_OUTER


func _gui_input(event: InputEvent) -> void:
	if not _is_open:
		return

	if event is InputEventMouseMotion:
		var was := _hovered
		_hovered = _sector_at(event.position)
		if was != _hovered:
			queue_redraw()

	elif event is InputEventMouseButton and event.pressed:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		accept_event()
		var idx := _sector_at(event.position)
		if idx < 0:
			# Hub or outside: cancel.
			close()
			return
		var action: Dictionary = _actions[idx]
		if not action["enabled"]:
			return
		var id: String = action["id"]
		# Emit BEFORE closing. close() frees the node, and a queued signal
		# from a freed emitter never arrives.
		action_invoked.emit(id)
		close()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


# Which wedge contains `local_pos`. Returns -1 for the hub dead zone, for
# anything past the outer edge, and when there are no actions.
func _sector_at(local_pos: Vector2) -> int:
	if _actions.is_empty():
		return -1
	var offset := local_pos - size * 0.5
	var r := offset.length()
	if r < HUB_RADIUS or r > RING_OUTER:
		return -1

	var step := TAU / float(_actions.size())
	# atan2 gives 0 at +X and grows counter-clockwise in screen space (where Y
	# is down, so it visually reads clockwise). Rotating by a quarter turn puts
	# index 0 at the TOP, and adding half a sector centres wedge 0 on straight
	# up rather than starting its edge there.
	var angle := fposmod(atan2(offset.y, offset.x) + TAU * 0.25 + step * 0.5, TAU)
	return int(angle / step) % _actions.size()


# Centre angle of wedge `idx`, in the same frame _sector_at() inverts.
func _sector_angle(idx: int) -> float:
	var step := TAU / float(_actions.size())
	return -TAU * 0.25 + step * float(idx)


func _draw() -> void:
	var c := size * 0.5

	# --- Bezel -----------------------------------------------------------
	# A filled dark annulus first, so the ring is legible over a bright hull
	# or a pale sky. Drawn as a thick arc rather than two circles because a
	# stroked arc gives a clean inner AND outer edge in one call.
	var mid_r := (RING_INNER + RING_OUTER) * 0.5
	var band := RING_OUTER - RING_INNER
	draw_arc(c, mid_r, 0.0, TAU, 96, Color(Tokens.BASE_900, 0.92), band, true)

	# --- Hovered wedge ---------------------------------------------------
	# Drawn under the tick marks and dividers so those stay crisp on top of it.
	if _hovered >= 0 and _hovered < _actions.size():
		var enabled: bool = _actions[_hovered]["enabled"]
		var fill := Tokens.SIGNAL_HAZARD_DIM if enabled else Tokens.BASE_700
		_draw_wedge(c, _hovered, Color(fill, 0.95))

	# --- Index ring and ticks --------------------------------------------
	draw_arc(c, RING_OUTER, 0.0, TAU, 96, Tokens.BASE_500, 1.0, true)
	draw_arc(c, RING_INNER, 0.0, TAU, 96, Tokens.BASE_500, 1.0, true)

	for i in TICK_COUNT:
		var a := TAU * float(i) / float(TICK_COUNT)
		var dir := Vector2(cos(a), sin(a))
		var major := i % 4 == 0
		var length := TICK_LEN_MAJOR if major else TICK_LEN_MINOR
		var col := Tokens.BASE_400 if major else Tokens.BASE_500
		draw_line(c + dir * (RING_OUTER - length), c + dir * RING_OUTER, col, 1.0, true)

	# --- Wedge dividers ---------------------------------------------------
	if _actions.size() > 1:
		var step := TAU / float(_actions.size())
		for i in _actions.size():
			var a := _sector_angle(i) - step * 0.5
			var dir := Vector2(cos(a), sin(a))
			draw_line(c + dir * RING_INNER, c + dir * RING_OUTER,
				Tokens.BASE_500, 1.0, true)

	# --- Hub ---------------------------------------------------------------
	# Deliberately semi-transparent. The ring opens centred ON the part being
	# edited, so an opaque hub hides the one thing the player is looking at -
	# which was true of the first version and is a genuinely bad trade for a
	# menu whose whole purpose is editing that part. At 0.45 the hub still
	# reads as a distinct dead zone against the wedges while the model shows
	# through it.
	draw_circle(c, HUB_RADIUS, Color(Tokens.BASE_900, 0.45))
	draw_arc(c, HUB_RADIUS, 0.0, TAU, 48, Tokens.BASE_500, 1.0, true)

	_draw_contents(c)


func _draw_wedge(c: Vector2, idx: int, col: Color) -> void:
	var step := TAU / float(_actions.size())
	var a0 := _sector_angle(idx) - step * 0.5
	var a1 := a0 + step

	# Approximate the annular sector with a triangle strip: outer edge one
	# way, inner edge back. 12 segments is smooth enough at this radius that
	# the facets don't read, and cheap enough to redraw on every mouse move.
	var segments := 12
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var a: float = lerp(a0, a1, float(i) / float(segments))
		pts.append(c + Vector2(cos(a), sin(a)) * RING_OUTER)
	for i in range(segments, -1, -1):
		var a: float = lerp(a0, a1, float(i) / float(segments))
		pts.append(c + Vector2(cos(a), sin(a)) * RING_INNER)
	draw_colored_polygon(pts, col)


func _draw_contents(c: Vector2) -> void:
	var font := get_theme_font("font", "Label")
	if font == null:
		font = get_theme_default_font()
	if font == null:
		return

	# --- Hub legend --------------------------------------------------------
	# The hub names only the HOVERED ACTION, never the part.
	#
	# It carried the part designation as its resting text at first, and that was
	# wrong twice over: module names like "AUTOCANNON" are far wider than a
	# 60px hub, so they rendered clipped to "AUTOCANN"; and the designation is
	# not something the player needs repeated at the centre of their aim while
	# choosing a verb. The action words are all short and all fit. The
	# designation moved to a legend plate under the ring - which is also what
	# the reference mockup does.
	if _hovered >= 0 and _hovered < _actions.size():
		var hub_text: String = _actions[_hovered]["label"]
		var hub_size := font.get_string_size(
			hub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.FONT_MICRO)
		draw_string(font,
			c + Vector2(-hub_size.x * 0.5, hub_size.y * 0.25),
			hub_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			Tokens.FONT_MICRO, Tokens.SIGNAL_HAZARD)

	# --- Subject legend ----------------------------------------------------
	# A stencilled plate under the ring naming the part, the way a panel legend
	# names the control above it. Sits outside the ring so it can be as wide as
	# the designation needs.
	if subject_label != "":
		var sz := font.get_string_size(
			subject_label, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.FONT_MICRO)
		var plate := Rect2(
			c + Vector2(-sz.x * 0.5 - 8.0, RING_OUTER + LABEL_GAP + 10.0),
			sz + Vector2(16.0, 6.0))
		draw_rect(plate, Color(Tokens.BASE_900, 0.85))
		draw_rect(plate, Tokens.BASE_500, false, 1.0)
		draw_string(font,
			plate.position + Vector2(8.0, sz.y * 0.85),
			subject_label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			Tokens.FONT_MICRO, Tokens.TEXT_SECONDARY)

	# --- Wedge contents ----------------------------------------------------
	for i in _actions.size():
		var action: Dictionary = _actions[i]
		var enabled: bool = action["enabled"]
		var a := _sector_angle(i)
		var dir := Vector2(cos(a), sin(a))

		var tint := Tokens.TEXT_PRIMARY if enabled else Tokens.TEXT_DISABLED
		if i == _hovered and enabled:
			tint = Tokens.SIGNAL_HAZARD

		var icon_name: String = action["icon"]
		var icon: Texture2D = null
		if icon_name != "" and UIIcons.has_icon(icon_name):
			icon = UIIcons.get_icon(icon_name)

		var mid := c + dir * ((RING_INNER + RING_OUTER) * 0.5)

		if icon:
			var isz := Vector2(20, 20)
			draw_texture_rect(icon, Rect2(mid - isz * 0.5, isz), false, tint)
		else:
			# No icon: the legend goes in the wedge instead of outside it.
			var lbl: String = action["label"]
			var lsz := font.get_string_size(
				lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.FONT_MICRO)
			draw_string(font, mid + Vector2(-lsz.x * 0.5, lsz.y * 0.25),
				lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.FONT_MICRO, tint)
			continue

		# Legend outside the ring, for the icon case.
		var lbl2: String = action["label"]
		var lsz2 := font.get_string_size(
			lbl2, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.FONT_MICRO)
		var lpos := c + dir * (RING_OUTER + LABEL_GAP)
		draw_string(font, lpos + Vector2(-lsz2.x * 0.5, lsz2.y * 0.3),
			lbl2, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.FONT_MICRO, tint)
