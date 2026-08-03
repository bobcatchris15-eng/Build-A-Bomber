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
const UITheme = preload("res://scripts/ui_theme.gd")
const MapCatalog = preload("res://scripts/map_catalog.gd")

var bg_rect: ColorRect

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
# Matches skirmish.gd's own hardcoded roster.slice(0, 12) - kept as a
# separate constant here (not read from skirmish.gd, which isn't loaded
# yet at this point in the flow) since this screen needs to warn BEFORE
# the roster is ever built, not just match its cap after the fact.
const ROSTER_CAP = 12

var map_btn: OptionButton
var map_desc_label: Label
var MAP_IDS: Array = []
var player_faction_btn: OptionButton
var enemy_faction_btn: OptionButton
var difficulty_btn: OptionButton
var resources_btn: OptionButton
var blueprint_checks: Array = [] # [{path, check: CheckBox}, ...]
var bp_manager: Node
var selection_counter_label: Label

func _ready():
	bp_manager = BlueprintManagerScript.new()
	add_child(bp_manager)

	FACTIONS = ["auto"]
	FACTION_LABELS = ["Auto (from roster)"]
	for fac_id in FactionCatalog.get_ids():
		FACTIONS.append(fac_id)
		FACTION_LABELS.append("%s - %s" % [FactionCatalog.get_faction_name(fac_id), FactionCatalog.get_passive(fac_id, "passive_summary", "")])

	bg_rect = ColorRect.new()
	bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg_rect)

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

	# Map selection now lives HERE rather than on a screen in front of this
	# one. MapSelect.tscn was a whole screen for a single choice, and picking
	# a map committed you to it - the old list transitioned scenes on click,
	# so you left before seeing anything about the map and had to back out to
	# change your mind. Folding it in makes the map one setting among the
	# others, visible alongside the forces it will be fought over.
	map_btn = _add_dropdown(grid, "Map", _build_map_labels())
	map_btn.item_selected.connect(_on_map_selected)
	map_btn.tooltip_text = "Where the match is fought."
	_sync_map_selection()

	player_faction_btn = _add_dropdown(grid, "Your Faction", FACTION_LABELS)
	# Live UI re-theme: the whole screen's brushed-aluminum chrome shifts to
	# match whichever faction the player picks, right in this dropdown -
	# the most direct possible proof the theme is faction-driven, not fixed.
	player_faction_btn.item_selected.connect(func(_i): _refresh_theme())
	enemy_faction_btn = _add_dropdown(grid, "Enemy Faction", FACTION_LABELS)
	var default_enemy_idx = FACTIONS.find("technocrats") # matches the old hardcoded enemy default
	if default_enemy_idx >= 0:
		enemy_faction_btn.selected = default_enemy_idx
	difficulty_btn = _add_dropdown(grid, "AI Difficulty", DIFFICULTY_LABELS)
	difficulty_btn.selected = 1 # Normal
	# Real, not cosmetic (enemy_ai.gd's own DIFFICULTY_TIMER_MULT/PITY_MULT) -
	# explained here since the dropdown itself gives no hint what changes.
	difficulty_btn.tooltip_text = "Changes how fast the AI builds/attacks and how quickly it recovers from a bad economy. Doesn't change unit stats - just AI pacing."
	difficulty_btn.set_item_tooltip(0, "AI builds and attacks more slowly, and struggles longer if its economy falls behind.")
	difficulty_btn.set_item_tooltip(1, "Balanced AI pacing.")
	difficulty_btn.set_item_tooltip(2, "AI builds and attacks faster, and recovers quickly from economic setbacks.")
	resources_btn = _add_dropdown(grid, "Starting Resources", RESOURCE_LABELS)

	# The selected map's description, live beneath the settings grid. On the
	# old MapSelect screen this text existed but you had to leave the screen
	# to act on it; here it updates in place as you change the dropdown.
	map_desc_label = Label.new()
	map_desc_label.theme_type_variation = "HintLabel"
	map_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	root_vbox.add_child(map_desc_label)
	_update_map_description()

	root_vbox.add_child(HSeparator.new())

	var library_label = Label.new()
	library_label.text = "Import From Blueprint Library (leave none checked to auto-include your newest designs)"
	library_label.add_theme_font_size_override("font_size", 14)
	library_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(library_label)

	selection_counter_label = Label.new()
	selection_counter_label.add_theme_font_size_override("font_size", 12)
	selection_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(selection_counter_label)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	var list_vbox = VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)

	# named_only: this is the "what goes into the match" list, so it shows
	# only designs the player deliberately saved under a name. Unnamed
	# leftovers from testing stay in the Blueprint Library where they can be
	# renamed or deleted.
	var entries = bp_manager.list_blueprints(true)
	if entries.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No saved designs yet - name and save a design in the Lab to field it. The match will use bundled defaults."
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
			check.toggled.connect(func(_pressed): _update_selection_counter())
			blueprint_checks.append({"path": entry.path, "check": check})
	_update_selection_counter()

	root_vbox.add_child(HSeparator.new())

	var button_row = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 20)
	root_vbox.add_child(button_row)

	var back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(200, 48)
	# Back now returns to the main menu, not to MapSelect - map choice is a
	# column on this screen, so there is no intermediate screen to go back to.
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	button_row.add_child(back_btn)

	var start_btn = Button.new()
	start_btn.text = "Start Match"
	start_btn.custom_minimum_size = Vector2(240, 48)
	start_btn.add_theme_font_size_override("font_size", 20)
	start_btn.modulate = Color(0.5, 1.0, 0.5)
	start_btn.pressed.connect(_on_start_pressed)
	button_row.add_child(start_btn)

	_refresh_theme()

# Map list, sourced from MapCatalog so a newly-added map file appears here
# with no code change - same discovery-over-declaration approach the terrain
# variants and hull roster already use.
func _build_map_labels() -> PackedStringArray:
	MAP_IDS = MapCatalog.get_map_ids()
	var labels := PackedStringArray()
	for map_id in MAP_IDS:
		labels.append(MapCatalog.get_map_name(map_id))
	return labels

# Selecting a map writes straight through to MatchConfig, so the choice
# survives even if the player backs out to the menu and returns - the old
# flow only recorded it at the moment of scene transition.
func _on_map_selected(idx: int) -> void:
	if idx < 0 or idx >= MAP_IDS.size():
		return
	var match_config = get_node_or_null("/root/MatchConfig")
	if match_config:
		match_config.selected_map_id = MAP_IDS[idx]
	_update_map_description()

func _sync_map_selection() -> void:
	var match_config = get_node_or_null("/root/MatchConfig")
	var current: String = ""
	if match_config and "selected_map_id" in match_config:
		current = str(match_config.selected_map_id)
	var idx := MAP_IDS.find(current)
	if idx < 0:
		idx = maxi(0, MAP_IDS.find(MapCatalog.DEFAULT_MAP_ID))
	map_btn.selected = idx
	_on_map_selected(idx)

func _update_map_description() -> void:
	if not map_desc_label or map_btn.selected < 0 or map_btn.selected >= MAP_IDS.size():
		return
	var map_def: Dictionary = MapCatalog.get_map(MAP_IDS[map_btn.selected])
	map_desc_label.text = str(map_def.get("description", ""))

func _refresh_theme():
	var idx = player_faction_btn.selected
	var faction = FACTIONS[idx] if idx >= 0 and idx < FACTIONS.size() else "auto"
	if faction == "auto":
		var match_config = get_node_or_null("/root/MatchConfig")
		faction = FactionCatalog.DEFAULT_FACTION
		if match_config and "player_faction" in match_config and match_config.player_faction != "":
			faction = match_config.player_faction
	UITheme.apply_brushed_panel(bg_rect, faction)

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

func _update_selection_counter():
	var count = 0
	for entry in blueprint_checks:
		if entry.check.button_pressed:
			count += 1
	if count == 0:
		selection_counter_label.text = ""
	elif count >= ROSTER_CAP:
		selection_counter_label.text = "%d / %d selected - only the first %d will make it into your roster" % [count, ROSTER_CAP, ROSTER_CAP]
		selection_counter_label.modulate = Color(1.0, 0.55, 0.35)
	else:
		selection_counter_label.text = "%d / %d selected" % [count, ROSTER_CAP]
		selection_counter_label.modulate = Color(0.65, 0.85, 0.65)
	# Once the cap is hit, disable the remaining unchecked boxes rather
	# than silently letting the player check more than will ever be used -
	# this is what the earlier audit flagged as a real gap (checking 15
	# designs with no feedback that only some subset actually gets in).
	for entry in blueprint_checks:
		if not entry.check.button_pressed:
			entry.check.disabled = count >= ROSTER_CAP

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

	# Routed through SceneRouter rather than change_scene_to_file(): loading
	# Skirmish.tscn synchronously blocks the main thread for over a second,
	# during which Windows marks the window "(Not Responding)". The router
	# loads it on a worker thread behind a loading screen instead.
	var router = get_node_or_null("/root/SceneRouter")
	var map_name := ""
	if map_btn and map_btn.selected >= 0 and map_btn.selected < MAP_IDS.size():
		map_name = MapCatalog.get_map_name(MAP_IDS[map_btn.selected])
	if router:
		router.change_scene_async("res://scenes/Skirmish.tscn", map_name)
	else:
		get_tree().change_scene_to_file("res://scenes/Skirmish.tscn")
