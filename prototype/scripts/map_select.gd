extends Control

const MapCatalog = preload("res://scripts/map_catalog.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")

func _ready() -> void:
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var match_config = get_node_or_null("/root/MatchConfig")
	var faction = FactionCatalog.DEFAULT_FACTION
	if match_config and "player_faction" in match_config and match_config.player_faction != "":
		faction = match_config.player_faction
	UITheme.apply_brushed_panel(bg, faction)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card = PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	card.custom_minimum_size = Vector2(640, 580)
	center.add_child(card)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	card.add_child(margin)

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 14)
	margin.add_child(root_vbox)

	var title = Label.new()
	title.text = "SELECT MAP"
	title.theme_type_variation = "TitleLabel"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(title)

	root_vbox.add_child(HSeparator.new())

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	var list_vbox = VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	list_vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(list_vbox)

	for map_id in MapCatalog.get_map_ids():
		var map_def = MapCatalog.get_map(map_id)
		_add_map_button(list_vbox, map_id, map_def)

	root_vbox.add_child(HSeparator.new())

	var back_btn = Button.new()
	back_btn.text = " Back"
	back_btn.icon = UIIcons.get_icon("chevron_left")
	back_btn.custom_minimum_size = Vector2(180, 44)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	root_vbox.add_child(back_btn)

func _add_map_button(parent: Control, map_id: String, map_def: Dictionary) -> void:
	var btn = Button.new()
	btn.text = map_def.get("name", map_id)
	btn.tooltip_text = map_def.get("description", "")
	btn.custom_minimum_size = Vector2(560, 48)
	btn.add_theme_font_size_override("font_size", 18)
	btn.pressed.connect(func():
		var match_config = get_node_or_null("/root/MatchConfig")
		if match_config:
			match_config.selected_map_id = map_id
		get_tree().change_scene_to_file("res://scenes/MatchSetup.tscn"))
	parent.add_child(btn)

	var desc = Label.new()
	desc.text = map_def.get("description", "")
	desc.add_theme_font_size_override("font_size", 12)
	desc.modulate = Color(0.65, 0.70, 0.75)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.custom_minimum_size = Vector2(560, 0)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(desc)
