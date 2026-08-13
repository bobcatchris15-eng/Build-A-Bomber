class_name CommandCard
extends MarginContainer
# A positional command surface for the current selection.
#
# Each cell is data-driven: {action, label, icon}. The hotkey text on the cell
# and the binding in the tooltip are read from InputService.binding_label(action)
# at render time, so a rebind reflects on the card without a second source of
# truth. The card subscribes to InputService.bindings_changed to refresh.
#
# STAGE WIRING DEFERRAL. The Tactile Interface Programme Part 4, Phase 8
# intends the cells to be StampedButtons on a shared UIPropStage (Phase 1).
# Until that lands, plain Button controls are used here. The 3x3 geometry is
# the pre-CommandRegistry shape; Phase 8's commit chain restructures it to
# 3x4 = 12 cells (D6) sourced from CommandRegistry.
#
# WHY THIS REWRITE EXISTED. Before it, the labels were HARDCODED strings like
# "Attack Move (A)" and "Stop (S)" - the card claimed A and S were the keys
# while the camera owned them and the InputService canonical table put
# attack-move and stop on F and G (the X1 fix). The card was lying, and the
# lying was specifically the part a player could see. Reading the binding
# from InputService here is the only way that can never happen again: the
# card and the input table are the same source.

const Tokens = preload("res://scripts/ui_tokens.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")
const InputServiceScript = preload("res://scripts/core/input_service.gd")
const UIIconsScript = preload("res://scripts/ui_icons.gd")

# Pre-CommandRegistry hand-authored set. The 3x3 grid is sized for nine cells;
# only the five below are currently surfaced. Commit 2 replaces this with a
# CommandRegistry-backed, 3x4 = 12-cell set.
const _CELLS: Array = [
	{"action": "cmd_attack_move", "label": "Attack-move", "icon": "cmd_attack_move"},
	{"action": "cmd_stop", "label": "Stop", "icon": "cmd_stop"},
	{"action": "cmd_hold", "label": "Hold", "icon": "cmd_hold"},
	{"action": "cmd_stance_aggressive", "label": "Aggressive", "icon": "cmd_stance_aggressive"},
	{"action": "cmd_stance_return_fire", "label": "Return Fire", "icon": "cmd_stance_return_fire"},
]

var _grid: GridContainer
var _director: Node
var _input_service: Node = null
var _cells: Array = _CELLS


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := PanelContainer.new()
	panel.theme_type_variation = "HUDPanel"
	add_child(panel)

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", Tokens.SPACE_SM)
	_grid.add_theme_constant_override("v_separation", Tokens.SPACE_SM)
	panel.add_child(_grid)

	# Build one Button per cell up front. They are re-rendered in
	# _render_selection() so the same slot can host different actions across
	# selection profiles without the grid's child count changing.
	for i in range(_cells.size()):
		_grid.add_child(_build_cell(i))


func setup(director: Node) -> void:
	_director = director
	_input_service = get_node_or_null("/root/InputService")
	if _input_service != null:
		# Refresh the card on rebind so a player who moves a key sees the new
		# one on the card without restarting the match. Also wired in _ready
		# because setup() may be called before the autoload is present in
		# some test harnesses.
		_input_service.bindings_changed.connect(_refresh_bindings)
	_director.selection.selection_changed.connect(_on_selection_changed)
	_on_selection_changed(_director.selection.selected)


func _ready() -> void:
	# Reconnect if the autoload showed up after setup(). Also picks up bindings
	# saved on a previous launch (saved overrides emit on rebind, not on load,
	# so we render once unconditionally here).
	if _input_service == null:
		_input_service = get_node_or_null("/root/InputService")
		if _input_service != null and not _input_service.bindings_changed.is_connected(_refresh_bindings):
			_input_service.bindings_changed.connect(_refresh_bindings)
	for i in range(_cells.size()):
		UIFeedbackScript.wire(_grid.get_child(i) as Control)
	_refresh_bindings("")


func _build_cell(index: int) -> Control:
	# A VBox with the icon on top, the label, then the key. Plain Button
	# cannot hold a child + a text label cleanly, so this is a Control with a
	# real Button that does the click work.
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(64, 64)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", Tokens.SPACE_XS)
	cell.add_child(vbox)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vbox.add_child(icon)

	var label := Label.new()
	label.name = "Label"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", Tokens.FONT_MICRO)
	vbox.add_child(label)

	var key_label := Label.new()
	key_label.name = "Key"
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.add_theme_font_size_override("font_size", Tokens.FONT_MICRO)
	key_label.add_theme_color_override("font_color", Tokens.TEXT_SECONDARY)
	vbox.add_child(key_label)

	# The Button sits underneath the VBox and is what receives the click. The
	# VBox is mouse_filter=PASS so the click falls through.
	var button := Button.new()
	button.name = "Press"
	button.flat = true
	cell.add_child(button)
	cell.set_meta("button", button)
	cell.set_meta("vbox", vbox)
	return cell


func _on_selection_changed(_selected: Array) -> void:
	# Selection currently drives visibility but the cell set is fixed; the next
	# phase introduces CommandRegistry.entries_for_selection() to filter per
	# what the current selection can actually do.
	for child in _grid.get_children():
		child.visible = false
	for i in range(_cells.size()):
		var cell: Control = _grid.get_child(i) as Control
		cell.visible = true
		_apply_cell(cell, _cells[i])


func _refresh_bindings(_action: String) -> void:
	# Re-apply every cell so the key label and tooltip pick up the rebind.
	for i in range(_cells.size()):
		var cell: Control = _grid.get_child(i) as Control
		if cell.visible:
			_apply_cell(cell, _cells[i])


func _apply_cell(cell: Control, entry: Dictionary) -> void:
	var action: String = entry["action"]
	var label_text: String = entry["label"]
	var icon_name: String = entry.get("icon", "")

	var vbox: BoxContainer = cell.get_meta("vbox") as BoxContainer
	var label: Label = vbox.get_node("Label") as Label
	var key_label: Label = vbox.get_node("Key") as Label
	var icon: TextureRect = vbox.get_node("Icon") as TextureRect
	var button: Button = cell.get_meta("button") as Button

	label.text = label_text
	icon.texture = UIIconsScript.get_icon(icon_name) if icon_name != "" else null
	icon.visible = icon.texture != null

	var key_text: String = _binding_label_for(action)
	key_label.text = key_text
	button.tooltip_text = "%s (%s)" % [label_text, _binding_label_all_for(action)]

	# Re-wire pressed if the action changed (it cannot in this revision, but
	# the future CommandRegistry may swap entries by row/col).
	if button.pressed.is_connected(_on_btn_pressed):
		button.pressed.disconnect(_on_btn_pressed)
	button.pressed.connect(_on_btn_pressed.bind(action))


func _binding_label_for(action: String) -> String:
	if _input_service == null:
		return ""
	return _input_service.binding_label(action)


func _binding_label_all_for(action: String) -> String:
	if _input_service == null:
		return "Unbound"
	return _input_service.binding_label_all(action)


func _on_btn_pressed(action: String) -> void:
	# The match director already listens to these actions via InputMap; firing
	# an InputEventAction delivers it to the right place without each card
	# cell needing a callback into director state.
	var ev = InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
