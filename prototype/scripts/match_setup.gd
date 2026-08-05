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
const Tokens = preload("res://scripts/ui_tokens.gd")
const MapCatalog = preload("res://scripts/map_catalog.gd")
const RosterPickerScript = preload("res://scripts/roster_picker.gd")

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
var bp_manager: Node
var roster_picker: RosterPicker

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
	# Steel backdrop, applied once at build time. Faction-independent, so unlike
	# the old _refresh_theme() this never needs re-running.
	#
	# Deliberately NOT plain apply_backdrop(): this screen wants a smoother and
	# lighter surface than the standard 0.42-brightness backdrop. Still steel, so
	# the material vocabulary is unchanged - only its finish is.
	#
	#   brightness 0.56  lighter. This screen can afford it because it carries no
	#                    powdercoat panels: the only things needing separation
	#                    from the backdrop are controls (bakelite, ~0.145) and
	#                    text, so the usual "hold the backdrop well below panel
	#                    luminance" constraint has slack here. Lands near 0.115.
	#   wear  0.05       the scuffed bright patches are the least smooth thing in
	#   grime 0.06       the shader; both masks are broad blotches that read as
	#                    dirt on a settings screen rather than as finish.
	#   scale 2.4        zooms the brush grain so it reads as a soft sheen rather
	#                    than as visible directional streaking (field_uv divides
	#                    by 512 * scale, so a larger scale means larger, softer
	#                    features - see ui_material.gdshader).
	#   vignette 0.16    flatter corner falloff, so the field reads even.
	UITheme.apply_material(bg_rect, "steel", {
		"brightness": 0.56,
		"wear": 0.05,
		"grime": 0.06,
		"scale": 2.4,
		"vignette": 0.16,
	})

	var root_vbox = VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.offset_top = 24
	root_vbox.offset_bottom = -24
	root_vbox.offset_left = 160
	root_vbox.offset_right = -160
	root_vbox.add_theme_constant_override("separation", Tokens.SPACE_SM)
	add_child(root_vbox)

	var title = Label.new()
	title.text = "MATCH SETTINGS"
	# TitleLabel is the registered screen-title variation: 24px stencil in
	# TEXT_PRIMARY. Deliberately smaller than the 34px it used to be - 34 is not
	# a step on the type scale, and the ad-hoc amber modulate it carried was a
	# near-miss on SIGNAL_HAZARD that spent an attention colour on decoration.
	# Amber has one job (attention required), and a screen title is not it.
	title.theme_type_variation = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(title)
	root_vbox.add_child(HSeparator.new())

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", Tokens.SPACE_LG)
	grid.add_theme_constant_override("v_separation", Tokens.SPACE_MD)
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
	# There used to be a _refresh_theme() re-theme wired to this dropdown, on the
	# premise that the screen's chrome repainted in the player's faction colour.
	# That premise is gone: UI chrome deliberately stopped being faction-tinted,
	# because faction colour's real job is telling the player who owns a unit on
	# the battlefield and repainting the menus in it collided with that. The
	# backdrop is now the same steel for every faction, so there is nothing left
	# to refresh and no handler to connect.
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
	library_label.text = "Drag designs into a roster slot (leave the roster empty to auto-include your newest designs)"
	library_label.theme_type_variation = "HintLabel"
	library_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(library_label)

	# named_only: this is the "what goes into the match" list, so it shows
	# only designs the player deliberately saved under a name. Unnamed
	# leftovers from testing stay in the Blueprint Library where they can be
	# renamed or deleted.
	var entries = bp_manager.list_blueprints(true)

	# Replaces a flat CheckBox list. See roster_picker.gd's header for why: the
	# checkbox version could express neither the ORDER designs are fielded in nor
	# the roster cap as anything more than a warning string. Its output contract
	# is identical - an ordered Array of blueprint paths - so _on_start_pressed()
	# below is unchanged apart from where it reads that array from.
	roster_picker = RosterPickerScript.new()
	roster_picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(roster_picker)
	roster_picker.setup(entries, ROSTER_CAP)

	root_vbox.add_child(HSeparator.new())

	var button_row = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", Tokens.SPACE_LG)
	root_vbox.add_child(button_row)

	var back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(200, 48)
	# Back now returns to the main menu, not to MapSelect - map choice is a
	# column on this screen, so there is no intermediate screen to go back to.
	back_btn.pressed.connect(_return_to_menu)
	button_row.add_child(back_btn)

	var start_btn = Button.new()
	start_btn.text = "Start Match"
	start_btn.custom_minimum_size = Vector2(240, 48)
	# PrimaryButton is carbon tinted toward SIGNAL_GO - the one primary action a
	# screen is allowed, which this is. The 0.5/1.0/0.5 modulate it replaces was
	# a saturated web green nowhere in the palette; SIGNAL_GO is a deliberately
	# desaturated olive so it reads as "ready" without competing with the units.
	start_btn.theme_type_variation = "PrimaryButton"
	start_btn.pressed.connect(_on_start_pressed)
	button_row.add_child(start_btn)

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

# _update_selection_counter() lived here. The whole function - the count, the
# over-cap HAZARD message, and the loop disabling unchecked boxes once the cap
# was hit - existed to compensate for a list that could not represent the cap.
# The slot grid represents it structurally: there are exactly ROSTER_CAP wells
# and no way to fill a thirteenth, so there is no over-cap state left to warn
# about. RosterPicker keeps its own "n / 12 slots filled" readout.

# _prettify() moved to RosterPicker.prettify() along with its only caller - the
# blueprint row that became a roster card.

func _on_start_pressed():
	var match_config = get_node_or_null("/root/MatchConfig")
	if match_config:
		match_config.player_faction = "" if FACTIONS[player_faction_btn.selected] == "auto" else FACTIONS[player_faction_btn.selected]
		match_config.enemy_faction = "" if FACTIONS[enemy_faction_btn.selected] == "auto" else FACTIONS[enemy_faction_btn.selected]
		match_config.ai_difficulty = DIFFICULTIES[difficulty_btn.selected]
		var preset: Vector2i = RESOURCE_PRESETS[resources_btn.selected]
		match_config.starting_metal = preset.x
		match_config.starting_crystal = preset.y
		# Slot order, left to right and top to bottom, gaps skipped. Under the old
		# checkbox list this was library sort order, which meant which designs
		# survived skirmish.gd's roster.slice(0, 12) was effectively incidental.
		match_config.selected_blueprint_paths = roster_picker.ordered_paths() if roster_picker else []

	# Routed through SceneRouter rather than change_scene_to_file(): loading
	# Skirmish.tscn synchronously blocks the main thread for over a second,
	# during which Windows marks the window "(Not Responding)". The router
	# loads it on a worker thread behind a loading screen instead.
	var router = get_node_or_null("/root/SceneRouter")
	var map_name := ""
	if map_btn and map_btn.selected >= 0 and map_btn.selected < MAP_IDS.size():
		map_name = MapCatalog.get_map_name(MAP_IDS[map_btn.selected])
	if router:
		router.goto("res://scenes/Skirmish.tscn", map_name)
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
