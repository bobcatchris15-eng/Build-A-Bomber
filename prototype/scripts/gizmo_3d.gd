extends Node3D

# Stretch handles (HandleX/Y/Z, the planar drag handles, and the tweak-drag
# math behind them) are retired as of the Instrument Console Pass Phase B:
# the radial tweak stations (scripts/ui/tweak_stations.gd, wired through the
# module action ring) are now the only path to a dimension. HandleRotate
# stays - it is the Rotate wedge's entry point and isn't a stretch handle.

const VisualBuilder = preload("res://scripts/visual_builder.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")

var target_module: Node3D
var start_scale: Vector3
var start_tweaks: Dictionary = {}

# Palette compliance: both the rotate ring and the drag readout use the
# design system's hazard/primary-text tokens rather than bespoke literals.
const HANDLE_COLORS := {
	"HandleRotate": Tokens.SIGNAL_HAZARD,
}

var _rotate_mode := false


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

	var ring = get_node_or_null("HandleRotate")
	if ring:
		ring.drag_started.connect(_on_drag_started)
		ring.rotated.connect(_on_rotated)
		ring.drag_ended.connect(_on_drag_ended)

	set_rotate_mode(false)


# Rotate wedge's entry point: HandleRotate is always the only handle now, so
# this just toggles its pickability. Kept as a named entry point (rather than
# inlined at the one call site) since callers still ask for rotate mode by
# name.
func set_rotate_mode(enabled: bool) -> void:
	_rotate_mode = enabled
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
	_telemetry_label.modulate = Tokens.SIGNAL_HAZARD
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


func _on_drag_ended():
	var main_lab = get_node_or_null("/root/MainLab")
	if main_lab and main_lab.has_method("check_all_clipping"):
		main_lab.check_all_clipping()
