class_name Wordmark
extends Control
# The game's identity lockup: the mark, and the name struck into a rating plate.
#
# WHY THE TEXT IS A Label AND NOT PART OF THE SVG. Godot imports SVG through
# ThorVG, which does not render <text> - a wordmark authored with text elements
# imports BLANK, and it does so silently. The alternative, hand-drawing
# "KITBASH COMMAND" as bezier paths, is a lot of work for letterforms that would
# come out worse than the stencil face the project already ships and has already
# licensed.
#
# So the plate is authored art (assets/branding/) and the letters are real type
# laid over it. That is also the honest version of the L3 placard layer: an
# engraved rating plate IS a metal blank with type struck into it, and the two
# genuinely are separate objects.
#
# THE TITLE WAS PREVIOUSLY A BARE Label with theme_type_variation = "DisplayLabel"
# and nothing else - no mark, no plate, no boot identity of any kind. This is the
# whole of the game's visual identity, so it is deliberately one widget rather
# than something each screen reassembles.

const Tokens = preload("res://scripts/ui_tokens.gd")

const TITLE := "KITBASH COMMAND"
const SUBTITLE := "DESIGN BUREAU AND PROVING GROUND"

const MARK_PATH := "res://assets/branding/mark.svg"
const PLATE_H_PATH := "res://assets/branding/wordmark_plate_horizontal.svg"
const PLATE_V_PATH := "res://assets/branding/wordmark_plate_stacked.svg"

enum Lockup { HORIZONTAL, STACKED, MARK_ONLY }

@export var lockup: Lockup = Lockup.HORIZONTAL
# The part-number line struck along the bottom rule of the plate. Deadpan
# equipment labelling, matching the register the rest of the chrome uses -
# "DESIGN BUREAU / CONSOLE 04" and so on.
@export var part_number: String = "KBC-1 / GENERAL ISSUE"


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	match lockup:
		Lockup.MARK_ONLY: _build_mark_only()
		Lockup.STACKED: _build_stacked()
		_: _build_horizontal()


func _mark(size: int) -> TextureRect:
	var tr := TextureRect.new()
	if ResourceLoader.exists(MARK_PATH):
		tr.texture = load(MARK_PATH)
	tr.custom_minimum_size = Vector2(size, size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return tr


# The plate goes behind as a NinePatchRect rather than a plain TextureRect so a
# longer name does not stretch the punched corner holes into ovals. The chamfer
# and the holes live in the frame; only the flat middle stretches.
func _plate(path: String, frame: int) -> NinePatchRect:
	var np := NinePatchRect.new()
	if ResourceLoader.exists(path):
		np.texture = load(path)
	np.patch_margin_left = frame
	np.patch_margin_right = frame
	np.patch_margin_top = frame
	np.patch_margin_bottom = frame
	np.set_anchors_preset(Control.PRESET_FULL_RECT)
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return np


func _title_label(size: int) -> Label:
	var l := Label.new()
	l.text = TITLE
	l.theme_type_variation = "DisplayLabel"
	l.add_theme_font_size_override("font_size", size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _build_horizontal() -> void:
	custom_minimum_size = Vector2(520, 96)
	add_child(_plate(PLATE_H_PATH, 28))

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", Tokens.SPACE_MD)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	row.add_child(_mark(64))

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	col.add_child(_title_label(Tokens.FONT_DISPLAY))
	col.add_child(_part_line())


func _build_stacked() -> void:
	custom_minimum_size = Vector2(240, 200)
	add_child(_plate(PLATE_V_PATH, 28))

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", Tokens.SPACE_XS)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	var centred := CenterContainer.new()
	centred.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centred.add_child(_mark(72))
	col.add_child(centred)

	# TITLE at the smaller step in this lockup. FONT_DISPLAY is 40px and set at
	# 240 wide it wraps mid-word, which is worse than a smaller wordmark.
	col.add_child(_title_label(Tokens.FONT_TITLE))
	col.add_child(_part_line())


func _build_mark_only() -> void:
	custom_minimum_size = Vector2(64, 64)
	add_child(_mark(64))


func _part_line() -> Label:
	var l := Label.new()
	l.text = part_number
	# PlacardLabel is BASE_900 on bright metal - engraving is a shadow cut into
	# the plate, not ink laid on it.
	l.theme_type_variation = "PlacardLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
