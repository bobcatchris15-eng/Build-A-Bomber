class_name CommandCard
extends MarginContainer
# A positional command surface for the current selection.
#
# Each cell is a real StampedButton on the shared UIPropStage (D2,
# D6): the 3D push-button mesh is the visible face, the stamped-enamel
# legend carries the command name, and an icon + key overlay sit on
# top of the mesh in 2D space. The cell's hotkey text and tooltip read
# from InputService.binding_label(action) at render time, so a rebind
# reflects on the card without a second source of truth. The card
# subscribes to InputService.bindings_changed to refresh.
#
# THE PHASE 1+8 CROSS. The earlier 3x3 cell was a flat PanelContainer
# with a Button on top and a VBox of icon/label/key. Phase 1's
# UIPropStage made the 3D push-button practical without per-control
# SubViewports (X2), so the cells here are now StampedButton (a
# Button that registers with the stage on _ready). The Button's
# pressed signal replaces the manual Button.pressed dance the old
# PanelContainer+Button cell needed.
#
# STAMPEDBUTTON + 2D OVERLAYS. The StampedLabel inside StampedButton
# is at FULL_RECT and shows the command name in stamped-enamel. The
# icon and key are added as child Controls on top of the label,
# anchored to top-center and bottom-center respectively. The StampedLabel
# is transparent between the glyphs, so the 3D mesh shows through
# where the icon and key don't cover it. Z-order: mesh (stage) →
# icon (top) → key (bottom) → StampedLabel (FULL_RECT, text only).
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
const StampedButtonScript = preload("res://scripts/ui_stamped_button.gd")
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
	if _input_service != null and not _input_service.bindings_changed.is_connected(_refresh_bindings):
		_input_service.bindings_changed.connect(_refresh_bindings)

	_registry = _resolve_registry() as CommandRegistryScript
	if _registry != null and not _registry.registry_changed.is_connected(_refresh_registry):
		_registry.registry_changed.connect(_refresh_registry)

	# Listen to selection changes from the match director's selection service.
	if _director != null and _director.selection != null:
		var sel = _director.selection
		if sel.has_signal("selection_changed") and not sel.selection_changed.is_connected(_on_selection_changed):
			sel.selection_changed.connect(_on_selection_changed)

	_refresh_cells()


func _ready() -> void:
	# Late-bind InputService if setup() ran before the autoload was in tree.
	if _input_service == null:
		_input_service = _resolve_input_service()
		if _input_service != null and not _input_service.bindings_changed.is_connected(_refresh_bindings):
			_input_service.bindings_changed.connect(_refresh_bindings)
	if _registry == null:
		_registry = _resolve_registry() as CommandRegistryScript
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


# A StampedButton cell. The 3D push-button mesh comes from the
# shared UIPropStage; the stamped-enamel legend (StampedLabel child)
# shows the command name; the icon and key are 2D overlays on top.
#
# Anchors on the overlays: icon at top-center (24x24, full cell width
# to keep the visual margin), key at bottom-center (small text). The
# StampedLabel is at FULL_RECT and only draws text, so the mesh shows
# through the gaps.
func _build_cell() -> Control:
	# DIAGNOSTIC SWAP 2026-08-18. Was StampedButtonScript.new() -
	# the StampedButton's fallback (no UIPropStage) path was supposed
	# to keep the theme stylebox, but the cells rendered blank in the
	# battle HUD. Plain Button renders the theme stylebox directly;
	# if a plain Button shows up and a StampedButton did not, the
	# StampedButton's _ready is the bug. If both are blank, the bug
	# is upstream (rail/scroll/cell-size layout).
	var cell := Button.new()
	# DIAGNOSTIC 2026-08-18. Forced to 200x200 + bright red so the
	# user can see if the cells are even being drawn. If red squares
	# appear in the right rail, the cells are rendering but the
	# GridContainer is collapsing their size to 0 (cell size issue).
	# If no red squares, the cells aren't being drawn at all (z-order
	# / modulate / not-in-tree issue). Revert once we know which.
	cell.custom_minimum_size = Vector2(200, 200)
	cell.modulate = Color(1, 0, 0, 1)
	cell.focus_mode = Control.FOCUS_ALL

	# Icon at the top. Anchored to top-center, 24x24. The cell is 64
	# wide so an offset of 20 from the left puts the icon's center at
	# the cell's center. MOUSE_FILTER_IGNORE so the click falls through
	# to the StampedButton underneath.
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_preset(Control.PRESET_TOP_WIDE)
	icon.offset_top = 4
	icon.offset_bottom = 28
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(icon)

	# Key at the bottom. Anchored to bottom-wide, with a fixed height
	# for the text. TEXT_SECONDARY color so it reads as metadata, not
	# the primary label. MOUSE_FILTER_IGNORE for the same reason.
	var key_label := Label.new()
	key_label.name = "Key"
	key_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	key_label.offset_top = -16
	key_label.offset_bottom = -2
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.add_theme_font_size_override("font_size", Tokens.FONT_MICRO)
	key_label.add_theme_color_override("font_color", Tokens.TEXT_SECONDARY)
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(key_label)

	cell.set_meta("icon", icon)
	cell.set_meta("key_label", key_label)
	cell.set_meta("button", cell)
	cell.set_meta("vbox", cell)
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

	var icon: TextureRect = cell.get_meta("icon") as TextureRect
	var key_label: Label = cell.get_meta("key_label") as Label

	# The StampedButton's `legend` setter pushes the string into its
	# own StampedLabel child. Setting the property here is the only
	# path that avoids a duplicate "printed on" copy in the theme's
	# stencil face (the trap the StampedButton header warns about).
	if "legend" in cell:
		cell.legend = label_text

	icon.texture = UIIconsScript.get_icon(icon_name) if icon_name != "" else null
	icon.visible = icon.texture != null

	if action == "":
		# Reserved placeholder. No key, no tooltip, no click.
		key_label.text = ""
		cell.tooltip_text = ""
		cell.set("disabled", true)
		cell.modulate = Color(1, 1, 1, 0.4)
		if cell.has_signal("pressed") and cell.pressed.is_connected(_on_btn_pressed):
			cell.pressed.disconnect(_on_btn_pressed)
		return

	key_label.text = _binding_label_for(action)
	cell.tooltip_text = "%s (%s)" % [label_text, _binding_label_all_for(action)]
	cell.set("disabled", not enabled)
	cell.modulate = Color(1, 1, 1, 1) if enabled else Color(1, 1, 1, 0.55)

	# Re-wire pressed so a selection that swaps a cell's action (it cannot
	# today, but CommandRegistry is the layer that decides) does not leave
	# a stale binding behind.
	if cell.has_signal("pressed"):
		if cell.pressed.is_connected(_on_btn_pressed):
			cell.pressed.disconnect(_on_btn_pressed)
		cell.pressed.connect(_on_btn_pressed.bind(action))


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
