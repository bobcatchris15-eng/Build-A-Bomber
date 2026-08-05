class_name UIShell
extends RefCounted
# One layout primitive for the out-of-match screens.
#
# HISTORY, because the name promises more than the file delivers: this started
# as a full shell toolkit - build_screen() to scaffold a full-bleed frame with a
# persistent bottom action bar, column() for side-by-side choices, field() for
# labelled dropdowns, action() for buttons, select_row() for list entries - all
# built to replace the fixed-size-card-floating-in-an-empty-frame shape every
# shell screen used to hand-roll.
#
# Only stat_row() was ever actually adopted. MapSelect, the screen that drove
# the rest of the API, was folded into match_setup.gd's map dropdown, and
# match_setup/operations_setup build their own layouts directly. The other six
# helpers sat here with zero call sites and have been removed; git history has
# them if that architecture is ever revisited.
#
# Structural helper only - all colour and type comes from the theme
# (tools/build_ui_theme.gd), so nothing here hardcodes appearance.

const Tokens = preload("res://scripts/ui_tokens.gd")
const UITheme = preload("res://scripts/ui_theme.gd")


# ---------------------------------------------------------------------------
# SCREEN SCAFFOLD
# ---------------------------------------------------------------------------
# The two nodes every out-of-match screen opens with: a full-bleed backdrop and
# a margin frame inset from the window edge.
#
# ADDED ON EVIDENCE, not on spec - which is the whole lesson of the history note
# above. These are not a guess at what screens might want; they are what four
# screens were already hand-rolling, and all four call sites move onto them in
# the same commit that adds them. The six helpers that were removed from this
# file had zero call sites because they were written first and adopted never.
#
# The margins were also genuinely DRIFTING, which is the second reason this is
# worth centralising rather than leaving alone:
#
#   main_menu, blueprint_library   SPACE_XL + SPACE_LG / SPACE_LG   (52 / 20)
#   operations_setup               48 / 48 / 36 / 36                (off-grid)
#   loading_screen                 72 / 72 / 56 / 48                (off-grid)
#
# Three different frames for the same job, two of them off the 4px grid the
# spacing tokens exist to enforce. The canonical value is the one the two
# already-correct screens use, which is also the frame UI_STYLE_GUIDE.md's
# main-menu layout section describes.
const SCREEN_MARGIN_H := Tokens.SPACE_XL + Tokens.SPACE_LG
const SCREEN_MARGIN_V := Tokens.SPACE_LG


# Full-bleed steel backdrop. Returns it so a caller that wants a non-default
# finish can re-apply a material over the top (match_setup does, deliberately -
# see its own comment).
static func backdrop(parent: Node) -> ColorRect:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# IGNORE, always: the backdrop sits under every control on the screen, and a
	# full-rect rect that accepts mouse input swallows clicks meant for them.
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	UITheme.apply_backdrop(bg)
	return bg


# The margin frame content is laid out inside. Pass overrides only for a screen
# that genuinely needs a different inset, and say why at the call site.
static func screen_frame(parent: Node, margin_h: int = SCREEN_MARGIN_H,
		margin_v: int = SCREEN_MARGIN_V) -> MarginContainer:
	var frame := MarginContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_constant_override("margin_left", margin_h)
	frame.add_theme_constant_override("margin_right", margin_h)
	frame.add_theme_constant_override("margin_top", margin_v)
	frame.add_theme_constant_override("margin_bottom", margin_v)
	parent.add_child(frame)
	return frame


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
