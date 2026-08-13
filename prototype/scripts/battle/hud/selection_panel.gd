class_name SelectionPanel
extends PanelContainer

# Battle Selection Panel (Phase 9, D8, D15).
# Aggregates heterogeneous selections by blueprint design, renders cached
# portraits, shows aggregate health bars, and supports sub-group selection grammar.

const Tokens = preload("res://scripts/ui_tokens.gd")
const UIIcons = preload("res://scripts/ui_icons.gd")

signal subgroup_selected(design_id: String, units: Array)
signal primary_changed(primary_design_id: String, primary_units: Array)

var selection_service: SelectionService = null
var _rows_container: VBoxContainer = null
var _groups: Dictionary = {}  # design_id -> { "name": ..., "units": [...], "priority": int }
var _primary_design_id: String = ""

# Thumbnail cache per design_id for the match
static var _thumbnail_cache: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(240, 0)
	mouse_filter = Control.MOUSE_FILTER_PASS

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_rows_container = VBoxContainer.new()
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_container.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows_container)


func bind_selection_service(service: SelectionService) -> void:
	if selection_service != null and selection_service.selection_changed.is_connected(_on_selection_changed):
		selection_service.selection_changed.disconnect(_on_selection_changed)
	selection_service = service
	if selection_service != null:
		selection_service.selection_changed.connect(_on_selection_changed)


func _on_selection_changed(units: Array) -> void:
	update_selection(units)


func update_selection(units: Array) -> void:
	_groups.clear()

	# 1. Aggregate by design
	for u in units:
		if u == null or not is_instance_valid(u):
			continue
		var design_id: String = _get_unit_design_id(u)
		var design_name: String = _get_unit_design_name(u)
		if not _groups.has(design_id):
			_groups[design_id] = {
				"id": design_id,
				"name": design_name,
				"units": [],
				"priority": _compute_design_priority(u),
				"max_hp": 0.0,
				"current_hp": 0.0,
			}
		_groups[design_id]["units"].append(u)
		var hp: float = u.get("health") if "health" in u else 100.0
		var max_hp: float = u.get("max_health") if "max_health" in u else 100.0
		_groups[design_id]["current_hp"] += hp
		_groups[design_id]["max_hp"] += max_hp

	# 2. Determine primary design
	_determine_primary_group()

	# 3. Rebuild UI rows
	_rebuild_rows()


func _get_unit_design_id(unit: Node) -> String:
	if unit.has_meta("blueprint_id"):
		return String(unit.get_meta("blueprint_id"))
	if "blueprint_id" in unit and unit.blueprint_id != "":
		return String(unit.blueprint_id)
	if unit.has_meta("design_id"):
		return String(unit.get_meta("design_id"))
	return unit.name


func _get_unit_design_name(unit: Node) -> String:
	if unit.has_meta("blueprint_name"):
		return String(unit.get_meta("blueprint_name"))
	if "blueprint_name" in unit and unit.blueprint_name != "":
		return String(unit.blueprint_name)
	if unit.has_meta("design_name"):
		return String(unit.get_meta("design_name"))
	return _get_unit_design_id(unit).capitalize()


func _compute_design_priority(unit: Node) -> int:
	# Active abilities (siege, special weapons) -> 100
	# Combat designs (weapons, autocannons) -> 50
	# Harvesters / logistics -> 10
	if unit.has_meta("has_active_abilities") and bool(unit.get_meta("has_active_abilities")):
		return 100
	if unit.has_meta("is_harvester") and bool(unit.get_meta("is_harvester")):
		return 10
	if unit.has_meta("is_combat") and bool(unit.get_meta("is_combat")):
		return 50
	# Check child modules or unit properties
	for child in unit.get_children():
		if child.has_meta("module_data"):
			var d = child.get_meta("module_data")
			var type_id: String = String(d.get("type_id", ""))
			if "cannon" in type_id or "rocket" in type_id or "laser" in type_id or "gun" in type_id:
				return 50
	return 25


func _determine_primary_group() -> void:
	if _groups.is_empty():
		_primary_design_id = ""
		primary_changed.emit("", [])
		return

	var best_id := ""
	var best_priority := -1
	for id in _groups.keys():
		var p: int = _groups[id]["priority"]
		if p > best_priority:
			best_priority = p
			best_id = id

	_primary_design_id = best_id
	primary_changed.emit(_primary_design_id, _groups[_primary_design_id]["units"])


func _rebuild_rows() -> void:
	if _rows_container == null:
		return

	for child in _rows_container.get_children():
		child.queue_free()

	visible = not _groups.is_empty()

	for id in _groups.keys():
		var group_data: Dictionary = _groups[id]
		var row := _create_group_row(group_data)
		_rows_container.add_child(row)


func _create_group_row(data: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var is_primary: bool = data["id"] == _primary_design_id

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	# Portrait / Icon
	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(36, 36)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex = _thumbnail_cache.get(data["id"], null)
	if tex == null and UIIcons.has_icon("cmd_hold"):
		tex = UIIcons.get_icon("cmd_hold")
	icon_rect.texture = tex
	hbox.add_child(icon_rect)

	# Name and count
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_lbl := Label.new()
	name_lbl.text = "%s (x%d)" % [data["name"], data["units"].size()]
	name_lbl.add_theme_color_override("font_color", Tokens.SIGNAL_HAZARD if is_primary else Tokens.TEXT_PRIMARY)
	info_vbox.add_child(name_lbl)

	# Aggregate health bar
	var hp_bar := ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(0, 6)
	hp_bar.show_percentage = false
	var max_hp: float = maxf(data["max_hp"], 1.0)
	var cur_hp: float = clampf(data["current_hp"], 0.0, max_hp)
	hp_bar.max_value = max_hp
	hp_bar.value = cur_hp
	info_vbox.add_child(hp_bar)

	hbox.add_child(info_vbox)

	# Row input handler for Sub-group grammar (D8)
	row.gui_input.connect(_on_row_gui_input.bind(data["id"]))

	return row


func _on_row_gui_input(event: InputEvent, design_id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not _groups.has(design_id):
			return
		var group_units: Array = _groups[design_id]["units"]

		if event.double_click:
			# Double click: select all of that design on screen
			subgroup_selected.emit(design_id, group_units)
			if selection_service:
				selection_service.selected = group_units.duplicate()
				selection_service.selection_changed.emit(selection_service.selected)

		elif event.ctrl_pressed and event.shift_pressed:
			# Ctrl+Shift+Click: remove the entire design group from selection
			if selection_service:
				var new_sel: Array = []
				for u in selection_service.selected:
					if u not in group_units:
						new_sel.append(u)
				selection_service.selected = new_sel
				selection_service.selection_changed.emit(selection_service.selected)

		elif event.shift_pressed:
			# Shift+Click: remove one unit of that design
			if selection_service and not group_units.is_empty():
				var unit_to_remove = group_units.pop_back()
				selection_service.selected.erase(unit_to_remove)
				selection_service.selection_changed.emit(selection_service.selected)

		else:
			# Plain click: select only this design group
			if selection_service:
				selection_service.selected = group_units.duplicate()
				selection_service.selection_changed.emit(selection_service.selected)
			subgroup_selected.emit(design_id, group_units)


static func cache_thumbnail(design_id: String, texture: Texture2D) -> void:
	_thumbnail_cache[design_id] = texture


static func clear_thumbnail_cache() -> void:
	_thumbnail_cache.clear()
