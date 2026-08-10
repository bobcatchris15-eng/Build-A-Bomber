class_name AdminMenu
extends Control
# The administrative toolbox: pause and the ways out of a match.
#
# Sits under the minimap on the right, in the same chamfered-plate language as
# the production toolboxes along the bottom, so the two read as the same kind of
# object - one is what you build with, one is what you do to the session.
#
# OPENING IT PAUSES. That is the normal contract for a menu in a real-time game
# and the reason to have it at all: the alternative is a player reading a list of
# options while their base is under attack. Closing it resumes, and so does
# Escape - the same key that already backs out of placement and selection.
#
# PAUSING IS get_tree().paused, WHICH STOPS THIS NODE TOO unless it opts out.
# Both this menu and SceneRouter's fade overlay run with PROCESS_MODE_ALWAYS,
# because a pause menu that freezes itself cannot be dismissed and a transition
# started from one would hang halfway through its fade.
#
# SAVE AND LOAD ARE PRESENT AND DISABLED. There is no save system in this project
# - not in the battle layer, not in the old runtime, nowhere - so there is
# nothing for them to call. They are shown greyed with a reason rather than
# omitted, because "can I save?" is a question the player will ask on their own
# and an empty menu answers it worse than a disabled row does. Wiring them to
# something that silently did nothing, or that wrote a file that could not be
# loaded, would be worse than either.

const Tokens = preload("res://scripts/ui_tokens.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")
const ToolboxPlateScript = preload("res://scripts/ui_toolbox_plate.gd")
const StampedLabelScript = preload("res://scripts/ui_stamped_label.gd")

signal main_menu_requested
signal quit_requested

const WIDTH := 200.0
const PLATE_PADDING := 10.0
const CONTENT_WIDTH := WIDTH - PLATE_PADDING * 2.0
const HEADER_HEIGHT := 40.0
const HEADER_FONT_SIZE := 17
# Clears the minimap. BattleHUD puts it at TOP_STRIP_HEIGHT + 8 with a 180px
# side, and this hangs below it with a gap.
const TOP_OFFSET := 64.0 + 180.0 + 20.0

var _plate: Control = null
var _slot: VBoxContainer = null
var _body: VBoxContainer = null
var _header: Button = null
var _panel: Control = null
var _open: bool = false


func _ready() -> void:
	# Runs while paused, or the menu that caused the pause freezes with it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fit_to_viewport()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(fit_to_viewport):
		vp.size_changed.connect(fit_to_viewport)
	_build()


# Same hand-sizing as the other HUD layers, for the same reason: a Control
# parented to a CanvasLayer has no parent rect for its anchors to resolve
# against, so it stays at size (0,0) and everything in it collapses onto the
# origin.
func fit_to_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	position = Vector2.ZERO
	size = vp.get_visible_rect().size
	_layout()


func _build() -> void:
	_plate = ToolboxPlateScript.new()
	add_child(_plate)

	_slot = VBoxContainer.new()
	_slot.custom_minimum_size = Vector2(CONTENT_WIDTH, 0)
	_slot.add_theme_constant_override("separation", 0)
	_slot.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_slot)

	_header = Button.new()
	_header.toggle_mode = true
	_header.focus_mode = Control.FOCUS_NONE
	_header.custom_minimum_size = Vector2(0, HEADER_HEIGHT)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		_header.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_slot.add_child(_header)
	UIFeedbackScript.wire(_header, "select")

	var stamp: Control = StampedLabelScript.new()
	stamp.text = "MENU"
	stamp.font_size = HEADER_FONT_SIZE
	stamp.set_anchors_preset(Control.PRESET_FULL_RECT)
	_header.add_child(stamp)
	_header.toggled.connect(_set_open)

	var panel := PanelContainer.new()
	panel.visible = false
	var well := StyleBoxFlat.new()
	well.bg_color = Tokens.BASE_900
	well.border_color = Tokens.BASE_500
	well.set_border_width_all(Tokens.BORDER_HAIRLINE)
	well.set_content_margin_all(Tokens.SPACE_XS)
	panel.add_theme_stylebox_override("panel", well)
	_slot.add_child(panel)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", Tokens.SPACE_XS)
	panel.add_child(_body)

	_add_action("RESUME", _close)
	# The two that have nothing to call. The reason rides on the tooltip AND the
	# label, because a disabled button with no explanation reads as a bug.
	_add_disabled("SAVE - UNAVAILABLE", "No save system exists in this build.")
	_add_disabled("LOAD - UNAVAILABLE", "No save system exists in this build.")
	_add_action("ABANDON - MAIN MENU", func(): _leave(main_menu_requested))
	_add_action("EXIT TO DESKTOP", func(): _leave(quit_requested))

	_panel = panel
	_layout()


func _add_action(label: String, action: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 34)
	_body.add_child(btn)
	UIFeedbackScript.wire(btn)
	btn.pressed.connect(action)


func _add_disabled(label: String, why: String) -> void:
	var btn := Button.new()
	btn.text = label
	btn.disabled = true
	btn.tooltip_text = why
	btn.custom_minimum_size = Vector2(0, 34)
	_body.add_child(btn)


func _set_open(open: bool) -> void:
	_open = open
	_panel.visible = open
	# The pause itself. Set here rather than in the caller so every route into
	# the menu - header click, Escape, a future hotkey - pauses identically.
	get_tree().paused = open
	_layout()


func _close() -> void:
	_header.set_pressed_no_signal(false)
	_set_open(false)


func is_open() -> bool:
	return _open


# Toggles from outside, so Escape can reach it.
func toggle() -> void:
	_header.set_pressed_no_signal(not _open)
	_set_open(not _open)


# Unpauses BEFORE handing off. A scene change made under get_tree().paused
# leaves the incoming scene paused too - the tree flag outlives the scene that
# set it - so the next screen would arrive frozen.
func _leave(what: Signal) -> void:
	get_tree().paused = false
	what.emit()


func _layout() -> void:
	if _slot == null:
		return
	_slot.size = Vector2(CONTENT_WIDTH, _slot.get_combined_minimum_size().y)
	_slot.position = Vector2(
		size.x - WIDTH - float(Tokens.SPACE_MD) + PLATE_PADDING, TOP_OFFSET)
	_plate.position = _slot.position - Vector2(PLATE_PADDING, PLATE_PADDING)
	_plate.size = _slot.size + Vector2(PLATE_PADDING, PLATE_PADDING) * 2.0
	_plate.queue_redraw()
