extends Control
# Title screen.
#
# REBUILT, not restyled. The original version was a 480x520 PanelContainer
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
# COLOUR AND TYPE COME FROM THE THEME, NOT FROM HERE. An earlier pass repainted
# this screen as a green-phosphor CRT terminal - a Color(0.2, 1.0, 0.5) title,
# a green ticker, and a hand-rolled StyleBoxFlat on every single control in the
# file. Two problems with that, and the second is the one that mattered:
#
#   1. That palette appears nowhere in ui_tokens.gd, whose header argues at
#      length for a WARM neutral base precisely because the cool sci-fi default
#      fights the warm aluminium/olive the units and terrain commit to. Green
#      terminal is also the single most over-used "military interface"
#      shorthand there is; the tokens' powdercoat is both more specific and
#      more period-correct.
#   2. Local overrides beat the theme. Every inline stylebox here was actively
#      preventing the design system from reaching this screen - the exact
#      failure mode ui_tokens.gd was created to end, recurring.
#
# So: no add_theme_color_override for anything the theme already answers, and
# no StyleBoxFlat in this file at all. Signal colours are read from Tokens.
#
# TONE. The interface plays it completely straight - see blueprint_namer.gd for
# the rule stated in full. The joke is structural: a procurement console
# reporting on whatever ludicrous contraption the player welded together, with
# total bureaucratic indifference. Nothing here winks. That means no emoji, no
# stars, no decorative glyphs, and copy in the register of equipment
# documentation rather than of a game menu.
#
# The wordmark is read from a single constant because the title is a working
# one and expected to change - see TITLE below.

const UITheme = preload("res://scripts/ui_theme.gd")
const UIShell = preload("res://scripts/ui_shell.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")
const DamageResolverScript = preload("res://scripts/damage_resolver.gd")

# Working title. Deliberately one constant rather than a literal scattered
# across screens, because this is expected to change and a rename shouldn't
# be a search-and-replace across the UI.
const TITLE := "KITBASH COMMAND"
const TAGLINE := "Design bureau and proving ground"

# The roster cap the status column reports against. Pulled out because it
# appears in a player-facing "n / N" readout and a silent drift between this
# and the real cap would read as a bug.
const ROSTER_CAP := 15

# Destinations, in the order a player meets them. Description lines state what
# the screen DOES in plain equipment language - no feature-marketing ("live
# vector telemetry"), which is both a lie about the tone and a lie about the
# build.
const DESTINATIONS := [
	{
		"title": "DESIGN LAB",
		"desc": "Assemble blueprints from hulls, modules and drives.",
		"scene": "res://scenes/MainLab.tscn",
	},
	{
		"title": "HULL AUTHORING",
		"desc": "Shape new hull forms from primitives.",
		"scene": "res://scenes/HullBuilder.tscn",
	},
	{
		"title": "OPERATIONS",
		"desc": "Multi-stage campaign with after-action reports.",
		"scene": "res://scenes/OperationsSetup.tscn",
	},
	{
		"title": "SKIRMISH",
		"desc": "Select a map and a roster, then engage enemy forces.",
		"scene": "res://scenes/MatchSetup.tscn",
	},
	{
		"title": "PROVING GROUND",
		"desc": "Field the current design against target dummies.",
		"scene": "res://scenes/Battlefield.tscn",
	},
]


func _ready() -> void:
	# The sheet-metal plate, not a flat fill. apply_backdrop() also keeps the
	# shader's panel_size uniform in sync with the node through `resized`,
	# which is what keeps the grain a fixed physical size at every window
	# size - see its comment for why that is not optional.
	var backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	UITheme.apply_backdrop(backdrop)

	var frame = MarginContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_constant_override("margin_left", Tokens.SPACE_XL + Tokens.SPACE_LG)
	frame.add_theme_constant_override("margin_right", Tokens.SPACE_XL + Tokens.SPACE_LG)
	frame.add_theme_constant_override("margin_top", Tokens.SPACE_XL)
	frame.add_theme_constant_override("margin_bottom", Tokens.SPACE_LG)
	add_child(frame)

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", Tokens.SPACE_LG)
	frame.add_child(root_vbox)

	_build_console_bar(root_vbox)

	var columns = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", Tokens.SPACE_XL)
	root_vbox.add_child(columns)

	_build_left_column(columns)
	_build_status_column(columns)


# A thin identification band across the top. This is the screen's one piece of
# pure flavour, and it earns its place by being utterly mundane - a console
# number and a shift, the sort of thing stencilled on a real panel. The
# previous "CLASSIFIED WAR ROOM TERMINAL // FREQ 142.9 MHz" was straining; a
# console that announces its own drama is the interface winking.
func _build_console_bar(parent: Control) -> void:
	var bar = PanelContainer.new()
	bar.theme_type_variation = "HeaderPanel"
	parent.add_child(bar)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", Tokens.SPACE_MD)
	bar.add_child(hbox)

	var ident = Label.new()
	ident.text = "DESIGN BUREAU / CONSOLE 4"
	ident.theme_type_variation = "HintLabel"
	hbox.add_child(ident)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var notice = Label.new()
	notice.text = "ALL DESIGNS SUBJECT TO FIELD TEST PRIOR TO ISSUE"
	notice.theme_type_variation = "HintLabel"
	hbox.add_child(notice)


func _build_left_column(parent: Control) -> void:
	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 0.9
	col.add_theme_constant_override("separation", Tokens.SPACE_XS)
	parent.add_child(col)

	# DisplayLabel is the stencil face at FONT_DISPLAY. That is the one place
	# the stencil earns its keep - large, short, carrying the tone alone. See
	# build_ui_theme.gd's note on why it is emphatically not the body font.
	var title = Label.new()
	title.text = TITLE
	title.theme_type_variation = "DisplayLabel"
	col.add_child(title)

	var tagline = Label.new()
	tagline.text = TAGLINE
	tagline.theme_type_variation = "HintLabel"
	col.add_child(tagline)

	var gap_top = Control.new()
	gap_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(gap_top)

	var nav = VBoxContainer.new()
	nav.add_theme_constant_override("separation", Tokens.SPACE_XS)
	col.add_child(nav)

	for dest in DESTINATIONS:
		_add_destination(nav, dest["title"], dest["desc"], dest["scene"])

	var gap_bottom = Control.new()
	gap_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap_bottom.size_flags_stretch_ratio = 1.2
	col.add_child(gap_bottom)

	# Plain, small, and last. Quit is not a hazard and does not need a red
	# machined bezel - reserving SIGNAL_ALERT for things that are actually
	# destructive is the whole point of having a signal palette.
	var quit_btn = Button.new()
	quit_btn.text = "QUIT"
	quit_btn.custom_minimum_size = Vector2(140, Tokens.HIT_TARGET_MIN)
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	quit_btn.pressed.connect(func(): get_tree().quit())
	col.add_child(quit_btn)


# A destination row: title over description, inside one large hit target.
#
# ListButton rather than Button - flat and borderless at rest so five of these
# read as a list of places to go rather than as five stacked slabs, gaining a
# hazard left edge on hover/selection. The description sits inside the button
# so the whole row is clickable, with mouse_filter IGNORE on the labels so
# they don't eat the button's own hover.
func _add_destination(parent: Control, title_text: String, description: String, scene_path: String) -> void:
	var btn = Button.new()
	btn.theme_type_variation = "ListButton"
	btn.custom_minimum_size = Vector2(0, 52)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(btn)

	var stack = VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 0)
	# The button's own content margin is horizontal padding for its (empty)
	# text; the anchored stack ignores it, so it gets its own.
	stack.offset_left = Tokens.SPACE_MD
	stack.offset_right = -Tokens.SPACE_MD
	btn.add_child(stack)

	var name_label = Label.new()
	name_label.text = title_text
	name_label.theme_type_variation = "HeadingLabel"
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


# The right column is a SPECIFICATION PLACARD for the player's most recent
# design, not a menu. This is the screen's thesis in one panel: whatever
# ridiculous thing the player built last is presented here as certified
# hardware - stencilled designation, hull class, affiliation, mass - with the
# format taking it completely seriously. The comedy is entirely structural.
func _build_status_column(parent: Control) -> void:
	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.1
	col.add_theme_constant_override("separation", Tokens.SPACE_SM)
	parent.add_child(col)

	var heading = Label.new()
	heading.text = "CURRENT STATUS"
	heading.theme_type_variation = "HeadingLabel"
	col.add_child(heading)

	var panel = PanelContainer.new()
	panel.theme_type_variation = "CardPanel"
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

	# UIShell.stat_row() puts the value on the monospace face, which is what
	# makes a column of these line up. Hand-rolling label pairs here was how
	# the previous version ended up with six different font sizes.
	UIShell.stat_row(body, "Designs ready to field", "%d / %d" % [roster.size(), ROSTER_CAP])
	UIShell.stat_row(body, "Designs in library", str(all.size()))

	body.add_child(HSeparator.new())

	if roster.is_empty():
		var empty = Label.new()
		empty.text = "No designs registered. Open the Design Lab to author one."
		empty.theme_type_variation = "HintLabel"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(empty)
		return

	var most_recent = Label.new()
	most_recent.text = "MOST RECENT"
	most_recent.theme_type_variation = "HintLabel"
	body.add_child(most_recent)

	var latest: Dictionary = roster[0]

	# The designation gets the stencil face at title size. A "GoatHauler Mk VI"
	# rendered as though it came off a procurement form is the joke, and it
	# only works if the rendering is entirely sincere.
	var name_label = Label.new()
	name_label.text = str(latest.get("name", "")).to_upper()
	name_label.theme_type_variation = "TitleLabel"
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(name_label)

	UIShell.stat_row(body, "Hull class", _prettify(str(latest.get("hull_type", ""))))
	UIShell.stat_row(body, "Affiliation", _prettify(str(latest.get("faction", ""))))
	_add_spec_placard(body, mgr, latest)

	if roster.size() <= 1:
		return

	body.add_child(HSeparator.new())

	var also = Label.new()
	also.text = "ALSO READY"
	also.theme_type_variation = "HintLabel"
	body.add_child(also)

	for entry in roster.slice(1, mini(5, roster.size())):
		UIShell.stat_row(body,
			str(entry.get("name", "")).to_upper(),
			_prettify(str(entry.get("hull_type", ""))))


# Mass, armour spec and the threshold table for the most recent design.
#
# VISUAL/UI plan item 9: "Presenting a 'GoatHauler Mk VI' on a spec placard with
# total deadpan is the thesis of the whole interface in one panel." The status
# column already carried the designation, hull class and affiliation; what was
# missing was the part that makes it read as a certification rather than a save
# slot - a mass figure and the armour thresholds the thing will actually be shot
# at with.
#
# list_blueprints() returns a SUMMARY (id/name/hull_type/faction/path), so the
# armour fields need the full record. That is one extra file read for one entry,
# not for the whole library - the roster loop below deliberately stays on the
# summary.
func _add_spec_placard(body: VBoxContainer, mgr: Node, latest: Dictionary) -> void:
	var path := str(latest.get("path", ""))
	if path == "":
		return
	var full: Dictionary = mgr.load_blueprint(path)
	if full.is_empty():
		return

	# Hull volume x thickness is not the real mass model - stat_calculator.gd owns
	# that, and it needs a reconstructed hull to compute it. Reporting the
	# authored hull envelope instead is honest about what a title screen can know
	# without rebuilding the vehicle: it is a DIMENSION line on a spec sheet, and
	# it is labelled as one rather than as a mass the game would disagree with.
	var hs: Dictionary = full.get("hull_size", {})
	if hs.has("x"):
		UIShell.stat_row(body, "Envelope", "%.1f x %.1f x %.1f m" % [
			float(hs.get("x", 0.0)), float(hs.get("y", 0.0)), float(hs.get("z", 0.0))])

	var module_count: int = (full.get("modules", []) as Array).size()
	UIShell.stat_row(body, "Fitted modules", str(module_count))

	var material := str(full.get("armor_material", "hardened_steel"))
	var thickness := float(full.get("armor_thickness", 1.0))
	UIShell.stat_row(body, "Armour", "%s, %.1fx" % [_prettify(material), thickness])

	# The threshold table, read from the same DamageResolver the combat model uses
	# - not a second copy of those numbers living on the title screen.
	var k: Vector2 = DamageResolverScript.get_material_threshold(material, "kinetic", thickness)
	var t: Vector2 = DamageResolverScript.get_material_threshold(material, "thermal", thickness)
	var e: Vector2 = DamageResolverScript.get_material_threshold(material, "explosive", thickness)
	var table = Label.new()
	table.text = "THRESHOLD  K %.1f / T %.1f / E %.1f" % [k.x, t.x, e.x]
	table.theme_type_variation = "StatLabel"
	body.add_child(table)


func _prettify(id: String) -> String:
	if id == "":
		return "-"
	return id.replace("_", " ").capitalize()
