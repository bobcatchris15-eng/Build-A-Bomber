class_name UILamps
extends Control
# Segment-lamp strip: a row of small rectangles with a lit band sweeping
# across them at LAMP_SWEEP_SPEED. The continuous visual proof-of-life
# a loading screen needs - a progress bar that doesn't move is
# indistinguishable from a freeze.
#
# WHAT THIS REPLACES. The same draw routine used to live inline in
# loading_screen.gd:_draw_lamps (loading_screen.gd:130-147), paired with
# LAMP_COUNT and LAMP_SWEEP_SPEED constants and a _process that advanced
# the phase. A second copy on the deploy gate's overlay would have
# drifted on a sweep-speed tweak, and a tweak to the colour ramp would
# have had to land in two files. Lifting the routine into its own
# Control means both the loading screen and the deploy gate instance
# the same node, with the same animation.
#
# USAGE
#
#     var lamps := UILamps.new()
#     col.add_child(lamps)
#     # Default height 18px (custom_minimum_size), sweep colour SIGNAL_HAZARD.
#     lamps.set_sweep_colour(Tokens.SIGNAL_GO)  # optional override
#
# The component owns its own _process and queue_redraw; the caller
# does not drive the phase.
#
# WHAT THIS DOES NOT DO
#
#   * No events. The lamps are a passive visual; if a screen needs
#     "did the sweep reach the end" feedback, it owns that itself
#     (the loading screen's _elapsed counter for the "STAND BY"
#     label is the existing example, and stays in the caller).
#   * No theming hook for the lamp body colour (BASE_600). The body
#     is the unlit state and never animates, so leaving it as a
#     hard-coded token keeps the API small. A screen that wants a
#     different body colour overrides _draw or subclasses.

const Tokens = preload("res://scripts/ui_tokens.gd")

# Number of lamps in the strip. 24 is enough to make the sweep read
# as a continuous band at any reasonable column width (a 400px column
# gives ~16px per lamp, including gap) without making the strip itself
# a load-bearing layout element.
const LAMP_COUNT := 24
# Sweeps per second. 1.5 is the loading screen's existing value: fast
# enough to read as "something is happening", slow enough that a player
# looking at the screen can pick out the sweep head if they want to.
const LAMP_SWEEP_SPEED := 1.5
# Vertical size the lamps render at. 18px matches the loading screen's
# pre-extracted value; a screen that wants a thicker strip sets
# custom_minimum_size on the instance after add_child.
const LAMP_HEIGHT := 18.0
# Horizontal gap between lamps. 3px is what the loading screen shipped
# with; a smaller gap makes the strip read as a continuous bar rather
# than as separate lamps, which is the wrong shape for this component.
const LAMP_GAP := 3.0
# The lit band's falloff. Higher = a shorter, sharper head with a
# longer tail; lower = a longer, softer band. 6.0 reads as "lit band"
# rather than "moving dot" at the 1.5 sweeps/sec speed above.
const SWEEP_FALLOFF := 6.0

# The band colour. Default SIGNAL_HAZARD matches the loading screen's
# pre-extracted value (amber, attention). A screen that wants a
# different palette (e.g. SIGNAL_GO for a "ready" state) overrides
# this via set_sweep_colour().
var _sweep_colour: Color = Tokens.SIGNAL_HAZARD

# Phase 0..1; the sweep head sits at t == _phase, the band trails
# behind. Driven from _process so the caller does not have to.
var _phase: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(0, LAMP_HEIGHT)
	# IGNORE: the strip is decorative chrome, never a hit target. A
	# rect that always swallowed input would make the entire screen
	# unclickable wherever the strip happens to sit.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	# Wraps so the band runs off one end and reappears at the other
	# without a seam. fmod's behaviour for negative values is
	# implementation-defined, but _phase only ever increases so this
	# is safe.
	_phase = fmod(_phase + delta * LAMP_SWEEP_SPEED, 1.0)
	# queue_redraw every frame is fine here - the strip is small and
	# the whole point is visible motion.
	queue_redraw()


# Override the lit band's head colour. The body (the unlit lamps)
# stays BASE_600 regardless - this is the sweep's colour, not the
# strip's.
func set_sweep_colour(colour: Color) -> void:
	_sweep_colour = colour


# Exposed for tests / screens that want to know where the head is.
# Not used by the current call sites; left public because the
# alternative is a sibling signal and the cost of a getter is zero.
func get_phase() -> float:
	return _phase


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0:
		return
	var lamp_w: float = maxf((w - LAMP_GAP * (LAMP_COUNT - 1)) / float(LAMP_COUNT), 1.0)

	for i in range(LAMP_COUNT):
		var x := i * (lamp_w + LAMP_GAP)
		var t := float(i) / float(LAMP_COUNT)
		# Distance from the sweep head, wrapped, so the band runs off
		# one end and reappears at the other without a seam.
		var d: float = fposmod(t - _phase, 1.0)
		# Short bright head with a tail behind it.
		var lit: float = clampf(1.0 - d * SWEEP_FALLOFF, 0.0, 1.0)
		var col: Color = Tokens.BASE_600.lerp(_sweep_colour, lit)
		draw_rect(Rect2(x, 0.0, lamp_w, h), col)
