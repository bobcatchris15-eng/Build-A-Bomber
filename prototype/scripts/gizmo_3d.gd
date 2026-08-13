extends Node3D

const LabDocumentScript = preload("res://scripts/lab_document.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")
const ModuleCatalogScript = preload("res://scripts/module_catalog.gd")
const GizmoHandleScript = preload("res://scripts/gizmo_handle.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")

var target_module: Node3D
var start_scale: Vector3
var start_tweaks: Dictionary = {}

const HANDLE_COLORS := {
	"HandleX": Color(0.95, 0.26, 0.30),
	"HandleY": Color(0.42, 0.85, 0.32),
	"HandleZ": Color(0.30, 0.55, 0.95),
	"HandleRotate": Tokens.SIGNAL_HAZARD,
}

var _rotate_mode := false
var _planar_handles: Array[Area3D] = []


func _paint_handles():
	for handle_name in HANDLE_COLORS:
		var handle = get_node_or_null(handle_name)
		if not handle:
			continue
		var mesh_inst = handle.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if not mesh_inst:
			continue
		var mat = StandardMaterial3D.new()
		mat.albedo_color = HANDLE_COLORS[handle_name]
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.render_priority = 1
		mesh_inst.material_override = mat


func _ready():
	target_module = get_parent()
	if target_module != null and target_module.name == "Hull":
		# Remove hull from gizmo entirely (D10). Hull uses fixed size classes.
		visible = false
		set_process(false)
		set_physics_process(false)
		queue_free()
		return

	_paint_handles()

	# Connect to the 3 linear handles (X/Y/Z scale/tweak drag)
	for child in get_children():
		if child.name == "HandleRotate" or child.name.begins_with("Planar"):
			continue
		if child.has_signal("drag_started"):
			child.drag_started.connect(_on_drag_started)
			child.dragged.connect(_on_dragged.bind(child.axis))
			child.drag_ended.connect(_on_drag_ended)

	var ring = get_node_or_null("HandleRotate")
	if ring:
		ring.drag_started.connect(_on_drag_started)
		ring.rotated.connect(_on_rotated)
		ring.drag_ended.connect(_on_drag_ended)

	_setup_planar_handles()
	set_rotate_mode(false)


func _setup_planar_handles() -> void:
	_create_planar_handle("PlanarXY", Vector3(1, 1, 0), Vector3(0, 0, 1), Vector3(0.35, 0.35, 0), Color(0.95, 0.95, 0.4, 0.45))
	_create_planar_handle("PlanarXZ", Vector3(1, 0, 1), Vector3(0, 1, 0), Vector3(0.35, 0, 0.35), Color(0.95, 0.4, 0.95, 0.45))
	_create_planar_handle("PlanarYZ", Vector3(0, 1, 1), Vector3(1, 0, 0), Vector3(0, 0.35, 0.35), Color(0.4, 0.95, 0.95, 0.45))


func _create_planar_handle(handle_name: String, axes: Vector3, normal: Vector3, offset: Vector3, col: Color) -> void:
	var existing = get_node_or_null(handle_name)
	if existing:
		return

	var area := Area3D.new()
	area.name = handle_name
	area.set_script(GizmoHandleScript)
	area.set("axis", axes)
	area.position = offset

	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.35, 0.35, 0.35)
	col_shape.shape = box
	area.add_child(col_shape)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "MeshInstance3D"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.28, 0.28)
	mesh_inst.mesh = quad

	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 2
	mesh_inst.material_override = mat

	if normal.x != 0:
		mesh_inst.rotation_degrees = Vector3(0, 90, 0)
	elif normal.y != 0:
		mesh_inst.rotation_degrees = Vector3(90, 0, 0)

	area.add_child(mesh_inst)
	add_child(area)

	area.set_meta("plane_normal", normal)
	area.set_meta("axes", axes)
	_planar_handles.append(area)

	area.drag_started.connect(_on_drag_started)
	area.dragged.connect(_on_planar_dragged.bind(axes))
	area.drag_ended.connect(_on_drag_ended)


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if not camera:
		return
	var cam_forward := -camera.global_transform.basis.z

	for p in _planar_handles:
		if not is_instance_valid(p):
			continue
		if _rotate_mode:
			p.visible = false
			p.input_ray_pickable = false
			continue

		var norm: Vector3 = p.get_meta("plane_normal", Vector3.UP)
		var world_norm: Vector3 = (global_transform.basis * norm).normalized()
		var face_on: float = abs(world_norm.dot(cam_forward))
		var is_visible: bool = face_on > 0.18
		p.visible = is_visible
		p.input_ray_pickable = is_visible
		p.scale = Vector3.ONE * clampf(face_on * 1.2, 0.5, 1.0)


# Swaps between the stretch handles and the rotation ring.
func set_rotate_mode(enabled: bool) -> void:
	_rotate_mode = enabled
	for axis_name in ["HandleX", "HandleY", "HandleZ"]:
		var h = get_node_or_null(axis_name)
		if h:
			h.visible = not enabled
			h.set_deferred("monitorable", not enabled)
			h.input_ray_pickable = not enabled
	for p in _planar_handles:
		if is_instance_valid(p):
			p.visible = not enabled
			p.input_ray_pickable = not enabled
	var ring = get_node_or_null("HandleRotate")
	if ring:
		ring.visible = enabled
		ring.set_deferred("monitorable", enabled)
		ring.input_ray_pickable = enabled


var _telemetry_label: Label3D = null


func _get_telemetry_label() -> Label3D:
	if _telemetry_label != null:
		return _telemetry_label
	_telemetry_label = Label3D.new()
	_telemetry_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_telemetry_label.double_sided = false
	_telemetry_label.no_depth_test = true
	_telemetry_label.render_priority = 10
	_telemetry_label.font_size = 18
	_telemetry_label.outline_size = 4
	_telemetry_label.outline_modulate = Color(0, 0, 0, 0.9)
	_telemetry_label.modulate = Color(0.0, 0.95, 1.0, 1.0)
	add_child(_telemetry_label)
	return _telemetry_label


func _show_telemetry_callout(text: String, pos_offset: Vector3):
	var lbl = _get_telemetry_label()
	lbl.text = text
	lbl.position = pos_offset
	lbl.visible = true


func _on_rotated(delta_angle: float):
	if not target_module or target_module.name == "Hull":
		return

	target_module.rotate_object_local(Vector3.UP, delta_angle)
	var yaw = wrapf(target_module.get_meta("yaw_offset", 0.0) + delta_angle, 0.0, 2.0 * PI)
	target_module.set_meta("yaw_offset", yaw)
	var yaw_deg = rad_to_deg(yaw)
	_show_telemetry_callout("∠ YAW: %.1f°" % yaw_deg, Vector3(0, 1.5, 0))
	VisualBuilder.refresh_sponson_blister(target_module)

	if target_module.has_meta("mirrored_counterpart"):
		var mirror = target_module.get_meta("mirrored_counterpart")
		if mirror and is_instance_valid(mirror):
			mirror.rotate_object_local(Vector3.UP, -delta_angle)
			var mirror_yaw = wrapf(mirror.get_meta("yaw_offset", 0.0) - delta_angle, 0.0, 2.0 * PI)
			mirror.set_meta("yaw_offset", mirror_yaw)
			VisualBuilder.refresh_sponson_blister(mirror)

	var root = get_node_or_null("/root/MainLab")
	if root and root.has_method("check_all_clipping"):
		root.check_all_clipping()


func _on_drag_started():
	var root = get_node_or_null("/root/MainLab")
	if root and root.has_method("push_undo_snapshot"):
		root.push_undo_snapshot()
	if target_module:
		start_scale = target_module.scale
		start_tweaks = {}
		if target_module.has_meta("tweaks"):
			start_tweaks = target_module.get_meta("tweaks").duplicate(true)
		elif target_module.has_meta("module_data"):
			var data = target_module.get_meta("module_data")
			if data.has("tweaks"):
				start_tweaks = data["tweaks"].duplicate(true)


func _on_planar_dragged(offset_3d: Vector3, axes: Vector3) -> void:
	if axes.x != 0:
		_on_dragged(Vector3(offset_3d.x, 0, 0), Vector3.RIGHT)
	if axes.y != 0:
		_on_dragged(Vector3(0, offset_3d.y, 0), Vector3.UP)
	if axes.z != 0:
		_on_dragged(Vector3(0, 0, offset_3d.z), Vector3.FORWARD)


func _on_dragged(offset_3d: Vector3, axis: Vector3):
	if not target_module or target_module.name == "Hull":
		return

	if target_module.has_meta("module_data"):
		var data = target_module.get_meta("module_data")
		var type_id = data.type_id
		var tweak_name = get_tweak_for_axis(type_id, axis)
		if tweak_name != "":
			var specs = LabDocumentScript.TWEAK_SPECS
			var spec = null
			if type_id in specs:
				for s in specs[type_id]:
					if s.name == tweak_name:
						spec = s
						break

			if spec:
				var start_val = start_tweaks.get(tweak_name, spec.default)
				var local_offset = offset_3d.dot(axis)
				var change = local_offset * 1.5
				var new_val = clamp(start_val + change, spec.min, spec.max)
				if spec.step > 0:
					new_val = round(new_val / spec.step) * spec.step

				data.tweaks[tweak_name] = new_val

				VisualBuilder.rebuild_visual(target_module)
				if target_module.has_meta("mirrored_counterpart"):
					var mirror = target_module.get_meta("mirrored_counterpart")
					if mirror and is_instance_valid(mirror):
						var mirror_data = mirror.get_meta("module_data")
						if mirror_data:
							mirror_data.tweaks[tweak_name] = new_val
						VisualBuilder.rebuild_visual(mirror)

				_show_telemetry_callout("%s: %.2f" % [spec.label if spec else tweak_name, new_val], Vector3(0, 1.5, 0))
				get_tree().call_group("stat_ui", "on_module_selected", target_module)
				var root = get_node_or_null("/root/MainLab")
				var hull = root.get_node_or_null("Hull") if root else null
				if hull:
					get_tree().call_group("stat_ui", "update_stats", hull)
				if root and root.has_method("check_all_clipping"):
					root.check_all_clipping()
				return

	# Fallback module scaling
	var local_offset = offset_3d.dot(axis)
	var scale_change = local_offset * 1.0
	var new_scale = start_scale
	if axis.x != 0:
		new_scale.x = max(0.1, start_scale.x + scale_change)
	elif axis.y != 0:
		new_scale.y = max(0.1, start_scale.y + scale_change)
	elif axis.z != 0:
		new_scale.z = max(0.1, start_scale.z + scale_change)

	_apply_scale_to_node(target_module, new_scale)
	_show_telemetry_callout("SCALE: (%.1f, %.1f, %.1f)" % [new_scale.x, new_scale.y, new_scale.z], Vector3(0, 1.5, 0))

	if target_module.has_meta("mirrored_counterpart"):
		var mirror = target_module.get_meta("mirrored_counterpart")
		if is_instance_valid(mirror):
			_apply_scale_to_node(mirror, new_scale)

	get_tree().call_group("stat_ui", "update_stats", get_node_or_null("/root/MainLab/Hull"))
	var main_lab = get_node_or_null("/root/MainLab")
	if main_lab and main_lab.has_method("check_all_clipping"):
		main_lab.check_all_clipping()


func _apply_scale_to_node(node: Node3D, new_scale: Vector3):
	if node == null or node.name == "Hull":
		return
	node.scale = new_scale
	if node.has_meta("module_data"):
		var data = node.get_meta("module_data")
		data.scale_multiplier = new_scale


func _on_drag_ended():
	var main_lab = get_node_or_null("/root/MainLab")
	if main_lab and main_lab.has_method("check_all_clipping"):
		main_lab.check_all_clipping()


static func get_tweak_for_axis(type_id: String, axis: Vector3) -> String:
	var specs = LabDocumentScript.TWEAK_SPECS
	if not (type_id in specs):
		return ""
	var list: Array = specs[type_id]
	if list.is_empty():
		return ""
	if axis.z != 0:
		for s in list:
			if s.name in ["barrel_length", "track_length", "pod_length", "mast_height"]:
				return s.name
	if axis.x != 0:
		for s in list:
			if s.name in ["caliber", "drum_radius", "dish_diameter", "shield_arc", "intake_size"]:
				return s.name
	if axis.y != 0:
		for s in list:
			if s.name in ["elevation", "vertical_arc", "aperture", "fins"]:
				return s.name
	return list[0].name
