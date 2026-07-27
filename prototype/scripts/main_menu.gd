extends Control

const UITheme = preload("res://scripts/ui_theme.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")

func _ready() -> void:
	# Root dark background + brushed aluminum panel shader
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

	# Main Card Panel
	var card = PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	card.custom_minimum_size = Vector2(480, 520)
	center.add_child(card)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	card.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title = Label.new()
	title.text = "BUILD-A-BOMBER"
	title.theme_type_variation = "TitleLabel"
	title.add_theme_font_size_override("font_size", 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Design ridiculous war machines.\nSend them to glorious, over-dramatized doom."   
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.modulate = Color(0.7, 0.75, 0.8)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())

	_add_menu_button(vbox, "wrench", "Design Lab", "Design and tweak unit & defense blueprints", func():
		get_tree().change_scene_to_file("res://scenes/MainLab.tscn"))

	_add_menu_button(vbox, "gear", "Hull Builder", "Construct custom hulls from primitive shapes", func():
		get_tree().change_scene_to_file("res://scenes/HullBuilder.tscn"))

	_add_menu_button(vbox, "attack", "Skirmish", "C&C-style battle: build a base, produce designs, destroy HQ", func():
		get_tree().change_scene_to_file("res://scenes/MapSelect.tscn"))

	_add_menu_button(vbox, "target", "Test Range", "Drive your latest saved design against target dummies", func():
		get_tree().change_scene_to_file("res://scenes/Battlefield.tscn"))

	_add_menu_button(vbox, "close", "Quit", "", func():
		get_tree().quit())

func _add_menu_button(parent: Control, icon_name: String, title_text: String, hint_text: String, callback: Callable) -> void:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(360, 52)
	btn.text = "  " + title_text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 18)

	var icon_tex = UIIcons.get_icon(icon_name)
	if icon_tex:
		btn.icon = icon_tex
		btn.expand_icon = true

	btn.pressed.connect(func():
		if get_node_or_null("/root/AudioManager"):
			get_node("/root/AudioManager").play_sfx("click")
		callback.call())
	btn.mouse_entered.connect(func():
		if get_node_or_null("/root/AudioManager"):
			get_node("/root/AudioManager").play_sfx("hover"))

	parent.add_child(btn)

	if hint_text != "":
		btn.tooltip_text = hint_text