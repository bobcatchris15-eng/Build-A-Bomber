class_name ProductionTabBar
extends Control
# Five production queue tabs above the desk bar.
# Always visible headers; click toggles ProductionDrawer for that tier.

const Tokens = preload("res://scripts/ui_tokens.gd")
const BuildingCatalog = preload("res://scripts/battle/economy/building_catalog.gd")
const AluminumTrim = preload("res://scripts/ui/aluminum_trim.gd")
const UIFeedback = preload("res://scripts/ui_feedback.gd")

const QUEUE_LABELS = {
	"light": "LIGHT",
	"medium": "MEDIUM",
	"heavy": "HEAVY",
	"building": "STRUCTURES",
	"defense": "DEFENCES",
}

signal tab_toggled(queue_name: String, open: bool)

var _director: Node = null
var _tab_buttons: Dictionary = {}
var _badges: Dictionary = {}
var _last_hovered: String = "light"

func _init() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	custom_minimum_size = Vector2(0, 36)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

func setup(director: Node) -> void:
	_director = director
	refresh_all_badges()

func _build() -> void:
	theme_type_variation = "HUDPanel"
	AluminumTrim.apply(self, {"brightness": 1.0})

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(row)

	for queue_name in BuildingCatalog.QUEUES:
		var btn := Button.new()
		btn.name = "Tab_%s" % queue_name
		btn.text = QUEUE_LABELS[queue_name]
		btn.theme_type_variation = "DrawerTab"
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 36)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIFeedback.wire(btn, "select")
		btn.toggled.connect(_on_tab_toggled.bind(queue_name))
		btn.mouse_entered.connect(_on_tab_mouse_entered.bind(queue_name))
		row.add_child(btn)

		var badge := Label.new()
		badge.name = "Badge"
		badge.add_theme_font_override("font", preload("res://assets/fonts/MonoFont-Regular.ttf"))
		badge.add_theme_font_size_override("font_size", Tokens.FONT_MICRO)
		badge.add_theme_color_override("font_color", Tokens.PHOSPHOR_AMBER)
		badge.text = ""
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_right = -4
		badge.offset_top = 2
		btn.add_child(badge)

		_tab_buttons[queue_name] = btn
		_badges[queue_name] = badge

func _on_tab_toggled(pressed: bool, queue_name: String) -> void:
	tab_toggled.emit(queue_name, pressed)

func refresh_badge(queue_name: String) -> void:
	if not _director or not _badges.has(queue_name):
		return
	var production = _director.production
	if production == null:
		return
	var status = production.status(_director.PLAYER_TEAM, queue_name)
	var depth = status.get("depth", 0)
	var badge = _badges[queue_name]
	if depth > 0:
		badge.text = str(depth)
		badge.visible = true
	else:
		badge.visible = false

func refresh_all_badges() -> void:
	for queue_name in BuildingCatalog.QUEUES:
		refresh_badge(queue_name)

func set_tab_pressed(queue_name: String, pressed: bool) -> void:
	if _tab_buttons.has(queue_name):
		_tab_buttons[queue_name].set_pressed_no_signal(pressed)

func _on_tab_mouse_entered(queue_name: String) -> void:
	_last_hovered = queue_name

func toggle_last_hovered() -> void:
	if _tab_buttons.has(_last_hovered):
		var btn = _tab_buttons[_last_hovered]
		btn.set_pressed_no_signal(not btn.button_pressed)
		tab_toggled.emit(_last_hovered, btn.button_pressed)