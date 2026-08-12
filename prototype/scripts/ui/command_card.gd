class_name CommandCard
extends MarginContainer
# A 3x3 grid that replaces raw hotkey usage by offering clickable abilities
# and stances for the current selection.

const Tokens = preload("res://scripts/ui_tokens.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")

var _grid: GridContainer
var _director: Node

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
	
	for i in range(9):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(48, 48)
		btn.focus_mode = Control.FOCUS_NONE
		btn.visible = false
		_grid.add_child(btn)

func setup(director: Node) -> void:
	_director = director
	_director.selection.selection_changed.connect(_on_selection_changed)
	_on_selection_changed(_director.selection.selected)

func _on_selection_changed(selected: Array) -> void:
	for child in _grid.get_children():
		child.visible = false
		if child.pressed.is_connected(_on_btn_pressed):
			child.pressed.disconnect(_on_btn_pressed)
	
	if selected.is_empty():
		return
		
	# Profile based on selection. Currently, we give the standard combat profile.
	_setup_btn(0, "A-Move", "cmd_attack_move", "Attack Move (A)")
	_setup_btn(1, "Stop", "cmd_stop", "Stop (S)")
	_setup_btn(2, "Hold", "cmd_hold", "Hold Position (C)")
	
	_setup_btn(3, "Aggr", "cmd_stance_aggressive", "Stance: Aggressive (Z)")
	_setup_btn(4, "RetF", "cmd_stance_return_fire", "Stance: Return Fire (X)")

func _setup_btn(index: int, label: String, action: String, tip: String) -> void:
	var btn = _grid.get_child(index) as Button
	btn.text = label
	btn.tooltip_text = tip
	btn.visible = true
	btn.pressed.connect(_on_btn_pressed.bind(action))
	# Avoid wiring UI feedback multiple times if already wired, though it's safe if we do it once in _init.
	# Actually, better to just wire it in _init.
	
func _ready() -> void:
	for child in _grid.get_children():
		UIFeedbackScript.wire(child)

func _on_btn_pressed(action: String) -> void:
	var ev = InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
