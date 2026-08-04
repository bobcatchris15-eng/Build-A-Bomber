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
