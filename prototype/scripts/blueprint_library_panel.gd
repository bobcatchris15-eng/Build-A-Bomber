extends Control
# Self-contained Blueprint Library browser.
# Instantiated entirely via code (LibraryPanel.new()) from stat_calculator.gd's
# "Blueprint Library..." button - no .tscn needed, consistent with how
# stat_calculator.gd already builds its dynamic dropdowns/sliders in code.

var list_vbox: VBoxContainer
var blueprint_manager: Node

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root = get_node_or_null("/root/MainLab")
	blueprint_manager = root.get_node_or_null("BlueprintManager") if root else null

	var backdrop = ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var panel = PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -260
	panel.offset_top = -240
	panel.offset_right = 260
	panel.offset_bottom = 240
	add_child(panel)
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	margin.add_child(vbox)

	var header = HBoxContainer.new()
	vbox.add_child(header)

	var title = Label.new()
	title.text = "Blueprint Library"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): queue_free())
	header.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 380)
	vbox.add_child(scroll)
	list_vbox = VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)

	_refresh_list()

func _refresh_list():
	for child in list_vbox.get_children():
		child.queue_free()

	if not blueprint_manager:
		var err = Label.new()
		err.text = "Blueprint Manager not found."
		list_vbox.add_child(err)
		return

	var entries = blueprint_manager.list_blueprints()

	if entries.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No saved blueprints yet. Design something and hit Save!"
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		list_vbox.add_child(empty_label)
		return

	for entry in entries:
		_add_row(entry)

func _add_row(entry: Dictionary):
	var row = PanelContainer.new()
	list_vbox.add_child(row)

	var hbox = HBoxContainer.new()
	row.add_child(hbox)

	var info = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var name_label = Label.new()
	name_label.text = entry.get("name", "Untitled Design")
	name_label.add_theme_font_size_override("font_size", 16)
	info.add_child(name_label)

	var sub_label = Label.new()
	sub_label.text = "%s | %s" % [_prettify(entry.get("hull_type", "")), _prettify(entry.get("faction", ""))]
	sub_label.modulate = Color(0.75, 0.75, 0.75)
	info.add_child(sub_label)

	var load_btn = Button.new()
	load_btn.text = "Load"
	load_btn.modulate = Color(0.4, 1, 0.4, 1)
	load_btn.pressed.connect(_on_load_pressed.bind(entry.get("id", "")))
	hbox.add_child(load_btn)

	var dup_btn = Button.new()
	dup_btn.text = "Duplicate"
	dup_btn.pressed.connect(_on_duplicate_pressed.bind(entry.get("id", "")))
	hbox.add_child(dup_btn)

	var del_btn = Button.new()
	del_btn.text = "Delete"
	del_btn.modulate = Color(1, 0.4, 0.4, 1)
	del_btn.pressed.connect(_on_delete_pressed.bind(entry.get("id", "")))
	hbox.add_child(del_btn)

	list_vbox.add_child(HSeparator.new())

func _on_load_pressed(id: String):
	if blueprint_manager:
		blueprint_manager.load_blueprint_into_designer(id)
	queue_free()

func _on_duplicate_pressed(id: String):
	if blueprint_manager:
		blueprint_manager.duplicate_blueprint(id)
	_refresh_list()

func _on_delete_pressed(id: String):
	if blueprint_manager:
		blueprint_manager.delete_blueprint(id)
	_refresh_list()

func _prettify(id: String) -> String:
	if id == "":
		return "Unknown"
	var words = id.split("_")
	var out: Array = []
	for w in words:
		if w.length() > 0:
			out.append(w[0].to_upper() + w.substr(1))
	return " ".join(PackedStringArray(out))
