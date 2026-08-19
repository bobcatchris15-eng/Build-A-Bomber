extends Control
# The tutorial's one piece of chrome: a dimming scrim with a hole cut in it over
# whatever the current step is talking about, plus a coach card beside the hole.
#
# PERMISSIVE BY CONSTRUCTION. This Control is MOUSE_FILTER_IGNORE, so every click
# and drag passes straight through to the game underneath - the spotlight is a
# suggestion, not a gate. Only the card itself takes input, because its buttons
# have to work. A player who ignores the highlight and does something else
# entirely is not blocked, and the step's condition simply stays unmet.
#
# WHY THE HOLE IS FOUR RECTS: StyleBoxFlat has no cutout and Godot has no
# clip-inverse for a filled rect. Drawing the dim as four bands around the
# spotlight is exact, allocation-free, and survives the target rect changing
# every frame (which it does - the hull's screen rect moves as the camera
# orbits).
#
# Parented to a CanvasLayer by tutorial_manager.gd. A Control under a CanvasLayer
# is NOT auto-sized, because a CanvasLayer has no rect to inherit - hence the
# explicit PRESET_TOP_LEFT plus _fit_to_viewport(), re-run on size_changed. Same
# trap production_hud.gd hit.
#
# Hand-hold mode: the spotlight ring breathes (pulsing width), a directional
# chevron arrow points from the coach card toward the target, and the card
# slides smoothly to its new position on step change. The NEXT/FINISH button
# also pulses to draw the eye when it is the step's advance condition.

const Tokens = preload("res://scripts/ui_tokens.gd")
const TutorialSteps = preload("res://scripts/tutorial/tutorial_steps.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")
const UIAnimScript = preload("res://scripts/ui_anim.gd")

const SCRIM_COLOR := Color(0.03, 0.03, 0.028, 0.62)
const SPOTLIGHT_PAD := 10.0
const RING_WIDTH := 2.0
const RING_PULSE_AMPLITUDE := 1.5
const RING_PULSE_PERIOD := 0.8
const CARD_WIDTH := 420.0
const CARD_GAP := 18.0
const EDGE_MARGIN := 24.0
const ARROW_LEN := 12.0
const ARROW_HEAD := 8.0
const ARROW_PAD_OUTER := 12.0
const ARROW_PAD_INNER := 8.0
const SETTLE_DELAY := 0.15

# A step whose target cannot be resolved this frame (the dock is still animating
# open, the hull is behind the camera) draws no hole at all rather than a hole in
# the wrong place. An empty Rect2 is the sentinel.
var _spot: Rect2 = Rect2()

var manager: Node = null

var _card: PanelContainer = null
var _counter_label: Label = null
var _title_label: Label = null
var _body_label: Label = null
var _action_button: Button = null
var _skip_button: Button = null

var _step_index: int = -1
var _step: Dictionary = {}
# The part card for a "part_card:" step, found ONCE when the step opens. Looking
# it up per frame would mean re-forcing the dock, tier and drawer open sixty
# times a second, which would fight a player who deliberately closed one - the
# exact opposite of what the scrim's pass-through is for. Cached, the drawer
# closing simply makes the card invisible and the spotlight quietly goes away.
var _card_target: Button = null

# --- Hand-hold animation state -----------------------------------------------
var _pulse_time: float = 0.0
var _pulse_amplitude: float = 0.0
var _pulse_tween: Tween = null
var _button_pulse_tween: Tween = null
var _card_slide_tween: Tween = null
var _settle_timer: float = 0.0
var _previous_step_key: String = ""
var _arrow_from: Vector2 = Vector2.ZERO
var _arrow_to: Vector2 = Vector2.ZERO
var _show_arrow: bool = false
var _arrow_alpha: float = 0.0


func _init() -> void:
	# See the header: the overlay must never eat a click meant for the Lab.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)


func _ready() -> void:
	_build_card()
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)


func _fit_to_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _exit_tree() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	if _button_pulse_tween and _button_pulse_tween.is_valid():
		_button_pulse_tween.kill()
	if _card_slide_tween and _card_slide_tween.is_valid():
		_card_slide_tween.kill()


# --- Step presentation ------------------------------------------------------

func show_step(index: int, step: Dictionary) -> void:
	_step_index = index
	_step = step

	_counter_label.text = "STEP %d / %d" % [index + 1, TutorialSteps.count()]
	_title_label.text = str(step.get("title", ""))
	_body_label.text = str(step.get("body", ""))

	var advance := str(step.get("advance", ""))
	_action_button.visible = TutorialSteps.is_button_step(advance)
	_action_button.text = "FINISH" if advance == "finish_button" else "NEXT"

	# Open whichever dock owns this step's target BEFORE the first resolve, or
	# the card spends its opening frames pointing at a 40px collapsed rail.
	_reveal_target_host(str(step.get("target", "")))

	var step_key := "%d:%s" % [index, str(step.get("target", ""))]
	var is_step_change := step_key != _previous_step_key
	_previous_step_key = step_key

	_pulse_time = 0.0
	_settle_timer = SETTLE_DELAY if is_step_change else 0.0
	var has_target := str(step.get("target", "")) != ""
	_pulse_amplitude = RING_PULSE_AMPLITUDE if has_target else 0.0
	_start_button_pulse(advance)
	queue_redraw()

	_place_card_animated(is_step_change)


func _process(_delta: float) -> void:
	if _step.is_empty():
		return

	if _settle_timer > 0.0:
		_settle_timer = maxf(_settle_timer - _delta, 0.0)

	_pulse_time += _delta

	var previous := _spot
	_spot = _resolve_target(str(_step.get("target", "")))
	_update_arrow()
	_place_card()
	if _spot != previous:
		queue_redraw()


# --- Target resolution ------------------------------------------------------

# Screen rect for a target id, or an empty Rect2 when it cannot be resolved
# right now. Every id here is declared in TutorialSteps.TARGET_IDS (plus the
# "part_card:" prefix family), and test_tutorial.gd asserts the two agree.
func _resolve_target(target: String) -> Rect2:
	if target == "":
		return Rect2()

	if target.begins_with(TutorialSteps.PART_CARD_PREFIX):
		return _control_rect(_card_target)

	match target:
		"parts_dock":
			# The bottom strip of four toolboxes + magnifying glass.
			# The dock is gone - there is no UIDock to expand - so the
			# spotlight is the union rect of the bar's plates, not a
			# dock's expanded panel.
			var parts := _parts_menu()
			if parts and parts.has_method("get_bar_focus_rect"):
				var r: Rect2 = parts.get_bar_focus_rect()
				if r.size.x > 0.0 and r.size.y > 0.0:
					return r
			return Rect2()
		"telemetry_dock":
			return _control_rect(_stat_member("stats_dock"))
		"name_field":
			return _control_rect(_stat_member("blueprint_name_edit"))
		"toolbar_save":
			return _control_rect(_stat_member("save_button"))
		"toolbar_test":
			return _control_rect(_stat_member("test_button"))
		"hull":
			var placer := _lab()
			if placer == null or not is_instance_valid(placer.hull):
				return Rect2()
			return _world_rect(placer.hull.global_position, 3.2)
		"arena_dummy":
			var arena := _arena()
			if arena == null:
				return Rect2()
			for dummy in arena.target_dummies:
				if is_instance_valid(dummy):
					return _world_rect(dummy.global_position, 2.4)
			return Rect2()
		"arena_return":
			var arena_scene := _arena()
			if arena_scene == null:
				return Rect2()
			return _control_rect(arena_scene.get_node_or_null("UI/ReturnButton"))
	return Rect2()


# Expands the dock a target lives inside. Called once per step rather than every
# frame, so a player who deliberately collapses the dock mid-step is not fought
# with - that is the same permissiveness the scrim has.
func _reveal_target_host(target: String) -> void:
	var UIDockScript = load("res://scripts/ui_dock.gd")
	_card_target = null
	if target.begins_with(TutorialSteps.PART_CARD_PREFIX):
		var parts_panel := _parts_menu()
		if parts_panel:
			# reveal_part() expands the dock, the tier AND the drawer, so there is
			# nothing left to do to the dock here.
			_card_target = parts_panel.reveal_part(
				target.substr(TutorialSteps.PART_CARD_PREFIX.length()))
	elif target == "parts_dock":
		# The bottom strip is always visible - no expansion to do. The
		# "find" half of the tutorial step happens through the body
		# text; the strip does not collapse.
		pass
	elif target in ["telemetry_dock", "name_field"]:
		var dock2 = _stat_member("stats_dock")
		if dock2:
			dock2.set_dock_state(UIDockScript.State.EXPANDED)


func _control_rect(node) -> Rect2:
	if node == null or not is_instance_valid(node) or not (node is Control):
		return Rect2()
	var c := node as Control
	if not c.is_visible_in_tree() or c.size.x <= 0.0 or c.size.y <= 0.0:
		return Rect2()
	return Rect2(c.global_position, c.size)


# A world point as a screen rect. The radius is measured along the camera's own
# right vector so the spotlight tracks zoom - a fixed pixel radius would swallow
# the whole screen when the designer camera dollies in.
func _world_rect(world_pos: Vector3, radius: float) -> Rect2:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(world_pos):
		return Rect2()
	var centre := cam.unproject_position(world_pos)
	var edge := cam.unproject_position(world_pos + cam.global_transform.basis.x * radius)
	var r: float = maxf(absf(edge.x - centre.x), 40.0)
	return Rect2(centre - Vector2(r, r), Vector2(r, r) * 2.0)


func _lab() -> Node:
	var scene := get_tree().current_scene
	if scene and scene.has_method("_place_hull_from_ui"):
		return scene
	return null


func _arena() -> Node:
	var scene := get_tree().current_scene
	if scene and "target_dummies" in scene:
		return scene
	return null


func _parts_menu() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var menu := scene.get_node_or_null("UI_PartsMenu")
	if menu and menu.has_method("reveal_part"):
		return menu
	return null


# The Lab's toolbar reparents save/test/name out of UI_StatBlock.tscn, so their
# node paths are worthless - but stat_calculator.gd's own member references stay
# valid across the move. Go through the group and read the member.
func _stat_member(member: String):
	var ui := get_tree().get_first_node_in_group("stat_ui")
	if ui == null:
		return null
	return ui.get(member)


# --- Arrow ------------------------------------------------------------------

func _update_arrow() -> void:
	var target := str(_step.get("target", ""))
	if _spot.size.x <= 0.0 or _spot.size.y <= 0.0 or target == "":
		_show_arrow = false
		_arrow_alpha = 0.0
		queue_redraw()
		return

	if target in ["hull", "arena_dummy", ""]:
		_show_arrow = false
		_arrow_alpha = 0.0
		queue_redraw()
		return

	var card_rect := Rect2(_card.position, _card.size)
	var target_center := _spot.get_center()
	var card_center := card_rect.get_center()

	var from := Vector2.ZERO
	if absf(card_center.x - target_center.x) > absf(card_center.y - target_center.y):
		if card_center.x < target_center.x:
			from = Vector2(card_rect.end.x, card_rect.get_center().y)
		else:
			from = Vector2(card_rect.position.x, card_rect.get_center().y)
	else:
		if card_center.y < target_center.y:
			from = Vector2(card_rect.get_center().x, card_rect.end.y)
		else:
			from = Vector2(card_rect.get_center().x, card_rect.position.y)

	var dir := (target_center - from).normalized()
	if dir.length() < 0.01:
		_show_arrow = false
		_arrow_alpha = 0.0
		queue_redraw()
		return

	_arrow_from = from + dir * ARROW_PAD_OUTER
	_arrow_to = target_center - dir * ARROW_PAD_INNER
	_show_arrow = true

	var pulse_cycle := fmod(_pulse_time, RING_PULSE_PERIOD) / RING_PULSE_PERIOD
	_arrow_alpha = 0.55 + 0.45 * sin(pulse_cycle * TAU)
	queue_redraw()


func _draw_arrow() -> void:
	if not _show_arrow or _arrow_alpha <= 0.01:
		return

	var col := Color(Tokens.SIGNAL_HAZARD.r, Tokens.SIGNAL_HAZARD.g, Tokens.SIGNAL_HAZARD.b, _arrow_alpha)
	var dir := (_arrow_to - _arrow_from).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var shaft_end := _arrow_to - dir * ARROW_HEAD

	draw_line(_arrow_from, shaft_end, col, 2.0, true)
	draw_line(shaft_end + perp * (ARROW_HEAD * 0.5), _arrow_to, col, 2.0, true)
	draw_line(shaft_end - perp * (ARROW_HEAD * 0.5), _arrow_to, col, 2.0, true)


# --- Button pulse -----------------------------------------------------------

func _start_button_pulse(advance: String) -> void:
	if _button_pulse_tween and _button_pulse_tween.is_valid():
		_button_pulse_tween.kill()
		_button_pulse_tween = null

	if advance in ["next_button", "finish_button"] and _action_button.visible:
		_action_button.modulate.a = 0.7
		var tw := _action_button.create_tween().set_loops()
		tw.tween_property(_action_button, "modulate:a", 1.0, RING_PULSE_PERIOD * 0.5) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(_action_button, "modulate:a", 0.7, RING_PULSE_PERIOD * 0.5) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		_button_pulse_tween = tw
	else:
		_action_button.modulate.a = 1.0


# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	var screen := Rect2(Vector2.ZERO, size)
	if _spot.size.x <= 0.0 or _spot.size.y <= 0.0:
		draw_rect(screen, SCRIM_COLOR)
		return

	var hole := _spot.grow(SPOTLIGHT_PAD).intersection(screen)
	if hole.size.x <= 0.0 or hole.size.y <= 0.0:
		draw_rect(screen, SCRIM_COLOR)
		return

	# Four bands around the hole. See the header for why this rather than a mask.
	draw_rect(Rect2(0, 0, size.x, hole.position.y), SCRIM_COLOR)
	draw_rect(Rect2(0, hole.end.y, size.x, size.y - hole.end.y), SCRIM_COLOR)
	draw_rect(Rect2(0, hole.position.y, hole.position.x, hole.size.y), SCRIM_COLOR)
	draw_rect(Rect2(hole.end.x, hole.position.y, size.x - hole.end.x, hole.size.y),
		SCRIM_COLOR)

	# Pulsing spotlight ring.
	var ring_w := RING_WIDTH
	if _settle_timer <= 0.0 and _pulse_amplitude > 0.0:
		var phase := fmod(_pulse_time, RING_PULSE_PERIOD) / RING_PULSE_PERIOD
		ring_w = RING_WIDTH + _pulse_amplitude * sin(phase * TAU)
	draw_rect(hole, Tokens.SIGNAL_HAZARD, false, ring_w)

	_draw_arrow()


# --- The coach card ---------------------------------------------------------

func _build_card() -> void:
	_card = PanelContainer.new()
	_card.name = "CoachCard"
	_card.theme_type_variation = "CardPanel"
	# The one node here that takes input, because its buttons must be clickable.
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	add_child(_card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", Tokens.SPACE_MD)
	margin.add_theme_constant_override("margin_right", Tokens.SPACE_MD)
	margin.add_theme_constant_override("margin_top", Tokens.SPACE_MD)
	margin.add_theme_constant_override("margin_bottom", Tokens.SPACE_MD)
	_card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", Tokens.SPACE_SM)
	margin.add_child(vbox)

	_counter_label = Label.new()
	_counter_label.theme_type_variation = "HintLabel"
	_counter_label.add_theme_color_override("font_color", Tokens.SIGNAL_HAZARD)
	vbox.add_child(_counter_label)

	_title_label = Label.new()
	_title_label.theme_type_variation = "HeadingLabel"
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_title_label)

	_body_label = Label.new()
	_body_label.theme_type_variation = "HintLabel"
	_body_label.add_theme_color_override("font_color", Tokens.TEXT_PRIMARY)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(CARD_WIDTH - Tokens.SPACE_MD * 2, 0)
	vbox.add_child(_body_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.SPACE_SM)
	vbox.add_child(row)

	# Always present, at every step including mid-arena. An onboarding flow a
	# player cannot leave is a trap, and the one thing worse than no tutorial is
	# a tutorial holding the game hostage on a step whose condition has broken.
	_skip_button = Button.new()
	_skip_button.name = "SkipButton"
	_skip_button.text = "SKIP TUTORIAL"
	_skip_button.custom_minimum_size = Vector2(0, Tokens.HIT_TARGET_MIN)
	_skip_button.pressed.connect(func(): if manager: manager.skip())
	UIFeedbackScript.wire(_skip_button)
	row.add_child(_skip_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_action_button = Button.new()
	_action_button.name = "ActionButton"
	_action_button.theme_type_variation = "PrimaryButton"
	_action_button.custom_minimum_size = Vector2(120, Tokens.HIT_TARGET_MIN)
	_action_button.pressed.connect(func(): if manager: manager.notify_button())
	UIFeedbackScript.wire(_action_button, "confirm")
	row.add_child(_action_button)


# Beside the spotlight when there is one, centred when there is not. Flips to
# whichever side has room so the card never runs off-screen and never covers the
# very thing it is pointing at.
func _place_card() -> void:
	var card_size := _card.get_combined_minimum_size()
	card_size.x = maxf(card_size.x, CARD_WIDTH)
	var pos := _compute_card_pos(card_size)
	_card.position = pos
	_card.size = card_size


func _compute_card_pos(card_size: Vector2) -> Vector2:
	if _spot.size.x <= 0.0:
		return (size - card_size) * 0.5

	var pos := Vector2.ZERO
	var right_edge := _spot.end.x + CARD_GAP
	if right_edge + card_size.x + EDGE_MARGIN <= size.x:
		pos.x = right_edge
	elif _spot.position.x - CARD_GAP - card_size.x >= EDGE_MARGIN:
		pos.x = _spot.position.x - CARD_GAP - card_size.x
	else:
		pos.x = clampf(_spot.get_center().x - card_size.x * 0.5,
			EDGE_MARGIN, size.x - card_size.x - EDGE_MARGIN)
		if _spot.end.y + CARD_GAP + card_size.y + EDGE_MARGIN <= size.y:
			pos.y = _spot.end.y + CARD_GAP
		else:
			pos.y = maxf(_spot.position.y - CARD_GAP - card_size.y, EDGE_MARGIN)
		return pos

	pos.y = clampf(_spot.get_center().y - card_size.y * 0.5,
		EDGE_MARGIN, maxf(size.y - card_size.y - EDGE_MARGIN, EDGE_MARGIN))
	return pos


func _place_card_animated(is_step_change: bool) -> void:
	var card_size := _card.get_combined_minimum_size()
	card_size.x = maxf(card_size.x, CARD_WIDTH)
	var new_pos := _compute_card_pos(card_size)
	_card.size = card_size

	if not is_step_change or _card.position == Vector2.ZERO:
		_card.position = new_pos
		return

	if _card_slide_tween and _card_slide_tween.is_valid():
		_card_slide_tween.kill()
	_card_slide_tween = UIAnimScript.card_slide_to(_card, new_pos)
