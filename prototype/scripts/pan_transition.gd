extends ColorRect
class_name PanTransitionOverlay
# A fullscreen overlay that produces the "background slides left" effect
# when entering or leaving the Armor Bay.
#
# WHAT IT DOES. Wraps the pan_blur.gdshader behind a Tween so callers can
# just call play_forward() or play_reverse() and await the finished
# signal. The overlay itself is a fullscreen ColorRect with the shader
# assigned; it MUST be added to a CanvasLayer that sits below the
# SceneRouter's fade layer (layer 128) and above the 3D viewport, so the
# smear covers the world but SceneRouter's fade-out still hides the
# scene swap.
#
# WHY NOT JUST A PLAIN SHADER NODE. A bare ColorRect + ShaderMaterial
# works, but tweening two shader parameters (progress, alpha) by hand at
# every call site (the Lab toolbar, the Armor Bay back button) duplicates
# the timing and easing logic. This wrapper owns those so callers only
# decide direction.
#
# HOW IT WORKS WITH SceneRouter. The Lab toolbar (or Armor Bay back) calls
# play_forward(). The overlay runs the tween, reaching 50% at half
# duration. The caller awaits overlay.halfway, then calls SceneRouter.goto()
# to swap the scene. The SceneRouter fade runs on TOP of this overlay
# (layer 128 vs the overlay's chosen layer), so the scene swap is hidden
# by both the smear AND the fade. Once the swap is done, the caller
# awaits overlay.finished, and the overlay is freed.
#
# For the reverse direction (back to Lab), the overlay is added to the
# Armor Bay scene and the same sequence runs in reverse. Because the
# overlay is added to the CURRENT scene and removed when done, no
# cross-scene state is leaked.
#
# One subtle thing: when SceneRouter fades out, the underlying world
# becomes a single uniform colour (BASE_900). The smear applied to a
# uniform colour is just the same colour, so the smear effectively
# "swallows itself" once SceneRouter's fade dominates, which is why
# the tween can keep running through the swap without artefacts.

const PAN_BLUR_SHADER := preload("res://shaders/pan_blur.gdshader")

# Layer index for the canvas layer this overlay expects to live on.
# SceneRouter's fade is at layer 128; this sits BELOW it so the fade
# still covers the overlay during the scene swap.
const CANVAS_LAYER := 100

signal halfway
signal finished

enum Direction {
	FORWARD, # world slides LEFT (we're turning to the right)
	REVERSE, # world slides RIGHT (we're turning back to the left)
}


var _direction: int = Direction.FORWARD
var _duration: float = 0.45
var _tween: Tween = null


func _init(direction: int = Direction.FORWARD,
		duration: float = 0.45) -> void:
	_direction = direction
	_duration = duration

	# Full-rect by default. The canvas layer this lives on is also full-
	# screen, so this is sufficient.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The overlay's only purpose is to smear the world; it must not
	# swallow input.

	# Shader material assignment.
	var mat := ShaderMaterial.new()
	mat.shader = PAN_BLUR_SHADER
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("alpha", 0.0)
	# Direction: -1 = world slides left (forward pan into Armor Bay),
	# +1 = world slides right (reverse pan back to Lab).
	mat.set_shader_parameter("pan_direction", -1.0 if _direction == Direction.FORWARD else 1.0)
	material = mat


# Plays the overlay from invisible to fully smeared. await halfway() to
# do the scene swap at the peak of the smear, then await finished()
# once the swap is complete. The overlay frees itself at the end.
func play() -> void:
	# Start visible at alpha 0 so the shader is sampling the framebuffer.
	# A ColorRect with alpha 0 is still rendering - just transparent -
	# and we need it to be in the draw pass for the smear to be visible.
	visible = true

	# Snap to the start state explicitly. The previous tween may have
	# left progress/alpha mid-animation if play() was called twice in
	# quick succession (e.g. a double-click on the toolbar button).
	var mat := material as ShaderMaterial
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("alpha", 0.0)

	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	# Two parallel tracks: progress (the smear itself) and alpha (the
	# overlay's overall visibility). Easing both together reads as
	# "the smear fades in and out", rather than "the smear appears at
	# a fixed strength and then fades".
	_tween.set_parallel(true)
	# Slower smear peak so the half-way mark is reached at a visually
	# readable midpoint. _tween_method can't use TRANS_STANDARD via set_
	# before parallel, so we set it on the underlying Tween.
	_tween.tween_method(_set_progress, 0.0, 1.0, _duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_set_alpha, 0.0, 1.0, _duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	# Halfway callback: lets the caller know it's safe to swap scenes.
	# Scheduled as a one-shot tween_callback at the midpoint.
	var cb_tween := create_tween()
	cb_tween.tween_interval(_duration * 0.5)
	cb_tween.tween_callback(func():
		if not is_instance_valid(self):
			return
		halfway.emit())

	# Finish callback: cleanup. The overlay frees itself at the end so
	# it doesn't sit in the scene tree forever. Freeing on the next
	# frame gives the awaiting caller's "finished" awaitable time to
	# see this overlay's state before it dies.
	var end_tween := create_tween()
	end_tween.tween_interval(_duration)
	end_tween.tween_callback(func():
		if not is_instance_valid(self):
			return
		finished.emit()
		# Free next frame so the awaiting caller can finish its work.
		queue_free())


func _set_progress(p: float) -> void:
	if not is_instance_valid(self):
		return
	var mat := material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("progress", p)


func _set_alpha(a: float) -> void:
	if not is_instance_valid(self):
		return
	var mat := material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("alpha", a)