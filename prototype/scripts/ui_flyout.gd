class_name UIFlyout
extends PanelContainer
# A transient panel anchored to a control or a screen point - the "menu subpart
# that pops up contextually" from an old IDE.
#
# WHAT IT IS FOR. Everything currently parked permanently in the Design Lab's
# right rail because there was nowhere else to put it: the armour material
# picker, the faction picker, the blueprint namer, a part's detail card, the
# debug/options panel. None of those are needed continuously, and a control
# that is only occasionally relevant should be occasionally present. A flyout
# is how a rail row becomes a toolbar button.
#
# BEHAVIOUR:
#   * Anchored to a source Control's rect, with automatic flipping when it
#     would leave the viewport, or to a bare screen point.
#   * Dismissed by clicking outside it, by Esc, or by the caller.
#   * CANVAS backing, so it reads as a soft thing laid over the metal rather
#     than as another panel welded to the frame.
#
# WHY IT IS NOT A Popup/PopupPanel. Godot's Popup family opens a separate
# embedded (or OS) window with its own input routing. That works for menus, but
# these flyouts have to sit inside the Design Lab's canvas alongside the 3D
# viewport gizmos and the tweak callouts, share their z-order, and never steal a
# drag that started on the model. A plain Control inside the existing UI tree
# does all of that; a Popup fights it.

const Tokens = preload("res://scripts/ui_tokens.gd")
const UIAnim = preload("res://scripts/ui_anim.gd")

signal closed()

enum Align { BELOW, ABOVE, RIGHT_OF, LEFT_OF }

# Gap between the flyout and the control it hangs off.
const OFFSET := 6.0
# Keep this far clear of the viewport edge when clamping.
const SCREEN_PAD := 8.0

var _body: VBoxContainer
var _closing := false

# Bounds to keep the flyout inside. Zero-size means "ask the viewport", which
# is what production always wants.
#
# It exists as an override because placement that reads a global is placement
# that cannot be tested: a headless check has whatever window size the project
# settings imply, not the one the test set up, so every assertion about edge
# flipping and clamping would be measuring the wrong rectangle. Making the
# bounds an injectable input costs one property and turns the trickiest part of
# this class into something with real coverage.
var screen_bounds_override: Rect2 = Rect2()


func _bounds() -> Rect2:
	if screen_bounds_override.size.x > 0.0 and screen_bounds_override.size.y > 0.0:
		return screen_bounds_override
	return get_viewport_rect()


func _init() -> void:
	theme_type_variation = "FlyoutPanel"
	# Above docks and callouts. A contextual panel that opens UNDER the thing
	# that spawned it is worse than not opening.
	z_index = 20


func _ready() -> void:
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", Tokens.SPACE_SM)
	add_child(_body)
	# Outside clicks have to be seen even when they land on another control, so
	# this listens at the viewport level rather than relying on _gui_input.
	set_process_unhandled_input(true)


func body() -> VBoxContainer:
	return _body


# Convenience: a titled flyout. The heading is part of the flyout rather than
# something callers each rebuild, so every one of them looks the same.
func set_title(text: String) -> void:
	var label = Label.new()
	label.text = text.to_upper()
	label.theme_type_variation = "HeadingLabel"
	_body.add_child(label)
	_body.move_child(label, 0)
	var rule = HSeparator.new()
	_body.add_child(rule)
	_body.move_child(rule, 1)


# Opens the flyout hanging off `source`, flipping and clamping as needed.
#
# Must be called after the flyout is in the tree and has been laid out, because
# placement needs its real size - hence the deferred second pass. Placing on the
# first frame with a zero size puts every flyout in the top-left corner, which
# is the classic version of this bug.
func open_from(source: Control, align: int = Align.BELOW) -> void:
	_show_common()
	_place_deferred(func(): return _rect_for_source(source, align))


func open_at(point: Vector2) -> void:
	_show_common()
	_place_deferred(func(): return Vector2(point))


func _show_common() -> void:
	visible = true
	modulate.a = 0.0


func _place_deferred(compute: Callable) -> void:
	# Two frames: one for the container to compute its minimum size from its
	# children, one for that to become `size`.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or _closing:
		return
	position = _clamp_to_screen(compute.call())
	UIAnim.slide_in(self, Vector2(0, -6), UIAnim.DURATION_FAST)


func _rect_for_source(source: Control, align: int) -> Vector2:
	if not is_instance_valid(source):
		return Vector2.ZERO
	var r := source.get_global_rect()
	var s := size
	var b := _bounds()
	var vp := b.position + b.size

	# Preferred placement, then flip to the opposite side if that would run off
	# the screen. Flipping rather than merely clamping matters: a clamped
	# flyout can end up covering the very control that opened it.
	match align:
		Align.BELOW:
			if r.end.y + OFFSET + s.y > vp.y and r.position.y - OFFSET - s.y >= 0.0:
				return Vector2(r.position.x, r.position.y - OFFSET - s.y)
			return Vector2(r.position.x, r.end.y + OFFSET)
		Align.ABOVE:
			if r.position.y - OFFSET - s.y < 0.0:
				return Vector2(r.position.x, r.end.y + OFFSET)
			return Vector2(r.position.x, r.position.y - OFFSET - s.y)
		Align.RIGHT_OF:
			if r.end.x + OFFSET + s.x > vp.x and r.position.x - OFFSET - s.x >= 0.0:
				return Vector2(r.position.x - OFFSET - s.x, r.position.y)
			return Vector2(r.end.x + OFFSET, r.position.y)
		_:
			if r.position.x - OFFSET - s.x < 0.0:
				return Vector2(r.end.x + OFFSET, r.position.y)
			return Vector2(r.position.x - OFFSET - s.x, r.position.y)


func _clamp_to_screen(pos: Vector2) -> Vector2:
	var b := _bounds()
	var lo := b.position + Vector2(SCREEN_PAD, SCREEN_PAD)
	var hi := b.end - size - Vector2(SCREEN_PAD, SCREEN_PAD)
	return Vector2(
		clampf(pos.x, lo.x, maxf(lo.x, hi.x)),
		clampf(pos.y, lo.y, maxf(lo.y, hi.y)))


func _unhandled_input(event: InputEvent) -> void:
	if _closing or not visible:
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
		return

	if event is InputEventMouseButton and event.pressed:
		# Only an outside click dismisses. Clicks that land ON the flyout are
		# consumed by its own children before reaching _unhandled_input, so
		# reaching here at all already means "not on a child" - but the rect
		# check is kept because the flyout's own padding is not a child.
		if not get_global_rect().has_point(event.global_position):
			close()


func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, UIAnim.DURATION_FAST)
	tween.tween_callback(queue_free)


# Builds a flyout, parents it, and returns it ready for content.
#
# Static because essentially every call site does the same four lines, and the
# one that forgets to add_child before open_from() gets a flyout that never
# lays out and therefore never places correctly.
static func create(parent: Node, title: String = "") -> UIFlyout:
	var f = UIFlyout.new()
	parent.add_child(f)
	if title != "":
		f.set_title(title)
	return f
