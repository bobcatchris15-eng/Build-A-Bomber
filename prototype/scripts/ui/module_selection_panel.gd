class_name ModuleSelectionPanel
extends PanelContainer

# Lab multi-module selection panel (Phase 10, D16).
# Aggregates selected modules by module type, displays counts, and
# supports the same modifier grammar as battle selection:
# - Shift+Click removes one module of that type
# - Ctrl+Shift+Click removes the entire module type from selection

const Tokens = preload("res://scripts/ui_tokens.gd")
const UIIcons = preload("res://scripts/ui_icons.gd")

signal module_subgroup_selected(type_id: String, modules: Array)
signal selection_changed(selected_modules: Array)

var _selected_modules: Array = []
var _groups: Dictionary = {}  # type_id -> { "name": ..., "modules": [...] }
var _rows_container: VBoxContainer = null


func _ready() -> void:
	custom_minimum_size = Vector2(220, 0)
	mouse_filter = Control.MOUSE_FILTER_PASS

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_rows_container = VBoxContainer.new()
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_container.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows_container)


func set_selected_modules(modules: Array) -> void:
	_selected_modules = modules.duplicate()
	_rebuild_groups()
	_rebuild_rows()


func get_selected_modules() -> Array:
	return _selected_modules.duplicate()


func _rebuild_groups() -> void:
	_groups.clear()
	for m in _selected_modules:
		if m == null or not is_instance_valid(m):
			continue
		var type_id: String = _get_module_type_id(m)
		var type_name: String = _get_module_name(m)
		if not _groups.has(type_id):
			_groups[type_id] = {
				"type_id": type_id,
				"name": type_name,
				"modules": [],
			}
		_groups[type_id]["modules"].append(m)


func _get_module_type_id(module: Node) -> String:
	if module.has_meta("module_data"):
		var d = module.get_meta("module_data")
		if d and "type_id" in d:
			return String(d.type_id)
	return module.name


func _get_module_name(module: Node) -> String:
	var tid := _get_module_type_id(module)
	return tid.replace("_", " ").capitalize()


func _rebuild_rows() -> void:
	if _rows_container == null:
		return

	for child in _rows_container.get_children():
		child.queue_free()

	visible = not _groups.is_empty()

	for type_id in _groups.keys():
		var data: Dictionary = _groups[type_id]
		var row := _create_module_row(data)
		_rows_container.add_child(row)


func _create_module_row(data: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(24, 24)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if UIIcons.has_icon("cmd_hold"):
		icon_rect.texture = UIIcons.get_icon("cmd_hold")
	hbox.add_child(icon_rect)

	var name_lbl := Label.new()
	name_lbl.text = "%d x %s" % [data["modules"].size(), data["name"]]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_color_override("font_color", Tokens.TEXT_PRIMARY)
	hbox.add_child(name_lbl)

	row.gui_input.connect(_on_row_gui_input.bind(data["type_id"]))
	return row


func _on_row_gui_input(event: InputEvent, type_id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not _groups.has(type_id):
			return
		var group_mods: Array = _groups[type_id]["modules"]

		if event.ctrl_pressed and event.shift_pressed:
			# Ctrl+Shift+Click: remove all modules of this type
			var remaining: Array = []
			for m in _selected_modules:
				if m not in group_mods:
					remaining.append(m)
			_selected_modules = remaining
			_rebuild_groups()
			_rebuild_rows()
			selection_changed.emit(_selected_modules)

		elif event.shift_pressed:
			# Shift+Click: remove one module of this type
			if not group_mods.is_empty():
				var mod_to_remove = group_mods.pop_back()
				_selected_modules.erase(mod_to_remove)
				_rebuild_groups()
				_rebuild_rows()
				selection_changed.emit(_selected_modules)

		else:
			# Plain click: select only this module type
			_selected_modules = group_mods.duplicate()
			_rebuild_groups()
			_rebuild_rows()
			module_subgroup_selected.emit(type_id, _selected_modules)
			selection_changed.emit(_selected_modules)
