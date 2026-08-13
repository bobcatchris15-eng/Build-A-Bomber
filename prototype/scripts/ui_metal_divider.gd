class_name UIMetalDivider
extends Control
# A physical sheet-metal fold used to separate categories in the toolbox catalog.
# Renders as a bent steel divider with a shadow and highlight.

const Tokens = preload("res://scripts/ui_tokens.gd")

var _label: Label

func _init() -> void:
	custom_minimum_size = Vector2(0, 32.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_label = Label.new()
	_label.theme_type_variation = "HeadingLabel"
	_label.add_theme_color_override("font_color", Tokens.BASE_900) # Embossed text
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)

func set_text(text: String) -> void:
	_label.text = text

func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return

	# Draw the physical folded metal structure
	var w = size.x
	var h = size.y
	
	# The base red color of the toolbox
	var base_red = Color("#a02222")
	var highlight = Color("#d83a3a")
	var shadow = Color("#5a1111")
	var drop_shadow = Tokens.SHADOW_COLOR
	drop_shadow.a = 0.5
	
	# Shadow underneath the fold
	draw_rect(Rect2(0, h - 8, w, 8), drop_shadow)
	
	# The angled bend (gradient or simple split)
	draw_rect(Rect2(0, 0, w, h - 12), base_red)
	
	# Highlight on the top rim
	draw_rect(Rect2(0, 0, w, 2), highlight)
	
	# Shadow inside the crease
	draw_rect(Rect2(0, h - 14, w, 2), shadow)
	
	# The flat shelf
	draw_rect(Rect2(0, h - 12, w, 4), highlight)
