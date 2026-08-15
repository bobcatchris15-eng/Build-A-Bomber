class_name RadialDial
extends Control

# Tactile rotary dial / arc gauge control for Design Lab radial tweak stations.
# Supports Left-Click (bump up), Right-Click (bump down), Click & Hold (auto-repeat),
# drag scrubbing, and mouse wheel.

const Tokens = preload("res://scripts/ui_tokens.gd")

signal value_changed(val: float)
signal drag_started()
signal drag_ended(changed: bool)

const DIAL_RADIUS := 32.0
const ARC_START_ANGLE := PI * 0.75       # 135 degrees (bottom left)
const ARC_SWEEP := PI * 1.5              # 270 degrees sweep to bottom right
const GAUGE_WIDTH := 4.5
const BEZEL_WIDTH := 1.5

const REPEAT_INITIAL_DELAY := 0.35       # seconds before auto-repeat begins
const REPEAT_INTERVAL := 0.08            # interval between repeat ticks

var param_name: String = ""
var label_text: String = ""
var min_value: float = 0.5
var max_value: float = 2.0
var step: float = 0.1
var default_value: float = 1.0
var value: float = 1.0:
	set(v):
		var clamped := clampf(v, min_value, max_value)
		if step > 0.0:
			clamped = snappedf(clamped, step)
		if not is_equal_approx(value, clamped):
			value = clamped
			_update_readout()
			queue_redraw()

var is_integer: bool = false
var unit_suffix: String = "x"

var _is_dragging: bool = false
var _drag_start_global_pos: Vector2 = Vector2.ZERO
var _drag_start_val: float = 1.0
var _dragged_distance: float = 0.0

var _hold_dir: int = 0                   # +1 for LMB (up), -1 for RMB (down), 0 = idle
var _hold_time: float = 0.0
var _last_repeat_time: float = 0.0

var _is_hovered: bool = false
var _font: Font = null


func _init(p_name: String = "", p_label: String = "", p_min: float = 0.5, p_max: float = 2.0, p_step: float = 0.1, p_default: float = 1.0) -> void:
	param_name = p_name
	label_text = p_label.to_upper()
	min_value = p_min
	max_value = p_max
	step = p_step
	default_value = p_default
	value = p_default
	is_integer = (step == 1.0)
	if is_integer:
		unit_suffix = ""
	
	custom_minimum_size = Vector2(DIAL_RADIUS * 2.0 + 8.0, DIAL_RADIUS * 2.0 + 8.0)
	size = custom_minimum_size
	pivot_offset = custom_minimum_size * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	_update_readout()


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _on_mouse_entered() -> void:
	_is_hovered = true
	queue_redraw()


func _on_mouse_exited() -> void:
	_is_hovered = false
	queue_redraw()


func _process(delta: float) -> void:
	if _hold_dir != 0:
		_hold_time += delta
		if _hold_time >= REPEAT_INITIAL_DELAY:
			var time_since_repeat := _hold_time - _last_repeat_time
			if time_since_repeat >= REPEAT_INTERVAL:
				_last_repeat_time = _hold_time
				_step_value(_hold_dir)


func _step_value(direction: int) -> void:
	var delta_val := step if step > 0.0 else (max_value - min_value) * 0.05
	if Input.is_key_pressed(KEY_SHIFT) and not is_integer:
		delta_val *= 0.2
	_set_value_from_input(value + delta_val * float(direction))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_dragging = true
				_drag_start_global_pos = mb.global_position
				_drag_start_val = value
				_dragged_distance = 0.0
				_hold_dir = 1
				_hold_time = 0.0
				_last_repeat_time = 0.0
				drag_started.emit()
				_step_value(1)
				accept_event()
			else:
				if _hold_dir == 1 or _is_dragging:
					_hold_dir = 0
					_is_dragging = false
					var changed := not is_equal_approx(value, _drag_start_val)
					drag_ended.emit(changed)
					accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_is_dragging = true
				_drag_start_global_pos = mb.global_position
				_drag_start_val = value
				_dragged_distance = 0.0
				_hold_dir = -1
				_hold_time = 0.0
				_last_repeat_time = 0.0
				drag_started.emit()
				_step_value(-1)
				accept_event()
			else:
				if _hold_dir == -1 or _is_dragging:
					_hold_dir = 0
					_is_dragging = false
					var changed := not is_equal_approx(value, _drag_start_val)
					drag_ended.emit(changed)
					accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			drag_started.emit()
			_step_value(1)
			drag_ended.emit(true)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			drag_started.emit()
			_step_value(-1)
			drag_ended.emit(true)
			accept_event()
	
	elif event is InputEventMouseMotion and _is_dragging:
		var mm := event as InputEventMouseMotion
		var delta_x := mm.global_position.x - _drag_start_global_pos.x
		var delta_y := _drag_start_global_pos.y - mm.global_position.y # up is positive
		_dragged_distance += mm.relative.length()
		# If user moves mouse significantly (> 8px), disable hold repeat and use continuous scrub
		if _dragged_distance > 8.0:
			_hold_dir = 0
			var span := max_value - min_value
			var scrub := (delta_x + delta_y) / 140.0
			if Input.is_key_pressed(KEY_SHIFT) and not is_integer:
				scrub *= 0.2 # 1/5th precision
			var target := _drag_start_val + scrub * span
			_set_value_from_input(target)
		accept_event()


func _set_value_from_input(new_val: float) -> void:
	var old_val := value
	value = new_val
	if not is_equal_approx(value, old_val):
		value_changed.emit(value)


func _update_readout() -> void:
	if is_integer:
		tooltip_text = "%s: %d\n[LMB] +1 | [RMB] -1 | Hold to repeat" % [label_text, int(value)]
	else:
		tooltip_text = "%s: %.2f%s\n[LMB] Step Up | [RMB] Step Down | Hold to repeat" % [label_text, value, unit_suffix]


func _draw() -> void:
	var center := size * 0.5
	var r := DIAL_RADIUS
	
	# 1. Bezel outer casing & body
	var body_color := Color(Tokens.BASE_900, 0.95) if not _is_hovered else Color(Tokens.BASE_800, 0.98)
	draw_circle(center, r, body_color)
	var rim_color := Tokens.SIGNAL_HAZARD if (_is_hovered or _is_dragging) else Tokens.BASE_500
	draw_arc(center, r, 0.0, TAU, 48, rim_color, BEZEL_WIDTH, true)
	
	# 2. Track Background Arc
	var track_r := r - 6.0
	draw_arc(center, track_r, ARC_START_ANGLE, ARC_START_ANGLE + ARC_SWEEP, 36, Color(Tokens.BASE_700, 0.7), GAUGE_WIDTH, true)
	
	# 3. Active Fill Arc
	var frac := 0.0
	if max_value > min_value:
		frac = clampf((value - min_value) / (max_value - min_value), 0.0, 1.0)
	
	if frac > 0.001:
		var fill_sweep := ARC_SWEEP * frac
		var active_color := Tokens.SIGNAL_HAZARD if (_is_hovered or _is_dragging) else Color(Tokens.SIGNAL_HAZARD, 0.85)
		draw_arc(center, track_r, ARC_START_ANGLE, ARC_START_ANGLE + fill_sweep, 36, active_color, GAUGE_WIDTH, true)
		
		# Needle / Indicator Pip at tip
		var tip_angle := ARC_START_ANGLE + fill_sweep
		var tip_pos := center + Vector2(cos(tip_angle), sin(tip_angle)) * track_r
		draw_circle(tip_pos, GAUGE_WIDTH * 0.75, Tokens.TEXT_PRIMARY)
	
	# 4. Detent Ticks for Discrete Integer Steps
	if is_integer and (max_value - min_value) <= 10:
		var steps_count := int(max_value - min_value)
		for i in range(steps_count + 1):
			var step_frac := float(i) / float(steps_count)
			var tick_angle := ARC_START_ANGLE + ARC_SWEEP * step_frac
			var p1 := center + Vector2(cos(tick_angle), sin(tick_angle)) * (track_r - 4.0)
			var p2 := center + Vector2(cos(tick_angle), sin(tick_angle)) * (track_r + 4.0)
			var tick_col := Tokens.BASE_400 if i <= int(value - min_value) else Tokens.BASE_600
			draw_line(p1, p2, tick_col, 1.0, true)
	
	# 5. Inner Core / Readout Hub
	var core_r := r - 13.0
	draw_circle(center, core_r, Color(Tokens.BASE_900, 0.75))
	draw_arc(center, core_r, 0.0, TAU, 32, Tokens.BASE_700, 1.0, true)
	
	# 6. Central Numerical Value
	if _font == null:
		_font = ThemeDB.fallback_font
	
	var val_str := ""
	if is_integer:
		val_str = "%d" % int(value)
	else:
		val_str = "%.2f%s" % [value, unit_suffix] if value < 10.0 else "%.1f%s" % [value, unit_suffix]
	
	var val_sz := _font.get_string_size(val_str, HORIZONTAL_ALIGNMENT_CENTER, -1, Tokens.FONT_SMALL)
	var val_col := Tokens.SIGNAL_HAZARD if (_is_hovered or _is_dragging) else Tokens.TEXT_PRIMARY
	draw_string(_font, center + Vector2(-val_sz.x * 0.5, val_sz.y * 0.2), val_str, HORIZONTAL_ALIGNMENT_CENTER, -1, Tokens.FONT_SMALL, val_col)
	
	# 7. Bottom Label (Caption)
	var lbl_sz := _font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 9)
	var lbl_col := Tokens.TEXT_SECONDARY if not _is_hovered else Tokens.TEXT_PRIMARY
	var badge_rect := Rect2(center.x - lbl_sz.x * 0.5 - 4.0, center.y + r + 2.0, lbl_sz.x + 8.0, lbl_sz.y + 4.0)
	draw_rect(badge_rect, Color(Tokens.BASE_900, 0.9))
	draw_rect(badge_rect, Tokens.BASE_600, false, 1.0)
	draw_string(_font, Vector2(center.x - lbl_sz.x * 0.5, center.y + r + 2.0 + lbl_sz.y * 0.8), label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 9, lbl_col)
