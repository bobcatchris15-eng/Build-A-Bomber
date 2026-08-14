class_name ModuleActionRing
extends Control

# Module action ring for Design Lab parts manipulation (Phase 6, D13).
# Sized dynamically to clear the module's projected silhouette,
# persistent across actions until deselection or escape.

const RingDraw = preload("res://scripts/ui/ring_draw.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const UIAnim = preload("res://scripts/ui_anim.gd")
const ModuleVolume = preload("res://scripts/module_volume.gd")

signal action_invoked(action_id: String)
signal dismissed()

const MIN_INNER_RADIUS := 42.0
const MAX_INNER_RADIUS := 160.0
const BAND_WIDTH := 44.0
const CLEARANCE_MARGIN := 16.0
const HUB_RADIUS := 28.0

var target_node: Node3D = null
var subject_label: String = ""
var max_zoom_distance: float = 40.0

var inner_radius: float = MIN_INNER_RADIUS
var outer_radius: float = MIN_INNER_RADIUS + BAND_WIDTH

var _actions: Array = []  # [{id, label, icon, enabled}]
var _hovered: int = -1
var _is_open: bool = false
var _target_screen_center: Vector2 = Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_canvas_size()


func _update_canvas_size() -> void:
	var span := (outer_radius + 64.0) * 2.0
	custom_minimum_size = Vector2(span, span)
	size = custom_minimum_size
	pivot_offset = custom_minimum_size * 0.5


func set_actions(actions: Array) -> void:
	_actions = actions
	queue_redraw()


func add_action(id: String, label: String, icon: String = "", enabled: bool = true) -> void:
	_actions.append({
		"id": id,
		"label": label.to_upper(),
		"icon": icon,
		"enabled": enabled,
	})
	queue_redraw()


func set_action_enabled(id: String, enabled: bool) -> void:
	for a in _actions:
		if a["id"] == id:
			if a["enabled"] != enabled:
				a["enabled"] = enabled
				queue_redraw()
			break


func open_for_module(module: Node3D, label_text: String = "") -> void:
	target_node = module
	subject_label = label_text
	_is_open = true
	visible = true
	_update_silhouette_radius(true)
	_update_screen_position()
	UIAnim.ring_pop(self)


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	dismissed.emit()
	var tween := create_tween()
	if tween:
		tween.tween_property(self, "scale", Vector2(0.6, 0.6), 0.1)
		tween.parallel().tween_property(self, "modulate:a", 0.0, 0.1)
		tween.tween_callback(queue_free)
	else:
		queue_free()


func _process(delta: float) -> void:
	if not _is_open:
		return
	if not is_instance_valid(target_node) or not target_node.is_inside_tree():
		close()
		return

	_update_silhouette_radius(false, delta)
	_update_screen_position()


func _update_silhouette_radius(immediate: bool = false, delta: float = 0.016) -> void:
	if target_node == null or not is_instance_valid(target_node):
		return
	var camera := get_viewport().get_camera_3d()
	if not camera or camera.is_position_behind(target_node.global_position):
		return

	# Calculate projected bounding box half diagonal
	var half_diag := _compute_projected_half_diagonal(camera, target_node)
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var viewport_cap: float = minf(vp_size.x, vp_size.y) * 0.40
	var max_inner: float = minf(MAX_INNER_RADIUS, viewport_cap)
	var target_inner: float = clampf(half_diag + CLEARANCE_MARGIN, MIN_INNER_RADIUS, max_inner)

	if immediate:
		inner_radius = target_inner
	else:
		inner_radius = lerpf(inner_radius, target_inner, clampf(delta * 10.0, 0.0, 1.0))

	outer_radius = inner_radius + BAND_WIDTH
	_update_canvas_size()
	queue_redraw()


## Measures the module's real drawn geometry (ModuleVolume.bounds(), the
## project's single source of a module's occupied space) rather than a single
## direct-child MeshInstance3D's mesh AABB, and projects all eight corners
## instead of four. Falls back to ModuleVolume.boxes() merged loosely if the
## fitted AABB proves too generous on a sponson-heavy part (a part whose
## measured box list disagrees strongly with its own merged AABB - i.e. its
## real footprint is not axis-aligned-box shaped - so we widen using the
## per-mesh box list's own worst-case corner instead of the single merged box).
func _compute_projected_half_diagonal(camera: Camera3D, node: Node3D) -> float:
	var aabb: AABB = ModuleVolume.bounds(node)
	if aabb.size == Vector3.ZERO:
		aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)

	var center_3d: Vector3 = node.global_position
	var center_2d: Vector2 = camera.unproject_position(center_3d)

	var max_dist: float = MIN_INNER_RADIUS
	var corners := _aabb_corners(aabb)
	for c in corners:
		var world_pos: Vector3 = node.global_transform * c
		if not camera.is_position_behind(world_pos):
			var screen_pos: Vector2 = camera.unproject_position(world_pos)
			var d := (screen_pos - center_2d).length()
			if d > max_dist:
				max_dist = d

	# Sponson-heavy fallback: if the per-mesh box list has a corner further
	# out (in module-local space) than the merged AABB's own corners suggest,
	# the merged box under-reads a non-convex silhouette - widen using the
	# individual boxes instead.
	var box_list: Array = ModuleVolume.boxes(node)
	if box_list.size() > 1:
		for box in box_list:
			var c: Vector3 = box.get("c", Vector3.ZERO)
			var h0: Vector3 = box.get("h0", Vector3.ZERO)
			var h1: Vector3 = box.get("h1", Vector3.ZERO)
			var h2: Vector3 = box.get("h2", Vector3.ZERO)
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						var local_pt: Vector3 = c + h0 * sx + h1 * sy + h2 * sz
						var world_pos: Vector3 = node.global_transform * local_pt
						if not camera.is_position_behind(world_pos):
							var screen_pos: Vector2 = camera.unproject_position(world_pos)
							var d := (screen_pos - center_2d).length()
							if d > max_dist:
								max_dist = d

	return max_dist


static func _aabb_corners(aabb: AABB) -> Array:
	return [
		Vector3(aabb.position.x, aabb.position.y, aabb.position.z),
		Vector3(aabb.end.x, aabb.position.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.end.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.position.y, aabb.end.z),
		Vector3(aabb.end.x, aabb.end.y, aabb.position.z),
		Vector3(aabb.end.x, aabb.position.y, aabb.end.z),
		Vector3(aabb.position.x, aabb.end.y, aabb.end.z),
		Vector3(aabb.end.x, aabb.end.y, aabb.end.z),
	]


func _update_screen_position() -> void:
	if target_node == null or not is_instance_valid(target_node):
		return
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	var dist := camera.global_position.distance_to(target_node.global_position)
	if dist > max_zoom_distance or camera.is_position_behind(target_node.global_position):
		modulate.a = 0.0
		return
	else:
		modulate.a = clampf(1.0 - (dist - (max_zoom_distance - 8.0)) / 8.0, 0.0, 1.0)

	_target_screen_center = camera.unproject_position(target_node.global_position)
	position = _target_screen_center - size * 0.5


func _has_point(point: Vector2) -> bool:
	var offset := point - size * 0.5
	var r := offset.length()
	return r >= inner_radius and r <= outer_radius


func _gui_input(event: InputEvent) -> void:
	if not _is_open:
		return

	if event is InputEventMouseMotion:
		var prev := _hovered
		_hovered = RingDraw.sector_at(event.position, size * 0.5, inner_radius, outer_radius, HUB_RADIUS, _actions.size())
		if _hovered != prev:
			queue_redraw()
		accept_event()

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var hit := RingDraw.sector_at(event.position, size * 0.5, inner_radius, outer_radius, HUB_RADIUS, _actions.size())
		if hit >= 0 and hit < _actions.size():
			var action: Dictionary = _actions[hit]
			if action.get("enabled", true):
				action_invoked.emit(action["id"])
				# Persistent until deselect (D13): do NOT close here!
				accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _draw() -> void:
	var font := get_theme_font("font", "Label")
	if font == null:
		font = ThemeDB.fallback_font
	RingDraw.draw_ring(
		self,
		size * 0.5,
		inner_radius,
		outer_radius,
		HUB_RADIUS,
		_actions,
		_hovered,
		subject_label,
		font
	)
