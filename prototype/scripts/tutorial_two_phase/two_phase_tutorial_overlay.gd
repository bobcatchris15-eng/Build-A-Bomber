extends Control
# The two-phase tutorial's chrome: a dimming scrim with a hole cut in it over
# whatever the current step is talking about, plus a coach card beside the hole.
#
# PERMISSIVE BY CONSTRUCTION. This Control is MOUSE_FILTER_IGNORE, so every click
# and drag passes straight through to the game underneath - the spotlight is a
# suggestion, not a gate. Only the card itself takes input, because its buttons
# have to work. A player who ignores the highlight and does something else
# entirely is not blocked, and the step's condition simply stays unmet.

const Tokens = preload("res://scripts/ui_tokens.gd")
const TwoPhaseTutorialSteps = preload("res://scripts/tutorial_two_phase/two_phase_tutorial_steps.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")

const SCRIM_COLOR := Color(0.03, 0.03, 0.028, 0.62)
const SPOTLIGHT_PAD := 10.0
const RING_WIDTH := 2.0
const CARD_WIDTH := 420.0
const CARD_GAP := 18.0
const EDGE_MARGIN := 24.0

# A step whose target cannot be resolved this frame draws no hole at all
# rather than a hole in the wrong place. An empty Rect2 is the sentinel.
var _spot: Rect2 = Rect2()

var manager: Node = null

var _card: PanelContainer = null
var _counter_label: Label = null
var _title_label: Label = null
var _body_label: Label = null
var _action_button: Button = null
var _skip_button: Button = null

var _phase: int = 1
var _step_index: int = -1
var _step: Dictionary = {}
# The part card for a "part_card:" step, found ONCE when the step opens.
var _card_target: Button = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)


func _ready() -> void:
	_build_card()
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)


func _fit_to_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


# --- Step presentation ------------------------------------------------------

func show_step(phase: int, index: int, step: Dictionary) -> void:
	_phase = phase
	_step_index = index
	_step = step

	_counter_label.text = "PHASE %d  •  STEP %d / %d" % [phase, index + 1, TwoPhaseTutorialSteps.count_for_phase(phase)]
	_title_label.text = str(step.get("title", ""))
	_body_label.text = str(step.get("body", ""))

	var advance := str(step.get("advance", ""))
	_action_button.visible = TwoPhaseTutorialSteps.is_button_step(advance)
	_action_button.text = "FINISH" if advance == "finish_button" else "NEXT"

	# Open whichever dock owns this step's target BEFORE the first resolve
	_reveal_target_host(str(step.get("target", "")))
	queue_redraw()


func _process(_delta: float) -> void:
	if _step.is_empty():
		return
	var previous := _spot
	_spot = _resolve_target(str(_step.get("target", "")))
	_place_card()
	if _spot != previous:
		queue_redraw()


# --- Target resolution ------------------------------------------------------

func _resolve_target(target: String) -> Rect2:
	if target == "":
		return Rect2()

	if target.begins_with(TwoPhaseTutorialSteps.PART_CARD_PREFIX):
		return _control_rect(_card_target)

	match target:
		"parts_dock":
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


func _reveal_target_host(target: String) -> void:
	var UIDockScript = load("res://scripts/ui_dock.gd")
	_card_target = null
	if target.begins_with(TwoPhaseTutorialSteps.PART_CARD_PREFIX):
		var parts_panel := _parts_menu()
		if parts_panel:
			_card_target = parts_panel.reveal_part(
				target.substr(TwoPhaseTutorialSteps.PART_CARD_PREFIX.length()))
	elif target == "parts_dock":
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


func _stat_member(member: String):
	var ui := get_tree().get_first_node_in_group("stat_ui")
	if ui == null:
		return null
	return ui.get(member)


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

	# Four bands around the hole
	draw_rect(Rect2(0, 0, size.x, hole.position.y), SCRIM_COLOR)
	draw_rect(Rect2(0, hole.end.y, size.x, size.y - hole.end.y), SCRIM_COLOR)
	draw_rect(Rect2(0, hole.position.y, hole.position.x, hole.size.y), SCRIM_COLOR)
	draw_rect(Rect2(hole.end.x, hole.position.y, size.x - hole.end.x, hole.size.y),
		SCRIM_COLOR)

	draw_rect(hole, Tokens.SIGNAL_HAZARD, false, RING_WIDTH)


# --- The coach card ---------------------------------------------------------

func _build_card() -> void:
	_card = PanelContainer.new()
	_card.name = "CoachCard"
	_card.theme_type_variation = "CardPanel"
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

	# Always present SKIP button
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


func _place_card() -> void:
	var card_size := _card.get_combined_minimum_size()
	card_size.x = maxf(card_size.x, CARD_WIDTH)

	if _spot.size.x <= 0.0:
		_card.position = (size - card_size) * 0.5
		_card.size = card_size
		return

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
		_card.position = pos
		_card.size = card_size
		return

	pos.y = clampf(_spot.get_center().y - card_size.y * 0.5,
		EDGE_MARGIN, maxf(size.y - card_size.y - EDGE_MARGIN, EDGE_MARGIN))
	_card.position = pos
	_card.size = card_size