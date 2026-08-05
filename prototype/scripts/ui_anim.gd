extends RefCounted
class_name UIAnim
# VISUAL_IMPROVEMENT_PLAN.md chunk G: a small shared motion library so the
# UI's handful of animated moments (panel slide-in, button press feedback,
# resource counter roll-up, status toast slide+fade, scene-transition fade)
# read as one consistent system - same standard durations/easings - instead
# of each call site hand-rolling its own one-off Tween with its own timing.

# The timings themselves now live in ui_tokens.gd alongside the rest of the
# visual language, because motion and appearance have to agree: a hover
# transition that outlasts the theme's hover plate swap reads as two separate
# effects. These are re-exported under their original names so the existing
# call sites (skirmish.gd, ui_dock.gd, ui_flyout.gd, ui_radial_menu.gd,
# parts_menu.gd) didn't all have to change in the same commit as the tokens.
const DURATION_INSTANT: float = UITokens.DURATION_INSTANT
const DURATION_FAST: float = UITokens.DURATION_FAST
const DURATION_NORMAL: float = UITokens.DURATION_NORMAL
const DURATION_SLOW: float = UITokens.DURATION_SLOW
const STAGGER_STEP: float = UITokens.STAGGER_STEP
const EASE_STANDARD := UITokens.EASE_STANDARD
const TRANS_STANDARD := UITokens.TRANS_STANDARD

# Slides a Control in from `from_offset` (relative to its own current/target
# position) while fading it in - a panel/card's entrance.
static func slide_in(node: Control, from_offset: Vector2, duration: float = DURATION_NORMAL) -> Tween:
	var target_pos = node.position
	node.position = target_pos + from_offset
	node.modulate.a = 0.0
	var tween = node.create_tween()
	tween.set_trans(TRANS_STANDARD)
	tween.set_ease(EASE_STANDARD)
	tween.tween_property(node, "position", target_pos, duration)
	tween.parallel().tween_property(node, "modulate:a", 1.0, duration)
	return tween

# A quick squash-then-release on press - real tactile feedback instead of
# just the theme's built-in pressed StyleBox swap.
static func button_press_feedback(button: Control) -> Tween:
	var tween = button.create_tween()
	tween.tween_property(button, "scale", Vector2(0.92, 0.92), DURATION_FAST * 0.4)
	tween.tween_property(button, "scale", Vector2.ONE, DURATION_FAST * 0.6)
	return tween

# A radial menu's entrance: scales up from small while fading in, with a
# slight overshoot.
#
# Deliberately NOT slide_in(). A ring opens AT a fixed point - the part it acts
# on - so it has nowhere to slide from; translating it would break the one
# thing the ring depends on, which is that its centre is exactly where the
# cursor already is. TRANS_BACK gives the overshoot that reads as a mechanism
# springing open, and EASE_OUT lands it without oscillation.
#
# The node must already be positioned before this is called - it animates
# `scale` about `pivot_offset` and never touches `position`.
static func ring_pop(node: Control, duration: float = DURATION_FAST) -> Tween:
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(0.72, 0.72)
	node.modulate.a = 0.0
	var tween = node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "scale", Vector2.ONE, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "modulate:a", 1.0, duration * 0.7)
	return tween


# Generic tween_method driver for a numeric roll-up (resource counters,
# score tallies, etc.) - deliberately takes a Callable rather than a fixed
# label/format string, since callers often need to update more than one
# value from a single interpolation parameter (e.g. metal AND crystal
# sharing one label's text).
static func roll_up(node: Object, from_value: float, to_value: float, duration: float, on_update: Callable) -> Tween:
	var tween = node.create_tween()
	tween.set_trans(TRANS_STANDARD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_method(on_update, from_value, to_value, duration)
	return tween

# A status toast's entrance - slides up slightly while fading in.
static func toast_slide_fade(node: Control, duration: float = DURATION_NORMAL) -> Tween:
	var start_pos = node.position
	node.position = start_pos + Vector2(0, 12)
	node.modulate.a = 0.0
	var tween = node.create_tween()
	tween.set_trans(TRANS_STANDARD)
	tween.set_ease(EASE_STANDARD)
	tween.tween_property(node, "position", start_pos, duration)
	tween.parallel().tween_property(node, "modulate:a", 1.0, duration)
	return tween

# Scene-transition fade (e.g. a victory/defeat dimming overlay) - sets the
# starting alpha itself (like slide_in()/toast_slide_fade() set their own
# starting position) so a caller doesn't have to remember to zero out
# modulate.a first; pass `from_alpha` explicitly for a fade-OUT instead.
static func fade(node: CanvasItem, target_alpha: float, duration: float = DURATION_SLOW, from_alpha: float = 0.0) -> Tween:
	node.modulate.a = from_alpha
	var tween = node.create_tween()
	tween.tween_property(node, "modulate:a", target_alpha, duration)
	return tween
