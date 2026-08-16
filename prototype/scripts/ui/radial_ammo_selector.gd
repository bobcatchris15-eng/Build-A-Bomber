class_name RadialAmmoSelector
extends Control

# Dedicated radial selector for weapon ammo and locomotion presets (e.g. Leg Profiles) at 12 o'clock.

const Tokens = preload("res://scripts/ui_tokens.gd")

signal ammo_selected(ammo_id: String)
signal cycle_requested(direction: int)

var header_text: String = "LOADED AMMO"
var ammo_options: Array = []       # Array of type keys (e.g. ["standard", "ap", "he"] or ["stryker", "raptor", ...])
var ammo_profiles: Dictionary = {} # id -> {label, desc, ...}
var selected_index: int = 0:
	set(v):
		if ammo_options.is_empty():
			selected_index = 0
			return
		selected_index = clampi(v, 0, ammo_options.size() - 1)
		_update_display()
		queue_redraw()

var _is_hovered: bool = false
var _hovered_btn: String = "" # "prev", "next", "body", ""
var _font: Font = null


func _init() -> void:
	custom_minimum_size = Vector2(160.0, 52.0)
	size = custom_minimum_size
	pivot_offset = custom_minimum_size * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font


func _ready() -> void:
	mouse_entered.connect(func(): _is_hovered = true; queue_redraw())
	mouse_exited.connect(func(): _is_hovered = false; _hovered_btn = ""; queue_redraw())


func set_options(options: Array, current_id: String, catalog_script = null, p_header: String = "LOADED AMMO") -> void:
	ammo_options = options
	ammo_profiles.clear()
	header_text = p_header
	if catalog_script:
		# Header-gated profile lookup. Without these guards, ModuleCatalog's
		# get_leg_profile would catch drone keys (returning the stryker
		# default for "attack"/"scout"/"repair") and get_drone_profile would
		# catch leg keys. Each profile source is now matched to its own
		# header prefix, in priority order.
		var is_ammo := p_header.begins_with("LOADED") or p_header.begins_with("AMMO")
		var is_leg := p_header.begins_with("LEG")
		var is_drone := p_header.begins_with("DRONE")
		for opt in options:
			if is_drone and catalog_script.has_method("get_drone_profile"):
				ammo_profiles[opt] = catalog_script.get_drone_profile(opt)
			elif is_leg and catalog_script.has_method("get_leg_profile"):
				ammo_profiles[opt] = catalog_script.get_leg_profile(opt)
			elif is_ammo and catalog_script.has_method("get_ammo_profile"):
				ammo_profiles[opt] = catalog_script.get_ammo_profile(opt)

	selected_index = max(options.find(current_id), 0)


func get_current_ammo_id() -> String:
	if selected_index >= 0 and selected_index < ammo_options.size():
		return ammo_options[selected_index]
	return ""


func _update_display() -> void:
	var cur_id := get_current_ammo_id()
	var prof: Dictionary = ammo_profiles.get(cur_id, {})
	var desc: String = prof.get("desc", "")
	var lbl: String = prof.get("label", cur_id.to_upper())
	tooltip_text = "%s: %s\n%s" % [header_text, lbl, desc]


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var pos := (event as InputEventMouseMotion).position
		var old_btn := _hovered_btn
		if pos.x < 24.0:
			_hovered_btn = "prev"
		elif pos.x > size.x - 24.0:
			_hovered_btn = "next"
		else:
			_hovered_btn = "body"
		if old_btn != _hovered_btn:
			queue_redraw()
	
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _hovered_btn == "prev":
				_cycle(-1)
			elif _hovered_btn == "next" or _hovered_btn == "body":
				_cycle(1)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_cycle(-1)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle(-1)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle(1)
			accept_event()


func _cycle(dir: int) -> void:
	if ammo_options.size() <= 1:
		return
	var count := ammo_options.size()
	selected_index = (selected_index + dir + count) % count
	var picked := get_current_ammo_id()
	ammo_selected.emit(picked)


func _draw() -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	
	var r := Rect2(Vector2.ZERO, size)
	
	# 1. Background Panel
	var bg_col := Color(Tokens.BASE_900, 0.95) if not _is_hovered else Color(Tokens.BASE_800, 0.98)
	draw_rect(r, bg_col)
	var border_col := Tokens.SIGNAL_HAZARD if _is_hovered else Tokens.BASE_500
	draw_rect(r, border_col, false, 1.5)
	
	# 2. Header Tag (LOADED AMMO / LEG PROFILE)
	var hdr_sz := _font.get_string_size(header_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 8)
	var hdr_rect := Rect2(size.x * 0.5 - hdr_sz.x * 0.5 - 4.0, -5.0, hdr_sz.x + 8.0, 10.0)
	draw_rect(hdr_rect, Color(Tokens.BASE_900, 1.0))
	draw_rect(hdr_rect, Tokens.BASE_500, false, 1.0)
	draw_string(_font, Vector2(size.x * 0.5 - hdr_sz.x * 0.5, 3.0), header_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Tokens.TEXT_SECONDARY)
	
	# 3. Cycle Arrows (< and >)
	var arrow_prev_col := Tokens.SIGNAL_HAZARD if _hovered_btn == "prev" else Tokens.BASE_400
	var arrow_next_col := Tokens.SIGNAL_HAZARD if _hovered_btn == "next" else Tokens.BASE_400
	draw_string(_font, Vector2(8.0, 24.0), "<", HORIZONTAL_ALIGNMENT_CENTER, -1, Tokens.FONT_BODY, arrow_prev_col)
	draw_string(_font, Vector2(size.x - 16.0, 24.0), ">", HORIZONTAL_ALIGNMENT_CENTER, -1, Tokens.FONT_BODY, arrow_next_col)
	
	# 4. Current Selected Item Label
	var cur_id := get_current_ammo_id()
	var prof: Dictionary = ammo_profiles.get(cur_id, {})
	var item_lbl: String = prof.get("label", cur_id.to_upper())
	var lbl_sz := _font.get_string_size(item_lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, Tokens.FONT_SMALL)
	var lbl_col := Tokens.SIGNAL_HAZARD if (_is_hovered and _hovered_btn == "body") else Tokens.TEXT_PRIMARY
	draw_string(_font, Vector2(size.x * 0.5 - lbl_sz.x * 0.5, 23.0), item_lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, Tokens.FONT_SMALL, lbl_col)
	
	# 5. Short Description / Modifier
	var desc: String = prof.get("desc", "")
	if desc.length() > 34:
		desc = desc.substr(0, 31) + "..."
	var desc_sz := _font.get_string_size(desc, HORIZONTAL_ALIGNMENT_CENTER, -1, 9)
	draw_string(_font, Vector2(size.x * 0.5 - desc_sz.x * 0.5, 42.0), desc, HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Tokens.TEXT_SECONDARY)
