extends Area3D
# Free-form rotation ring (Spore/KSP style): click-drag anywhere around the
# ring to continuously rotate the selected module about its local Y (yaw)
# axis, instead of the old fixed 90-degree snap. Emits a per-frame angle
# DELTA (not an absolute angle) so the caller just needs to
# rotate_object_local(UP, delta) - no need to reconcile reference frames.

signal drag_started
signal rotated(delta_angle: float)
signal drag_ended

var is_dragging: bool = false
var last_angle: float = 0.0

func _ready():
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.GOLD
	mat.emission_enabled = true
	mat.emission = Color.GOLD
	mat.emission_energy_multiplier = 0.6
	if has_node("MeshInstance3D"):
		get_node("MeshInstance3D").material_override = mat

func start_drag(event, pos):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_dragging = true
			last_angle = _angle_from_world_pos(pos)
			emit_signal("drag_started")

func _angle_from_world_pos(world_pos: Vector3) -> float:
	# Angle around the pivot (this handle's own world position, which
	# coincides with the selected module's origin) measured in world space.
	# World space (not the module's local space) is deliberate: we only ever
	# use the DIFFERENCE between two consecutive readings, and a world-space
	# delta is exactly the amount the module needs to turn to keep pace with
	# the mouse regardless of its current orientation.
	var offset = world_pos - global_position
	return atan2(offset.x, -offset.z)

func _input(event):
	if is_dragging and event is InputEventMouseMotion:
		var camera = get_viewport().get_camera_3d()
		if not camera: return
		var plane = Plane(Vector3.UP, global_position.y)
		var ray_origin = camera.project_ray_origin(event.position)
		var ray_dir = camera.project_ray_normal(event.position)
		var hit = plane.intersects_ray(ray_origin, ray_dir)
		if hit == null: return
		var cur_angle = _angle_from_world_pos(hit)
		var delta = wrapf(cur_angle - last_angle, -PI, PI)
		last_angle = cur_angle
		if abs(delta) > 0.0001:
			emit_signal("rotated", delta)

	if is_dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		is_dragging = false
		emit_signal("drag_ended")
