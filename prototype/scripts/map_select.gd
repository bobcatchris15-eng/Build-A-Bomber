extends Control
# Map-select screen: MainMenu's "Skirmish" button lands here first now,
# instead of jumping straight into Skirmish.tscn. Lists every map in
# MapCatalog, sets MatchConfig.selected_map_id on pick, then continues to
# Skirmish.tscn same as before.
#
# The map list is a ScrollContainer, not a plain VBox centered on screen -
# a first pass without it looked fine with 1 map but silently ran off both
# the top AND bottom of a 720px viewport once all 4 existed (a centered
# VBox overflows symmetrically around its center once its content exceeds
# the viewport, unlike a top-anchored one which only overflows downward).
# Caught by the mandatory screenshot check before considering this done -
# same class of bug the build bar's own ScrollContainer (skirmish.gd)
# already exists to avoid.

const MapCatalog = preload("res://scripts/map_catalog.gd")

func _ready():
	var bg = ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root_vbox = VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.offset_top = 30
	root_vbox.offset_bottom = -30
	root_vbox.offset_left = 200
	root_vbox.offset_right = -200
	root_vbox.add_theme_constant_override("separation", 10)
	add_child(root_vbox)

	var title = Label.new()
	title.text = "SELECT MAP"
	title.add_theme_font_size_override("font_size", 40)
	title.modulate = Color(1.0, 0.75, 0.25)
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
	list_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(list_vbox)

	for map_id in MapCatalog.get_map_ids():
		var map_def = MapCatalog.get_map(map_id)
		_add_map_button(list_vbox, map_id, map_def)

	root_vbox.add_child(HSeparator.new())

	var back_btn = Button.new()
	back_btn.text = "◀ Back"
	back_btn.custom_minimum_size = Vector2(200, 44)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	root_vbox.add_child(back_btn)

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
		get_tree().change_scene_to_file("res://scenes/MatchSetup.tscn"))
	parent.add_child(btn)

	var desc = Label.new()
	desc.text = map_def.get("description", "")
	desc.add_theme_font_size_override("font_size", 12)
	desc.modulate = Color(0.6, 0.65, 0.7)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.custom_minimum_size = Vector2(420, 0)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(desc)
