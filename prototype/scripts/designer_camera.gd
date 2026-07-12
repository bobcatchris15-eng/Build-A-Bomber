extends Camera3D

@export var orbit_speed: float = 0.01
@export var zoom_speed: float = 1.0
@export var min_zoom: float = 5.0
@export var max_zoom: float = 30.0
@export var pan_speed: float = 0.015

var _pivot: Node3D
var _distance: float = 15.0

func _ready():
	_pivot = Node3D.new()
	get_parent().add_child.call_deferred(_pivot)
	await get_tree().process_frame
	
	var original_pos = position
	get_parent().remove_child(self)
	_pivot.add_child(self)
	
	position = Vector3(0, 0, _distance)
	look_at(_pivot.position)

func _input(event):
	pass

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_pivot.rotate_y(-event.relative.x * orbit_speed)
			var pitch = _pivot.rotation.x - event.relative.y * orbit_speed
			pitch = clamp(pitch, -PI/2.5, PI/2.5)
			_pivot.rotation.x = pitch

		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			# Middle-drag pan, matching the Skirmish camera convention (README).
			_pivot.position += _compute_pan_delta(event.relative)

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance -= zoom_speed
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance += zoom_speed
			
		_distance = clamp(_distance, min_zoom, max_zoom)
		position.z = _distance

func _compute_pan_delta(mouse_relative: Vector2) -> Vector3:
	# Scale with distance so pan speed stays consistent whether zoomed in
	# tight on a turret or zoomed out to see the whole hull. Pulled out as a
	# pure function so it's unit-testable without needing real OS mouse-button
	# state, which headless Godot can't simulate via Input.parse_input_event.
	var pan_scale = pan_speed * (_distance / 15.0)
	var right = _pivot.global_transform.basis.x
	var up = _pivot.global_transform.basis.y
	return -right * mouse_relative.x * pan_scale + up * mouse_relative.y * pan_scale
