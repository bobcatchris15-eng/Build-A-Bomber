extends Control
# After-Action Report (AAR) Overlay UI
# Displays rich post-battle statistics per blueprint, MVP callout,
# tactical vulnerability suggestions, and direct iteration actions.

const UITheme = preload("res://scripts/ui_theme.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")

var is_victory: bool = false
var match_duration: float = 0.0
var bp_stats: Dictionary = {} # blueprint_name -> {built, kills, damage_dealt, damage_taken_kinetic, damage_taken_thermal, damage_taken_explosive, metal_spent, hull_type}
var is_operation: bool = false

signal iterate_requested(blueprint_name: String)
signal next_stage_requested()
signal main_menu_requested()

func setup(p_victory: bool, p_duration: float, p_stats: Dictionary, p_is_op: bool = false) -> void:
	is_victory = p_victory
	match_duration = p_duration
	bp_stats = p_stats
	is_operation = p_is_op
	_build_ui()

func _build_ui() -> void:
	# Backdrop blur / dim overlay
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var frame = MarginContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_constant_override("margin_left", 64)
	frame.add_theme_constant_override("margin_right", 64)
	frame.add_theme_constant_override("margin_top", 48)
	frame.add_theme_constant_override("margin_bottom", 48)
	add_child(frame)

	var card = PanelContainer.new()
	card.theme_type_variation = "InsetPanel"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(card)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 16)
	card.add_child(main_vbox)

	# Header Section
	var header_hbox = HBoxContainer.new()
	var banner = Label.new()
	banner.text = "VICTORY" if is_victory else "DEFEAT"
	banner.theme_type_variation = "TitleLabel"
	# GO / ALERT rather than Color.GOLD and a hand-mixed red. Same pair skirmish.gd's
	# game-over card uses, so a match now ends the same colour in both places -
	# they were two different reds and two different golds for the same two events.
	banner.add_theme_color_override("font_color", Tokens.SIGNAL_GO if is_victory else Tokens.SIGNAL_ALERT)
	header_hbox.add_child(banner)

	var sub_header = Label.new()
	var mins = int(match_duration) / 60
	var secs = int(match_duration) % 60
	sub_header.text = "  |  Match Duration: %02d:%02d  |  AFTER-ACTION REPORT" % [mins, secs]
	sub_header.theme_type_variation = "HeadingLabel"
	# horizontal_alignment, not alignment. Label has no `alignment` property -
	# BoxContainer does - so this line raised "Invalid assignment of property or
	# key 'alignment' ... on a base object of type 'Label'" and ABORTED _build_ui()
	# right here, every time. The report has never rendered past its header: no
	# per-design table, no iterate button, no way out except the escape key. Found
	# by an end-to-end probe looking for the campaign's "Next Engagement" button
	# and not finding any button at all.
	sub_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_hbox.add_child(sub_header)
	main_vbox.add_child(header_hbox)

	main_vbox.add_child(HSeparator.new())

	# Middle Content: Split into Table + Highlights/Advice
	var mid_split = HBoxContainer.new()
	mid_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_split.add_theme_constant_override("separation", 24)
	main_vbox.add_child(mid_split)

	# Left Side: Per-Blueprint Table
	var table_vbox = VBoxContainer.new()
	table_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_vbox.size_flags_stretch_ratio = 1.4
	mid_split.add_child(table_vbox)

	var table_title = Label.new()
	table_title.text = "BLUEPRINT PERFORMANCE BREAKDOWN"
	table_title.theme_type_variation = "HeadingLabel"
	table_vbox.add_child(table_title)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_vbox.add_child(scroll)

	var grid = GridContainer.new()
	grid.columns = 7
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)

	# Table Headers
	var headers = ["Blueprint", "Built", "Kills", "Dmg Dealt", "Dmg Taken", "Metal", "Efficiency"]
	for h in headers:
		var lbl = Label.new()
		lbl.text = h
		lbl.theme_type_variation = "HeadingLabel"
		grid.add_child(lbl)

	# Populate Blueprint Rows
	var mvp_name = ""
	var mvp_score = -1.0
	var total_kin = 0.0
	var total_therm = 0.0
	var total_exp = 0.0

	for bp_name in bp_stats.keys():
		var data = bp_stats[bp_name]
		var built = data.get("built", 0)
		var kills = data.get("kills", 0)
		var dmg_dealt = data.get("damage_dealt", 0.0)
		var kin = data.get("damage_taken_kinetic", 0.0)
		var therm = data.get("damage_taken_thermal", 0.0)
		var exp = data.get("damage_taken_explosive", 0.0)
		var dmg_taken = kin + therm + exp
		var metal = data.get("metal_spent", 0)

		total_kin += kin
		total_therm += therm
		total_exp += exp

		var eff = (dmg_dealt / maxf(1.0, float(metal))) * 100.0
		if eff > mvp_score:
			mvp_score = eff
			mvp_name = bp_name

		_add_table_cell(grid, bp_name)
		_add_table_cell(grid, str(built))
		_add_table_cell(grid, str(kills))
		_add_table_cell(grid, "%.0f" % dmg_dealt)
		_add_table_cell(grid, "%.0f" % dmg_taken)
		_add_table_cell(grid, str(metal))
		_add_table_cell(grid, "%.1f" % eff)

	# Right Side: MVP & Tactical Advice
	var right_vbox = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_stretch_ratio = 0.8
	right_vbox.add_theme_constant_override("separation", 16)
	mid_split.add_child(right_vbox)

	# MVP Card
	var mvp_panel = PanelContainer.new()
	mvp_panel.theme_type_variation = "InsetPanel"
	var mvp_vbox = VBoxContainer.new()
	var mvp_lbl = Label.new()
	mvp_lbl.text = "BEST PERFORMING DESIGN"
	mvp_lbl.theme_type_variation = "HeadingLabel"
	# HAZARD is the tokens' attention colour; Color.GOLD is a raw engine constant.
	mvp_lbl.add_theme_color_override("font_color", Tokens.SIGNAL_HAZARD)
	mvp_vbox.add_child(mvp_lbl)

	var mvp_name_lbl = Label.new()
	mvp_name_lbl.text = mvp_name if mvp_name != "" else "N/A"
	mvp_name_lbl.theme_type_variation = "HeadingLabel"
	mvp_vbox.add_child(mvp_name_lbl)
	mvp_panel.add_child(mvp_vbox)
	right_vbox.add_child(mvp_panel)

	# Tactical Advice Card
	var advice_panel = PanelContainer.new()
	advice_panel.theme_type_variation = "InsetPanel"
	var advice_vbox = VBoxContainer.new()
	var adv_title = Label.new()
	adv_title.text = "ASSESSMENT"
	adv_title.theme_type_variation = "HeadingLabel"
	advice_vbox.add_child(adv_title)

	var advice_text = Label.new()
	advice_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	advice_text.theme_type_variation = "HintLabel"

	var total_dmg_taken = total_kin + total_therm + total_exp
	if total_dmg_taken > 0.0:
		var kin_pct = (total_kin / total_dmg_taken) * 100.0
		var therm_pct = (total_therm / total_dmg_taken) * 100.0
		var exp_pct = (total_exp / total_dmg_taken) * 100.0

		if kin_pct >= 50.0:
			advice_text.text = "• Enemy fielded heavy Kinetic weaponry (%.0f%% of damage taken).\n• Recommendation: Increase armor thickness or switch to Steel/Ceramic armor plates." % kin_pct
		elif therm_pct >= 40.0:
			advice_text.text = "• Enemy dealt high Thermal damage (%.0f%% of damage taken).\n• Recommendation: Mount Ablative or Ceramic armor plates to absorb thermal beams." % therm_pct
		elif exp_pct >= 40.0:
			advice_text.text = "• Enemy landed heavy Explosive/Missile damage (%.0f%% of damage taken).\n• Recommendation: Mount Reactive Armor plates or Point-Defense CIWS turrets." % exp_pct
		else:
			advice_text.text = "• Damage taken was balanced across classes.\n• Tip: Check module traverse speeds and continuous tweak barrel lengths for range advantage."
	else:
		advice_text.text = "• Dominant performance! Zero damage sustained."

	advice_vbox.add_child(advice_text)
	advice_panel.add_child(advice_vbox)
	right_vbox.add_child(advice_panel)

	main_vbox.add_child(HSeparator.new())

	# Bottom Action Bar
	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(bottom_hbox)

	var bp_select = OptionButton.new()
	bp_select.custom_minimum_size.x = 220
	for bp_name in bp_stats.keys():
		bp_select.add_item("Tweak " + bp_name)
	bottom_hbox.add_child(bp_select)

	var iterate_btn = Button.new()
	iterate_btn.text = "Iterate in Design Lab"
	iterate_btn.theme_type_variation = "PrimaryButton"
	iterate_btn.custom_minimum_size = Vector2(200, 44)
	iterate_btn.pressed.connect(func():
		var sel_idx = bp_select.selected
		if sel_idx >= 0 and sel_idx < bp_stats.keys().size():
			var selected_bp = bp_stats.keys()[sel_idx]
			iterate_requested.emit(selected_bp)
	)
	bottom_hbox.add_child(iterate_btn)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_hbox.add_child(spacer)

	if is_operation:
		var next_btn = Button.new()
		# "Engagement", matching what the setup and draft screens call a round.
		# "Stage" was this file's own word for it and appeared nowhere else.
		next_btn.text = "Next Engagement >"
		next_btn.theme_type_variation = "PrimaryButton"
		next_btn.custom_minimum_size = Vector2(200, 44)
		next_btn.pressed.connect(func(): next_stage_requested.emit())
		bottom_hbox.add_child(next_btn)

	var menu_btn = Button.new()
	menu_btn.text = "Main Menu"
	menu_btn.custom_minimum_size = Vector2(140, 44)
	menu_btn.pressed.connect(func(): main_menu_requested.emit())
	bottom_hbox.add_child(menu_btn)

func _add_table_cell(parent: Control, text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.theme_type_variation = "StatLabel"
	parent.add_child(lbl)
