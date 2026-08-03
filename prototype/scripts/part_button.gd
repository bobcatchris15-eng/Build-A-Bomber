extends Button

var module_type_id: String = ""

# VISUAL_IMPROVEMENT_PLAN.md chunk G: Godot's default tooltip is a plain
# PopupPanel - this overrides the virtual _make_custom_tooltip() Godot
# itself calls to build one, returning a styled card instead. `for_text` is
# whatever this button's own `tooltip_text` is currently set to (parts_menu.
# gd's _stat_tooltip() - "<name>\nHP: ... | Weight: ...\nCost: ...\nDPS: ...")
# - split on newlines into a bold title row (the part name) plus smaller
# stat rows below, matching the "icon + title + stat rows" card shape the
# plan calls for (no icon graphic system exists in this project yet - see
# VISUAL_IMPROVEMENT_PLAN.md's own note that every "icon" today is emoji in
# button text, which the title row already carries through unchanged).
func _make_custom_tooltip(for_text: String) -> Control:
	var panel = PanelContainer.new()
	# CANVAS from the theme, the same soft backing the flyouts and callouts use -
	# a tooltip is exactly that category of object, laid over the interface rather
	# than built into it.
	#
	# The inline stylebox this replaces was a blue-black fill with a 5px "Yellow
	# Model Kit Instruction Decal Border" and 4px corners: three separate values
	# that appear nowhere in ui_tokens.gd, on the one card a player reads dozens of
	# times per session while comparing parts.
	panel.theme_type_variation = "FlyoutPanel"

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	var lines = for_text.split("\n")
	if lines.is_empty():
		return panel
	var title = Label.new()
	title.text = lines[0]
	title.theme_type_variation = "HeadingLabel"
	vbox.add_child(title)
	for i in range(1, lines.size()):
		var row = Label.new()
		row.text = lines[i]
		# StatLabel: these rows ARE stats ("HP: 75 | Weight: 65 kg"), and the mono
		# face is what makes a column of them comparable between two tooltips.
		row.theme_type_variation = "StatLabel"
		vbox.add_child(row)

	# Flavor row (VISUAL_ART_DIRECTION.md 1.2 - the tone target's cheapest
	# detail-scale channel; see ModuleCatalog.MODULE_FLAVOR for the voice
	# rules). Looked up from module_type_id rather than parsed out of
	# `for_text`: keeps tooltip_text as pure stat data with no sentinel
	# encoding, and means the flavor line can't be mistaken for a stat row
	# by anything else reading that string.
	var flavor := ""
	if module_type_id != "":
		flavor = ModuleCatalog.get_module_flavor(module_type_id)
	if flavor != "":
		# Thin rule separating hard numbers from voice, so the card doesn't
		# read as though the flavor line were another stat.
		var sep = HSeparator.new()
		sep.add_theme_constant_override("separation", 6)
		vbox.add_child(sep)

		var flavor_label = Label.new()
		flavor_label.text = flavor
		# HintLabel is the secondary-text role: present but subordinate, so the
		# voice line never competes with the numbers a player is comparing. That is
		# what the old hand-mixed (0.62, 0.60, 0.55) was approximating - it is
		# within a hair of Tokens.TEXT_SECONDARY, which HintLabel already carries.
		flavor_label.theme_type_variation = "HintLabel"
		# These lines run to ~90 chars; without an explicit wrap the tooltip
		# card would stretch into a single very wide strip.
		flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		flavor_label.custom_minimum_size = Vector2(260, 0)
		vbox.add_child(flavor_label)

	return panel

func _get_drag_data(at_position: Vector2):
	# Create a simple preview label for the drag
	var preview_label = Label.new()
	preview_label.text = text
	var preview_control = Control.new()
	preview_control.add_child(preview_label)
	
	set_drag_preview(preview_control)
	
	# Pass a dictionary containing the drag payload
	return {"type": "module_part", "id": module_type_id}
