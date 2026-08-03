class_name UIStamp
extends RefCounted
# The rubber ink stamp overlay: "APPROVED FOR FIELD TEST", "DESTRUCTIVE TEST
# PERMIT", "DECOMMISSIONED / DISCARDED".
#
# This is the interface's single funniest moment and it works entirely because
# it is played straight. A player bolts a naval propeller to a water tower,
# hits save, and a procurement office stamps it APPROVED FOR FIELD TEST without
# comment. Nothing in the presentation may acknowledge that this is absurd -
# see scripts/blueprint_namer.gd:6-13 for the rule in full.
#
# WHAT CHANGED AND WHY:
#
# The previous version rendered "★ APPROVED FOR FIELD TEST ★" in the default UI
# sans, inside a 6px-bordered rounded PanelContainer, in saturated web green,
# with a TRANS_BOUNCE scale-in. Every one of those is the joke told out loud:
# the stars are decoration, the rounded border is a UI card rather than a
# stamp, and a bounce is a cartoon landing. It read as a toast notification
# congratulating the player.
#
# A real rubber stamp instead:
#   * STENCIL FACE. The same display font the titles use.
#   * DOUBLE RULE, SQUARE CORNERS. Drawn, not a StyleBox - an outer heavy rule
#     and an inner hairline with a gap, which is what actual inspection stamps
#     carry. No corner radius; ink has no corner radius.
#   * ROTATED, never level. Hand-placed marks are always a few degrees off.
#   * UNEVEN INK. shaders/rubber_stamp_ink.gdshader punches pinholes and
#     starves one edge, seeded per instance so no two land alike.
#   * SLAM, NOT BOUNCE. Fast overshoot into the surface, then dead stop and a
#     long hold. TRANS_BACK on the way in, no oscillation - the block does not
#     spring back off the paper.
#   * SIGNAL COLOURS FROM TOKENS. Callers pass a ROLE, not a Color. The old
#     signature took a literal and every call site invented its own saturated
#     green/red/amber, which is exactly the drift ui_tokens.gd exists to stop.

const Tokens = preload("res://scripts/ui_tokens.gd")
const INK_SHADER = preload("res://shaders/rubber_stamp_ink.gdshader")

const HOLD_SECONDS := 1.35
const FADE_SECONDS := 0.45
# Degrees. Wide enough to always read as hand-placed, tight enough that the
# mark never looks like it was thrown at the screen.
const TILT_RANGE_DEG := 4.5


static func _ink_color(role: String) -> Color:
	match role:
		"alert":
			return Tokens.SIGNAL_ALERT
		"hazard":
			return Tokens.SIGNAL_HAZARD
		_:
			return Tokens.SIGNAL_GO


# Spawns a stamp over `parent` and returns its container (which frees itself).
#
# `role` is one of "go" | "alert" | "hazard" - the same three meanings the rest
# of the interface uses, so a stamp cannot introduce a fourth red.
static func spawn_stamp(parent: Node, stamp_text: String, role: String = "go") -> Control:
	if parent == null:
		return null

	var ink := _ink_color(role)

	var container = CenterContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(container)

	var mark = StampMark.new()
	mark.ink = ink
	mark.text = stamp_text.to_upper()
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(mark)

	# Per-instance ink seed. Without this every stamp dries out in the same
	# places and the "handmade" cue inverts into an obviously repeated texture.
	var mat = ShaderMaterial.new()
	mat.shader = INK_SHADER
	mat.set_shader_parameter("stamp_seed", randf() * 100.0)
	mat.set_shader_parameter("ink_wear", randf_range(0.4, 0.7))
	mark.material = mat
	# The shader needs pixel dimensions to keep the pinholes a fixed physical
	# size regardless of how long the text is. A Control's size is not final
	# until layout has run, so push it on `resized` as well as now - same
	# reasoning as UITheme.apply_backdrop().
	var push_size := func() -> void:
		if mark.size.x > 1.0 and mark.size.y > 1.0:
			mat.set_shader_parameter("stamp_size", mark.size)
	push_size.call()
	mark.resized.connect(push_size)

	var tilt := deg_to_rad(randf_range(-TILT_RANGE_DEG, TILT_RANGE_DEG))

	# Start large and land hard. pivot_offset must come from the minimum size
	# rather than `size`, which is still zero this frame - pivoting about a
	# zero point scales the mark about its top-left corner.
	mark.pivot_offset = mark.get_combined_minimum_size() * 0.5
	mark.scale = Vector2(1.9, 1.9)
	mark.rotation = tilt
	mark.modulate.a = 0.0

	var tree = container.get_tree()
	if tree and tree.root.has_node("AudioManager"):
		tree.root.get_node("AudioManager").play_sfx("select")

	# TRANS_BACK/EASE_OUT overshoots slightly past 1.0 and settles - the block
	# compressing the paper. TRANS_BOUNCE, which this used before, oscillates,
	# and a stamp that bobs reads as rubber ball rather than rubber stamp.
	var land = container.create_tween().set_parallel(true)
	land.tween_property(mark, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	land.tween_property(mark, "modulate:a", 1.0, 0.07)

	var fade = container.create_tween()
	fade.tween_interval(HOLD_SECONDS)
	fade.tween_property(container, "modulate:a", 0.0, FADE_SECONDS)
	fade.tween_callback(container.queue_free)

	return container


# The mark itself. Custom-drawn rather than assembled from a PanelContainer and
# a Label because the double rule, the square corners and the tight optical
# padding around stencil caps are all things a StyleBox cannot express, and
# faking them with border widths is how the old version ended up looking like a
# notification card.
class StampMark extends Control:
	var ink: Color = Color.WHITE
	var text: String = ""

	const PAD_H := 22.0
	const PAD_V := 12.0
	const RULE_OUTER := 4.0
	const RULE_INNER := 1.0
	const RULE_GAP := 4.0

	func _get_font() -> Font:
		# DisplayLabel carries the stencil face (build_ui_theme.gd wires it
		# there). Falling back to the default font keeps this drawable in a
		# headless test where no theme is attached.
		var theme_font := get_theme_font("font", "DisplayLabel")
		if theme_font:
			return theme_font
		return get_theme_default_font()

	func _font_size() -> int:
		return Tokens.FONT_TITLE

	func _get_minimum_size() -> Vector2:
		var font := _get_font()
		if font == null:
			return Vector2(320, 64)
		var text_size := font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size())
		var frame := (RULE_OUTER + RULE_GAP + RULE_INNER) * 2.0
		return text_size + Vector2(PAD_H * 2.0 + frame, PAD_V * 2.0 + frame)

	func _draw() -> void:
		var font := _get_font()
		if font == null:
			return
		var fs := _font_size()

		# Outer heavy rule, inset by half its own width so the stroke sits
		# inside the control's bounds rather than straddling the edge and
		# getting half-clipped.
		var outer := Rect2(Vector2(RULE_OUTER * 0.5, RULE_OUTER * 0.5),
			size - Vector2(RULE_OUTER, RULE_OUTER))
		draw_rect(outer, ink, false, RULE_OUTER)

		# Inner hairline.
		var inset := RULE_OUTER + RULE_GAP
		var inner := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
		draw_rect(inner, ink, false, RULE_INNER)

		# Text, optically centred. get_string_size gives the advance width;
		# the vertical term centres the cap height rather than the baseline.
		var text_size := font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var origin := Vector2(
			(size.x - text_size.x) * 0.5,
			(size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
		draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
