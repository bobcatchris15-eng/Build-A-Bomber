class_name StampedLabel
extends Control
# Lettering stamped into a metal plate and flooded with enamel.
#
# WHY THIS IS NOT A Label WITH THEME OVERRIDES. The previous attempt was, and
# Chris's read of it was exactly right: "still reads as text printed on". Theme
# overrides give one outline colour at one width and one shadow offset, which
# produces a hard-edged sticker. Two things are missing from that and neither is
# expressible as an override:
#
#   THE FALL-OFF. A real stamped character has a wall that drops away from the
#   surface into shadow. One flat outline colour is a border; a STACK of outline
#   passes, widest and blackest first, narrowing as they lighten, is a gradient
#   down that wall. Steep by request - most of the ramp is spent at black, so the
#   letter looks cut rather than embossed.
#
#   THE GLOSS. Enamel is a wet, poured surface: it catches the room brightly
#   along its upper half and goes deep and saturated below. That is a vertical
#   gradient INSIDE the glyphs, and Godot has no gradient text fill. It is done
#   here by drawing the string twice and clipping the bright pass to the top
#   band, which is why this node has a child of its own class.
#
# The whole thing draws with draw_string/draw_string_outline against a font
# resource, so it costs one _draw() per repaint and nothing per frame - these
# labels change only when a queue's name changes, which is never.

const Tokens = preload("res://scripts/ui_tokens.gd")

# The enamel. Bright along the top, deep and saturated below - the split that
# makes it read as poured and wet rather than as flat fill.
const ENAMEL_GLOSS := Color(1.0, 0.925, 0.620, 1.0)
const ENAMEL_BODY := Color(0.847, 0.612, 0.110, 1.0)
# Where the gloss gives way to the body, as a fraction of cap height. Above the
# midline, because a highlight centred on the glyph reads as a stripe rather than
# as a lit surface.
const GLOSS_FRACTION := 0.46

# The fall-off down the cut wall, outermost pass first. Widths are in pixels of
# outline radius; the alpha ramp is what makes it steep - it is still essentially
# black at the second pass and only lifts on the last.
const WALL := [
	{"width": 9.0, "color": Color(0.0, 0.0, 0.0, 1.0)},
	{"width": 6.0, "color": Color(0.031, 0.027, 0.020, 1.0)},
	{"width": 4.0, "color": Color(0.078, 0.059, 0.020, 1.0)},
	{"width": 2.0, "color": Color(0.204, 0.145, 0.031, 1.0)},
]

var text: String = "":
	set(value):
		text = value
		if _gloss_child != null:
			_gloss_child.text = value
		_resize()

var font_size: int = 18:
	set(value):
		font_size = value
		if _gloss_child != null:
			_gloss_child.font_size = value
		_resize()

# True on the clipped child that paints the highlight band only.
var is_gloss_pass: bool = false
# Set by the parent on the gloss pass: the rect to lay text out against, which is
# NOT the gloss pass's own (clipped) rect.
var layout_size: Vector2 = Vector2.ZERO

var _font: FontVariation = null
var _gloss_child: Control = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Heavier than the bold face ships as. Chris asked for heavier lettering and
	# there is no black weight in assets/fonts/, so the bold is emboldened
	# synthetically - which is also what keeps the wall passes from closing up the
	# counters of letters like R and D at this size.
	_font = FontVariation.new()
	_font.base_font = load("res://assets/fonts/UIFont-Bold.ttf")
	_font.variation_embolden = 0.28
	# Stamped lettering on real plant equipment is spaced out; it also stops the
	# 9 px wall passes of adjacent glyphs from merging into a single black slab.
	_font.spacing_glyph = 2


func _ready() -> void:
	if is_gloss_pass:
		return
	var gloss: Control = get_script().new()
	gloss.is_gloss_pass = true
	# Clips the bright pass to the top band of the glyphs. This is the whole
	# reason for a second node: clip_contents is a property of a Control's own
	# rect, so the only way to mask part of a drawing is to put it in a child
	# whose rect IS the mask.
	gloss.clip_contents = true
	gloss.text = text
	gloss.font_size = font_size
	add_child(gloss)
	_gloss_child = gloss
	_resize()


func _resize() -> void:
	custom_minimum_size = Vector2(0.0, float(font_size) * 1.6)
	queue_redraw()
	if _gloss_child != null:
		_gloss_child.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if _gloss_child != null:
			# The child is a MASK, not a copy: its rect is only the top band, but
			# it is told the FULL rect to lay out against. Letting it derive the
			# baseline from its own clipped height would slide the highlight down
			# the glyphs instead of cutting them.
			_gloss_child.layout_size = size
			_gloss_child.position = Vector2.ZERO
			_gloss_child.size = Vector2(size.x, _gloss_cut())
		queue_redraw()


# The y below which the gloss is cut. Derived from the text's actual ascent
# rather than from the rect, so the highlight sits on the cap band of the letters
# and not at some fixed fraction of a box that may be taller than they are.
func _gloss_cut() -> float:
	var ascent: float = _font.get_ascent(font_size)
	return clampf(_baseline() - ascent * (1.0 - GLOSS_FRACTION), 0.0, size.y)


# The rect to lay the string out against. Identical to `size` except on the gloss
# pass, whose own rect is deliberately short.
func _layout() -> Vector2:
	return layout_size if is_gloss_pass else size


func _baseline() -> float:
	var box: Vector2 = _layout()
	return (box.y + _font.get_ascent(font_size) - _font.get_descent(font_size)) * 0.5


func _draw() -> void:
	if text == "" or _font == null or _layout().x <= 0.0:
		return
	var width: float = _font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var origin := Vector2((_layout().x - width) * 0.5, _baseline())

	if is_gloss_pass:
		# Highlight only. The wall is the parent's job - drawing it again here,
		# clipped, would put a hard horizontal cut across the black.
		draw_string(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, ENAMEL_GLOSS)
		return

	for pass_spec in WALL:
		draw_string_outline(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, int(pass_spec["width"]), pass_spec["color"])
	draw_string(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, ENAMEL_BODY)


# Dims the enamel without touching the wall, for a queue with nothing to build.
# modulate would fade the black too and turn the cut into a smudge.
func set_live(live: bool) -> void:
	var tint: Color = Color.WHITE if live else Color(0.62, 0.62, 0.62, 1.0)
	self_modulate = tint
	if _gloss_child != null:
		_gloss_child.self_modulate = tint
