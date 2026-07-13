extends Control
# Pre-match settings screen: MapSelect.tscn routes here after the map is
# chosen (MatchConfig.selected_map_id is already set by then), this screen
# adds faction selection, Blueprint Library import, AI difficulty, and
# starting resources - then "Start Match" writes everything into
# MatchConfig and continues to Skirmish.tscn, same relay pattern
# MapSelect already established for the map choice.
#
# Every field here is genuinely optional: leaving factions on "Auto",
# selecting zero blueprints, and leaving resources on "Standard" all
# reproduce the exact old hardcoded-default behavior (see match_config.gd's
# own field comments) - this screen only OVERRIDES skirmish.gd's existing
# defaults, it doesn't replace them.

const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")

# Built in _ready() from FactionCatalog.get_ids() (all 10 factions), not a
# hardcoded 3-item const - adding an 11th faction later needs zero changes
# here.
var FACTIONS: Array = []
var FACTION_LABELS: Array = []
const DIFFICULTIES = ["easy", "normal", "hard"]
const DIFFICULTY_LABELS = ["Easy", "Normal", "Hard"]
# (metal, crystal); -1 means "use Skirmish's own default" (Standard reproduces
# the old hardcoded 450/150 exactly, not just a same-looking copy of it).
const RESOURCE_PRESETS = [Vector2i(-1, -1), Vector2i(250, 75), Vector2i(900, 400)]
const RESOURCE_LABELS = ["Standard", "Low (tight economy)", "High (build fast, fight fast)"]

var player_faction_btn: OptionButton
var enemy_faction_btn: OptionButton
var difficulty_btn: OptionButton
var resources_btn: OptionButton
var blueprint_checks: Array = [] # [{path, check: CheckBox}, ...]
var bp_manager: Node

func _ready():
	bp_manager = BlueprintManagerScript.new()
	add_child(bp_manager)

	FACTIONS = ["auto"]
	FACTION_LABELS = ["Auto (from roster)"]
	for fac_id in FactionCatalog.get_ids():
		FACTIONS.append(fac_id)
		FACTION_LABELS.append("%s - %s" % [FactionCatalog.get_faction_name(fac_id), FactionCatalog.get_passive(fac_id, "passive_summary", "")])

	var bg = ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root_vbox = VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.offset_top = 24
	root_vbox.offset_bottom = -24
	root_vbox.offset_left = 160
	root_vbox.offset_right = -160
	root_vbox.add_theme_constant_override("separation", 8)
	add_child(root_vbox)

	var title = Label.new()
	title.text = "MATCH SETTINGS"
	title.add_theme_font_size_override("font_size", 34)
	title.modulate = Color(1.0, 0.75, 0.25)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(title)
	root_vbox.add_child(HSeparator.new())

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 10)
	root_vbox.add_child(grid)

	player_faction_btn = _add_dropdown(grid, "Your Faction", FACTION_LABELS)
	enemy_faction_btn = _add_dropdown(grid, "Enemy Faction", FACTION_LABELS)
	var default_enemy_idx = FACTIONS.find("technocrats") # matches the old hardcoded enemy default
	if default_enemy_idx >= 0:
		enemy_faction_btn.selected = default_enemy_idx
	difficulty_btn = _add_dropdown(grid, "AI Difficulty", DIFFICULTY_LABELS)
	difficulty_btn.selected = 1 # Normal
	resources_btn = _add_dropdown(grid, "Starting Resources", RESOURCE_LABELS)

	root_vbox.add_child(HSeparator.new())

	var library_label = Label.new()
	library_label.text = "Import From Blueprint Library (leave none checked to auto-include your newest designs)"
	library_label.add_theme_font_size_override("font_size", 14)
	library_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(library_label)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	var list_vbox = VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)

	var entries = bp_manager.list_blueprints()
	if entries.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No saved designs yet - the match will use bundled defaults."
		empty_label.modulate = Color(0.6, 0.65, 0.7)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list_vbox.add_child(empty_label)
	else:
		for entry in entries:
			var row = HBoxContainer.new()
			list_vbox.add_child(row)
			var check = CheckBox.new()
			check.text = "%s  (%s | %s)" % [entry.get("name", "Untitled"), _prettify(entry.get("hull_type", "")), _prettify(entry.get("faction", ""))]
			row.add_child(check)
			blueprint_checks.append({"path": entry.path, "check": check})

	root_vbox.add_child(HSeparator.new())

	var button_row = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 20)
	root_vbox.add_child(button_row)

	var back_btn = Button.new()
	back_btn.text = "◀ Back"
	back_btn.custom_minimum_size = Vector2(200, 48)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MapSelect.tscn"))
	button_row.add_child(back_btn)

	var start_btn = Button.new()
	start_btn.text = "Start Match ▶"
	start_btn.custom_minimum_size = Vector2(240, 48)
	start_btn.add_theme_font_size_override("font_size", 20)
	start_btn.modulate = Color(0.5, 1.0, 0.5)
	start_btn.pressed.connect(_on_start_pressed)
	button_row.add_child(start_btn)

func _add_dropdown(parent: Control, label_text: String, labels: PackedStringArray) -> OptionButton:
	var label = Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parent.add_child(label)

	var btn = OptionButton.new()
	btn.custom_minimum_size = Vector2(260, 36)
	for l in labels:
		btn.add_item(l)
	parent.add_child(btn)
	return btn

func _prettify(id: String) -> String:
	if id == "":
		return "Unknown"
	var words = id.split("_")
	var out: Array = []
	for w in words:
		if w.length() > 0:
			out.append(w[0].to_upper() + w.substr(1))
	return " ".join(PackedStringArray(out))

func _on_start_pressed():
	var match_config = get_node_or_null("/root/MatchConfig")
	if match_config:
		match_config.player_faction = "" if FACTIONS[player_faction_btn.selected] == "auto" else FACTIONS[player_faction_btn.selected]
		match_config.enemy_faction = "" if FACTIONS[enemy_faction_btn.selected] == "auto" else FACTIONS[enemy_faction_btn.selected]
		match_config.ai_difficulty = DIFFICULTIES[difficulty_btn.selected]
		var preset: Vector2i = RESOURCE_PRESETS[resources_btn.selected]
		match_config.starting_metal = preset.x
		match_config.starting_crystal = preset.y
		var chosen_paths = []
		for entry in blueprint_checks:
			if entry.check.button_pressed:
				chosen_paths.append(entry.path)
		match_config.selected_blueprint_paths = chosen_paths
	get_tree().change_scene_to_file("res://scenes/Skirmish.tscn")
