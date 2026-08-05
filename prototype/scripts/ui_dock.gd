class_name UIDock
extends PanelContainer
# An edge-anchored dock that collapses to a rail and can auto-hide - the
# old-IDE panel, in Godot.
#
# THE PROBLEM IT SOLVES. The Design Lab's two sidebars are permanently open and
# permanently full: a 320px parts column of two dozen identical rows on the
# left, a stat column on the right carrying armour material, faction, thickness,
# undo/redo and three action buttons - all of it visible whether or not it
# applies to anything selected. The model being edited, which is the entire
# point of the screen, gets whatever is left in the middle. Chrome should be
# reachable, not resident.
#
# THREE STATES, cycled by the header chevron or set directly:
#   EXPANDED  full body visible, resizable by dragging the splitter edge.
#   RAILED    collapsed to a ~40px strip showing the title and an icon. Click
#             the rail to expand. This is the IDE behaviour and the default for
#             the Design Lab's two docks.
#   HIDDEN    fully off-edge, leaving a narrow grab tab. If `auto_reveal` is on,
#             hovering the screen edge slides it back in and it re-hides on
#             mouse-out.
#
# AUTO-HIDE IS OPT-IN AND OFF BY DEFAULT, and Skirmish must leave it off. A dock
# that vanishes on its own mid-fight costs the player the fight; "gets out of
# the way" is a virtue in an editor and a defect in a real-time match.
#
# THE LAYOUT TRAP, learned in parts_menu.gd:389-408 and worth restating because
# it is invisible until it bites: a collapsed panel CANNOT be a Container with
# clip_contents. A Container propagates its children's combined minimum size to
# its parent regardless of clipping, so a "collapsed" dock would still demand
# its full expanded width from the layout and collapse nothing at all. The body
# therefore lives inside a plain Control clip wrapper whose custom_minimum_size
# this script drives directly. That wrapper carries the `ui_audit_clip_ok` meta
# so the layout-overflow audit knows the zero-size window around a full-size
# child is deliberate (see ui_audit.gd:11-25 for why that opt-out has to be
# stated rather than inferred from clip_contents).

const Tokens = preload("res://scripts/ui_tokens.gd")
const UIAnim = preload("res://scripts/ui_anim.gd")
const UIIcons = preload("res://scripts/ui_icons.gd")

signal state_changed(new_state: int)

enum State { EXPANDED, RAILED, HIDDEN }
enum Side { LEFT, RIGHT, BOTTOM }

const RAIL_SIZE := 40.0
# How far the dock is held off its window edge. SPACE_MD reads as a deliberate
# gap at every window size without eating usable panel width.
const EDGE_INSET := 12.0
# The collapsed rectangle's OUTER size, which is not RAIL_SIZE.
#
# RAIL_SIZE is the inner extent the clip/minimum-size contract is written against
# (outer_extent() returns it, and a suite in test_ui_and_camera asserts that), but
# the dock's PLATE adds SPACE_SM of padding on each side and the rail button's own
# plate margins sit inside that. The box therefore renders at RAIL_SIZE + 16.
#
# The offsets have to use the real outer figure or the collapsed rectangle
# overhangs its own inset - measured as the right-hand dock spanning 1868..1924 on
# a 1920 viewport, i.e. 4px off-screen, while its left edge looked correct.
const RAIL_BOX := RAIL_SIZE + 16.0
const TAB_SIZE := 10.0
const MIN_EXPANDED := 180.0
const MAX_EXPANDED := 640.0
const SPLITTER_GRAB := 6.0
# How close to the screen edge the pointer must come to wake a hidden dock.
const REVEAL_MARGIN := 12.0

@export var dock_title: String = "PANEL"
@export var dock_icon: String = ""
# Typed `int`, not `Side`, and assigned from the enum.
#
# Godot 4.3 will not accept a script-local enum as an @export type on a script
# that also declares class_name - it reports "Cannot assign a value of type
# UIDock.Side as Side", because the exported property resolves the type through
# the global class registration and ends up comparing the enum to itself under
# two different names. Typing the storage as int and keeping the enum for
# readability sidesteps it without giving up the named constants.
@export var side: int = Side.LEFT
@export var expanded_size: float = 320.0
@export var auto_reveal: bool = false
# State a dock opens in the FIRST time, before it has a persisted preference.
# VISUAL/UI plan item 7 wants the Design Lab's two docks railed by default, so the
# 3D model - the actual subject - gets the screen instead of the leftover middle.
@export var default_state: int = State.EXPANDED
# Where this dock's state is remembered. Empty disables persistence, which is
# what the tests want - otherwise a test run rewrites the player's layout.
@export var persist_key: String = ""

const LAYOUT_PATH := "user://ui_layout.cfg"

var _state: int = State.EXPANDED
var _body_host: VBoxContainer
var _clip: Control
var _header_btn: Button
var _rail_btn: Button
var _tween: Tween
var _dragging_splitter := false


func _init() -> void:
	theme_type_variation = "DockPanel"
	clip_contents = false


func _ready() -> void:
	_build()
	# The default goes in BEFORE _load_state(), which uses `_state` as its own
	# fallback. Setting it afterwards would silently overrule whatever the player
	# last left the dock as, which is the opposite of what persistence is for.
	_state = default_state
	_load_state()
	_apply_state(false)
	set_process_input(auto_reveal)


func _build() -> void:
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	# --- Header ----------------------------------------------------------
	# The whole header is the collapse control. A dedicated 16px chevron is a
	# worse target than a 320x28 bar, and there is nothing else the header
	# does.
	_header_btn = Button.new()
	_header_btn.theme_type_variation = "TabButton"
	_header_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header_btn.custom_minimum_size = Vector2(0, 28)
	_header_btn.text = dock_title
	_header_btn.focus_mode = Control.FOCUS_NONE
	_header_btn.pressed.connect(_on_header_pressed)
	column.add_child(_header_btn)

	# --- Body, inside the clip wrapper ------------------------------------
	_clip = Control.new()
	_clip.name = "DockClip"
	_clip.clip_contents = true
	_clip.set_meta("ui_audit_clip_ok", true)
	_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_clip)

	_body_host = VBoxContainer.new()
	_body_host.name = "DockBody"
	_body_host.add_theme_constant_override("separation", Tokens.SPACE_SM)
	# FULL_RECT: the body always matches the clip in BOTH axes.
	#
	# It used to be LEFT_WIDE (or TOP_WIDE for a bottom dock), which leaves one
	# axis unanchored and therefore sized by the content's own minimum. That works
	# only as long as the content HAS a minimum on that axis, and it silently fails
	# for the one container that deliberately does not: a ScrollContainer reports a
	# zero minimum, because being smaller than its content is the entire point of
	# it. The Design Lab's telemetry rail is a ScrollContainer, so the body came out
	# 0px wide and the whole expanded panel rendered empty - header visible, nothing
	# under it. The clip is what bounds the content here; the body should just fill
	# it and let overflow scroll or clip.
	_body_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_clip.add_child(_body_host)

	# --- Rail -------------------------------------------------------------
	# Shown only in RAILED/HIDDEN.
	#
	# This used to carry `dock_title.substr(0, 3)` on the grounds that "an
	# unlabelled strip of icons is a memory test". The intent was right and the
	# execution did not survive contact with the width: a 40px rail is ~24px inside
	# the panel's padding, so three stencil capitals either forced the rail wider
	# than 40px (which they did - see _rail_btn.clip_text below) or clipped to
	# nothing legible. A rotated vertical label is what an IDE does here and what
	# Godot's Button cannot do.
	#
	# So the rail identifies itself by ICON plus tooltip instead. Every dock in the
	# project sets dock_icon for exactly this reason; a dock without one gets a bare
	# strip, which is the case worth avoiding.
	_rail_btn = Button.new()
	_rail_btn.theme_type_variation = "TabButton"
	_rail_btn.focus_mode = Control.FOCUS_NONE
	_rail_btn.visible = false
	_rail_btn.pressed.connect(func(): set_dock_state(State.EXPANDED))
	if dock_icon != "" and UIIcons.has_icon(dock_icon):
		_rail_btn.icon = UIIcons.get_icon(dock_icon)
	_rail_btn.tooltip_text = dock_title
	# clip_text, and this is load-bearing rather than cosmetic. A Button's minimum
	# size includes its full text width, and this button is the only VISIBLE child
	# while the dock is railed - so its minimum became the dock's minimum. A
	# 3-letter title measured ~51px against a 40px rail, which meant a "collapsed"
	# dock silently demanded 64px including the panel's padding: the exact
	# Container-propagation trap the plan flags in item 4, arriving through the
	# rail button instead of through the clip. Caught by
	# test_ui_dock_state_cycle, not by looking at it - a 24px overrun looks fine.
	_rail_btn.clip_text = true
	_rail_btn.custom_minimum_size = Vector2.ZERO
	column.add_child(_rail_btn)


# Where callers put their content. Never add children to the dock directly -
# they would land beside the header rather than inside the clip window, and
# would not collapse.
func body() -> VBoxContainer:
	return _body_host


# The dock's OUTER extent for whatever state it is in or heading to - width for a
# LEFT/RIGHT dock, height for a BOTTOM one.
#
# Public because neighbours have to lay themselves out against it: skirmish.gd's
# minimap sits directly on top of the production bar and has to know how tall
# that bar will BE, not how tall it currently is. Reading `size` mid-collapse
# gives an interpolated value, and reading custom_minimum_size gives the inner
# extent (padding-discounted, see _clip_extent), so neither answers the question.
func outer_extent() -> float:
	return _target_extent()


func get_dock_state() -> int:
	return _state


func set_dock_state(new_state: int, animate: bool = true) -> void:
	if new_state == _state:
		return
	_state = new_state
	_apply_state(animate)
	_save_state()
	state_changed.emit(_state)


func toggle() -> void:
	# EXPANDED -> RAILED -> EXPANDED. HIDDEN is deliberately NOT in the cycle:
	# a player who clicks a header twice should get back where they started,
	# not lose the panel off the edge of the screen. Hiding is an explicit act.
	set_dock_state(State.RAILED if _state == State.EXPANDED else State.EXPANDED)


func _on_header_pressed() -> void:
	toggle()


# The dock's extent along its own axis, for the current state.
func _target_extent() -> float:
	match _state:
		State.EXPANDED:
			return expanded_size
		State.RAILED:
			return RAIL_SIZE
		_:
			return TAB_SIZE


func _is_horizontal() -> bool:
	return side != Side.BOTTOM


func _apply_state(animate: bool) -> void:
	var expanded := _state == State.EXPANDED
	_header_btn.visible = expanded
	_rail_btn.visible = not expanded
	# The clip is HIDDEN when collapsed, not merely narrowed.
	#
	# Driving _clip.custom_minimum_size to zero is not enough: the clip lives in a
	# VBoxContainer, which hands every visible child the full available width, and
	# custom_minimum_size is a floor rather than a ceiling. So a railed dock still
	# handed the clip its inner width (~24px) and cropped the catalogue to a 24px
	# vertical sliver - a column of "Li / Ro / Th / Ca" letter-fragments down the
	# rail instead of the rail button. Visibly wrong in the first capture of the
	# railed Lab, and invisible to the width assertions, which were all correct.
	_clip.visible = expanded
	# Never text - see the rail's construction comment in _build() for why three
	# capitals cannot fit a 40px rail. Identity is the icon plus the tooltip.
	_rail_btn.text = ""
	# In HIDDEN the rail button IS the grab tab, and it has to be able to shrink to
	# TAB_SIZE. The TabButton plate's content margins are 12px a side, so even an
	# empty clipped button held the dock at 24px + the panel's 16px = 40px - the
	# same width as RAILED, which made HIDDEN indistinguishable from it and so
	# pointless. A grab tab is a sliver of bare metal rather than a control with a
	# face, so it gets a zero-margin fill; the moment the dock is railed or
	# expanded, the plate comes back.
	if _state == State.HIDDEN:
		_rail_btn.add_theme_stylebox_override("normal", _tab_style(Tokens.BASE_600))
		_rail_btn.add_theme_stylebox_override("hover", _tab_style(Tokens.BASE_500))
		_rail_btn.add_theme_stylebox_override("pressed", _tab_style(Tokens.BASE_500))
		# The dock's OWN plate goes too. DockPanel carries SPACE_SM of padding on
		# each side, which is a 16px floor on the dock's minimum width - wider than
		# TAB_SIZE, so the tab could never actually reach its intended 10px. A
		# hidden dock is off-edge and has no visible body to put a surface on, so
		# there is nothing to lose by dropping the plate until it comes back.
		add_theme_stylebox_override("panel", _tab_style(Color(0, 0, 0, 0)))
	else:
		_rail_btn.remove_theme_stylebox_override("normal")
		_rail_btn.remove_theme_stylebox_override("hover")
		_rail_btn.remove_theme_stylebox_override("pressed")
		remove_theme_stylebox_override("panel")

	# METALLIC WHEN COLLAPSED. DockRail is the steel variation - brushed bare
	# sheet - against DockPanel's powdercoat body. Expanded, the dock is a panel
	# you read from and powdercoat is right; collapsed it is a small machined tab
	# you press, and steel is what makes it read as a piece of hardware rather
	# than as a shrunken panel. Steel also sits highest in the material luminance
	# stack, so the closed rectangle stays findable against the 3D viewport.
	if _state == State.HIDDEN:
		pass  # keeps the bare zero-margin tab style assigned above
	elif expanded:
		theme_type_variation = "DockPanel"
	else:
		theme_type_variation = "DockRail"

	var extent := _target_extent()

	if _tween and _tween.is_valid():
		_tween.kill()

	# The CLIP drives collapse, not the dock's own size - see the layout trap
	# in the header comment.
	# Discounted by the panel's own padding so the dock's OUTER extent is `extent`
	# rather than `extent` + padding - see _panel_padding() for the test failure
	# that came from getting this wrong.
	var inner := _clip_extent(extent)
	var clip_target := Vector2.ZERO
	if _is_horizontal():
		clip_target = Vector2(inner if expanded else 0.0, 0)
	else:
		clip_target = Vector2(0, inner if expanded else 0.0)

	_apply_edge_offsets(extent)

	if not animate:
		custom_minimum_size = _extent_vector(_clip_extent(extent))
		_clip.custom_minimum_size = clip_target
		return

	# One clock for the whole interface - UIAnim's constants, not a local
	# guess, so docks move at the same speed as everything else.
	_tween = create_tween()
	_tween.set_trans(UIAnim.TRANS_STANDARD)
	_tween.set_ease(UIAnim.EASE_STANDARD)
	_tween.set_parallel(true)
	var prop := "custom_minimum_size:x" if _is_horizontal() else "custom_minimum_size:y"
	_tween.tween_property(self, prop, _clip_extent(extent), UIAnim.DURATION_NORMAL)
	_tween.tween_property(_clip, prop,
		clip_target.x if _is_horizontal() else clip_target.y,
		UIAnim.DURATION_NORMAL)


func _extent_vector(extent: float) -> Vector2:
	return Vector2(extent, 0) if _is_horizontal() else Vector2(0, extent)


# Pins the dock INSIDE its edge rather than just outside it.
#
# THE TRAP THIS CLOSES, which cost two separate bugs before it was centralised.
# Callers anchor a dock with the matching preset - PRESET_LEFT_WIDE,
# PRESET_RIGHT_WIDE, PRESET_BOTTOM_WIDE - and those presets set BOTH anchors on
# the docked axis to the same edge with zero offsets. A LEFT dock happens to work,
# because its anchors are at 0.0 and custom_minimum_size grows it rightward into
# the screen. RIGHT and BOTTOM anchor at 1.0, so the same growth goes OUTWARD:
#   * the Design Lab's stat dock rendered at x=1920 in a 1920-wide viewport,
#     entirely off the right edge (caught by test_ui_no_overflow_or_offscreen);
#   * the Skirmish production bar rendered below the bottom edge and was simply
#     absent from the HUD (caught by looking at a capture).
#
# Both are the same mistake, so the dock now takes responsibility for the offset
# on its own docked axis. Callers still own the ANCHORS; this only ever writes
# offsets, and only on the axis the dock occupies.
func _apply_edge_offsets(extent: float) -> void:
	# INSET FROM THE EDGE rather than flush against it. A panel welded to the
	# window edge reads as part of the window chrome; held off it by a margin it
	# reads as an instrument sitting ON the console, which is the whole material
	# metaphor. The inset also gives the collapsed rectangle's shadow somewhere to
	# fall - flush against the edge, elevation is invisible on that side.
	# Collapsed uses the real outer box (see RAIL_BOX); expanded uses the caller's
	# requested extent, which already reads as an outer width.
	var outer := extent if _state == State.EXPANDED else RAIL_BOX
	match side:
		Side.LEFT:
			offset_left = EDGE_INSET
			offset_right = EDGE_INSET + outer
		Side.RIGHT:
			offset_left = -(EDGE_INSET + outer)
			offset_right = -EDGE_INSET
		_:
			offset_top = -extent
			offset_bottom = 0.0

	# COLLAPSED IS A SMALL FLOATING RECTANGLE, not a full-height strip.
	#
	# A railed dock used to run the entire viewport height, which is a lot of ink
	# for "there is a panel here" and made both edges of the Lab read as permanent
	# furniture even when nothing was open. Collapsed, it now clamps to a squarish
	# button that hovers near the top of its own side; expanded, it takes the height
	# back.
	#
	# Only touches offset_bottom / anchor_bottom, never offset_top: the caller sets
	# offset_top to clear the Design Lab's toolbar and that inset has to survive.
	if side == Side.LEFT or side == Side.RIGHT:
		if _state == State.EXPANDED:
			anchor_bottom = 1.0
			offset_bottom = -EDGE_INSET
		else:
			# anchor_bottom to the TOP anchor, so offset_bottom measures a fixed
			# height down from wherever the caller pinned the top rather than up
			# from the bottom of the screen.
			anchor_bottom = anchor_top
			offset_bottom = offset_top + RAIL_BOX


# The hidden dock's grab tab: a flat sliver with NO content margins, so it can
# actually reach TAB_SIZE. Cached per colour to keep _apply_state() allocation-free.
var _tab_styles: Dictionary = {}

func _tab_style(c: Color) -> StyleBoxFlat:
	if not _tab_styles.has(c):
		var sb = StyleBoxFlat.new()
		sb.bg_color = c
		sb.content_margin_left = 0
		sb.content_margin_right = 0
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		_tab_styles[c] = sb
	return _tab_styles[c]


# The dock's own panel padding, in pixels.
#
# WHY THIS EXISTS. `expanded_size` has to mean the dock's OUTER width, because
# that is what every caller assumes: parts_menu.gd anchors a 336px host Control
# and sets expanded_size = 336 expecting the two to match. But this node is a
# PanelContainer, and a PanelContainer's minimum size is its child's minimum PLUS
# its stylebox's content margins - and Godot takes the MAX of that and any
# custom_minimum_size, so the padding could not be absorbed by simply asking for
# less.
#
# The symptom was a real test failure, not a theory: test_ui_no_overflow_or_
# offscreen reported UI_PartsMenu at fixed_size=(336,1080) against
# content_min=(352,51). 352 = the clip's 336 + DockPanel's SPACE_SM on each side.
# So the dock demanded 16px more than the column it was placed in, every frame,
# in both of the Design Lab's docks.
#
# Read from the live stylebox rather than hardcoded from Tokens.SPACE_SM, because
# build_ui_theme.gd owns that padding and is free to change it.
func _panel_padding() -> Vector2:
	var sb := get_theme_stylebox("panel")
	if sb == null:
		return Vector2.ZERO
	return Vector2(
		sb.content_margin_left + sb.content_margin_right,
		sb.content_margin_top + sb.content_margin_bottom)


# The extent the CLIP should ask for, so that the dock's outer size lands on
# `extent`. Never negative: a padding wider than the rail would otherwise flip
# the rail inside out.
func _clip_extent(extent: float) -> float:
	var pad := _panel_padding()
	return maxf(0.0, extent - (pad.x if _is_horizontal() else pad.y))


# --- Splitter -------------------------------------------------------------
# Dragging the dock's inner edge resizes it. Only meaningful when expanded.

func _gui_input(event: InputEvent) -> void:
	if _state != State.EXPANDED:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _over_splitter(event.position):
			_dragging_splitter = true
			accept_event()
		elif not event.pressed:
			if _dragging_splitter:
				_save_state()
			_dragging_splitter = false

	elif event is InputEventMouseMotion:
		if _dragging_splitter:
			# Explicitly typed: GDScript cannot infer through a ternary whose
			# branches it has not resolved yet.
			var delta: float = event.relative.x if _is_horizontal() else event.relative.y
			# A dock on the RIGHT grows when dragged left, so the sign flips.
			if side == Side.RIGHT:
				delta = -delta
			if side == Side.BOTTOM:
				delta = -delta
			expanded_size = clampf(expanded_size + delta, MIN_EXPANDED, MAX_EXPANDED)
			custom_minimum_size = _extent_vector(expanded_size)
			_clip.custom_minimum_size = _extent_vector(expanded_size)
			accept_event()
		elif _over_splitter(event.position):
			mouse_default_cursor_shape = (Control.CURSOR_HSIZE
				if _is_horizontal() else Control.CURSOR_VSIZE)
		else:
			mouse_default_cursor_shape = Control.CURSOR_ARROW


func _over_splitter(pos: Vector2) -> bool:
	match side:
		Side.LEFT:
			return pos.x >= size.x - SPLITTER_GRAB
		Side.RIGHT:
			return pos.x <= SPLITTER_GRAB
		_:
			return pos.y <= SPLITTER_GRAB


# --- Auto-reveal ----------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not auto_reveal or _state != State.HIDDEN:
		return
	if not (event is InputEventMouseMotion):
		return
	var vp := get_viewport_rect()
	var p: Vector2 = (event as InputEventMouseMotion).position
	var at_edge := false
	match side:
		Side.LEFT:
			at_edge = p.x <= REVEAL_MARGIN
		Side.RIGHT:
			at_edge = p.x >= vp.size.x - REVEAL_MARGIN
		_:
			at_edge = p.y >= vp.size.y - REVEAL_MARGIN
	if at_edge:
		set_dock_state(State.RAILED)


# --- Persistence ----------------------------------------------------------

func _save_state() -> void:
	if persist_key == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(LAYOUT_PATH)  # missing file is fine; we are about to write one
	cfg.set_value(persist_key, "state", _state)
	cfg.set_value(persist_key, "size", expanded_size)
	cfg.save(LAYOUT_PATH)


func _load_state() -> void:
	if persist_key == "":
		return
	var cfg := ConfigFile.new()
	if cfg.load(LAYOUT_PATH) != OK:
		return
	_state = int(cfg.get_value(persist_key, "state", _state))
	expanded_size = float(cfg.get_value(persist_key, "size", expanded_size))
	# A dock restored as HIDDEN with auto_reveal off would be unreachable -
	# there is no visible affordance to bring it back. Clamp to RAILED.
	if _state == State.HIDDEN and not auto_reveal:
		_state = State.RAILED
