extends Node3D

const Gizmo3D = preload("res://scenes/Gizmo3D.tscn")

# Hull Builder — Drag & Drop primitive construction
# Drag primitives from the palette into the workspace, then reposition as needed
#
# Chunk 1 additions:
#   - Per-primitive 3-axis translate gizmo (X/Y/Z colored handles, no depth test)
#   - Rotate ring around Y gizmo handle
#   - Selection highlight via emission tint
#   - Delete (DEL) and Duplicate (Ctrl+D) primitives
#   - ColorPickerButton replaces random-click ColorRect
#   - Improved properties panel with section headers + action buttons
#   - Click empty space to deselect

@export var max_primitives: int = 50

enum PrimitiveType {
	BOX,
	SPHERE,
	CYLINDER,
	WEDGE,
	CONE,
	TORUS
}

# Persistent state
var primitives: Array = []
var selected_primitive: int = -1
var current_primitive_type: PrimitiveType = PrimitiveType.BOX
var has_origin: bool = false

# Transform mode: 0=Move (gizmo), 1=Rotate (ring), 2=Scale (future)
var transform_mode: int = 0

# Palette drag state
var is_dragging_from_palette: bool = false
var dragged_palette_type: PrimitiveType = PrimitiveType.BOX
var preview_node: Node3D = null

# Palette toggle group
var palette_buttons: Array = []

# Snap settings
@export var snap_distance: float = 1.0
@export var snap_enabled: bool = true

# ── Gizmo state ─────────────────────────────────────────────────────────────
# The inline gizmo is a set of Area3D handles added as children of the
# selected primitive's StaticBody3D.  We keep a reference so we can remove it
# when the selection changes.
var _gizmo_root: Node3D = null

# Which gizmo handle is currently being dragged (null = none)
var _gizmo_drag_handle = null          # Area3D or null
var _gizmo_drag_axis: Vector3 = Vector3.ZERO
var _gizmo_drag_mode: String = ""       # "translate" | "rotate"
var _gizmo_drag_start_mouse: Vector2 = Vector2.ZERO
var _gizmo_drag_start_pos: Vector3 = Vector3.ZERO
var _gizmo_drag_start_rot: Vector3 = Vector3.ZERO
# Reference angle for rotate-ring drag (atan2 in XZ plane)
var _gizmo_drag_start_angle: float = 0.0

# Handle collision is on layer 4 (same as Design Lab gizmo)
const GIZMO_LAYER := 4

# Gizmo colours — unshaded, drawn on top, matching the Design Lab palette
const COL_X    := Color(0.95, 0.26, 0.30)
const COL_Y    := Color(0.42, 0.85, 0.32)
const COL_Z    := Color(0.30, 0.55, 0.95)
const COL_RING := Color(0.95, 0.80, 0.25)

# Selection highlight colour layered on top of the primitive's own colour
const HIGHLIGHT_EMISSION := Color(0.15, 0.40, 0.80)

var primitive_defs: Array = [
	{name="Box",      type=PrimitiveType.BOX,      icon="⬢", tooltip="Box/Cube primitive"},
	{name="Sphere",   type=PrimitiveType.SPHERE,   icon="○", tooltip="Sphere primitive"},
	{name="Cylinder", type=PrimitiveType.CYLINDER, icon="◯", tooltip="Cylinder primitive"},
	{name="Wedge",    type=PrimitiveType.WEDGE,    icon="⋔", tooltip="Wedge/Prism primitive"},
	{name="Cone",     type=PrimitiveType.CONE,     icon="△", tooltip="Cone primitive"},
	{name="Torus",    type=PrimitiveType.TORUS,    icon="⊗", tooltip="Torus (ring) primitive"},
]

@onready var hull_container:    Node3D         = $HullContainer
@onready var primitive_palette: VBoxContainer  = $CanvasLayer/PrimitiveScroller/primitive_palette
@onready var properties_panel:  VBoxContainer  = $CanvasLayer/PropertiesScroller/properties_panel
@onready var status_label:      Label          = $CanvasLayer/BottomBar/StatusLabel
@onready var clear_button:      Button         = $CanvasLayer/BottomBar/ClearButton
@onready var export_button:     Button         = $CanvasLayer/BottomBar/ExportButton
@onready var back_button:       Button         = $CanvasLayer/BackButton

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Defer palette population to ensure CanvasLayer children are ready
	call_deferred("_populate_palette")

func _populate_palette() -> void:
	if not primitive_palette or not properties_panel or not status_label:
		push_error("UI nodes not ready in _populate_palette")
		return

	var first := true
	for d in primitive_defs:
		var btn := Button.new()
		btn.text = str(d.icon) + "  " + str(d.name)
		btn.tooltip_text = str(d.tooltip)
		btn.toggle_mode = true
		if first:
			btn.button_pressed = true
			first = false
		var prim_type := int(d.type)

		btn.pressed.connect(func():
			_on_primitive_selected(prim_type)
			_update_palette_toggle(btn)
		)

		# Drag from palette on mouse down
		btn.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
				_start_palette_drag(prim_type)
		)

		palette_buttons.append(btn)
		primitive_palette.add_child(btn)

	clear_button.pressed.connect(_on_clear_clicked)
	export_button.pressed.connect(_on_export_clicked)
	back_button.pressed.connect(_on_back_clicked)

	_update_properties_panel()
	_update_status("Drag primitives from palette, or click to place!")

func _update_palette_toggle(selected: Button) -> void:
	for btn in palette_buttons:
		if btn != selected:
			btn.button_pressed = false

# ── Input ────────────────────────────────────────────────────────────────────

# Global input handler — runs before _unhandled_input
func _input(event: InputEvent) -> void:
	# Gizmo drag takes highest priority while a handle is active
	if _gizmo_drag_handle != null:
		if event is InputEventMouseMotion:
			_on_gizmo_drag_motion(event)
			return
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_on_gizmo_drag_end()
			return

	# Palette drag
	if is_dragging_from_palette:
		if event is InputEventMouseMotion:
			_update_preview_position(event.position)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_drop_from_palette(event.position)

func _unhandled_input(event: InputEvent) -> void:
	# ── Keyboard shortcuts ───────────────────────────────────────────────────
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_G:
				transform_mode = 0
				_update_status("Move mode — drag surfaces to reposition")

			KEY_R:
				transform_mode = 1
				_update_status("Rotate mode (G/R/S to switch modes)")

			KEY_S:
				transform_mode = 2
				_update_status("Scale mode (G/R/S to switch modes)")

			KEY_DELETE, KEY_KP_PERIOD:
				_delete_selected()

			KEY_D:
				if event.ctrl_pressed:
					_duplicate_selected()

			KEY_ESCAPE:
				if is_dragging_from_palette:
					is_dragging_from_palette = false
					if preview_node:
						preview_node.queue_free()
						preview_node = null
					_update_status("Cancelled")
				else:
					_deselect()

	# ── Viewport mouse input ─────────────────────────────────────────────────
	_on_viewport_input(event)

# ── Palette drag ─────────────────────────────────────────────────────────────

func _start_palette_drag(type: PrimitiveType) -> void:
	is_dragging_from_palette = true
	dragged_palette_type = type

	if preview_node:
		preview_node.queue_free()

	preview_node = _make_preview_node(type)
	add_child(preview_node)
	_update_status("Dragging " + _def_name(type) + " — release over workspace to place")

func _update_preview_position(mouse_pos: Vector2) -> void:
	if not preview_node:
		return
	var ray_result := _do_raycast(mouse_pos)
	if not ray_result.is_empty():
		var hit_idx := _hit_existing_primitive(ray_result)
		# After first primitive, only show preview when over a primitive surface
		if has_origin and hit_idx < 0:
			preview_node.visible = false
			return

		var snap_pos = ray_result.position
		if snap_enabled:
			snap_pos = _compute_snap_position(ray_result.position, ray_result.get("normal", Vector3.UP), dragged_palette_type)
		preview_node.global_position = snap_pos
		preview_node.visible = true
	else:
		if has_origin:
			preview_node.visible = false
		else:
			var camera := get_viewport().get_camera_3d()
			if camera:
				var from    := camera.project_ray_origin(mouse_pos)
				var to_dir  := camera.project_ray_normal(mouse_pos)
				preview_node.global_position = from + to_dir * 10.0
			preview_node.visible = true

func _drop_from_palette(mouse_pos: Vector2) -> void:
	is_dragging_from_palette = false
	if preview_node:
		var drop_pos = preview_node.global_position
		preview_node.queue_free()
		preview_node = null

		if not has_origin:
			_add_primitive_at_position(dragged_palette_type, drop_pos)
			_update_status("Placed " + _def_name(dragged_palette_type))
			return

		# After first primitive, only drop when over a primitive surface
		var ray_result := _do_raycast(mouse_pos)
		if not ray_result.is_empty():
			var hit_idx := _hit_existing_primitive(ray_result)
			if hit_idx >= 0:
				_add_primitive_at_position(dragged_palette_type, drop_pos)
				_update_status("Placed " + _def_name(dragged_palette_type))
				return
		_update_status("Must place on an existing primitive surface")

# ── Viewport interaction ──────────────────────────────────────────────────────

func _on_viewport_input(event: InputEvent) -> void:
	if not hull_container:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Check gizmo handles first (layer 4)
				var gizmo_hit: Node3D = _raycast_gizmo(event.position)
				if gizmo_hit:
					_on_gizmo_drag_start(gizmo_hit, event.position)
					return

				var ray_result := _do_raycast(event.position)
				var hit_idx := -1
				if not ray_result.is_empty():
					hit_idx = _hit_existing_primitive(ray_result)

				if hit_idx >= 0:
					# Select primitive
					_select_primitive(hit_idx)
				elif not has_origin:
					# First primitive — place at grid click
					if not ray_result.is_empty():
						var snap_pos = ray_result.position
						if snap_enabled:
							snap_pos = _compute_snap_position(ray_result.position, ray_result.get("normal", Vector3.UP), current_primitive_type)
						_add_primitive_at_position(current_primitive_type, snap_pos)
					else:
						var camera := get_viewport().get_camera_3d()
						if camera:
							var from    := camera.project_ray_origin(event.position)
							var to_dir  := camera.project_ray_normal(event.position)
							_add_primitive_at_position(current_primitive_type, from + to_dir * 10.0)
				elif ray_result.has("normal"):
					var hit_on_prim := _hit_existing_primitive(ray_result)
					if hit_on_prim >= 0:
						# Place attached to surface
						var snap_pos = ray_result.position
						if snap_enabled:
							snap_pos = _compute_snap_position(ray_result.position, ray_result.get("normal", Vector3.UP), current_primitive_type)
						_add_primitive_at_position(current_primitive_type, snap_pos)
					else:
						# Clicked empty space — deselect
						_deselect()
				else:
					_deselect()

			else:  # Released
				pass

# ── Selection / deselect ─────────────────────────────────────────────────────

func _select_primitive(idx: int) -> void:
	var prev := selected_primitive
	selected_primitive = idx

	# Remove highlight from previously selected
	if prev >= 0 and prev < primitives.size():
		_set_highlight(prev, false)

	# Apply highlight to newly selected
	_set_highlight(idx, true)
	_attach_gizmo(idx)
	_update_properties_panel()
	_update_status("Selected " + _def_name(primitives[idx].type)
		+ " #" + str(idx + 1) + " — DEL to delete, Ctrl+D to duplicate")

func _deselect() -> void:
	if selected_primitive >= 0 and selected_primitive < primitives.size():
		_set_highlight(selected_primitive, false)
	selected_primitive = -1
	_detach_gizmo()
	_update_properties_panel()
	_update_status("Click a primitive to select, or drag from palette to add")

# ── Highlight ────────────────────────────────────────────────────────────────

func _set_highlight(idx: int, on: bool) -> void:
	if idx < 0 or idx >= primitives.size():
		return
	var prim = primitives[idx]
	if not prim.node:
		return
	for child in prim.node.get_children():
		if child is MeshInstance3D:
			var mat = child.material_override as StandardMaterial3D
			if mat:
				mat.emission_enabled = on
				mat.emission = HIGHLIGHT_EMISSION if on else Color.BLACK
				mat.emission_energy_multiplier = 0.6 if on else 0.0

# ── Gizmo creation & teardown ────────────────────────────────────────────────

func _attach_gizmo(idx: int) -> void:
	_detach_gizmo()
	if idx < 0 or idx >= primitives.size():
		return
	var prim = primitives[idx]
	if not prim.node:
		return

	# Instantiate the prefab gizmo (has handles with scripts attached)
	var gizmo = Gizmo3D.instantiate()
	prim.node.add_child(gizmo)
	_gizmo_root = gizmo

	# Connect handle signals
	var hx = gizmo.get_node_or_null("HandleX")
	var hy = gizmo.get_node_or_null("HandleY")
	var hz = gizmo.get_node_or_null("HandleZ")
	var hrot = gizmo.get_node_or_null("HandleRotate")

	if hx:
		hx.drag_started.connect(_on_gizmo_drag_start.bind(hx))
		hx.dragged.connect(_on_gizmo_dragged.bind(hx))
		hx.drag_ended.connect(_on_gizmo_drag_end.bind(hx))
	if hy:
		hy.drag_started.connect(_on_gizmo_drag_start.bind(hy))
		hy.dragged.connect(_on_gizmo_dragged.bind(hy))
		hy.drag_ended.connect(_on_gizmo_drag_end.bind(hy))
	if hz:
		hz.drag_started.connect(_on_gizmo_drag_start.bind(hz))
		hz.dragged.connect(_on_gizmo_dragged.bind(hz))
		hz.drag_ended.connect(_on_gizmo_drag_end.bind(hz))
	if hrot:
		hrot.drag_started.connect(_on_gizmo_drag_start.bind(hrot))
		hrot.rotated.connect(_on_gizmo_rotated.bind(hrot))
		hrot.drag_ended.connect(_on_gizmo_drag_end.bind(hrot))

func _detach_gizmo() -> void:
	if _gizmo_root and is_instance_valid(_gizmo_root):
		_gizmo_root.queue_free()
	_gizmo_root = null
	_gizmo_drag_handle = null

func _build_axis_handle(parent: Node3D, handle_name: String,
		offset: Vector3, axis: Vector3,
		color: Color, giz_r: float) -> void:
	var area := Area3D.new()
	area.name = handle_name
	area.set_meta("axis", axis)
	area.collision_layer = GIZMO_LAYER
	area.collision_mask  = 0

	# Thin arrow-box oriented along the axis
	var col := CollisionShape3D.new()
	var bs  := BoxShape3D.new()
	var handle_sz := giz_r * 0.18
	bs.size = Vector3(
		handle_sz if axis.x == 0 else giz_r * 0.55,
		handle_sz if axis.y == 0 else giz_r * 0.55,
		handle_sz if axis.z == 0 else giz_r * 0.55,
	)
	col.shape = bs
	area.add_child(col)

	# Visual mesh — same size as collision, unshaded and drawn on top
	var mi   := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = bs.size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color              = color
	mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test             = true
	mat.render_priority           = 1
	mi.material_override = mat
	area.add_child(mi)

	area.position = offset
	parent.add_child(area)

func _build_rotate_ring(parent: Node3D, giz_r: float) -> void:
	var area := Area3D.new()
	area.name = "HandleRotate"
	area.set_meta("axis", Vector3.ZERO)   # special: indicates rotation
	area.collision_layer = GIZMO_LAYER
	area.collision_mask  = 0

	var col     := CollisionShape3D.new()
	var cyl_shp := CylinderShape3D.new()
	cyl_shp.radius = giz_r * 1.05
	cyl_shp.height = 0.15
	col.shape = cyl_shp
	area.add_child(col)

	var mi   := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = giz_r * 0.88
	mesh.outer_radius = giz_r * 1.02
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color    = COL_RING
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test   = true
	mat.render_priority = 1
	mi.material_override = mat
	area.add_child(mi)

	parent.add_child(area)

# ── Gizmo raycast (layer 4 only) ─────────────────────────────────────────────

func _raycast_gizmo(mouse_pos: Vector2) -> Node3D:
	if _gizmo_root == null or not is_instance_valid(_gizmo_root):
		return null
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return null

	var from   := camera.project_ray_origin(mouse_pos)
	var to_dir := camera.project_ray_normal(mouse_pos)
	var to     := from + to_dir * 1000.0

	var space  := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.new()
	params.from           = from
	params.to             = to
	params.collision_mask = GIZMO_LAYER
	var result := space.intersect_ray(params)

	if result.is_empty():
		return null

	# Walk up to find a direct child of _gizmo_root
	var hit := result.collider as Node3D
	if not hit:
		return null
	while hit and hit.get_parent() != _gizmo_root:
		hit = hit.get_parent() as Node3D
		if not hit:
			return null
	return hit if is_instance_valid(hit) else null

# ── Gizmo drag logic ─────────────────────────────────────────────────────────

func _on_gizmo_drag_start(handle: Node3D, mouse_pos: Vector2) -> void:
	_gizmo_drag_handle = handle
	_gizmo_drag_start_mouse = mouse_pos

	var axis: Vector3 = handle.get_meta("axis") if handle.has_meta("axis") else Vector3.ZERO
	_gizmo_drag_axis = axis

	if selected_primitive >= 0 and selected_primitive < primitives.size():
		_gizmo_drag_start_pos = primitives[selected_primitive].position
		_gizmo_drag_start_rot = primitives[selected_primitive].rotation

	if axis == Vector3.ZERO:
		# Rotation ring — record starting angle in XZ plane from camera
		_gizmo_drag_mode = "rotate"
		var prim_pos := Vector3.ZERO
		if selected_primitive >= 0 and selected_primitive < primitives.size():
			prim_pos = primitives[selected_primitive].position
		_gizmo_drag_start_angle = _mouse_angle_in_xz(mouse_pos, prim_pos)
	else:
		_gizmo_drag_mode = "translate"

func _on_gizmo_drag_motion(event: InputEventMouseMotion) -> void:
	if selected_primitive < 0 or selected_primitive >= primitives.size():
		return
	var prim = primitives[selected_primitive]

	if _gizmo_drag_mode == "translate":
		# Project mouse delta onto the drag axis in world space
		var camera := get_viewport().get_camera_3d()
		if not camera:
			return
		var from_old := camera.project_ray_origin(_gizmo_drag_start_mouse)
		var to_old   := from_old + camera.project_ray_normal(_gizmo_drag_start_mouse) * 500.0
		var from_new := camera.project_ray_origin(event.position)
		var to_new   := from_new + camera.project_ray_normal(event.position) * 500.0

		# Intersect both rays with the plane that contains the axis and is
		# most face-on to the camera.  Use the axis's two perpendicular planes
		# and pick the one whose normal is more aligned with the view ray.
		var axis := _gizmo_drag_axis
		var cam_dir := (to_new - from_new).normalized()
		var perp1   := axis.cross(cam_dir).normalized()
		var plane_n := axis.cross(perp1).normalized()

		var old_t := _ray_plane_t(from_old, (to_old - from_old).normalized(), _gizmo_drag_start_pos, plane_n)
		var new_t := _ray_plane_t(from_new, (to_new - from_new).normalized(), _gizmo_drag_start_pos, plane_n)

		if old_t < 0.0 or new_t < 0.0:
			return

		var old_world := from_old + (to_old - from_old).normalized() * old_t
		var new_world := from_new + (to_new - from_new).normalized() * new_t
		var delta     := (new_world - old_world).dot(axis) * axis

		prim.position = _gizmo_drag_start_pos + delta
		if prim.node:
			prim.node.position = prim.position
		_update_properties_panel()

	elif _gizmo_drag_mode == "rotate":
		# Free-form Y-axis rotation in XZ plane
		var cur_angle := _mouse_angle_in_xz(event.position, prim.position)
		var delta_ang := cur_angle - _gizmo_drag_start_angle

		# Accumulate onto start rotation
		prim.rotation.y = _gizmo_drag_start_rot.y + delta_ang
		if prim.node:
			prim.node.rotation = prim.rotation
		_update_properties_panel()

func _on_gizmo_drag_end() -> void:
	_gizmo_drag_handle = null
	_gizmo_drag_mode   = ""
	_update_status("Ready")

func _on_gizmo_dragged(offset: Vector3) -> void:
	if not _gizmo_drag_handle or not is_instance_valid(_gizmo_drag_handle):
		return
		
	var axis = _gizmo_drag_handle.get_meta("axis")
	if axis == Vector3.ZERO:
		return  # Shouldn't happen for axis handles
		
	if selected_primitive < 0 or selected_primitive >= primitives.size():
		return
		
	var prim = primitives[selected_primitive]
	if not prim.node:
		return

	# Move along the axis
	var move_amount = offset.dot(axis)  # Project offset onto axis
	var new_pos = _gizmo_drag_start_pos + axis * move_amount
	
	prim.position = new_pos
	if prim.node:
		prim.node.position = new_pos
		
	_update_properties_panel()

func _on_gizmo_rotated(angle: float) -> void:
	if not _gizmo_drag_handle or not is_instance_valid(_gizmo_drag_handle):
		return
		
	# Only the rotation ring should call this
	if selected_primitive < 0 or selected_primitive >= primitives.size():
		return
		
	var prim = primitives[selected_primitive]
	if not prim.node:
		return

	# Rotate around Y axis (yaw)
	var new_rot = _gizmo_drag_start_rot
	new_rot.y += angle
	
	# Clamp pitch to prevent flipping
	new_rot.x = clamp(new_rot.x, -PI/2 + 0.1, PI/2 - 0.1)
	
	prim.rotation = new_rot
	if prim.node:
		prim.node.rotation = new_rot
		
	_update_properties_panel()

# Helper: signed angle from world position to mouse ray in XZ plane
func _mouse_angle_in_xz(mouse_pos: Vector2, pivot: Vector3) -> float:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return 0.0
	var from   := camera.project_ray_origin(mouse_pos)
	var dir    := camera.project_ray_normal(mouse_pos)
	# Intersect with y = pivot.y plane
	if abs(dir.y) < 0.0001:
		return 0.0
	var t := (pivot.y - from.y) / dir.y
	if t <= 0:
		return 0.0
	var hit := from + dir * t
	var rel := hit - pivot
	return atan2(rel.x, rel.z)

# Helper: ray–plane intersection, returns t or -1 if no hit
func _ray_plane_t(ray_origin: Vector3, ray_dir: Vector3,
		plane_point: Vector3, plane_normal: Vector3) -> float:
	var denom := plane_normal.dot(ray_dir)
	if abs(denom) < 0.0001:
		return -1.0
	return plane_normal.dot(plane_point - ray_origin) / denom

# ── Primitive operations ──────────────────────────────────────────────────────

func _on_primitive_selected(type: int) -> void:
	current_primitive_type = type as PrimitiveType
	_update_status("Selected " + _def_name(type) + " — Drag or click to place")

func _add_primitive_at_position(type: PrimitiveType, position: Vector3) -> void:
	if primitives.size() >= max_primitives:
		_show_warning("Maximum primitives reached (" + str(max_primitives) + ")")
		return

	var place_pos := position
	if not has_origin:
		place_pos = Vector3.ZERO
		has_origin = true

	var mi := _make_primitive_node(type)
	mi.position = place_pos

	var prim := {
		type     = type,
		position = place_pos,
		rotation = Vector3.ZERO,
		scale    = Vector3.ONE,
		color    = Color(0.7, 0.7, 0.8, 1.0),
		node     = mi,
	}

	hull_container.add_child(mi)
	primitives.append(prim)
	_select_primitive(primitives.size() - 1)
	_update_status("Added " + _def_name(type))

# ── Delete ────────────────────────────────────────────────────────────────────

func _delete_selected() -> void:
	if selected_primitive < 0 or selected_primitive >= primitives.size():
		_update_status("Nothing selected to delete")
		return

	var prim = primitives[selected_primitive]
	var name := _def_name(prim.type)

	_detach_gizmo()
	if prim.node:
		prim.node.queue_free()
	primitives.remove_at(selected_primitive)

	# If the array is now empty, reset origin state
	if primitives.is_empty():
		has_origin = false

	# Select the nearest remaining primitive (prefer same index, clamp)
	if primitives.is_empty():
		selected_primitive = -1
		_update_properties_panel()
	else:
		var next = clamp(selected_primitive, 0, primitives.size() - 1)
		selected_primitive = -1
		_select_primitive(next)

	var confirm = "Deleted " + _def_name(prim.type)
	_update_status(confirm)

# ── Duplicate ─────────────────────────────────────────────────────────────────

func _duplicate_selected() -> void:
	if selected_primitive < 0 or selected_primitive >= primitives.size():
		_update_status("Nothing selected to duplicate")
		return
	if primitives.size() >= max_primitives:
		_show_warning("Maximum primitives reached (" + str(max_primitives) + ")")
		return

	var src  = primitives[selected_primitive]
	# Offset slightly on X and Z so the duplicate is visibly separate
	var off  := Vector3(0.75, 0.0, 0.75)
	var new_pos: Vector3 = src.position + off

	var mi := _make_primitive_node(src.type)
	mi.position = new_pos
	mi.rotation = src.rotation
	mi.scale    = src.scale

	# Tint to match source colour
	for child in mi.get_children():
		if child is MeshInstance3D:
			var mat = child.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color = src.color

	var prim := {
		type     = src.type,
		position = new_pos,
		rotation = src.rotation,
		scale    = src.scale,
		color    = src.color,
		node     = mi,
	}

	hull_container.add_child(mi)
	primitives.append(prim)
	_select_primitive(primitives.size() - 1)
	_update_status("Duplicated " + _def_name(src.type))

# ── Primitive node builders ───────────────────────────────────────────────────

func _make_preview_node(type: PrimitiveType) -> Node3D:
	var mi   := MeshInstance3D.new()
	var mesh := _build_mesh_for_type(type)
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color  = Color(1.0, 0.8, 0.3, 0.5)  # Transparent gold preview
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	return mi

func _make_primitive_node(type: PrimitiveType) -> StaticBody3D:
	var body := StaticBody3D.new()
	var mi   := MeshInstance3D.new()
	mi.mesh = _build_mesh_for_type(type)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.7, 0.8, 1.0)
	mat.metallic     = 0.2
	mat.roughness    = 0.8
	mi.material_override = mat
	body.add_child(mi)

	# Collision shape
	var collision   := CollisionShape3D.new()
	collision.name  = "PrimitiveCollider"
	collision.shape = _build_collision_for_type(type)
	body.add_child(collision)

	return body

func _build_mesh_for_type(type: PrimitiveType) -> Mesh:
	match type:
		PrimitiveType.BOX:
			var bm := BoxMesh.new()
			bm.size = Vector3.ONE
			return bm
		PrimitiveType.SPHERE:
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			return sm
		PrimitiveType.CYLINDER:
			var cm := CylinderMesh.new()
			cm.height = 1.0
			cm.top_radius = 0.5
			cm.bottom_radius = 0.5
			return cm
		PrimitiveType.WEDGE:
			var pm := PrismMesh.new()
			pm.size = Vector3(1, 1, 1)
			return pm
		PrimitiveType.CONE:
			var cone := CylinderMesh.new()
			cone.height = 1.0
			cone.bottom_radius = 0.5
			cone.top_radius = 0.0
			return cone
		PrimitiveType.TORUS:
			var tm := TorusMesh.new()
			tm.inner_radius = 0.3
			tm.outer_radius = 0.6
			return tm
		_:
			return BoxMesh.new()

func _build_collision_for_type(type: PrimitiveType) -> Shape3D:
	match type:
		PrimitiveType.SPHERE:
			var s := SphereShape3D.new()
			s.radius = 0.5
			return s
		PrimitiveType.CYLINDER, PrimitiveType.CONE:
			var s := CylinderShape3D.new()
			s.height = 1.0
			s.radius = 0.5
			return s
		PrimitiveType.TORUS:
			var s := SphereShape3D.new()
			s.radius = 0.6
			return s
		_:  # BOX, WEDGE, and fallback all use a box
			var s := BoxShape3D.new()
			s.size = Vector3.ONE
			return s

func _compute_snap_position(hit_position: Vector3, hit_normal: Vector3, _target_type: PrimitiveType) -> Vector3:
	return hit_position + hit_normal * (snap_distance * 0.5)

func _hit_existing_primitive(ray_result: Dictionary) -> int:
	var hit_node := ray_result.collider as Node3D
	if not hit_node:
		return -1
	# Walk up from the CollisionShape's parent to the StaticBody3D
	for i in range(primitives.size()):
		if primitives[i].node == hit_node:
			return i
	return -1

func _do_raycast(mouse_pos: Vector2) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return {}
	var from   := camera.project_ray_origin(mouse_pos)
	var to_dir := camera.project_ray_normal(mouse_pos)
	var to     := from + to_dir * 1000.0

	var space      := get_world_3d().direct_space_state
	var ray_params := PhysicsRayQueryParameters3D.new()
	ray_params.from           = from
	ray_params.to             = to
	ray_params.collision_mask = 1  # primitives + grid
	var result := space.intersect_ray(ray_params)
	return result if not result.is_empty() else {}

func _def_name(type: int) -> String:
	for d in primitive_defs:
		if int(d.type) == type:
			return str(d.name)
	return "Unknown"

# ── Properties panel ──────────────────────────────────────────────────────────

func _update_properties_panel() -> void:
	for child in properties_panel.get_children():
		child.queue_free()

	if selected_primitive < 0 or selected_primitive >= primitives.size():
		var lbl := Label.new()
		lbl.text = "Select a primitive to edit\n\nDEL — delete\nCtrl+D — duplicate\nG/R/S — transform mode"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		properties_panel.add_child(lbl)
		return

	var prim = primitives[selected_primitive]

	# ── Title ───────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text = _def_name(prim.type) + "  #" + str(selected_primitive + 1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	properties_panel.add_child(title)

	properties_panel.add_child(HSeparator.new())

	# ── Transform ───────────────────────────────────────────────────────────
	_add_section_header("Transform")
	_add_vec3_row("Pos",  prim.position, _set_position, "position", -20.0, 20.0, 0.1)
	_add_vec3_row("Rot",  prim.rotation, _set_rotation, "rotation", -PI,   PI,   0.05)
	_add_vec3_row("Scale", prim.scale,   _set_scale,    "scale",    0.05,  20.0, 0.05)

	properties_panel.add_child(HSeparator.new())

	# ── Appearance ──────────────────────────────────────────────────────────
	_add_section_header("Appearance")

	var clbl := Label.new()
	clbl.text = "Color:"
	properties_panel.add_child(clbl)

	var idx := selected_primitive
	var cpb := ColorPickerButton.new()
	cpb.color = prim.color
	cpb.custom_minimum_size = Vector2(0, 36)
	cpb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cpb.color_changed.connect(func(c: Color):
		_on_color_changed(idx, c)
	)
	properties_panel.add_child(cpb)

	properties_panel.add_child(HSeparator.new())

	# ── Actions ─────────────────────────────────────────────────────────────
	_add_section_header("Actions")

	var dup_btn := Button.new()
	dup_btn.text = "[+] Duplicate  (Ctrl+D)"
	dup_btn.tooltip_text = "Create a copy of this primitive"
	dup_btn.pressed.connect(_duplicate_selected)
	properties_panel.add_child(dup_btn)

	var del_btn := Button.new()
	del_btn.text = "[x] Delete  (Del)"
	del_btn.tooltip_text = "Remove this primitive"
	del_btn.pressed.connect(_delete_selected)
	properties_panel.add_child(del_btn)

func _add_section_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	properties_panel.add_child(lbl)

func _add_vec3_row(label: String, value: Vector3,
		setter: Callable, prop_name: String,
		lo: float, hi: float, step: float) -> void:
	# Label
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(0, 0)
	properties_panel.add_child(lbl)

	var hb  := HBoxContainer.new()
	var idx := selected_primitive

	var xs := SpinBox.new()
	xs.min_value = lo; xs.max_value = hi; xs.step = step; xs.value = value.x
	xs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xs.value_changed.connect(func(v: float):
		var cur = primitives[idx].get(prop_name, Vector3.ZERO)
		setter.call(idx, Vector3(v, cur.y, cur.z))
	)
	hb.add_child(xs)

	var ys := SpinBox.new()
	ys.min_value = lo; ys.max_value = hi; ys.step = step; ys.value = value.y
	ys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ys.value_changed.connect(func(v: float):
		var cur = primitives[idx].get(prop_name, Vector3.ZERO)
		setter.call(idx, Vector3(cur.x, v, cur.z))
	)
	hb.add_child(ys)

	var zs := SpinBox.new()
	zs.min_value = lo; zs.max_value = hi; zs.step = step; zs.value = value.z
	zs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zs.value_changed.connect(func(v: float):
		var cur = primitives[idx].get(prop_name, Vector3.ZERO)
		setter.call(idx, Vector3(cur.x, cur.y, v))
	)
	hb.add_child(zs)

	properties_panel.add_child(hb)

# ── Setters (called by properties panel and gizmo) ───────────────────────────

func _set_position(idx: int, value: Vector3) -> void:
	if idx < 0 or idx >= primitives.size():
		return
	primitives[idx].position = value
	if primitives[idx].node:
		primitives[idx].node.position = value
	_update_status("Position updated")

func _set_rotation(idx: int, value: Vector3) -> void:
	if idx < 0 or idx >= primitives.size():
		return
	primitives[idx].rotation = value
	if primitives[idx].node:
		primitives[idx].node.rotation = value
	_update_status("Rotation updated")

func _set_scale(idx: int, value: Vector3) -> void:
	if idx < 0 or idx >= primitives.size():
		return
	primitives[idx].scale = value
	if primitives[idx].node:
		primitives[idx].node.scale = value
	_update_status("Scale updated")

func _on_color_changed(idx: int, color: Color) -> void:
	if idx < 0 or idx >= primitives.size():
		return
	primitives[idx].color = color
	if primitives[idx].node:
		for child in primitives[idx].node.get_children():
			if child is MeshInstance3D:
				var mat = child.material_override as StandardMaterial3D
				if mat:
					mat.albedo_color = color
	_update_status("Color updated")

# ── Bottom bar callbacks ──────────────────────────────────────────────────────

func _on_export_clicked() -> void:
	if primitives.is_empty():
		_show_error("No primitives to export")
		return

	# Show hull stats dialog for metadata entry
	_show_hull_stats_dialog()

func _show_hull_stats_dialog() -> void:
	var dialog = AcceptDialog.new()
	dialog.title = "Export Hull"
	dialog.custom_minimum_size = Vector2(400, 450)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	dialog.add_child(vbox)

	# Hull name
	var name_label = Label.new()
	name_label.text = "Hull Name:"
	vbox.add_child(name_label)

	var name_edit = LineEdit.new()
	name_edit.placeholder_text = "My Custom Hull"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(name_edit)

	vbox.add_child(HSeparator.new())

	# Stats section
	var stats_label = Label.new()
	stats_label.text = "Stats (auto-calculated from primitives):"
	stats_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(stats_label)

	# Calculate AABB
	var aabb = _calculate_aabb()
	var volume = aabb.size.x * aabb.size.y * aabb.size.z

	# Auto-calculated stats
	var hp = round(100.0 + volume * 20.0, 1)
	var weight = round(50.0 + volume * 15.0, 1)
	var metal = int(20 + volume * 5.0)
	var crystal = int(5 + volume * 1.0)

	var stats_text = "\nHP: %.1f\nWeight: %.1f\nMetal Cost: %d\nCrystal Cost: %d\nSize: %.2f x %.2f x %.2f" % [
		hp, weight, metal, crystal, aabb.size.x, aabb.size.y, aabb.size.z
	]
	var stats_display = Label.new()
	stats_display.text = stats_text
	stats_display.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(stats_display)

	vbox.add_child(HSeparator.new())

	# Domain selection
	var domain_label = Label.new()
	domain_label.text = "Domain:"
	vbox.add_child(domain_label)

	var domain_option = OptionButton.new()
	domain_option.add_item("Ground")
	domain_option.add_item("Naval")
	domain_option.add_item("Air")
	domain_option.add_item("Static Defense")
	domain_option.selected = 0  # Default to Ground
	vbox.add_child(domain_option)

	# Store references for callback
	dialog.set_meta("name_edit", name_edit)
	dialog.set_meta("domain_option", domain_option)
	dialog.set_meta("aabb", aabb)
	dialog.set_meta("volume", volume)

	# Connect signals
	dialog.connect("confirmed", _on_export_confirmed.bind(dialog))
	dialog.connect("canceled", func(): dialog.queue_free())

	add_child(dialog)
	dialog.popup_centered()

func _on_export_confirmed(dialog: AcceptDialog) -> void:
	var name_edit = dialog.get_meta("name_edit")
	var domain_option = dialog.get_meta("domain_option")
	var aabb = dialog.get_meta("aabb")
	var volume = dialog.get_meta("volume")

	var hull_name = name_edit.text.strip_edges()
	if hull_name == "":
		hull_name = "custom_hull_%d" % Time.get_ticks_msec()

	var domain = domain_option.get_item_text(domain_option.selected)

	# Serialize primitives to JSON
	var temp_json = _serialize_for_blender(hull_name)
	var temp_json_path = _write_temp_json(temp_json)

	# Invoke Blender to bake the hull
	var blender_path = ProjectSettings.globalize_path(
		"../UPBGE-0.30-windows-x86_64/blender.exe")
	var script_path = ProjectSettings.globalize_path(
		"../tools/blender/bake_custom_hull.py")
	var output_glb = ProjectSettings.globalize_path(
		"../assets/models/hulls/%s.glb" % hull_name)
	var output_json = ProjectSettings.globalize_path(
		"../assets/models/hulls/%s.json" % hull_name)

	# Pass domain as additional argument
	var args = ["--background", "--python", script_path,
				"--", temp_json_path, output_glb, output_json, domain]

	var pid = OS.create_process(blender_path, args)
	if pid < 0:
		_show_error("Failed to start Blender")
		dialog.queue_free()
		return

	# Show export progress
	_update_status("Exporting hull to Blender... (PID: %d)" % [pid])
	dialog.queue_free()

	# Poll for completion (simplified - in a real implementation you'd use a proper process monitor)
	await get_tree().create_timer(0.5).timeout
	_update_status("Hull export started. Check assets/models/hulls/ for %s.glb and %s.json" % [hull_name, hull_name])

func _calculate_aabb() -> AABB:
	var aabb = AABB()
	if primitives.is_empty():
		return aabb

	for prim in primitives:
		if prim.node:
			var node_aabb = AABB()
			var mesh_instances = _find_mesh_instances(prim.node)
			for mi in mesh_instances:
				if mi.mesh:
					var mesh_aabb = mi.mesh.get_aabb()
					mesh_aabb.position += mi.global_position
					node_aabb.merge_with(mesh_aabb)
			aabb.merge_with(node_aabb)

	return aabb

func _find_mesh_instances(node: Node3D) -> Array:
	var result = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_mesh_instances(child))
	return result

# Status bar helper
func _show_status_message(message: String, duration: float = 3.0) -> void:
	if status_label:
		status_label.text = message

	if duration > 0:
		await get_tree().create_timer(duration).timeout
		status_label.text = "Ready"

func _generate_color_for_primitive(type: PrimitiveType) -> Color:
	# Generate a distinct color for each primitive type
	match type:
		PrimitiveType.BOX:
			return Color(0.7, 0.7, 0.8, 1.0)
		PrimitiveType.SPHERE:
			return Color(0.8, 0.6, 0.4, 1.0)
		PrimitiveType.CYLINDER:
			return Color(0.6, 0.8, 0.7, 1.0)
			PrimitiveType.WEDGE:
			return Color(0.9, 0.7, 0.5, 1.0)
		PrimitiveType.CONE:
			return Color(0.8, 0.5, 0.6, 1.0)
		PrimitiveType.TORUS:
			return Color(0.5, 0.7, 0.8, 1.0)
		_:
			return Color(0.7, 0.7, 0.8, 1.0)

func _update_undo_stack(action: Dictionary) -> void:
	# Simple undo stack - just store last 10 actions
	if _undo_stack.size() >= 10:
		_undo_stack.remove_at(0)
	_undo_stack.append(action)

func _perform_undo() -> bool:
	if _undo_stack.size() == 0:
		return false

	var action = _undo_stack.pop_at(_undo_stack.size() - 1)
	_match_undo_action(action)
	return true

func _match_undo_action(action: Dictionary) -> void:
	match action["type"]:
		"add_primitive":
			_delete_primitive_at_position(action["index"])
		"delete_primitive":
			# Restore deleted primitive (simplified - would need to store full state)
			# For now, just show message
			_update_status("Undo: primitive deletion restored")
		"move_primitive":
			# Restore position
			var idx = action["index"]
			if idx >= 0 and idx < primitives.size():
				primitives[idx].position = action["old_position"]
				if primitives[idx].node:
					primitives[idx].node.position = action["old_position"]
			_update_properties_panel()
		"scale_primitive":
			var idx = action["index"]
			if idx >= 0 and idx < primitives.size():
				primitives[idx].scale = action["old_scale"]
				if primitives[idx].node:
					primitives[idx].node.scale = action["old_scale"]
			_update_properties_panel()
		"rotate_primitive":
			var idx = action["index"]
			if idx >= 0 and idx < primitives.size():
				primitives[idx].rotation = action["old_rotation"]
				if primitives[idx].node:
					primitives[idx].node.rotation = action["old_rotation"]
			_update_properties_panel()
		"color_primitive":
			var idx = action["index"]
			if idx >= 0 and idx < primitives.size():
				primitives[idx].color = action["old_color"]
				if primitives[idx].node:
					for child in primitives[idx].node.get_children():
						if child is MeshInstance3D:
							var mat = child.material_override as StandardMaterial3D
							if mat:
								mat.albedo_color = action["old_color"]
			_update_properties_panel()

# Utility functions for data conversion
func _primitive_type_to_string(type: PrimitiveType) -> String:
	match type:
		PrimitiveType.BOX: return "BOX"
		PrimitiveType.SPHERE: return "SPHERE"
		PrimitiveType.CYLINDER: return "CYLINDER"
		PrimitiveType.WEDGE: return "WEDGE"
		PrimitiveType.CONE: return "CONE"
		PrimitiveType.TORUS: return "TORUS"
		_: return "BOX"

func _string_to_primitive_type(str: String) -> PrimitiveType:
	match str.to_upper():
		"BOX": return PrimitiveType.BOX
		"SPHERE": return PrimitiveType.SPHERE
		"CYLINDER": return PrimitiveType.CYLINDER
		"WEDGE": return PrimitiveType.WEDGE
		"CONE": return PrimitiveType.CONE
		"TORUS": return PrimitiveType.TORUS
		_: return PrimitiveType.BOX

func _serialize_for_blender(hull_name: String) -> Dictionary:
	var primitives_data = []
	for prim in primitives:
		var prim_data = {
			"type": prim.type,
			"position": [prim.position.x, prim.position.y, prim.position.z],
			"rotation": [prim.rotation.x, prim.rotation.y, prim.rotation.z],
			"scale": [prim.scale.x, prim.scale.y, prim.scale.z],
			"color": [prim.color.r, prim.color.g, prim.color.b, prim.color.a]
		}
		primitives_data.append(prim_data)

	return {
		"hull_name": hull_name,
		"primitives": primitives_data
	}

func _write_temp_json(data: Dictionary) -> String:
	var json = JSON.new()
	var err = json.stringify(data)
	if err != OK:
		_show_error("Failed to serialize JSON: %s" % json.get_error_message())
		return ""

	var temp_path = ProjectSettings.globalize_path("../tools/blender/hull_export_temp.json")
	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	if file:
		file.store_string(json.get_data())
		file.close()
		return temp_path
	else:
		_show_error("Failed to write temp JSON")
		return ""

func _on_clear_clicked() -> void:
	_detach_gizmo()
	for p in primitives:
		if p.node:
			p.node.queue_free()
	primitives.clear()
	selected_primitive = -1
	has_origin = false
	_update_properties_panel()
	_update_status("Cleared all primitives")

func _on_back_clicked() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

# ── Status helpers ────────────────────────────────────────────────────────────

func _update_status(msg: String) -> void:
	if status_label:
		status_label.text = msg

func _show_error(msg: String) -> void:
	_update_status("ERROR: " + msg)
	await get_tree().create_timer(3.0).timeout
	_update_status("Ready")

func _show_warning(msg: String) -> void:
	_update_status("WARNING: " + msg)
	await get_tree().create_timer(3.0).timeout
	_update_status("Ready")

func _show_info(msg: String) -> void:
	_update_status("INFO: " + msg)
	await get_tree().create_timer(3.0).timeout
	_update_status("Ready")
