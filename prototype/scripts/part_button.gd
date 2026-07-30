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
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.95)
	style.border_color = Color(0.85, 0.75, 0.4, 1.0)
	style.border_width_top = 3
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	var lines = for_text.split("\n")
	if lines.is_empty():
		return panel
	var title = Label.new()
	title.text = lines[0]
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6, 1.0))
	vbox.add_child(title)
	for i in range(1, lines.size()):
		var row = Label.new()
		row.text = lines[i]
		row.add_theme_font_size_override("font_size", 13)
		row.add_theme_color_override("font_color", Color(0.8, 0.82, 0.85, 1.0))
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
		flavor_label.add_theme_font_size_override("font_size", 12)
		# Dimmer and cooler than the stat rows - present but subordinate, so
		# it never competes with the numbers a player is actually comparing.
		flavor_label.add_theme_color_override("font_color", Color(0.62, 0.60, 0.55, 1.0))
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
