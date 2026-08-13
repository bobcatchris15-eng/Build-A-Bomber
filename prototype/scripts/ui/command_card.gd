class_name CommandCard
extends MarginContainer
# A positional command surface for the current selection.
#
# Each cell is data-driven from CommandRegistry (3x4 = 12 cells, D6).
# The hotkey text on the cell and the binding in the tooltip are read
# from InputService.binding_label(action) at render time, so a rebind
# reflects on the card without a second source of truth. The card
# subscribes to InputService.bindings_changed to refresh.
#
# STAGE WIRING DEFERRAL. The Tactile Interface Programme Part 4, Phase 8
# intends the cells to be StampedButtons on a shared UIPropStage (Phase 1).
# Until that lands, plain Button controls are used here. The header on
# this file from the 3x3 rewrite had this note; it remains true at 3x4.
#
# WHY THIS REWRITE EXISTED. Before it, the labels were HARDCODED strings
# like "Attack Move (A)" and "Stop (S)" - the card claimed A and S were
# the keys while the camera owned them and the InputService canonical
# table put attack-move and stop on F and G (the X1 fix). The card was
# lying, and the lying was specifically the part a player could see.
# Reading the binding from InputService here is the only way that can
# never happen again: the card and the input table are the same source.

const Tokens = preload("res://scripts/ui_tokens.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")
const InputServiceScript = preload("res://scripts/core/input_service.gd")
const UIIconsScript = preload("res://scripts/ui_icons.gd")
const CommandRegistryScript = preload("res://scripts/battle/orders/command_registry.gd")

var _grid: GridContainer
var _director: Node
var _input_service: Node = null
var _registry: CommandRegistryScript = null
var _cells: Array[Dictionary] = []  # one entry per grid child, in physical order


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := PanelContainer.new()
	panel.theme_type_variation = "HUDPanel"
	add_child(panel)

	_grid = GridContainer.new()
	_grid.columns = CommandRegistryScript.COLUMNS
	_grid.add_theme_constant_override("h_separation", Tokens.SPACE_SM)
	_grid.add_theme_constant_override("v_separation", Tokens.SPACE_SM)
	panel.add_child(_grid)

	# Build the full 3x4 cell set up front. Row 3 cells with action="" in
	# the registry are rendered as disabled placeholders rather than gaps,
	# because positional binding only pays off when the cell for a command
	# is the same cell every time.
	var positions: Array = CommandRegistryScript.all_positions()
	for _pos in positions:
		_grid.add_child(_build_cell())


func setup(director: Node) -> void:
	_director = director
	_input_service = get_node_or_null("/root/InputService")
	_registry = get_node_or_null("/root/CommandRegistry")
	if _input_service == null:
		_input_service = _resolve_input_service()
	if _registry == null:
		_registry = _resolve_registry()
	if _input_service != null and not _input_service.bindings_changed.is_connected(_refresh_bindings):
		_input_service.bindings_changed.connect(_refresh_bindings)
	if _registry != null and not _registry.registry_changed.is_connected(_refresh_registry):
		_registry.registry_changed.connect(_refresh_registry)
	_director.selection.selection_changed.connect(_on_selection_changed)
	_on_selection_changed(_director.selection.selected)


func _ready() -> void:
	# Reconnect if the autoloads showed up after setup(). Also picks up
	# bindings saved on a previous launch (saved overrides emit on rebind,
	# not on load, so we render once unconditionally here).
	if _input_service == null:
		_input_service = _resolve_input_service()
		if _input_service != null and not _input_service.bindings_changed.is_connected(_refresh_bindings):
			_input_service.bindings_changed.connect(_refresh_bindings)
	if _registry == null:
		_registry = _resolve_registry()
		if _registry != null and not _registry.registry_changed.is_connected(_refresh_registry):
			_registry.registry_changed.connect(_refresh_registry)
	for child in _grid.get_children():
		UIFeedbackScript.wire(child as Control)
	_refresh_bindings("")


# The two services we depend on. In a normal game they are autoloads; in
# tests they may not be, in which case we instantiate them locally and
# hold them for the lifetime of this card. The local instances are
# discarded on free() — they are not singletons.
func _resolve_input_service() -> Node:
	var svc := get_node_or_null("/root/InputService")
	if svc != null:
		return svc
	var s = InputServiceScript.new()
	add_child(s)
	return s


func _resolve_registry() -> Node:
	var r := get_node_or_null("/root/CommandRegistry")
	if r != null:
		return r
	var reg = CommandRegistryScript.new()
	add_child(reg)
	return reg


func _build_cell() -> Control:
	# A VBox with the icon on top, the label, then the key. Plain Button
	# cannot hold a child + a text label cleanly, so this is a PanelContainer
	# with a real Button that does the click work sitting on top.
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

	# The Button sits on top and is what receives the click. The VBox is
	# mouse_filter=PASS so the click falls through.
	var button := Button.new()
	button.name = "Press"
	button.flat = true
	cell.add_child(button)
	cell.set_meta("button", button)
	cell.set_meta("vbox", vbox)
	return cell


func _on_selection_changed(_selected: Array) -> void:
	_refresh_cells()


func _refresh_bindings(_action: String) -> void:
	_refresh_cells()


func _refresh_registry() -> void:
	_refresh_cells()


func _refresh_cells() -> void:
	if _registry == null:
		# No registry yet: render all cells disabled with no label. A card
		# that does not know its own layout would be worse than an empty
		# one, so this only happens during the brief setup window before
		# the autoload is wired in production.
		_cells = []
		for child in _grid.get_children():
			(child as Control).visible = false
		return
	var entries: Array = _registry.entries_for_selection(_director.selection.selected if _director != null else [])
	# entries() is already in (row, col) order. Build a map from the grid
	# child's own (row, col) metadata back to the entry.
	var by_position: Dictionary = {}
	for e in entries:
		by_position[Vector2i(int(e["row"]), int(e["col"]))] = e
	var positions: Array = CommandRegistryScript.all_positions()
	_cells = []
	for i in range(positions.size()):
		var pos: Vector2i = positions[i]
		var cell: Control = _grid.get_child(i) as Control
		cell.visible = true
		var entry: Dictionary = by_position.get(pos, {"row": pos.x, "col": pos.y, "enabled": false, "action": "", "label": "", "icon": ""})
		_cells.append(entry)
		_apply_cell(cell, entry)


func _apply_cell(cell: Control, entry: Dictionary) -> void:
	var action: String = String(entry.get("action", ""))
	var label_text: String = String(entry.get("label", ""))
	var icon_name: String = String(entry.get("icon", ""))
	var enabled: bool = bool(entry.get("enabled", false))

	var vbox: BoxContainer = cell.get_meta("vbox") as BoxContainer
	var label: Label = vbox.get_node("Label") as Label
	var key_label: Label = vbox.get_node("Key") as Label
	var icon: TextureRect = vbox.get_node("Icon") as TextureRect
	var button: Button = cell.get_meta("button") as Button

	label.text = label_text
	icon.texture = UIIconsScript.get_icon(icon_name) if icon_name != "" else null
	icon.visible = icon.texture != null

	if action == "":
		# Reserved placeholder. No key, no tooltip, no click.
		key_label.text = ""
		button.tooltip_text = ""
		button.disabled = true
		cell.modulate = Color(1, 1, 1, 0.4)
		if button.pressed.is_connected(_on_btn_pressed):
			button.pressed.disconnect(_on_btn_pressed)
		return

	key_label.text = _binding_label_for(action)
	button.tooltip_text = "%s (%s)" % [label_text, _binding_label_all_for(action)]
	button.disabled = not enabled
	cell.modulate = Color(1, 1, 1, 1) if enabled else Color(1, 1, 1, 0.55)

	# Re-wire pressed so a selection that swaps a cell's action (it cannot
	# today, but CommandRegistry is the layer that decides) does not leave
	# a stale binding behind.
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
