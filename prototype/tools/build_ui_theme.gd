@tool
extends MainLoop

func _process(_delta: float) -> bool:
	build_theme()
	return true

func _load_font(path: String) -> FontFile:
	var font = FontFile.new()
	var err = font.load_dynamic_font(path)
	if err == OK:
		return font
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is FontFile:
			return res as FontFile
	return null

func build_theme() -> void:
	print("Building Bomber Theme (res://resources/bomber_theme.tres)...")
	var theme = Theme.new()

	# Load Fonts
	var ui_font_reg = _load_font("res://assets/fonts/UIFont-Regular.ttf")
	var ui_font_bold = _load_font("res://assets/fonts/UIFont-Bold.ttf")
	var mono_font_reg = _load_font("res://assets/fonts/MonoFont-Regular.ttf")

	if ui_font_reg:
		ui_font_reg.multichannel_signed_distance_field = true
		theme.set_default_font(ui_font_reg)
	theme.set_default_font_size(14)

	# Colors
	var bg_dark = Color(0.07, 0.08, 0.10, 0.88)
	var bg_header = Color(0.10, 0.12, 0.15, 0.95)
	var border_subtle = Color(0.20, 0.25, 0.32, 0.80)
	var border_accent = Color(0.20, 0.60, 0.85, 0.90)
	var border_gold = Color(0.90, 0.70, 0.20, 0.90)
	var text_main = Color(0.94, 0.96, 0.98, 1.0)
	var text_subtle = Color(0.60, 0.65, 0.72, 1.0)

	# Base Panel StyleBox
	var sb_panel = StyleBoxFlat.new()
	sb_panel.bg_color = bg_dark
	sb_panel.border_color = border_subtle
	set_stylebox_border_width_all(sb_panel, 1)
	set_stylebox_corner_radius_all(sb_panel, 4)
	set_stylebox_expand_margin_all(sb_panel, 2)
	theme.set_stylebox("panel", "Panel", sb_panel)
	theme.set_stylebox("panel", "PanelContainer", sb_panel)

	# CardPanel Variation
	var sb_card = sb_panel.duplicate() as StyleBoxFlat
	sb_card.border_color = border_accent
	set_stylebox_border_width_all(sb_card, 2)
	theme.set_stylebox("panel", "CardPanel", sb_card)

	# HeaderPanel Variation
	var sb_header = StyleBoxFlat.new()
	sb_header.bg_color = bg_header
	sb_header.border_color = border_accent
	sb_header.border_width_bottom = 2
	set_stylebox_corner_radius_all(sb_header, 2)
	theme.set_stylebox("panel", "HeaderPanel", sb_header)

	# Buttons
	var sb_btn_normal = StyleBoxFlat.new()
	sb_btn_normal.bg_color = Color(0.12, 0.14, 0.18, 0.90)
	sb_btn_normal.border_color = border_subtle
	set_stylebox_border_width_all(sb_btn_normal, 1)
	set_stylebox_corner_radius_all(sb_btn_normal, 4)

	var sb_btn_hover = sb_btn_normal.duplicate() as StyleBoxFlat
	sb_btn_hover.bg_color = Color(0.18, 0.22, 0.28, 0.95)
	sb_btn_hover.border_color = border_accent

	var sb_btn_pressed = sb_btn_normal.duplicate() as StyleBoxFlat
	sb_btn_pressed.bg_color = Color(0.08, 0.10, 0.14, 0.95)
	sb_btn_pressed.border_color = border_accent

	theme.set_stylebox("normal", "Button", sb_btn_normal)
	theme.set_stylebox("hover", "Button", sb_btn_hover)
	theme.set_stylebox("pressed", "Button", sb_btn_pressed)
	theme.set_stylebox("focus", "Button", sb_btn_hover)
	theme.set_color("font_color", "Button", text_main)

	# PrimaryButton Variation
	var sb_primary_normal = sb_btn_normal.duplicate() as StyleBoxFlat
	sb_primary_normal.bg_color = Color(0.12, 0.32, 0.48, 0.90)
	sb_primary_normal.border_color = border_accent
	theme.set_stylebox("normal", "PrimaryButton", sb_primary_normal)

	# DangerButton Variation
	var sb_danger_normal = sb_btn_normal.duplicate() as StyleBoxFlat
	sb_danger_normal.bg_color = Color(0.48, 0.12, 0.14, 0.90)
	sb_danger_normal.border_color = Color(0.85, 0.25, 0.25, 0.90)
	theme.set_stylebox("normal", "DangerButton", sb_danger_normal)

	# Labels & Title Variations
	theme.set_color("font_color", "Label", text_main)
	if ui_font_bold:
		theme.set_font("font", "TitleLabel", ui_font_bold)
	theme.set_font_size("font_size", "TitleLabel", 24)
	theme.set_color("font_color", "TitleLabel", border_gold)

	if mono_font_reg:
		theme.set_font("font", "HUDValueLabel", mono_font_reg)
	theme.set_font_size("font_size", "HUDValueLabel", 16)
	theme.set_color("font_color", "HUDValueLabel", text_main)

	# Save Theme
	var res_path = "res://resources/bomber_theme.tres"
	var err = ResourceSaver.save(theme, res_path)
	if err == OK:
		print("Successfully saved bomber_theme.tres!")
	else:
		print("Failed to save bomber_theme.tres, error code: ", err)

func set_stylebox_border_width_all(sb: StyleBoxFlat, width: int) -> void:
	sb.border_width_left = width
	sb.border_width_right = width
	sb.border_width_top = width
	sb.border_width_bottom = width

func set_stylebox_corner_radius_all(sb: StyleBoxFlat, radius: int) -> void:
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius

func set_stylebox_expand_margin_all(sb: StyleBoxFlat, margin: float) -> void:
	sb.expand_margin_left = margin
	sb.expand_margin_right = margin
	sb.expand_margin_top = margin
	sb.expand_margin_bottom = margin
