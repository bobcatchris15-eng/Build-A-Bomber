extends Control
# Title screen tying the game loop together:
# Design Lab (build blueprints) -> Skirmish (fight with them) -> repeat.

const UITheme = preload("res://scripts/ui_theme.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")

func _ready():
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Brushed-aluminum chrome, tinted to whichever faction the player last
	# configured a match with (MatchConfig persists across scene changes) -
	# falls back to the default faction if no match has been set up yet.
	var match_config = get_node_or_null("/root/MatchConfig")
	var faction = FactionCatalog.DEFAULT_FACTION
	if match_config and "player_faction" in match_config and match_config.player_faction != "":
		faction = match_config.player_faction
	UITheme.apply_brushed_panel(bg, faction)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	var title = Label.new()
	title.text = "BUILD-A-BOMBER"
	title.add_theme_font_size_override("font_size", 64)
	title.modulate = Color(1.0, 0.75, 0.25)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Design ridiculous war machines. Send them to glorious, over-dramatized doom."
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.modulate = Color(0.7, 0.75, 0.8)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())

	_add_button(vbox, "🔧  Design Lab", "Design and tweak unit & defense blueprints", func():
		get_tree().change_scene_to_file("res://scenes/MainLab.tscn"))
	_add_button(vbox, "⚔️  Skirmish", "C&C-style battle: build a base, produce your designs, destroy the enemy HQ", func():
		get_tree().change_scene_to_file("res://scenes/MapSelect.tscn"))
	_add_button(vbox, "🎯  Test Range", "Drive your latest saved design against target dummies", func():
		get_tree().change_scene_to_file("res://scenes/Battlefield.tscn"))
	_add_button(vbox, "🚪  Quit", "", func():
		get_tree().quit())

func _add_button(parent: Control, text: String, tooltip: String, callback: Callable):
	var btn = Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = Vector2(340, 54)
	btn.add_theme_font_size_override("font_size", 22)
	btn.pressed.connect(callback)
	parent.add_child(btn)

	if tooltip != "":
		var hint = Label.new()
		hint.text = tooltip
		hint.add_theme_font_size_override("font_size", 12)
		hint.modulate = Color(0.55, 0.6, 0.65)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		parent.add_child(hint)
