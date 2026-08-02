extends Control
# Title screen.
#
# REBUILT, not restyled. The previous version was a 480x520 PanelContainer
# centred in a 1600x900 frame holding five identical stacked buttons - the
# stock main-menu shape, and the thing that made the whole interface read as
# dated no matter what colours went on it. Restyling it could not fix it,
# because the layout itself was the problem.
#
# What this does instead:
#   * FULL-BLEED, asymmetric. A heavy left column carries the wordmark and
#     the destinations; the right column is given over to the player's own
#     work. Nothing floats in the middle of an empty screen.
#   * CONTENT-FORWARD. The right column shows the most recent design, the
#     roster count and what the game will actually field if you hit deploy.
#     A title screen that only lists destinations tells the player nothing;
#     this one answers "where was I?" before they click anything.
#   * DESTINATIONS CARRY THEIR OWN DESCRIPTION. Each entry is a title plus a
#     line of plain text, so the menu is self-explaining rather than relying
#     on a tooltip the player has to hover to discover.
#
# The wordmark is read from a single constant because the title is a working
# one and expected to change - see TITLE below.

const UITheme = preload("res://scripts/ui_theme.gd")
const UIShell = preload("res://scripts/ui_shell.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")

# Working title. Deliberately one constant rather than a literal scattered
# across screens, because this is expected to change and a rename shouldn't
# be a search-and-replace across the UI.
const TITLE := "BUILD-A-BOMBER"
const TAGLINE := "Design bureau and proving ground"

func _ready() -> void:
	# Deep obsidian backdrop
	var backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.07, 0.05) # Emerald-black CRT substrate
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var frame = MarginContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_constant_override("margin_left", 48)
	frame.add_theme_constant_override("margin_right", 48)
	frame.add_theme_constant_override("margin_top", 32)
	frame.add_theme_constant_override("margin_bottom", 32)
	add_child(frame)

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 16)
	frame.add_child(root_vbox)

	_build_top_intelligence_bar(root_vbox)

	var columns = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 32)
	root_vbox.add_child(columns)

	_build_left_column(columns)
	_build_status_column(columns)

func _build_top_intelligence_bar(parent: Control) -> void:
	var bar_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.12, 0.06, 0.9)
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_color = Color(0.0, 0.9, 0.4, 0.8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	bar_panel.add_theme_stylebox_override("panel", style)
	parent.add_child(bar_panel)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	bar_panel.add_child(hbox)

	var sec_tag = Label.new()
	sec_tag.text = "● CLASSIFIED WAR ROOM TERMINAL // FREQ 142.9 MHz"
	sec_tag.add_theme_font_size_override("font_size", 13)
	sec_tag.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))
	hbox.add_child(sec_tag)

	var ticker = Label.new()
	ticker.text = " | INTEL: TECHNOCRATS FIELDING HEAVY GAUSS VEHICLES -- ALL SECTORS ON HIGH ALERT"
	ticker.add_theme_font_size_override("font_size", 12)
	ticker.add_theme_color_override("font_color", Color(0.0, 0.75, 0.35, 0.85))
	ticker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(ticker)

func _build_left_column(parent: Control) -> void:
	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 0.9
	col.add_theme_constant_override("separation", Tokens.SPACE_SM)
	parent.add_child(col)

	var title = Label.new()
	title.text = "★ " + TITLE + " ★"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.3, 0.1))
	title.add_theme_constant_override("outline_size", 4)
	col.add_child(title)

	var tagline = Label.new()
	tagline.text = "DEFENSE BUREAU & PROVING GROUND CONSOLE"
	tagline.add_theme_font_size_override("font_size", 13)
	tagline.add_theme_color_override("font_color", Color(0.0, 0.7, 0.35))
	col.add_child(tagline)

	var gap_top = Control.new()
	gap_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(gap_top)

	var nav = VBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	col.add_child(nav)

	var gap_bottom = Control.new()
	gap_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap_bottom.size_flags_stretch_ratio = 1.2
	col.add_child(gap_bottom)

	_add_destination(nav, "⚔️ SKIRMISH DEPLOYMENT", "Pick a map, select custom rosters, and engage enemy AI.", "res://scenes/MatchSetup.tscn")
	_add_destination(nav, "🔧 DESIGN LAB WORKBENCH", "Build and tweak custom vehicles with real 3D mesh ghosts & live vector telemetry.", "res://scenes/MainLab.tscn")
	_add_destination(nav, "🗺️ OPERATION THEATER", "Multi-stage campaign with after-action debriefing reports.", "res://scenes/OperationsSetup.tscn")
	_add_destination(nav, "🎯 WEAPONS PROVING GROUND", "Test current design in arena against target dummies.", "res://scenes/Battlefield.tscn")
	_add_destination(nav, "🛠️ HULL AUTHORING STUDIO", "Shape custom hull primitives for your fleet.", "res://scenes/HullBuilder.tscn")

	var quit_btn = Button.new()
	quit_btn.text = "PWR OFF / QUIT"
	var q_style = StyleBoxFlat.new()
	q_style.bg_color = Color(0.2, 0.05, 0.05, 0.9)
	q_style.border_width_left = 3
	q_style.border_width_right = 3
	q_style.border_width_top = 3
	q_style.border_width_bottom = 3
	q_style.border_color = Color(0.9, 0.2, 0.2)
	q_style.corner_radius_top_left = 4
	q_style.corner_radius_top_right = 4
	q_style.corner_radius_bottom_left = 4
	q_style.corner_radius_bottom_right = 4
	q_style.content_margin_left = 16
	q_style.content_margin_right = 16
	q_style.content_margin_top = 8
	q_style.content_margin_bottom = 8
	quit_btn.add_theme_stylebox_override("normal", q_style)
	quit_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	quit_btn.custom_minimum_size = Vector2(140, 36)
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	quit_btn.pressed.connect(func(): get_tree().quit())
	col.add_child(quit_btn)

# Chunky Bakelite & Brass Button for destinations
func _add_destination(parent: Control, title_text: String, description: String, scene_path: String) -> void:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(0, 58)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.06, 0.16, 0.09, 0.95)
	normal_style.border_width_left = 4
	normal_style.border_color = Color(0.0, 0.85, 0.4)
	normal_style.corner_radius_top_left = 4
	normal_style.corner_radius_top_right = 4
	normal_style.corner_radius_bottom_left = 4
	normal_style.corner_radius_bottom_right = 4
	normal_style.content_margin_left = 14
	normal_style.content_margin_right = 14
	normal_style.content_margin_top = 6
	normal_style.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style = normal_style.duplicate()
	hover_style.bg_color = Color(0.08, 0.24, 0.12, 0.98)
	hover_style.border_color = Color(0.3, 1.0, 0.5)
	btn.add_theme_stylebox_override("hover", hover_style)

	parent.add_child(btn)

	var stack = VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 2)
	btn.add_child(stack)

	var name_label = Label.new()
	name_label.text = title_text
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(name_label)

	var desc_label = Label.new()
	desc_label.text = description
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.add_theme_color_override("font_color", Color(0.0, 0.7, 0.35))
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(desc_label)

	btn.pressed.connect(func():
		var audio = get_node_or_null("/root/AudioManager")
		if audio:
			audio.play_sfx("click")
		get_tree().change_scene_to_file(scene_path))
	btn.mouse_entered.connect(func():
		var audio = get_node_or_null("/root/AudioManager")
		if audio:
			audio.play_sfx("hover"))

func _build_status_column(parent: Control) -> void:
	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.1
	col.add_theme_constant_override("separation", Tokens.SPACE_SM)
	parent.add_child(col)

	var heading = Label.new()
	heading.text = "FLEET ROSTER & INTEL DOSSIER"
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))
	col.add_child(heading)

	var panel = PanelContainer.new()
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.12, 0.07, 0.95)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.0, 0.7, 0.35)
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(panel)

	var body = VBoxContainer.new()
	body.add_theme_constant_override("separation", Tokens.SPACE_SM)
	panel.add_child(body)

	var mgr = Node.new()
	mgr.set_script(BlueprintManagerScript)
	add_child(mgr)

	var roster: Array = mgr.list_blueprints(true)
	var all: Array = mgr.list_blueprints(false)

	_vector_stat_row(body, "Combat Blueprints Ready", str(roster.size()) + " / 15")
	_vector_stat_row(body, "Total Archive Designs", str(all.size()))

	body.add_child(HSeparator.new())

	if roster.is_empty():
		var empty = Label.new()
		empty.text = "NO COMBAT BLUEPRINTS REGISTERED.\n\nEnter the Design Lab Workbench to author your first unit."
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color(0.0, 0.65, 0.35))
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		body.add_child(empty)
	else:
		var latest_label = Label.new()
		latest_label.text = "★ FLAGSHIP UNIT DOSSIER"
		latest_label.add_theme_font_size_override("font_size", 13)
		latest_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))
		body.add_child(latest_label)

		var latest: Dictionary = roster[0]
		var name_label = Label.new()
		name_label.text = str(latest.get("name", "")).to_upper()
		name_label.add_theme_font_size_override("font_size", 22)
		name_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		body.add_child(name_label)

		_vector_stat_row(body, "Hull Class", _prettify(str(latest.get("hull_type", ""))))
		_vector_stat_row(body, "Affiliation", _prettify(str(latest.get("faction", ""))))

		if roster.size() > 1:
			body.add_child(HSeparator.new())
			var also = Label.new()
			also.text = "REGISTERED FLEET BLUEPRINTS"
			also.add_theme_font_size_override("font_size", 12)
			also.add_theme_color_override("font_color", Color(0.0, 0.75, 0.35))
			body.add_child(also)
			for entry in roster.slice(1, mini(5, roster.size())):
				var row = Label.new()
				row.text = "• %s  [%s]" % [str(entry.get("name", "")).to_upper(), _prettify(str(entry.get("hull_type", "")))]
				row.add_theme_font_size_override("font_size", 12)
				row.add_theme_color_override("font_color", Color(0.2, 0.9, 0.5))
				row.autowrap_mode = TextServer.AUTOWRAP_WORD
				body.add_child(row)

func _vector_stat_row(parent: Control, key: String, val: String) -> void:
	var row = HBoxContainer.new()
	var l_key = Label.new()
	l_key.text = key
	l_key.add_theme_font_size_override("font_size", 12)
	l_key.add_theme_color_override("font_color", Color(0.0, 0.7, 0.35))
	l_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l_key)

	var l_val = Label.new()
	l_val.text = val
	l_val.add_theme_font_size_override("font_size", 12)
	l_val.add_theme_color_override("font_color", Color(0.3, 1.0, 0.6))
	row.add_child(l_val)
	parent.add_child(row)

func _prettify(id: String) -> String:
	if id == "":
		return "-"
	return id.replace("_", " ").capitalize()
