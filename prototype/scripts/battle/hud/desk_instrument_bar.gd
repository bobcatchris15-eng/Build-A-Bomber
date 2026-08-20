class_name DeskInstrumentBar
extends Control
# Bottom 48px persistent instrument bar.
# Bakelite panel with amber CRT readouts for resources, power, clock + alert stack.

const Tokens = preload("res://scripts/ui_tokens.gd")
const CRTReadoutScript = preload("res://scripts/ui/crt_readout.gd")
const BakelitePanel = preload("res://scripts/ui/bakelite_panel.gd")
const UIFeedback = preload("res://scripts/ui_feedback.gd")

signal alert_clicked(category: String)

var _director: Node = null
var _local_team: int = 0

var _resources_crt: CRTReadout = null
var _power_crt: CRTReadout = null
var _power_bar: ProgressBar = null
var _power_label: Label = null
var _clock_crt: CRTReadout = null
var _alert_stack: HBoxContainer = null

# 5 Hz refresh throttle
const REFRESH_INTERVAL := 0.2
var _refresh_acc: float = 0.0

func _init() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	custom_minimum_size = Vector2(0, 48)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

func setup(director: Node, local_team: int) -> void:
	_director = director
	_local_team = local_team
	_refresh_resources()

func _build() -> void:
	# Bakelite panel background
	theme_type_variation = "HUDPanel"
	BakelitePanel.apply(self, {"brightness": 0.75})

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.SPACE_LG)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = Tokens.SPACE_MD
	row.offset_right = -Tokens.SPACE_MD
	row.offset_top = Tokens.SPACE_XS
	row.offset_bottom = -Tokens.SPACE_XS
	add_child(row)

	# Resources CRT (left group)
	_resources_crt = CRTReadoutScript.new()
	_resources_crt.tube_color = "amber"
	_resources_crt.font_size = 14
	_resources_crt.custom_minimum_size = Vector2(200, 32)
	_resources_crt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(_resources_crt)

	# Power CRT + bar (left group)
	var power_container := HBoxContainer.new()
	power_container.add_theme_constant_override("separation", Tokens.SPACE_SM)
	power_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(power_container)

	_power_label = Label.new()
	_power_label.add_theme_font_override("font", preload("res://assets/fonts/MonoFont-Regular.ttf"))
	_power_label.add_theme_font_size_override("font_size", 12)
	_power_label.add_theme_color_override("font_color", Tokens.PHOSPHOR_AMBER)
	_power_label.text = "POWER"
	_power_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	power_container.add_child(_power_label)

	_power_crt = CRTReadoutScript.new()
	_power_crt.tube_color = "amber"
	_power_crt.font_size = 14
	_power_crt.custom_minimum_size = Vector2(80, 24)
	_power_crt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	power_container.add_child(_power_crt)

	_power_bar = ProgressBar.new()
	_power_bar.custom_minimum_size = Vector2(160, 10)
	_power_bar.show_percentage = false
	_power_bar.max_value = 1.0
	_power_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Amber→red fill via theme override
	var fill := StyleBoxFlat.new()
	fill.bg_color = Tokens.PHOSPHOR_AMBER
	_power_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Tokens.PHOSPHOR_AMBER_DIM
	_power_bar.add_theme_stylebox_override("background", bg)
	power_container.add_child(_power_bar)

	# Spacer to push clock + alerts right
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	# Mission Clock (green CRT)
	_clock_crt = CRTReadoutScript.new()
	_clock_crt.tube_color = "green"
	_clock_crt.font_size = 14
	_clock_crt.custom_minimum_size = Vector2(140, 32)
	_clock_crt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(_clock_crt)

	# Alert Stack (4 icon buttons)
	_alert_stack = HBoxContainer.new()
	_alert_stack.add_theme_constant_override("separation", Tokens.SPACE_SM)
	_alert_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_alert_stack)

	var alert_defs := [
		{"id": "contact", "icon": "ui_radar", "tooltip": "Enemy Contact"},
		{"id": "ready", "icon": "ui_hammer", "tooltip": "Structure Ready"},
		{"id": "power", "icon": "ui_bolt", "tooltip": "Low Power"},
		{"id": "intel", "icon": "ui_paper", "tooltip": "Intel Update"},
	]

	for def in alert_defs:
		var btn := Button.new()
		btn.name = "Alert_%s" % def.id
		btn.custom_minimum_size = Vector2(28, 28)
		btn.focus_mode = Control.FOCUS_NONE
		btn.tooltip_text = def.tooltip
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		# Icon will be set via theme variation
		btn.theme_type_variation = "AlertIcon"
		UIFeedback.wire(btn, "select")
		btn.pressed.connect(_on_alert_pressed.bind(def.id))
		_alert_stack.add_child(btn)

	# Initial clock
	_update_clock()

func _process(delta: float) -> void:
	_refresh_acc += delta
	if _refresh_acc >= REFRESH_INTERVAL:
		_refresh_acc = 0.0
		_refresh_resources()
		_update_clock()

func _refresh_resources() -> void:
	if _director == null:
		return
	var economy = _director.economy
	if economy == null:
		return

	var credits: int = economy.credits(_local_team)
	var income: float = economy.income_rate(_local_team)
	_resources_crt.set_text("%d cr  +%.0f/s" % [credits, income])

	var capacity: float = economy.power_capacity(_local_team)
	var draw: float = economy.power_draw(_local_team)
	var ratio: float = 0.0 if capacity <= 0.0 else clampf(draw / capacity, 0.0, 1.0)
	_power_bar.value = ratio

	if economy.is_low_power(_local_team):
		_power_label.add_theme_color_override("font_color", Tokens.SIGNAL_ALERT)
		_power_crt.set_tube_color("amber")  # Switch to amber for warning
		_power_bar.get_theme_stylebox("fill").bg_color = Tokens.SIGNAL_ALERT
	else:
		_power_label.add_theme_color_override("font_color", Tokens.PHOSPHOR_AMBER)
		_power_crt.set_tube_color("amber")
		_power_bar.get_theme_stylebox("fill").bg_color = Tokens.PHOSPHOR_AMBER

	_power_crt.set_text("%d%%" % int(ratio * 100))

func _update_clock() -> void:
	if _director == null:
		return
	var match = _director.match_state if "match_state" in _director else null
	var elapsed: float = 0.0
	var limit: float = 0.0
	if match != null:
		elapsed = match.get_elapsed_time() if match.has_method("get_elapsed_time") else 0.0
		limit = match.get_time_limit() if match.has_method("get_time_limit") else 0.0
	else:
		# Fallback: use OS time since match start
		elapsed = Time.get_unix_time_from_system() - (_director.match_start_time if "match_start_time" in _director else Time.get_unix_time_from_system())
		limit = _director.match_time_limit if "match_time_limit" in _director else 2700.0  # 45 min default

	var elapsed_str := _format_time(elapsed)
	var limit_str := _format_time(limit)
	_clock_crt.set_text("%s / %s" % [elapsed_str, limit_str])

func _format_time(seconds: float) -> String:
	var m := int(seconds / 60)
	var s := int(seconds) % 60
	return "%02d:%02d" % [m, s]

func _on_alert_pressed(category: String) -> void:
	alert_clicked.emit(category)

# Public API for IntelFeed to flash alerts
func flash_alert(category: String) -> void:
	var btn = _alert_stack.find_child("Alert_%s" % category)
	if btn != null and btn is Button:
		# Visual flash via modulation pulse
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(btn, "modulate:a", 0.3, 0.1)
		tween.tween_property(btn, "modulate:a", 1.0, 0.1)
		tween.set_loops(3)
