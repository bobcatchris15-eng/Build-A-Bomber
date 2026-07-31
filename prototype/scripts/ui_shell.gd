class_name UIShell
extends RefCounted
# Layout primitives for the out-of-match screens.
#
# WHY: every shell screen used to hand-roll the same structure - a
# fullscreen ColorRect, a CenterContainer, a fixed-size PanelContainer, a
# MarginContainer, a VBoxContainer of buttons. That shape is the problem,
# not its styling. A fixed-size card floating in the middle of an empty
# frame wastes the entire screen, can't grow with content, and makes every
# decision feel like a modal you have to get past.
#
# What replaces it:
#   * FULL-BLEED. Content is anchored to the frame's edges, not pooled in
#     the middle. The screen is the layout.
#   * A PERSISTENT ACTION BAR pinned to the bottom. The primary action lives
#     in one fixed place on every screen and is always visible, instead of
#     being the last item in a scrolling column.
#   * COLUMNS, not stacks. Related choices sit side by side so they can
#     inform each other, rather than being serialised into separate screens
#     the player has to walk through and back out of.
#
# These are structural helpers only - all colour and type comes from the
# theme (tools/build_ui_theme.gd), so nothing here hardcodes appearance.

const Tokens = preload("res://scripts/ui_tokens.gd")
const UITheme = preload("res://scripts/ui_theme.gd")


# Builds the standard screen scaffold onto `root` and returns the regions
# callers fill in:
#   { "backdrop", "header", "content", "actions_left", "actions_right" }
#
# `content` is an HBoxContainer - screens lay their columns into it
# directly. Anything that wants a single column just adds one child.
static func build_screen(root: Control, title_text: String, subtitle_text: String = "") -> Dictionary:
	var backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)
	UITheme.apply_backdrop(backdrop)

	var frame = MarginContainer.new()
	frame.name = "Frame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Generous, asymmetric-friendly gutters. The old screens had 32px around
	# a 480px card on a 1600px display; the frame itself is the composition
	# now, so it gets real margins.
	for side in ["left", "right"]:
		frame.add_theme_constant_override("margin_" + side, Tokens.SPACE_XL + Tokens.SPACE_LG)
	frame.add_theme_constant_override("margin_top", Tokens.SPACE_XL)
	frame.add_theme_constant_override("margin_bottom", Tokens.SPACE_LG)
	root.add_child(frame)

	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", Tokens.SPACE_LG)
	frame.add_child(column)

	# --- Header ---------------------------------------------------------
	var header = VBoxContainer.new()
	header.add_theme_constant_override("separation", Tokens.SPACE_XS)
	column.add_child(header)

	var title = Label.new()
	title.text = title_text
	title.theme_type_variation = "TitleLabel"
	header.add_child(title)

	if subtitle_text != "":
		var sub = Label.new()
		sub.text = subtitle_text
		sub.theme_type_variation = "HintLabel"
		header.add_child(sub)

	var rule = HSeparator.new()
	column.add_child(rule)

	# --- Content --------------------------------------------------------
	var content = HBoxContainer.new()
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", Tokens.SPACE_LG)
	column.add_child(content)

	# --- Persistent action bar -----------------------------------------
	# Pinned below the content, which is size_flags_vertical EXPAND, so this
	# sits on the bottom edge regardless of how much content there is.
	var actions = HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", Tokens.SPACE_SM)
	column.add_child(HSeparator.new())
	column.add_child(actions)

	var actions_left = HBoxContainer.new()
	actions_left.add_theme_constant_override("separation", Tokens.SPACE_SM)
	actions.add_child(actions_left)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)

	var actions_right = HBoxContainer.new()
	actions_right.add_theme_constant_override("separation", Tokens.SPACE_SM)
	actions.add_child(actions_right)

	return {
		"backdrop": backdrop,
		"header": header,
		"content": content,
		"actions_left": actions_left,
		"actions_right": actions_right,
	}


# A titled column within the content region.
#
# `stretch` is the share of horizontal space it claims relative to its
# siblings, so screens describe proportion rather than pixel widths - the
# old fixed custom_minimum_size columns were what forced the Design Lab's
# stat panel to overflow its own bounds.
static func column(parent: Control, heading: String, stretch: float = 1.0, scrolling: bool = true) -> Control:
	var wrap = VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_stretch_ratio = stretch
	wrap.add_theme_constant_override("separation", Tokens.SPACE_SM)
	parent.add_child(wrap)

	if heading != "":
		var label = Label.new()
		label.text = heading
		label.theme_type_variation = "HeadingLabel"
		wrap.add_child(label)

	var panel = PanelContainer.new()
	panel.theme_type_variation = "InsetPanel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.add_child(panel)

	var body = VBoxContainer.new()
	body.add_theme_constant_override("separation", Tokens.SPACE_SM)

	if not scrolling:
		panel.add_child(body)
		return body

	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	return body


# A selectable row in a list - the pattern for maps, designs, factions.
#
# Deliberately NOT a button that navigates. Selecting shows detail in a
# neighbouring column and leaves the player on the screen; committing is the
# action bar's job. The old map list transitioned scenes the instant you
# clicked a map, so choosing one meant leaving before you'd seen anything
# about it, and changing your mind meant backing out.
static func select_row(parent: Control, title_text: String, detail_text: String = "") -> Button:
	var btn = Button.new()
	btn.theme_type_variation = "ListButton"
	btn.toggle_mode = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, Tokens.HIT_TARGET_MIN)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.text = title_text
	if detail_text != "":
		btn.tooltip_text = detail_text
	parent.add_child(btn)
	return btn


# A label/value pair for a specification readout. Value uses the tabular
# monospace face so a column of these lines up.
static func stat_row(parent: Control, label_text: String, value_text: String) -> Label:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.SPACE_SM)
	parent.add_child(row)

	var key = Label.new()
	key.text = label_text
	key.theme_type_variation = "HintLabel"
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key)

	var value = Label.new()
	value.text = value_text
	value.theme_type_variation = "StatLabel"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return value


# A labelled dropdown laid out as a row, so a stack of settings aligns.
static func field(parent: Control, label_text: String, options: PackedStringArray) -> OptionButton:
	var row = VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)

	var label = Label.new()
	label.text = label_text
	label.theme_type_variation = "HintLabel"
	row.add_child(label)

	var btn = OptionButton.new()
	btn.custom_minimum_size = Vector2(0, Tokens.HIT_TARGET_MIN)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for o in options:
		btn.add_item(o)
	row.add_child(btn)
	return btn


static func action(parent: Control, text: String, variation: String = "Button") -> Button:
	var btn = Button.new()
	btn.text = text
	btn.theme_type_variation = variation
	btn.custom_minimum_size = Vector2(150, Tokens.HIT_TARGET_MIN + 8)
	parent.add_child(btn)
	return btn
