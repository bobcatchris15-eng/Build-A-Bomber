extends Area3D

signal drag_started
signal dragged(offset_3d: Vector3)
signal drag_ended

@export var axis: Vector3 = Vector3.RIGHT

var is_dragging: bool = false
var drag_start_mouse_pos: Vector2
var drag_start_3d_pos: Vector3

func _ready():
	# Visual color based on axis
	var mat = StandardMaterial3D.new()
	if axis.x != 0: mat.albedo_color = Color.RED
	elif axis.y != 0: mat.albedo_color = Color.GREEN
	elif axis.z != 0: mat.albedo_color = Color.BLUE
	
	if has_node("MeshInstance3D"):
		var mesh_inst = get_node("MeshInstance3D")
		mesh_inst.material_override = mat

func start_drag(event, pos):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_dragging = true
			drag_start_mouse_pos = event.position
			drag_start_3d_pos = pos
			emit_signal("drag_started")

func _input(event):
	if is_dragging and event is InputEventMouseMotion:
		# Very basic 2D-to-3D projection mapping for dragging
		var camera = get_viewport().get_camera_3d()
		if not camera: return
		
		# Find the plane defined by our axis and the camera's look vector
		var cam_forward = -camera.global_transform.basis.z
		
		# Create a plane at our start position that we will project mouse onto
		var plane_normal = cam_forward.cross(axis).cross(axis).normalized()
		var plane = Plane(plane_normal, drag_start_3d_pos)
		
		var ray_origin = camera.project_ray_origin(event.position)
		var ray_dir = camera.project_ray_normal(event.position)
		
		var intersection = plane.intersects_ray(ray_origin, ray_dir)
		if intersection != null:
			var offset = intersection - drag_start_3d_pos
			# Project the offset purely onto our constrained axis
			var projected_offset = offset.project(axis)
			emit_signal("dragged", projected_offset)

	if is_dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		is_dragging = false
		emit_signal("drag_ended")
