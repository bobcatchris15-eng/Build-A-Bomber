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
const UIShell = preload("res://scripts/ui_shell.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const UILampsScript = preload("res://scripts/ui_lamps.gd")

var _context: String = ""
var _bar: ProgressBar
var _lamps: UILamps
var _elapsed: float = 0.0
var _status_label: Label
var _step_label: Label


func _ready() -> void:
	# SceneRouter can't configure the instance change_scene_to_packed()
	# builds, so the context is handed over through the autoload.
	var router = get_node_or_null("/root/SceneRouter")
	if router and "pending_context" in router and router.pending_context != "":
		_context = router.pending_context

	# Out-of-match screen - sits on the workbench, not on the in-match steel.
	# Chipboard reads as the bench under the loading hardware, and the
	# segment lamps / progress bar are easier to read against its visible
	# grain than against the steel backdrop the in-match screens use.
	UIShell.workbench(self, "chipboard")
	# Canonical screen frame. Was 72/72/56/48 - none of those are spacing tokens,
	# and it made the loading screen's content sit visibly further in than the
	# screen it transitions to, so the frame appeared to jump on arrival.
	var frame := UIShell.screen_frame(self)

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

	_lamps = UILampsScript.new()
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
	# Lamps own their own _process / queue_redraw since the 2026-08-13
	# lift into scripts/ui_lamps.gd - this function is just the
	# "STAND BY" text escalation now.

	# After a few seconds, say something rather than leaving the player
	# staring at an unexplained wait.
	if _elapsed > 4.0 and is_instance_valid(_status_label):
		_status_label.text = "PREPARING DEPLOYMENT - STAND BY"
