class_name MarkingMenu
extends Control

# Transient stroke-driven marking menu (Phase 7, D9, D14).
# Fast strokes (< 200 ms, > 24 px) commit immediately with zero visual pop.
# Slow holds (>= 200 ms) reveal the ring dial with UIAnim.ring_pop.
# Releasing outside the hub commits the sector regardless of distance.

const RingDraw = preload("res://scripts/ui/ring_draw.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const UIAnim = preload("res://scripts/ui_anim.gd")

signal action_committed(action_id: String)
signal dismissed()

const REVEAL_DELAY_MS := 200
const MIN_STROKE_PX := 24.0
const HUB_RADIUS := 30.0
const RING_INNER := 44.0
const RING_OUTER := 92.0
const CANVAS_PAD := 56.0

var subject_label: String = ""

var _actions: Array = []  # [{id, label, icon, enabled}]
var _origin: Vector2 = Vector2.ZERO
var _current_pos: Vector2 = Vector2.ZERO
var _press_time_msec: int = 0
var _revealed: bool = false
var _hovered: int = -1
var _is_active: bool = false


func _init() -> void:
	var span := (RING_OUTER + CANVAS_PAD) * 2.0
	custom_minimum_size = Vector2(span, span)
	size = custom_minimum_size
	pivot_offset = custom_minimum_size * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func set_actions(actions: Array) -> void:
	_actions = actions
	queue_redraw()


func add_action(id: String, label: String, icon: String = "", enabled: bool = true) -> void:
	_actions.append({
		"id": id,
		"label": label.to_upper(),
		"icon": icon,
		"enabled": enabled,
	})
	queue_redraw()


func start_stroke(press_pos: Vector2, actions: Array = [], context_label: String = "") -> void:
	if not actions.is_empty():
		_actions = actions
	subject_label = context_label
	_origin = press_pos
	_current_pos = press_pos
	_press_time_msec = Time.get_ticks_msec()
	_revealed = false
	_hovered = -1
	_is_active = true
	visible = false


func update_stroke(curr_pos: Vector2) -> void:
	if not _is_active:
		return
	_current_pos = curr_pos

	var elapsed := Time.get_ticks_msec() - _press_time_msec
	if not _revealed and elapsed >= REVEAL_DELAY_MS:
		_revealed = true
		visible = true
		position = _origin - size * 0.5
		UIAnim.ring_pop(self)

	if _revealed:
		var prev := _hovered
		var offset := curr_pos - _origin
		if offset.length() < HUB_RADIUS:
			_hovered = -1
		else:
			_hovered = _sector_from_offset(offset)
		if _hovered != prev:
			queue_redraw()


func end_stroke(release_pos: Vector2) -> void:
	if not _is_active:
		return
	_is_active = false

	var offset := release_pos - _origin
	var dist := offset.length()

	if not _revealed:
		# Expert quick-flick path (< 200 ms)
		if dist >= MIN_STROKE_PX:
			var idx := _sector_from_offset(offset)
			_commit_sector(idx)
		else:
			dismissed.emit()
	else:
		# Revealed radial menu release
		if dist < HUB_RADIUS:
			# Hub release = dead zone cancel
			dismissed.emit()
		else:
			# Infinitely expanding sector release
			var idx := _sector_from_offset(offset)
			_commit_sector(idx)

	_close()


func _commit_sector(idx: int) -> void:
	if idx >= 0 and idx < _actions.size():
		var action: Dictionary = _actions[idx]
		if action.get("enabled", true):
			action_committed.emit(action["id"])
		else:
			dismissed.emit()
	else:
		dismissed.emit()


func _sector_from_offset(offset: Vector2) -> int:
	if _actions.is_empty():
		return -1
	var step := TAU / float(_actions.size())
	var angle := fposmod(atan2(offset.y, offset.x) + TAU * 0.25 + step * 0.5, TAU)
	return int(angle / step) % _actions.size()


func _close() -> void:
	_is_active = false
	if _revealed:
		var tween := create_tween()
		if tween:
			tween.tween_property(self, "scale", Vector2(0.6, 0.6), 0.1)
			tween.parallel().tween_property(self, "modulate:a", 0.0, 0.1)
			tween.tween_callback(queue_free)
		else:
			queue_free()
	else:
		queue_free()


func _draw() -> void:
	if not _revealed:
		return
	var font := get_theme_font("font", "Label")
	if font == null:
		font = ThemeDB.fallback_font
	RingDraw.draw_ring(
		self,
		size * 0.5,
		RING_INNER,
		RING_OUTER,
		HUB_RADIUS,
		_actions,
		_hovered,
		subject_label,
		font
	)
