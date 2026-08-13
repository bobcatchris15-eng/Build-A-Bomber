extends Area3D

signal drag_started
signal dragged(offset_3d: Vector3)
signal drag_ended

@export var axis: Vector3 = Vector3.RIGHT

var is_dragging: bool = false
var drag_start_mouse_pos: Vector2
var drag_start_3d_pos: Vector3

var _mat_positive: StandardMaterial3D = null
var _mat_negative: StandardMaterial3D = null
var _is_negative: bool = false
var _mesh_inst: MeshInstance3D = null

const PRECISION_SCALE: float = 0.2


func _ready():
	_mesh_inst = get_node_or_null("MeshInstance3D") as MeshInstance3D

	var base_col: Color = Color.RED
	if axis.x != 0:
		base_col = Color(0.95, 0.26, 0.30)
	elif axis.y != 0:
		base_col = Color(0.42, 0.85, 0.32)
	elif axis.z != 0:
		base_col = Color(0.30, 0.55, 0.95)

	_mat_positive = StandardMaterial3D.new()
	_mat_positive.albedo_color = base_col
	_mat_positive.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_positive.no_depth_test = true
	_mat_positive.render_priority = 1

	_mat_negative = StandardMaterial3D.new()
	_mat_negative.albedo_color = Color(base_col.r, base_col.g, base_col.b, 0.35)
	_mat_negative.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_negative.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_negative.no_depth_test = true
	_mat_negative.render_priority = 1

	if _mesh_inst:
		_mesh_inst.material_override = _mat_positive


func _process(_delta: float) -> void:
	# Hollow negative arrows (D12): check axis against camera forward
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera and _mesh_inst:
		var cam_forward := -camera.global_transform.basis.z
		var world_axis := (global_transform.basis * axis).normalized()
		var points_away: bool = world_axis.dot(cam_forward) > 0.05
		if points_away != _is_negative:
			_is_negative = points_away
			_mesh_inst.material_override = _mat_negative if _is_negative else _mat_positive


func start_drag(event, pos):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_dragging = true
			drag_start_mouse_pos = event.position
			drag_start_3d_pos = pos
			emit_signal("drag_started")


func _input(event):
	if is_dragging and event is InputEventMouseMotion:
		var camera := get_viewport().get_camera_3d()
		if not camera:
			return

		var cam_forward := -camera.global_transform.basis.z
		var plane_normal := cam_forward.cross(axis).cross(axis).normalized()
		var plane := Plane(plane_normal, drag_start_3d_pos)

		var ray_origin := camera.project_ray_origin(event.position)
		var ray_dir := camera.project_ray_normal(event.position)

		var intersection = plane.intersects_ray(ray_origin, ray_dir)
		if intersection != null:
			var offset = intersection - drag_start_3d_pos
			var projected_offset: Vector3 = offset.project(axis)

			# Precision modifier: 5x reduction (D12)
			var precision := false
			if Input.is_action_pressed("manip_precision") or event.shift_pressed:
				precision = true
			if precision:
				projected_offset *= PRECISION_SCALE

			emit_signal("dragged", projected_offset)

	if is_dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		is_dragging = false
		emit_signal("drag_ended")
