extends Camera3D

@export var orbit_speed: float = 0.01
@export var zoom_speed: float = 1.0
@export var min_zoom: float = 5.0
@export var max_zoom: float = 30.0
@export var pan_speed: float = 0.015
# World-space point the camera orbits. Defaults to the parent node's
# origin; design-lab scenes set this to the model's raised centre so
# orbit / zoom / pan all stay anchored to the hull, not to the floor.
@export var pivot_offset: Vector3 = Vector3.ZERO
# Far-blur DOF. The camera keeps the model sharp and the workshop
# floor (LabEnvironment) blurred. Far-blur only on purpose: a near-
# blur band on a panning camera reads as a doubled image / lens
# defect, same reason rts_camera.gd skips near blur.
#   dof_focus_back: extra distance past the model before the far
#     blur starts (units of camera-to-model distance).
#   dof_blur_transition: width of the sharp->blurred ramp.
#   dof_blur_amount: maximum blur intensity, 0..1. The lab wants
#     this high (~0.25, well above Battle's 0.06) because the mat
#     and the cardboard boxes are set dressing, not subjects.
# All three are skipped if no CameraAttributesPractical is wired on
# the camera - any scene that doesn't want DOF just doesn't set
# the `attributes` slot, and the rest of the camera keeps working.
@export var dof_focus_back: float = 2.0
@export var dof_blur_transition: float = 2.0
@export var dof_blur_amount: float = 0.25

var _pivot: Node3D
var _distance: float = 15.0
var zoom_service: SemanticZoomService = SemanticZoomService.new()
# Held in _ready if the camera has a CameraAttributesPractical
# resource assigned; null otherwise. All DOF work in this script
# is gated on this being non-null.
var _cam_attributes: CameraAttributesPractical = null

func _ready():
	_pivot = Node3D.new()
	get_parent().add_child.call_deferred(_pivot)
	await get_tree().process_frame

	_pivot.position = pivot_offset

	var original_pos = position
	get_parent().remove_child(self)
	_pivot.add_child(self)

	position = Vector3(0, 0, _distance)
	# _pivot is the new parent, so its local position is the orbit
	# centre; look_at() takes a world-space target and the pivot's
	# global position is the same offset (the camera's parent is at
	# the parent's origin). Reading it explicitly rather than via
	# _pivot.position keeps the call honest if a future change
	# parents the camera somewhere that isn't the world origin.
	look_at(_pivot.global_position)

	# Pick up DOF attributes if the scene wired one. Same pattern as
	# rts_camera.gd: read `attributes` once at boot, never create
	# a default - the DOF pass has a real per-frame cost, so scenes
	# that don't want it pay nothing.
	if attributes != null and attributes is CameraAttributesPractical:
		_cam_attributes = attributes
		_apply_dof()

func _process(delta):
	position.z = lerp(position.z, _distance, 10.0 * delta)
	if zoom_service:
		zoom_service.update_distance(position.z)

func _input(event):
	pass

const PointerGainScript = preload("res://scripts/core/pointer_gain.gd")


func _unhandled_input(event):
	if event is InputEventMouseMotion:
		var scaled_delta: Vector2 = PointerGainScript.apply_gain(event.relative)
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_pivot.rotate_y(-scaled_delta.x * orbit_speed)
			var pitch = _pivot.rotation.x - scaled_delta.y * orbit_speed
			pitch = clamp(pitch, -PI/2.5, PI/2.5)
			_pivot.rotation.x = pitch

		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			# Middle-drag pan, matching the Skirmish camera convention (README).
			_pivot.position += _compute_pan_delta(scaled_delta)

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance -= zoom_speed
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance += zoom_speed

		_distance = clamp(_distance, min_zoom, max_zoom)
		# DOF tracks the orbit distance, so every wheel tick that
		# moved _distance moves the focal point with it. Called here
		# (not in _process) for the same reason rts_camera.gd does:
		# the DOF post-process pass is per-frame expensive and
		# _distance moves only on wheel events.
		_apply_dof()

func _compute_pan_delta(mouse_relative: Vector2) -> Vector3:
	# Scale with distance so pan speed stays consistent whether zoomed in
	# tight on a turret or zoomed out to see the whole hull. Pulled out as a
	# pure function so it's unit-testable without needing real OS mouse-button
	# state, which headless Godot can't simulate via Input.parse_input_event.
	var pan_scale = pan_speed * (_distance / 15.0)
	var right = _pivot.global_transform.basis.x
	var up = _pivot.global_transform.basis.y
	return -right * mouse_relative.x * pan_scale + up * mouse_relative.y * pan_scale


# Sets the far-blur band so its near edge sits dof_focus_back units
# past the model (i.e. the model is sharp, everything past it
# transitions to fully blurred). The blur amount is taken from
# dof_blur_amount on every call too - tweaking that in the
# inspector while playing is a no-op without this.
#
# Pulled out as its own function (mirroring rts_camera.gd's
# _apply_dof_distances) so the test suite can drive a synthetic
# wheel event, capture the resulting far-distance, and pin the
# "focal point tracks the model" behaviour.
func _apply_dof() -> void:
	if _cam_attributes == null:
		return
	_cam_attributes.dof_blur_far_distance = _distance + dof_focus_back
	_cam_attributes.dof_blur_far_transition = dof_blur_transition
	_cam_attributes.dof_blur_amount = dof_blur_amount
