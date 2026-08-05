extends Control
# Setup screen for Operations Mode (Iterative Campaign)
# Allows the player to view the 3-stage map itinerary, choose difficulty,
# select their starting blueprint roster, and initiate the campaign loop.

const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const MapCatalog = preload("res://scripts/map_catalog.gd")
const OperationsManager = preload("res://scripts/operations_manager.gd")
const UIShell = preload("res://scripts/ui_shell.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")
const UIAnimScript = preload("res://scripts/ui_anim.gd")

var difficulty_btn: OptionButton
var player_faction_btn: OptionButton
var bp_manager: Node
var blueprint_checks: Array = []
var selection_counter_label: Label
var FACTIONS: Array = []
var FACTION_LABELS: Array = []
const DIFFICULTIES = ["easy", "normal", "hard"]
const DIFFICULTY_LABELS = ["Easy", "Normal", "Hard"]

func _ready() -> void:
	bp_manager = BlueprintManagerScript.new()
	add_child(bp_manager)

	FACTIONS = ["auto"]
	FACTION_LABELS = ["Auto (from roster)"]
	for fac_id in FactionCatalog.get_ids():
		FACTIONS.append(fac_id)
		FACTION_LABELS.append("%s - %s" % [FactionCatalog.get_faction_name(fac_id), FactionCatalog.get_passive(fac_id, "passive_summary", "")])

	# Also picks up MOUSE_FILTER_IGNORE, which this hand-rolled version was
	# missing - a full-rect ColorRect with the default PASS filter sits under
	# every control on the screen and eats clicks aimed past it.
	UIShell.backdrop(self)

	# Canonical screen frame. Was 48/48/36/36, none of them spacing tokens.
	var frame := UIShell.screen_frame(self)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", Tokens.SPACE_MD)
	frame.add_child(vbox)

	# Header
	var title = Label.new()
	title.text = "OPERATIONS CAMPAIGN SETUP"
	title.theme_type_variation = "DisplayLabel"
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Fight through a 3-stage operation. After each battle, inspect the After-Action Report and return to the Design Lab to adapt your roster."
	subtitle.theme_type_variation = "HintLabel"
	vbox.add_child(subtitle)

	# Main content HBox
	var content_hbox = HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", Tokens.SPACE_XL)
	vbox.add_child(content_hbox)

	# Left Column: Campaign Options & Itinerary
	var left_col = VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_stretch_ratio = 1.0
	left_col.add_theme_constant_override("separation", Tokens.SPACE_MD)
	content_hbox.add_child(left_col)

	var settings_heading = Label.new()
	settings_heading.text = "CAMPAIGN SETTINGS"
	settings_heading.theme_type_variation = "HeadingLabel"
	left_col.add_child(settings_heading)

	# Difficulty selection
	var diff_box = HBoxContainer.new()
	var diff_label = Label.new()
	diff_label.text = "AI Difficulty:"
	diff_label.custom_minimum_size.x = Tokens.SPACE_XL * 4
	diff_box.add_child(diff_label)
	difficulty_btn = OptionButton.new()
	for d in DIFFICULTY_LABELS:
		difficulty_btn.add_item(d)
	difficulty_btn.selected = 1 # Normal
	difficulty_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diff_box.add_child(difficulty_btn)
	left_col.add_child(diff_box)

	# Faction selection
	var fac_box = HBoxContainer.new()
	var fac_label = Label.new()
	fac_label.text = "Player Faction:"
	fac_label.custom_minimum_size.x = Tokens.SPACE_XL * 4
	fac_box.add_child(fac_label)
	player_faction_btn = OptionButton.new()
	for fl in FACTION_LABELS:
		player_faction_btn.add_item(fl)
	player_faction_btn.selected = 0
	player_faction_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fac_box.add_child(player_faction_btn)
	left_col.add_child(fac_box)

	left_col.add_child(HSeparator.new())

	# Itinerary Display
	var itin_heading = Label.new()
	itin_heading.text = "OPERATION ITINERARY (3 STAGES)"
	itin_heading.theme_type_variation = "HeadingLabel"
	left_col.add_child(itin_heading)

	var ops_mgr = OperationsManager.new()
	var itinerary = ops_mgr.stages_itinerary
	ops_mgr.queue_free()

	for i in range(itinerary.size()):
		var st = itinerary[i]
		var card = PanelContainer.new()
		card.theme_type_variation = "InsetPanel"
		var card_vbox = VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", Tokens.SPACE_XS)

		var st_title = Label.new()
		st_title.text = "%s — Map: %s" % [st.get("title", ""), st.get("map_id", "").replace("_", " ").capitalize()]
		st_title.theme_type_variation = "HeadingLabel"
		card_vbox.add_child(st_title)

		var map_info = MapCatalog.get_map(st.get("map_id", ""))
		var st_desc = Label.new()
		st_desc.text = map_info.get("description", "Standard battlefield.")
		st_desc.theme_type_variation = "HintLabel"
		card_vbox.add_child(st_desc)

		card.add_child(card_vbox)
		left_col.add_child(card)

	# Right Column: Roster Selection
	var right_col = VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_stretch_ratio = 1.0
	right_col.add_theme_constant_override("separation", Tokens.SPACE_MD)
	content_hbox.add_child(right_col)

	var roster_heading = Label.new()
	roster_heading.text = "DECK ROSTER (STARTING DESIGNS)"
	roster_heading.theme_type_variation = "HeadingLabel"
	right_col.add_child(roster_heading)

	selection_counter_label = Label.new()
	selection_counter_label.theme_type_variation = "HintLabel"
	right_col.add_child(selection_counter_label)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_child(scroll)

	var bp_list_vbox = VBoxContainer.new()
	bp_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(bp_list_vbox)

	_populate_blueprints(bp_list_vbox)

	# Bottom Action Bar
	var bottom_bar = HBoxContainer.new()
	bottom_bar.add_theme_constant_override("separation", Tokens.SPACE_MD)
	vbox.add_child(bottom_bar)

	var back_btn = Button.new()
	back_btn.text = "< Back to Main Menu"
	back_btn.custom_minimum_size = Vector2(180, 44)
	back_btn.pressed.connect(_return_to_menu)
	bottom_bar.add_child(back_btn)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_child(spacer)

	var start_btn = Button.new()
	start_btn.text = "Begin Operation >"
	start_btn.theme_type_variation = "PrimaryButton"
	start_btn.custom_minimum_size = Vector2(220, 44)
	start_btn.pressed.connect(_on_start_operation_pressed)
	bottom_bar.add_child(start_btn)

	# Roles matter here: "Begin Operation" commits to a campaign, so it gets the
	# radio acknowledgement rather than a click. wire_tree covers the dropdowns and
	# the roster checkboxes in one pass.
	UIFeedbackScript.wire(start_btn, "confirm")
	UIFeedbackScript.wire(back_btn)
	UIFeedbackScript.wire_tree(content_hbox, "select")

	# The itinerary cards and the roster list both arrive as a sweep rather than
	# all at once. Deferred: stagger_in reads each child's position, which is not
	# final until the containers have laid out.
	call_deferred("_animate_entrance", left_col, bp_list_vbox)

func _animate_entrance(itinerary_col: Control, roster_list: Control) -> void:
	if is_instance_valid(itinerary_col):
		UIAnimScript.stagger_in(itinerary_col)
	if is_instance_valid(roster_list):
		UIAnimScript.stagger_in(roster_list)


func _populate_blueprints(container: Control) -> void:
	blueprint_checks.clear()
	var blueprints: Array = bp_manager.list_blueprints(true)

	if blueprints.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No saved blueprints found in your library.\nDefault loadout will be used."
		empty_lbl.theme_type_variation = "HintLabel"
		container.add_child(empty_lbl)
		_update_counter()
		return

	for bp in blueprints:
		var cb = CheckBox.new()
		cb.text = "%s (%s)" % [bp.get("name", "Unnamed"), bp.get("hull_type", "").replace("_", " ").capitalize()]
		cb.button_pressed = true
		cb.toggled.connect(func(_val): _update_counter())
		container.add_child(cb)
		blueprint_checks.append({"bp": bp, "cb": cb})

	_update_counter()

func _update_counter() -> void:
	var count = 0
	for item in blueprint_checks:
		if item.cb.button_pressed:
			count += 1
	selection_counter_label.text = "Selected Blueprints: %d / %d" % [count, blueprint_checks.size()]

func _on_start_operation_pressed() -> void:
	var sel_diff = DIFFICULTIES[difficulty_btn.selected]
	var sel_fac = FACTIONS[player_faction_btn.selected]

	# Configure Operation in singleton
	var ops_node = get_node_or_null("/root/OperationsManager")
	if not ops_node:
		ops_node = load("res://scripts/operations_manager.gd").new()
		ops_node.name = "OperationsManager"
		get_tree().root.add_child(ops_node)

	ops_node.start_new_operation([], sel_diff)

	# Set match config for Stage 1
	var stage_1 = ops_node.get_current_stage_info()
	var match_config = get_node_or_null("/root/MatchConfig")
	if match_config:
		match_config.selected_map_id = stage_1.get("map_id", "open_plains")
		match_config.ai_difficulty = sel_diff
		if sel_fac != "auto":
			match_config.player_faction = sel_fac

		# Collect checked blueprints
		var chosen_paths = []
		for item in blueprint_checks:
			if item.cb.button_pressed and "bp" in item and "path" in item.bp:
				chosen_paths.append(item.bp.path)
		if not chosen_paths.is_empty():
			match_config.selected_blueprint_paths = chosen_paths

	var router = get_node_or_null("/root/SceneRouter")
	if router:
		router.goto("res://scenes/Skirmish.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Skirmish.tscn")


# Routed through SceneRouter so leaving this screen fades out rather than cutting.
# The get_node_or_null guard keeps the direct call as a fallback, matching the
# pattern the other router call sites in this file already use - a scene
# instantiated outside the running game (a test fixture) has no autoloads.
func _return_to_menu() -> void:
	var router = get_node_or_null("/root/SceneRouter")
	if router:
		router.goto("res://scenes/MainMenu.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
