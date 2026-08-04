extends Control
# The screen shown while SceneRouter loads the next scene on a worker thread.
#
# Its whole job is to prove the app is alive. That means it must ANIMATE on
# its own clock rather than only moving when progress updates: a background
# load can sit at one percentage for a second, and a bar that doesn't move
# is indistinguishable from the freeze this exists to replace.
#
# So there are two indicators, doing different jobs:
#   * The SEGMENT LAMPS sweep continuously off _process. They say "the
#     process is running." They are never blocked on load progress.
#   * The PROGRESS BAR reflects real ResourceLoader progress. It says "this
#     much is done." It can legitimately stall.
#
# Styled as instrument panel rather than as a spinner - a row of lamps
# marching across a stamped bezel is the same visual family as the rest of
# the chrome, and it degrades gracefully if the load finishes instantly.

const UITheme = preload("res://scripts/ui_theme.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")

var _context: String = ""
var _bar: ProgressBar
var _lamps: Control
var _phase: float = 0.0
var _elapsed: float = 0.0
var _status_label: Label
var _step_label: Label

const LAMP_COUNT := 24
const LAMP_SWEEP_SPEED := 1.5  # sweeps per second


func _ready() -> void:
	# SceneRouter can't configure the instance change_scene_to_packed()
	# builds, so the context is handed over through the autoload.
	var router = get_node_or_null("/root/SceneRouter")
	if router and "pending_context" in router and router.pending_context != "":
		_context = router.pending_context

	var backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	UITheme.apply_backdrop(backdrop)

	var frame = MarginContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_constant_override("margin_left", 72)
	frame.add_theme_constant_override("margin_right", 72)
	frame.add_theme_constant_override("margin_top", 56)
	frame.add_theme_constant_override("margin_bottom", 48)
	add_child(frame)

	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", Tokens.SPACE_SM)
	frame.add_child(col)

	# Everything is bottom-anchored: the top of the frame is deliberately
	# left empty so a looping background clip can go there later without
	# this needing to be rebuilt.
	var push = Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(push)

	_status_label = Label.new()
	_status_label.text = "PREPARING DEPLOYMENT"
	_status_label.theme_type_variation = "TitleLabel"
	col.add_child(_status_label)

	if _context != "":
		var ctx = Label.new()
		ctx.text = _context
		ctx.theme_type_variation = "HintLabel"
		col.add_child(ctx)

	# Names the step currently running. Real per-step reporting is the whole
	# reason the load is walked incrementally rather than done in one call -
	# a bar that only moves twice is barely better than no bar.
	_step_label = Label.new()
	_step_label.text = "Preparing"
	_step_label.theme_type_variation = "StatLabel"
	col.add_child(_step_label)

	_lamps = Control.new()
	_lamps.custom_minimum_size = Vector2(0, 18)
	_lamps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lamps.draw.connect(_draw_lamps)
	col.add_child(_lamps)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 10)
	col.add_child(_bar)

	if router and router.has_signal("load_progress"):
		router.load_progress.connect(_on_progress)

	set_process(true)

	# Start the load only AFTER this screen has actually rendered a couple of
	# frames. Kicking it off in _ready() means the first blocking step runs
	# before anything reaches the swap chain, and the player sees the old
	# screen sit frozen instead of seeing this one appear.
	if router and router.has_method("run_load"):
		await get_tree().process_frame
		await get_tree().process_frame
		router.run_load()


func _on_progress(fraction: float, label: String = "") -> void:
	_bar.value = clampf(fraction, 0.0, 1.0)
	if label != "" and is_instance_valid(_step_label):
		_step_label.text = label


func _process(delta: float) -> void:
	_elapsed += delta
	_phase = fmod(_phase + delta * LAMP_SWEEP_SPEED, 1.0)
	# queue_redraw every frame is fine here - this is the only thing on
	# screen, and the whole point is visible motion.
	if is_instance_valid(_lamps):
		_lamps.queue_redraw()

	# After a few seconds, say something rather than leaving the player
	# staring at an unexplained wait.
	if _elapsed > 4.0 and is_instance_valid(_status_label):
		_status_label.text = "PREPARING DEPLOYMENT - STAND BY"


# A row of rectangular indicator lamps with a lit band sweeping across them,
# drawn rather than assembled from nodes so the sweep can be a continuous
# function of time instead of N animated children.
func _draw_lamps() -> void:
	var w := _lamps.size.x
	var h := _lamps.size.y
	if w <= 0.0:
		return
	var gap := 3.0
	var lamp_w: float = maxf((w - gap * (LAMP_COUNT - 1)) / float(LAMP_COUNT), 1.0)

	for i in range(LAMP_COUNT):
		var x := i * (lamp_w + gap)
		var t := float(i) / float(LAMP_COUNT)
		# Distance from the sweep head, wrapped, so the band runs off one
		# end and reappears at the other without a seam.
		var d: float = fposmod(t - _phase, 1.0)
		# Short bright head with a tail behind it.
		var lit: float = clampf(1.0 - d * 6.0, 0.0, 1.0)
		var col: Color = Tokens.BASE_600.lerp(Tokens.SIGNAL_HAZARD, lit)
		_lamps.draw_rect(Rect2(x, 0.0, lamp_w, h), col)
