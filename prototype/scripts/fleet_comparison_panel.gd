extends Control
# Fleet Comparison Panel (Split-Screen Telemetry Delta Window)
# Compares the active WIP Design Lab construct against a target Fleet Roster blueprint side-by-side.

const UITheme = preload("res://scripts/ui_theme.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const StatCalculatorScript = preload("res://scripts/stat_calculator.gd")
const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")

var target_blueprint: Dictionary = {}
var target_id: String = ""

func _init(p_target_id: String, p_target_bp: Dictionary):
	target_id = p_target_id
	target_blueprint = p_target_bp

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop = ColorRect.new()
	# Modal scrim: BASE_900 is the token designated for it.
	backdrop.color = Color(Tokens.BASE_900, 0.85)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var panel = PanelContainer.new()
	panel.theme_type_variation = "CardPanel"
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -480
	panel.offset_top = -300
	panel.offset_right = 480
	panel.offset_bottom = 300
	add_child(panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var main_vbox = VBoxContainer.new()
	margin.add_child(main_vbox)

	# Header
	var header = HBoxContainer.new()
	main_vbox.add_child(header)

	var title = Label.new()
	title.text = "BLUEPRINT COMPARISON"
	# TitleLabel takes the stencil face and the scale's title step. The old cyan
	# (0.2, 0.9, 1.0) was the last of the sci-fi accent left anywhere in the UI.
	title.theme_type_variation = "TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): queue_free())
	header.add_child(close_btn)

	main_vbox.add_child(HSeparator.new())

	# Read WIP stats from StatCalculator
	var wip_stats = _get_wip_stats()
	var target_stats = _get_target_stats(target_blueprint)

	# 3-Column Split View (WIP | DELTA TELEMETRY | TARGET ROSTER)
	var split_hbox = HBoxContainer.new()
	split_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(split_hbox)

	# Left Column: Active WIP Design
	var wip_panel = _build_unit_column("ACTIVE WORKBENCH DESIGN", wip_stats, Tokens.SIGNAL_INFO)
	wip_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split_hbox.add_child(wip_panel)

	# Center Column: Telemetry Deltas
	var delta_panel = _build_delta_column(wip_stats, target_stats)
	delta_panel.custom_minimum_size = Vector2(240, 0)
	split_hbox.add_child(delta_panel)

	# Right Column: Target Fleet Roster Blueprint
	var target_name = target_blueprint.get("name", "Saved Blueprint")
	var target_col = _build_unit_column(target_name.to_upper(), target_stats, Tokens.SIGNAL_HAZARD)
	target_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split_hbox.add_child(target_col)

	main_vbox.add_child(HSeparator.new())

	# Bottom Actions
	var actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	main_vbox.add_child(actions)

	var load_target_btn = Button.new()
	load_target_btn.text = "Load Comparison Unit into Workbench"
	# The one primary action on this panel, so it takes the CARBON plate rather
	# than a green tint - PrimaryButton exists for exactly this.
	load_target_btn.theme_type_variation = "PrimaryButton"
	load_target_btn.pressed.connect(func():
		var root = get_node_or_null("/root/MainLab")
		if root:
			var bm = root.get_node_or_null("BlueprintManager")
			if bm and target_id != "":
				bm.load_blueprint_into_designer(target_id)
		queue_free()
	)
	actions.add_child(load_target_btn)

func _get_wip_stats() -> Dictionary:
	var root = get_node_or_null("/root/MainLab")
	if not root: return {}
	var stat_calc = root.get_node_or_null("UI_StatBlock")
	if not stat_calc: return {}
	
	return {
		# Read through stat_calculator's own member, not by node path. The path
		# "ScrollContainer/VBoxContainer/BlueprintNameEdit" stopped resolving the
		# moment VISUAL/UI plan item 7 moved that ScrollContainer inside a UIDock -
		# and it would have failed SILENTLY, because has_node() returning false just
		# selects the "WIP Unit" fallback and the comparison panel would have
		# quietly compared against a design with the wrong name forever.
		"name": stat_calc.blueprint_name_edit.text if ("blueprint_name_edit" in stat_calc and is_instance_valid(stat_calc.blueprint_name_edit)) else "WIP Unit",
		"hp": stat_calc.total_hp if "total_hp" in stat_calc else 0.0,
		"weight": stat_calc.total_weight if "total_weight" in stat_calc else 0.0,
		"dps": stat_calc.total_dps if "total_dps" in stat_calc else 0.0,
		"metal": stat_calc.total_metal if "total_metal" in stat_calc else 0,
		"crystal": stat_calc.total_crystal if "total_crystal" in stat_calc else 0,
		"power": stat_calc.base_energy if "base_energy" in stat_calc else 0.0,
	}

func _get_target_stats(bp: Dictionary) -> Dictionary:
	var stats = bp.get("stats", {})
	var modules = bp.get("modules", [])
	
	# Estimate stats from blueprint data if not pre-cached
	var hp: float = float(stats.get("total_hp", 300.0))
	var weight: float = float(stats.get("total_weight", 200.0))
	var dps: float = float(stats.get("total_dps", 50.0))
	var metal: int = int(stats.get("total_metal", 100))
	var crystal: int = int(stats.get("total_crystal", 20))
	var power: float = float(stats.get("base_energy", 50.0))

	return {
		"name": bp.get("name", "Saved Unit"),
		"hp": hp,
		"weight": weight,
		"dps": dps,
		"metal": metal,
		"crystal": crystal,
		"power": power,
	}

func _build_unit_column(title_text: String, s: Dictionary, title_color: Color) -> PanelContainer:
	var pc = PanelContainer.new()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	pc.add_child(vbox)

	var h = Label.new()
	h.text = title_text
	h.theme_type_variation = "HeadingLabel"
	# `title_color` is now one of the signal tokens rather than a per-call literal -
	# see the two call sites. It still distinguishes the two columns, which is the
	# one thing this colour is actually for.
	h.add_theme_color_override("font_color", title_color)
	vbox.add_child(h)
	vbox.add_child(HSeparator.new())

	vbox.add_child(_make_stat_row("Health (HP)", "%.0f" % s.get("hp", 0.0)))
	vbox.add_child(_make_stat_row("Total Mass", "%.1f kg" % s.get("weight", 0.0)))
	vbox.add_child(_make_stat_row("Firepower (DPS)", "%.1f" % s.get("dps", 0.0)))
	vbox.add_child(_make_stat_row("Metal Cost", "%d M" % s.get("metal", 0)))
	vbox.add_child(_make_stat_row("Crystal Cost", "%d C" % s.get("crystal", 0)))
	vbox.add_child(_make_stat_row("Base Power", "%.1f kW" % s.get("power", 0.0)))

	return pc

func _make_stat_row(label: String, val: String) -> HBoxContainer:
	var hb = HBoxContainer.new()
	var l1 = Label.new()
	l1.text = label
	l1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l1.theme_type_variation = "HintLabel"
	hb.add_child(l1)

	var l2 = Label.new()
	l2.text = val
	l2.theme_type_variation = "StatLabel"
	hb.add_child(l2)
	return hb

func _build_delta_column(wip: Dictionary, target: Dictionary) -> PanelContainer:
	var pc = PanelContainer.new()
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	pc.add_child(vbox)

	var h = Label.new()
	h.text = "TELEMETRY DELTA"
	h.theme_type_variation = "HeadingLabel"
	h.add_theme_color_override("font_color", Tokens.SIGNAL_GO)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(h)
	vbox.add_child(HSeparator.new())

	var hp_delta = float(wip.get("hp", 0)) - float(target.get("hp", 0))
	var mass_delta = float(wip.get("weight", 0)) - float(target.get("weight", 0))
	var dps_delta = float(wip.get("dps", 0)) - float(target.get("dps", 0))
	var metal_delta = int(wip.get("metal", 0)) - int(target.get("metal", 0))

	vbox.add_child(_make_delta_badge("HP", hp_delta, "", true))
	vbox.add_child(_make_delta_badge("Mass", mass_delta, "kg", false)) # Lighter mass is better
	vbox.add_child(_make_delta_badge("DPS", dps_delta, "", true))
	vbox.add_child(_make_delta_badge("Metal", metal_delta, "M", false))

	return pc

func _make_delta_badge(label: String, val: float, unit: String, higher_is_better: bool) -> PanelContainer:
	var pc = PanelContainer.new()
	var hb = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	pc.add_child(hb)

	var l = Label.new()
	l.text = label + ":"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)

	var delta_lbl = Label.new()
	var sign_str = "+" if val > 0 else ""
	delta_lbl.text = "%s%.1f %s" % [sign_str, val, unit]
	
	# A better/worse/equal readout is state, which is what the signal tokens are
	# for. `modulate` also tints a node's children, so these are set as a font
	# colour instead - harmless on a bare Label, but the wrong tool.
	delta_lbl.theme_type_variation = "StatLabel"
	if abs(val) < 0.01:
		delta_lbl.text = "MATCH"
		delta_lbl.add_theme_color_override("font_color", Tokens.TEXT_SECONDARY)
	elif (val > 0 and higher_is_better) or (val < 0 and not higher_is_better):
		delta_lbl.add_theme_color_override("font_color", Tokens.SIGNAL_GO)
	else:
		delta_lbl.add_theme_color_override("font_color", Tokens.SIGNAL_ALERT)

	hb.add_child(delta_lbl)
	return pc
