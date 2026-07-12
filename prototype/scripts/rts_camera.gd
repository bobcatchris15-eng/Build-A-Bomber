extends Camera3D
# Classic RTS camera: WASD/arrow pan, mouse-wheel zoom, middle-mouse drag pan.

@export var pan_speed: float = 22.0
@export var zoom_speed: float = 2.5
@export var min_height: float = 10.0
@export var max_height: float = 45.0

var height: float = 26.0

func _ready():
	height = clamp(global_position.y, min_height, max_height)
	_apply_pitch()

func _apply_pitch():
	# Steeper look-down when zoomed out
	var t = (height - min_height) / (max_height - min_height)
	rotation_degrees.x = lerp(-42.0, -62.0, t)

func _process(delta):
	var move = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x += 1
	if move != Vector2.ZERO:
		move = move.normalized() * pan_speed * delta * (height / 26.0)
		global_position.x += move.x
		global_position.z += move.y

	global_position.y = lerp(global_position.y, height, 10.0 * delta)

func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			height = clamp(height - zoom_speed, min_height, max_height)
			_apply_pitch()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			height = clamp(height + zoom_speed, min_height, max_height)
			_apply_pitch()
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		var factor = height / 500.0
		global_position.x -= event.relative.x * factor
		global_position.z -= event.relative.y * factor
