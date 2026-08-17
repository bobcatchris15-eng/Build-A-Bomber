class_name PerfToast
extends CanvasLayer
# Transient on-screen message used for the kind of feedback that print() cannot
# deliver in a windowed build: a keypress that the player needs to SEE landed,
# with enough information to act on it (the log path basename is the most
# common case, but anything that needs to be visible to the player for a few
# seconds goes through this).
#
# WHY THIS EXISTS AS ITS OWN CANVASLAYER. perf_hud.gd has its own CanvasLayer
# and is the obvious place to bolt a label on. Two reasons not to:
#   - the HUD is conditional (F3 toggles it) and a toast that is visible only
#     when the HUD is on defeats the purpose; a player who needs the dump
#     should not also have to remember F3
#   - the HUD rebuilds its label every refresh tick, which is fine for live
#     numbers and wrong for a static message that has to stay readable for 3
#     seconds
# So this is a separate layer 129 (just above perf_hud's 128), top-centre
# anchored, with its own message label and a Timer that clears it.
#
# COST WHEN IDLE. Zero. Nothing is created until the first show() call; the
# Timer is added once and stays stopped.

# Show the message in this layer. Above perf_hud (128) so a toast is visible
# even with the HUD on, below the modal pause (typically 200+) so an active
# pause is not overpainted.
const LAYER := 129

# Default duration. 3 seconds is the sweet spot the F4 path needs: long
# enough to read the basename, short enough that a stale message from a
# previous match does not contaminate the next one if show() is never
# re-called.
const DEFAULT_DURATION := 3.0

var _label: Label = null
var _timer: Timer = null
var _panel: PanelContainer = null


# Public API. Safe to call before the node is in the tree; the panel is
# built lazily so a script that preloads PerfToast pays nothing until the
# first message. Calling show() repeatedly with a fresh message resets the
# timer and the text - the F4 use case is a burst of dumps during a hitch
# investigation, and the last one is the one the player needs to see.
func show_message(text: String, duration: float = DEFAULT_DURATION) -> void:
	_ensure_ui()
	_label.text = text
	_panel.visible = true
	# Restart the timer from zero on every call so a second F4 does not
	# have the toast vanish mid-read because the first one's countdown
	# was still running.
	_timer.start(duration)


# Hide without waiting for the timer (e.g. when leaving the match).
func clear() -> void:
	if _label:
		_label.text = ""
	if _panel:
		_panel.visible = false
	if _timer:
		_timer.stop()


# Build the panel + label + timer the first time anything is shown. A
# reload of Battle.tscn recreates the node, so this can be called many
# times across a session; the guard at the top keeps it cheap.
func _ensure_ui() -> void:
	if _panel != null:
		return
	layer = LAYER
	_panel = PanelContainer.new()
	# Top-centre anchor: not cornered, so the message reads as a system
	# notification rather than as part of the chrome. The top inset clears
	# the skirmish.gd 68px top info strip, mirroring the perf_hud's offset.
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -260
	_panel.offset_right = 260
	_panel.offset_top = 8
	_panel.offset_bottom = 40
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.theme_type_variation = "HUDPanel"
	add_child(_panel)

	_label = Label.new()
	# StatLabel for the mono face - the message is short and a
	# proportional font makes the basename of the dump file hard to
	# scan.
	_label.theme_type_variation = "StatLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)

	# One-shot timer. A child Timer is preferred over create_timer
	# (which is a closure that captures self) for the same reason
	# commander.gd switched to child Timers: closures over script
	# instances survive past the node, which causes "method on freed
	# instance" on the next match. A child Timer is parented to this
	# CanvasLayer and dies with it.
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.autostart = false
	add_child(_timer)
	_timer.timeout.connect(_on_timer_timeout)


func _on_timer_timeout() -> void:
	if _panel:
		_panel.visible = false
	if _label:
		_label.text = ""
