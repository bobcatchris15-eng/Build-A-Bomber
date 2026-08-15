class_name DeployGate
extends Control
# The deploy gate: the last beat of a battle's opening sequence.
#
# WHAT THIS IS: A full-screen tactical viewport overlay that sits between
# the camera and the world during match preparation. It provides:
#   1. A full-screen heavily frosted glass visor (shaders/deploy_glass.gdshader)
#      that diffuses, softens, and dims the world while terrain/navmesh bake.
#   2. A centered industrial command console bezel housing system readiness
#      telemetry, milestone progress, and the physical 3D DEPLOY actuator.
#   3. Clean lifecycle management: pauses the tree once all systems are ready,
#      awaits player commitment via DEPLOY, unpauses simulation, and dissolves.

const Tokens = preload("res://scripts/ui_tokens.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const UIShell = preload("res://scripts/ui_shell.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")
const UILampsScript = preload("res://scripts/ui_lamps.gd")
const StampedButtonScript = preload("res://scripts/ui_stamped_button.gd")
const MatchRuleSetScript = preload("res://scripts/match_rule_set.gd")

const GlassShader = preload("res://shaders/deploy_glass.gdshader")

# Button and bezel dimensions
const BUTTON_MIN_SIZE := Vector2(280, 52)
const BEZEL_MIN_WIDTH := 520.0
const BEZEL_BORDER := 2
const BEZEL_INSET_H := 32
const BEZEL_INSET_V := 24

const READY_BORDER := Tokens.SIGNAL_GO
const BUILD_BORDER := Tokens.BASE_500
const BEZEL_BORDER_EASE := Tokens.DURATION_NORMAL
const BEZEL_LAMP_COUNT := 6
const DISMISS_FADE := Tokens.DURATION_NORMAL
const READY_TIMEOUT := 30.0

signal deploy_pressed

var _glass: ColorRect
var _bezel: Panel
var _bezel_stylebox: StyleBoxFlat
var _bezel_lamps: Array[ColorRect] = []
var _status_label: Label
var _step_label: Label
var _bar: ProgressBar
var _lamps: UILamps
var _button: StampedButton

var _director: Node = null
var _state: String = "build"


func _ready() -> void:
	# DeployGate is a full-screen overlay Control
	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_glass()
	_build_bezel_container()


# ---------------------------------------------------------------------------
# Visual Assembly
# ---------------------------------------------------------------------------

func _build_glass() -> void:
	_glass = ColorRect.new()
	_glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glass.anchor_left = 0.0
	_glass.anchor_top = 0.0
	_glass.anchor_right = 1.0
	_glass.anchor_bottom = 1.0
	_glass.offset_left = 0.0
	_glass.offset_top = 0.0
	_glass.offset_right = 0.0
	_glass.offset_bottom = 0.0
	_glass.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_glass.grow_vertical = Control.GROW_DIRECTION_BOTH
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.color = Color(1.0, 1.0, 1.0, 1.0)

	var mat := ShaderMaterial.new()
	mat.shader = GlassShader
	mat.set_shader_parameter("alpha", 0.85)
	mat.set_shader_parameter("tint", Tokens.BASE_900)
	mat.set_shader_parameter("blur_amount", 1.0)
	mat.set_shader_parameter("blur_radius", 18.0)
	mat.set_shader_parameter("frost_amount", 0.22)
	mat.set_shader_parameter("refraction_amount", 0.008)
	mat.set_shader_parameter("vignette_amount", 0.45)
	_glass.material = mat

	add_child(_glass)


func _build_bezel_container() -> void:
	var center := CenterContainer.new()
	center.name = "CenterContainer"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.anchor_left = 0.0
	center.anchor_top = 0.0
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.offset_left = 0.0
	center.offset_top = 0.0
	center.offset_right = 0.0
	center.offset_bottom = 0.0
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_bezel = Panel.new()
	_bezel.custom_minimum_size = Vector2(BEZEL_MIN_WIDTH, 0.0)
	_bezel.mouse_filter = Control.MOUSE_FILTER_STOP

	_bezel_stylebox = StyleBoxFlat.new()
	_bezel_stylebox.bg_color = Color(0.04, 0.04, 0.05, 0.88)
	_bezel_stylebox.border_width_left = BEZEL_BORDER
	_bezel_stylebox.border_width_right = BEZEL_BORDER
	_bezel_stylebox.border_width_top = BEZEL_BORDER
	_bezel_stylebox.border_width_bottom = BEZEL_BORDER
	_bezel_stylebox.border_color = BUILD_BORDER
	_bezel_stylebox.corner_radius_top_left = 8
	_bezel_stylebox.corner_radius_top_right = 8
	_bezel_stylebox.corner_radius_bottom_left = 8
	_bezel_stylebox.corner_radius_bottom_right = 8
	_bezel_stylebox.content_margin_left = BEZEL_INSET_H
	_bezel_stylebox.content_margin_right = BEZEL_INSET_H
	_bezel_stylebox.content_margin_top = BEZEL_INSET_V
	_bezel_stylebox.content_margin_bottom = BEZEL_INSET_V
	_bezel.add_theme_stylebox_override("panel", _bezel_stylebox)

	UITheme.apply_material(_bezel, "steel", {
		"brightness": 0.45,
		"wear": 0.20,
		"grime": 0.12,
		"scale": 1.4,
		"vignette": 0.20,
	})
	center.add_child(_bezel)

	_build_inner_column()


func _build_inner_column() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Tokens.SPACE_MD)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bezel.add_child(col)

	# Tactical Header Tag
	var header_tag := Label.new()
	header_tag.text = "TACTICAL COMMAND LINK // ENGAGEMENT STAGING"
	header_tag.theme_type_variation = "StatLabel"
	header_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_tag.add_theme_color_override("font_color", Tokens.BASE_400)
	col.add_child(header_tag)

	var sep := HSeparator.new()
	col.add_child(sep)

	# Primary System Status
	_status_label = Label.new()
	_status_label.text = "PREPARING DEPLOYMENT"
	_status_label.theme_type_variation = "TitleLabel"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status_label)

	# Detailed Phase Step Label
	_step_label = Label.new()
	_step_label.text = "Initializing systems..."
	_step_label.theme_type_variation = "StatLabel"
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step_label.add_theme_color_override("font_color", Tokens.TEXT_SECONDARY)
	col.add_child(_step_label)

	# Calibration & Build Progress Bar
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 8)
	col.add_child(_bar)

	# Animated Sweep Lamps
	_lamps = UILampsScript.new()
	col.add_child(_lamps)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, Tokens.SPACE_XS)
	col.add_child(spacer)

	_build_lamps_and_button_row(col)


func _build_lamps_and_button_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.SPACE_MD)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(row)

	# Left status LED array
	var left_box := HBoxContainer.new()
	left_box.add_theme_constant_override("separation", Tokens.SPACE_XS)
	for _i in range(BEZEL_LAMP_COUNT / 2):
		left_box.add_child(_make_bezel_lamp())
	row.add_child(left_box)

	# Center Spacer Left
	var left_spacer := Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left_spacer)

	# Tactile 3D Stamped Deploy Button
	_button = StampedButtonScript.new()
	_button.legend = "DEPLOY FORCES"
	_button.variant = StampedButtonScript.Variant.PRIMARY
	_button.custom_minimum_size = BUTTON_MIN_SIZE
	_button.disabled = true
	_button.pressed.connect(_on_deploy_pressed)
	UIFeedbackScript.wire(_button, "confirm")
	row.add_child(_button)

	# Center Spacer Right
	var right_spacer := Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right_spacer)

	# Right status LED array
	var right_box := HBoxContainer.new()
	right_box.add_theme_constant_override("separation", Tokens.SPACE_XS)
	for _i in range(BEZEL_LAMP_COUNT / 2):
		right_box.add_child(_make_bezel_lamp())
	row.add_child(right_box)


func _make_bezel_lamp() -> ColorRect:
	var lamp := ColorRect.new()
	lamp.custom_minimum_size = Vector2(10, 10)
	lamp.color = Tokens.BASE_700
	lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bezel_lamps.append(lamp)
	return lamp


# ---------------------------------------------------------------------------
# Lifecycle & State Machine
# ---------------------------------------------------------------------------

func start() -> void:
	_director = get_tree().current_scene
	if _director != null and _director.has_signal("progress"):
		_director.progress.connect(_on_progress)
		if _director.has_method("get_last_progress"):
			var current: Dictionary = _director.get_last_progress()
			if current.get("fraction", 0.0) > 0.0:
				_on_progress(float(current["fraction"]), str(current.get("label", "")))
	_poll_world_is_ready()


func mark_ready() -> void:
	if _state != "build":
		return
	_state = "ready"

	# Pause simulation tree so player can survey before initiating combat
	get_tree().paused = true

	var tween := create_tween()
	tween.tween_property(_bezel_stylebox, "border_color", READY_BORDER, BEZEL_BORDER_EASE)
	tween.parallel().tween_method(_set_glass_blur, 1.0, 1.3, BEZEL_BORDER_EASE)
	tween.parallel().tween_method(_set_glass_alpha, 0.85, 0.90, BEZEL_BORDER_EASE)

	# Activate all bezel status LEDs
	for lamp in _bezel_lamps:
		lamp.color = READY_BORDER

	# Status text and color transition
	_status_label.text = _ready_status_text()
	_status_label.add_theme_color_override("font_color", READY_BORDER)
	_step_label.text = "Systems synchronized // Ready to deploy"
	_step_label.add_theme_color_override("font_color", Tokens.SIGNAL_GO)

	# Enable and focus deploy button
	_button.disabled = false
	_button.grab_focus()


func _ready_status_text() -> String:
	if _director == null or not ("_match_rule_set" in _director):
		return "ALL SYSTEMS READY"
	var rs = _director._match_rule_set
	if rs == null:
		return "ALL SYSTEMS READY"
	if rs.mode == MatchRuleSetScript.Mode.OPERATIONS:
		var ops := get_tree().root.get_node_or_null("OperationsManager")
		if ops != null:
			var n: int = int(ops.current_stage) + 1
			var total: int = int(ops.total_stages)
			return "ENGAGEMENT %d OF %d — ALL SYSTEMS READY" % [n, total]
	elif rs.mode == MatchRuleSetScript.Mode.TEST_RANGE:
		return "PROVING GROUND // READY"
	return "ALL SYSTEMS READY"


func _on_deploy_pressed() -> void:
	if _state != "ready":
		return
	deploy_pressed.emit()


func dismiss() -> void:
	if _state == "dismissed":
		return
	_state = "dismissed"
	get_tree().paused = false

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_method(_set_glass_alpha, 0.90, 0.0, DISMISS_FADE)
	tween.tween_property(self, "modulate:a", 0.0, DISMISS_FADE)
	await tween.finished
	queue_free()


func _set_glass_alpha(value: float) -> void:
	if _glass == null or _glass.material == null:
		return
	(_glass.material as ShaderMaterial).set_shader_parameter("alpha", value)


func _set_glass_blur(value: float) -> void:
	if _glass == null or _glass.material == null:
		return
	(_glass.material as ShaderMaterial).set_shader_parameter("blur_amount", value)


func _on_progress(fraction: float, label: String) -> void:
	_bar.value = clampf(fraction, 0.0, 1.0)
	if label != "" and is_instance_valid(_step_label):
		_step_label.text = label
	if fraction >= 1.0 and _state == "build":
		mark_ready()


func _poll_world_is_ready() -> void:
	if _director == null:
		return
	var waited := 0.0
	while _state == "build":
		if "world_is_ready" in _director and _director.world_is_ready:
			mark_ready()
			return
		if waited >= READY_TIMEOUT:
			push_warning("DeployGate: world_is_ready timed out after %.1fs, forcing ready" % READY_TIMEOUT)
			mark_ready()
			return
		await get_tree().process_frame
		waited += get_process_delta_time()
