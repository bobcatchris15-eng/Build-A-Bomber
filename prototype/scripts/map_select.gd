extends Control
# Map-select screen: MainMenu's "Skirmish" button lands here first now,
# instead of jumping straight into Skirmish.tscn. Lists every map in
# MapCatalog, sets MatchConfig.selected_map_id on pick, then continues to
# Skirmish.tscn same as before.

const MapCatalog = preload("res://scripts/map_catalog.gd")

func _ready():
	var bg = ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	var title = Label.new()
	title.text = "SELECT MAP"
	title.add_theme_font_size_override("font_size", 40)
	title.modulate = Color(1.0, 0.75, 0.25)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	for map_id in MapCatalog.get_map_ids():
		var map_def = MapCatalog.get_map(map_id)
		_add_map_button(vbox, map_id, map_def)

	vbox.add_child(HSeparator.new())

	var back_btn = Button.new()
	back_btn.text = "◀ Back"
	back_btn.custom_minimum_size = Vector2(200, 44)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	vbox.add_child(back_btn)

func _add_map_button(parent: Control, map_id: String, map_def: Dictionary):
	var btn = Button.new()
	btn.text = map_def.get("name", map_id)
	btn.tooltip_text = map_def.get("description", "")
	btn.custom_minimum_size = Vector2(420, 50)
	btn.add_theme_font_size_override("font_size", 20)
	btn.pressed.connect(func():
		var match_config = get_node_or_null("/root/MatchConfig")
		if match_config:
			match_config.selected_map_id = map_id
		get_tree().change_scene_to_file("res://scenes/Skirmish.tscn"))
	parent.add_child(btn)

	var desc = Label.new()
	desc.text = map_def.get("description", "")
	desc.add_theme_font_size_override("font_size", 12)
	desc.modulate = Color(0.6, 0.65, 0.7)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.custom_minimum_size = Vector2(420, 0)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(desc)
