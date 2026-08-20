class_name TeletypeLog
extends ScrollContainer
# Scrolling paper-tape teletype log with character-by-character print animation.

const Tokens = preload("res://scripts/ui_tokens.gd")

var _vbox: VBoxContainer = null
var _print_timer: Timer = null
var _pending_lines: Array = []
var _current_line: Label = null
var _current_text: String = ""
var _char_index: int = 0

const MAX_LINES := 200
const PRINT_SPEED := 0.02  # seconds per character

func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()

func _build() -> void:
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 2)
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_vbox)

	_print_timer = Timer.new()
	_print_timer.wait_time = PRINT_SPEED
	_print_timer.one_shot = true
	_print_timer.timeout.connect(_print_next_char)
	add_child(_print_timer)

func add_entry(timestamp: String, icon: String, message: String, color: Color) -> void:
	# Remove oldest if at max
	while _vbox.get_child_count() >= MAX_LINES:
		_vbox.get_child(0).queue_free()

	var line = Label.new()
	line.add_theme_font_override("font", preload("res://assets/fonts/MonoFont-Regular.ttf"))
	line.add_theme_font_size_override("font_size", Tokens.FONT_MICRO)
	line.add_theme_color_override("font_color", color)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.text = ""
	_vbox.add_child(line)

	var full_text = "[%s] %s %s" % [timestamp, icon, message]
	_pending_lines.append({
		"label": line,
		"text": full_text,
		"index": 0,
	})

	if not _print_timer.time_left > 0.0:
		_start_next_line()

func _start_next_line() -> void:
	if _pending_lines.is_empty():
		return
	_current_line = _pending_lines[0]["label"]
	_current_text = _pending_lines[0]["text"]
	_char_index = 0
	_print_timer.start()

func _print_next_char() -> void:
	if _char_index >= _current_text.length():
		_pending_lines.pop_front()
		if not _pending_lines.is_empty():
			_start_next_line()
		else:
			_current_line = null
			_current_text = ""
		# Auto-scroll to bottom
		call_deferred("_scroll_to_bottom")
		return

	_current_line.text += _current_text[_char_index]
	_char_index += 1
	_print_timer.start()

func _scroll_to_bottom() -> void:
	scroll_vertical = get_v_scroll_bar().max_value