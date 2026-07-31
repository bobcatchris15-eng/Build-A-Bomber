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
	var backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	UITheme.apply_backdrop(backdrop)

	var frame = MarginContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_constant_override("margin_left", 72)
	frame.add_theme_constant_override("margin_right", 72)
	frame.add_theme_constant_override("margin_top", 56)
	frame.add_theme_constant_override("margin_bottom", 40)
	add_child(frame)

	var columns = HBoxContainer.new()
	# 40px, not 64. The first pass left a ~560px void down the middle of the
	# screen: the nav column was allocated a large stretch but its content is
	# left-aligned and short, so the extra width became empty space rather
	# than anything. Full-bleed means the frame is the composition - it does
	# not mean spreading two clusters to opposite walls.
	columns.add_theme_constant_override("separation", 40)
	frame.add_child(columns)

	_build_left_column(columns)
	_build_status_column(columns)


func _build_left_column(parent: Control) -> void:
	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 0.85
	col.add_theme_constant_override("separation", Tokens.SPACE_SM)
	parent.add_child(col)

	var title = Label.new()
	title.text = TITLE
	title.theme_type_variation = "DisplayLabel"
	col.add_child(title)

	var tagline = Label.new()
	tagline.text = TAGLINE
	tagline.theme_type_variation = "HintLabel"
	col.add_child(tagline)

	# Expanding spacers above and below centre the destination list in the
	# column's remaining height. Anchoring it directly under the wordmark
	# left the bottom two-thirds of the column empty, which read as an
	# unfinished screen rather than as deliberate space.
	var gap_top = Control.new()
	gap_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(gap_top)

	var nav = VBoxContainer.new()
	nav.add_theme_constant_override("separation", Tokens.SPACE_XS)
	col.add_child(nav)

	var gap_bottom = Control.new()
	gap_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap_bottom.size_flags_stretch_ratio = 1.4
	col.add_child(gap_bottom)

	_add_destination(nav, "Design Lab", "Build and tweak blueprints from hulls and modules.",
		"res://scenes/MainLab.tscn")
	_add_destination(nav, "Hull Builder", "Author new hull shapes from primitives.",
		"res://scenes/HullBuilder.tscn")
	_add_destination(nav, "Operations", "Multi-round campaign with after-action reports and inter-round redesigns.",
		"res://scenes/OperationsSetup.tscn")
	# Routes straight to the deploy screen. Map selection used to be its own
	# screen in front of this one; it is now a column inside it, so this is
	# one step shorter than it was.
	_add_destination(nav, "Skirmish", "Pick a map, set the forces, and fight the AI.",
		"res://scenes/MatchSetup.tscn")
	_add_destination(nav, "Test Range", "Drive your current design against target dummies.",
		"res://scenes/Battlefield.tscn")

	var quit_btn = Button.new()
	quit_btn.text = "Quit"
	quit_btn.theme_type_variation = "DangerButton"
	quit_btn.custom_minimum_size = Vector2(120, Tokens.HIT_TARGET_MIN)
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	quit_btn.pressed.connect(func(): get_tree().quit())
	col.add_child(quit_btn)


# One destination: a large title with an explanatory line beneath it, both
# inside a single button so the whole block is the hit target.
func _add_destination(parent: Control, title_text: String, description: String, scene_path: String) -> void:
	var btn = Button.new()
	btn.theme_type_variation = "ListButton"
	btn.custom_minimum_size = Vector2(0, 62)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(btn)

	# Labels sit on top of the button rather than using btn.text, because a
	# Button renders a single line in a single style and this needs two.
	# MOUSE_FILTER_IGNORE keeps them from eating the button's own input.
	var rows = VBoxContainer.new()
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.add_theme_constant_override("separation", 0)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	btn.add_child(rows)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", Tokens.SPACE_MD)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(margin)

	var stack = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 1)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(stack)

	var name_label = Label.new()
	name_label.text = title_text
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(name_label)

	var desc_label = Label.new()
	desc_label.text = description
	desc_label.theme_type_variation = "HintLabel"
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


# The right column: what the player already has. This is the half of the
# screen the old menu spent on nothing.
func _build_status_column(parent: Control) -> void:
	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.15
	col.add_theme_constant_override("separation", Tokens.SPACE_SM)
	parent.add_child(col)

	var heading = Label.new()
	heading.text = "CURRENT STATUS"
	heading.theme_type_variation = "HeadingLabel"
	col.add_child(heading)

	var panel = PanelContainer.new()
	panel.theme_type_variation = "InsetPanel"
	# Fills the column's full height. Without this the panel shrank to its
	# content and left two thirds of the screen empty below it, which is the
	# same "content pooled at the top" failure as the centred card, just
	# rotated.
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(panel)

	var body = VBoxContainer.new()
	body.add_theme_constant_override("separation", Tokens.SPACE_SM)
	panel.add_child(body)

	# BlueprintManager is a scene node in MainLab, not an autoload, so it
	# has to be instanced here to read the roster. Freed with this screen.
	var mgr = Node.new()
	mgr.set_script(BlueprintManagerScript)
	add_child(mgr)

	var roster: Array = mgr.list_blueprints(true)
	var all: Array = mgr.list_blueprints(false)

	UIShell.stat_row(body, "Designs ready to field", str(roster.size()))
	UIShell.stat_row(body, "Designs in library", str(all.size()))

	body.add_child(HSeparator.new())

	if roster.is_empty():
		var empty = Label.new()
		empty.text = "No named designs yet.\n\nBuild one in the Design Lab and give it a name - a design only reaches the field once it has one."
		empty.theme_type_variation = "HintLabel"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		body.add_child(empty)
	else:
		var latest_label = Label.new()
		latest_label.text = "MOST RECENT"
		latest_label.theme_type_variation = "HintLabel"
		body.add_child(latest_label)

		var latest: Dictionary = roster[0]
		var name_label = Label.new()
		name_label.text = str(latest.get("name", ""))
		name_label.add_theme_font_size_override("font_size", 20)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		body.add_child(name_label)

		UIShell.stat_row(body, "Hull", _prettify(str(latest.get("hull_type", ""))))
		UIShell.stat_row(body, "Faction", _prettify(str(latest.get("faction", ""))))

		# Up to three more, so the panel shows a roster rather than a single
		# entry - the point is recognising your own work at a glance.
		if roster.size() > 1:
			body.add_child(HSeparator.new())
			var also = Label.new()
			also.text = "ALSO READY"
			also.theme_type_variation = "HintLabel"
			body.add_child(also)
			for entry in roster.slice(1, mini(4, roster.size())):
				var row = Label.new()
				row.text = "%s   %s" % [str(entry.get("name", "")), _prettify(str(entry.get("hull_type", "")))]
				row.theme_type_variation = "StatLabel"
				row.autowrap_mode = TextServer.AUTOWRAP_WORD
				body.add_child(row)


func _prettify(id: String) -> String:
	if id == "":
		return "-"
	return id.replace("_", " ").capitalize()
