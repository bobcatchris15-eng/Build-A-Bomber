extends Node3D

const SDFMeshBaker = preload("res://scripts/sdf_mesh_baker.gd")
const HullLoader = preload("res://scripts/hull_loader.gd")
const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")

# Voxel resolution (longest-axis voxel count) for each Bake Quality choice -
# see SDFMeshBaker.bake(). Higher = smoother/more accurate fillets, slower
# bake (the bake is synchronous GDScript, triggered once from Export).
const BAKE_RESOLUTIONS := [24, 32, 48]
const BAKE_QUALITY_NAMES := ["Low", "Medium", "High"]

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
	TORUS,
	# Expanded "Lego kit" - see tools/blender/build_hull_primitives.py for the
	# 10 Blender-authored shapes (everything below except CAPSULE/HEX_PRISM/
	# PYRAMID, which Godot already builds natively via CapsuleMesh/CylinderMesh
	# with a low radial segment count - no authored asset needed for those 3).
	SLOPE,
	FRUSTUM,
	CHAMFER_BOX,
	HALF_CYLINDER,
	HEMISPHERE,
	CAPSULE,
	I_BEAM,
	L_BEAM,
	HEX_PRISM,
	PYRAMID,
	FENDER,
	CANOPY,
	RING,
}

# Shape-type ids whose mesh is an authored .glb (tools/blender/build_hull_
# primitives.py) rather than a Godot-native procedural Mesh - keyed by the
# exact filename stem under assets/models/hull_primitives/.
const AUTHORED_PRIMITIVE_SHAPES := {
	PrimitiveType.SLOPE: "slope",
	PrimitiveType.FRUSTUM: "frustum",
	PrimitiveType.CHAMFER_BOX: "chamfer_box",
	PrimitiveType.HALF_CYLINDER: "half_cylinder",
	PrimitiveType.HEMISPHERE: "hemisphere",
	PrimitiveType.I_BEAM: "i_beam",
	PrimitiveType.L_BEAM: "l_beam",
	PrimitiveType.FENDER: "fender",
	PrimitiveType.CANOPY: "canopy",
	PrimitiveType.RING: "ring",
}

# Persistent state
var primitives: Array = []
var selected_primitive: int = -1
var current_primitive_type: PrimitiveType = PrimitiveType.BOX
var has_origin: bool = false

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
# _gizmo_drag_axis: the handle's fixed local axis (RIGHT/UP/BACK) ROTATED
# into the primitive's current world orientation - used for projecting mouse
# movement (translate/scale) and as the actual rotation axis (rotate).
# _gizmo_drag_local_axis: the raw, UNROTATED local axis - only used to pick
# which of prim.scale's x/y/z components a scale drag should modify, since
# that's inherently a local-space concept (see _on_gizmo_drag_motion()).
var _gizmo_drag_axis: Vector3 = Vector3.ZERO
var _gizmo_drag_local_axis: Vector3 = Vector3.ZERO
var _gizmo_drag_mode: String = ""       # "translate" | "rotate" | "scale"
var _gizmo_drag_start_mouse: Vector2 = Vector2.ZERO
var _gizmo_drag_start_pos: Vector3 = Vector3.ZERO
var _gizmo_drag_start_rot: Vector3 = Vector3.ZERO
var _gizmo_drag_start_scale: Vector3 = Vector3.ONE
# Reference angle for rotate-ring drag (atan2 in XZ plane)
var _gizmo_drag_start_angle: float = 0.0

# Undo stack (see _update_undo_stack/_perform_undo below)
var _undo_stack: Array = []

# Handle collision is on layer 4 (translate/scale) and layer 8 (rotate ring),
# kept on SEPARATE bits so _raycast_gizmo() can query them in two passes and
# give translate/scale priority - the rotate ring necessarily lies flat in
# the XZ plane (it represents yaw), so any camera angle that looks nearly
# straight down X or Z views it edge-on; from that angle a ring segment can
# sit nearer the camera than a translate/scale handle along the EXACT SAME
# ray, and a plain nearest-hit raycast would pick the ring regardless of
# on-screen position - confirmed directly: the default designer_camera.gd
# starting angle looks almost exactly down -Z, so this wasn't a rare edge
# case, it was the very first thing a player would hit.
const GIZMO_LAYER := 4
const GIZMO_ROTATE_LAYER := 8

# Gizmo colours — unshaded, drawn on top, matching the Design Lab palette.
# Each rotation ring now uses its own axis's colour too (see _attach_gizmo()),
# rather than one shared gold ring colour, now that there are three rings.
const COL_X := Color(0.95, 0.26, 0.30)
const COL_Y := Color(0.42, 0.85, 0.32)
const COL_Z := Color(0.30, 0.55, 0.95)

# Selection highlight colour layered on top of the primitive's own colour
const HIGHLIGHT_EMISSION := Color(0.15, 0.40, 0.80)

var primitive_defs: Array = [
	{name="Box",          type=PrimitiveType.BOX,           icon="⬢", tooltip="Box/Cube primitive"},
	{name="Sphere",       type=PrimitiveType.SPHERE,        icon="○", tooltip="Sphere primitive"},
	{name="Cylinder",     type=PrimitiveType.CYLINDER,      icon="◯", tooltip="Cylinder primitive"},
	{name="Wedge",        type=PrimitiveType.WEDGE,         icon="⋔", tooltip="Wedge/Prism primitive"},
	{name="Cone",         type=PrimitiveType.CONE,          icon="△", tooltip="Cone primitive"},
	{name="Torus",        type=PrimitiveType.TORUS,         icon="⊗", tooltip="Torus (ring) primitive"},
	{name="Slope",        type=PrimitiveType.SLOPE,         icon="◺", tooltip="Box with one bevelled top-front edge - Lego-slope read"},
	{name="Frustum",      type=PrimitiveType.FRUSTUM,       icon="⏢", tooltip="Box tapered to a smaller top footprint"},
	{name="Chamfer Box",  type=PrimitiveType.CHAMFER_BOX,   icon="▢", tooltip="Box with all edges bevelled - cast-armor-block read"},
	{name="Half-Cylinder",type=PrimitiveType.HALF_CYLINDER, icon="◗", tooltip="Flat-bottomed half-round trough/canopy shell"},
	{name="Hemisphere",   type=PrimitiveType.HEMISPHERE,    icon="◔", tooltip="Flat-bottomed dome - turret hatch/sensor blister"},
	{name="Capsule",      type=PrimitiveType.CAPSULE,       icon="⬭", tooltip="Rounded-end cylinder - pod/fuselage section"},
	{name="I-Beam",       type=PrimitiveType.I_BEAM,        icon="ǁ", tooltip="I-beam structural section"},
	{name="L-Beam",       type=PrimitiveType.L_BEAM,        icon="⌐", tooltip="L-angle bracket structural section"},
	{name="Hex Prism",    type=PrimitiveType.HEX_PRISM,     icon="⬡", tooltip="Hexagonal prism - turret/nut/bolt read"},
	{name="Pyramid",      type=PrimitiveType.PYRAMID,       icon="▲", tooltip="4-sided pyramid/spike"},
	{name="Fender",       type=PrimitiveType.FENDER,        icon="◠", tooltip="Open half-torus arch - wheel-arch/mudguard read"},
	{name="Canopy",       type=PrimitiveType.CANOPY,        icon="◓", tooltip="Dome elongated along Z - cockpit/turret bubble read"},
	{name="Ring",         type=PrimitiveType.RING,          icon="◎", tooltip="Flat annulus/washer - turret ring collar"},
]

@onready var hull_container:    Node3D         = $HullContainer
@onready var primitive_palette: VBoxContainer  = $CanvasLayer/PrimitiveScroller/primitive_palette
@onready var properties_panel:  VBoxContainer  = $CanvasLayer/PropertiesScroller/properties_panel
@onready var status_label:      Label          = $CanvasLayer/BottomBar/StatusLabel
@onready var clear_button:      Button         = $CanvasLayer/HullActionsScroller/HullActionsPanel/ClearButton
@onready var export_button:     Button         = $CanvasLayer/HullActionsScroller/HullActionsPanel/ExportButton
@onready var back_button:       Button         = $CanvasLayer/BackButton
@onready var smoothness_slider: HSlider        = $CanvasLayer/HullActionsScroller/HullActionsPanel/SmoothnessSlider
@onready var bake_quality_option: OptionButton = $CanvasLayer/HullActionsScroller/HullActionsPanel/BakeQualityOption
@onready var save_assembly_button: Button      = $CanvasLayer/HullActionsScroller/HullActionsPanel/SaveAssemblyButton
@onready var load_assembly_button: Button      = $CanvasLayer/HullActionsScroller/HullActionsPanel/LoadAssemblyButton

# Bake parameters, read from the bottom-bar controls at export time.
var smoothness: float = 0.15
var bake_resolution: int = 32
var bake_method: String = "dc"
var fit_percent: float = 95.0
var facet_angle: float = 15.0
var crystallinity: float = 0.0

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
		btn.custom_minimum_size = Vector2(0, 48)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 16)
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
	save_assembly_button.pressed.connect(_on_save_assembly_clicked)
	load_assembly_button.pressed.connect(_on_load_assembly_clicked)

	for i in range(BAKE_QUALITY_NAMES.size()):
		bake_quality_option.add_item(BAKE_QUALITY_NAMES[i])
	bake_quality_option.selected = 1  # Medium
	bake_quality_option.item_selected.connect(func(idx: int):
		bake_resolution = BAKE_RESOLUTIONS[idx]
	)
	bake_resolution = BAKE_RESOLUTIONS[bake_quality_option.selected]

	smoothness_slider.value = smoothness
	smoothness_slider.value_changed.connect(func(v: float):
		smoothness = v
		_queue_smoothness_preview()
	)

	_setup_smoothness_preview()
	_setup_forward_arrow()

	_update_properties_panel()
	_update_status("Drag primitives from palette, or click to place!")

func _process(_delta: float) -> void:
	_update_forward_arrow()

# ── Forward-direction indicator ─────────────────────────────────────────────
# Every hull in this project shares a -Z-forward convention (see
# mesh_asset_loader.gd's/build_meshes.py's own comments: "the nose is the
# most-negative-Z tip") - worth making that visible while building, since
# nothing else in this editor otherwise shows which end is the front. Recomputed
# every frame off the CURRENT primitive AABB rather than hooked into every
# individual mutation path (add/delete/duplicate/drag-move/drag-scale/clear) -
# simpler and can't miss a path, and an AABB walk over at most
# max_primitives=50 small primitives is not a meaningful per-frame cost.
const FORWARD_ARROW_COLOR := Color(0.25, 0.95, 0.35)
const FORWARD_ARROW_MARGIN := 0.6

var _forward_arrow: Node3D = null

func _setup_forward_arrow() -> void:
	_forward_arrow = Node3D.new()
	hull_container.add_child(_forward_arrow)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = FORWARD_ARROW_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 1

	# CylinderMesh's default axis is local Y; rotation.x = -PI/2 maps local
	# +Y onto world -Z (verified: Basis(Vector3.RIGHT, -PI/2) * Vector3.UP ==
	# Vector3(0,0,-1)), i.e. "forward" in this project's convention.
	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.045
	shaft_mesh.bottom_radius = 0.045
	shaft_mesh.height = 0.8
	shaft_mesh.radial_segments = 10
	shaft.mesh = shaft_mesh
	shaft.material_override = mat
	shaft.rotation = Vector3(-PI / 2.0, 0, 0)
	shaft.position = Vector3(0, 0, -0.4)
	_forward_arrow.add_child(shaft)

	var head := MeshInstance3D.new()
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = 0.16
	head_mesh.height = 0.32
	head_mesh.radial_segments = 12
	head.mesh = head_mesh
	head.material_override = mat
	head.rotation = Vector3(-PI / 2.0, 0, 0)
	head.position = Vector3(0, 0, -0.96)
	_forward_arrow.add_child(head)

func _update_forward_arrow() -> void:
	if not _forward_arrow:
		return
	if primitives.is_empty():
		_forward_arrow.visible = false
		return
	_forward_arrow.visible = true
	var aabb := _calculate_aabb()
	var center_x := aabb.position.x + aabb.size.x * 0.5
	var center_y := aabb.position.y + aabb.size.y * 0.5
	var front_z := aabb.position.z - FORWARD_ARROW_MARGIN  # -Z = front/nose
	_forward_arrow.position = Vector3(center_x, center_y, front_z)

# ── Live smoothness preview ─────────────────────────────────────────────────
# A full-quality bake is too slow to run on every slider tick (measured:
# ~0.3-7s depending on primitive count/resolution - see sdf_mesh_baker.gd),
# so this isn't truly per-frame live. Instead: a low-resolution bake runs
# once, a short debounce after the user stops moving the slider, and renders
# as a translucent overlay ON TOP of the normal hard-primitive view (not
# replacing it) - the primitives stay fully selectable/draggable underneath,
# since the preview mesh has no collision shape at all.
const PREVIEW_BAKE_RESOLUTION := 14
const PREVIEW_DEBOUNCE_SECONDS := 0.25

var _preview_mesh_instance: MeshInstance3D = null
var _preview_debounce_timer: Timer = null

func _setup_smoothness_preview() -> void:
	_preview_mesh_instance = MeshInstance3D.new()
	_preview_mesh_instance.visible = false
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.3, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_preview_mesh_instance.material_override = mat
	hull_container.add_child(_preview_mesh_instance)

	_preview_debounce_timer = Timer.new()
	_preview_debounce_timer.one_shot = true
	_preview_debounce_timer.wait_time = PREVIEW_DEBOUNCE_SECONDS
	_preview_debounce_timer.timeout.connect(_rebake_smoothness_preview)
	add_child(_preview_debounce_timer)

func _queue_smoothness_preview() -> void:
	if not _preview_debounce_timer:
		return
	# start() on a running one-shot Timer restarts its countdown - each new
	# slider tick pushes the bake back, so it only actually runs once the
	# user pauses, not once per tick.
	_preview_debounce_timer.start()
	_update_status("Smoothness: %.2f (preview updating...)" % smoothness)

func _rebake_smoothness_preview() -> void:
	if primitives.is_empty():
		_preview_mesh_instance.visible = false
		return
	var mesh := SDFMeshBaker.bake(primitives, smoothness, PREVIEW_BAKE_RESOLUTION, bake_method, fit_percent, facet_angle, crystallinity)
	if mesh == null:
		_preview_mesh_instance.visible = false
		return
	_preview_mesh_instance.mesh = mesh
	_preview_mesh_instance.visible = true
	_update_status("Smoothness: %.2f" % smoothness)

func _hide_smoothness_preview() -> void:
	if _preview_mesh_instance:
		_preview_mesh_instance.visible = false
	if _preview_debounce_timer:
		_preview_debounce_timer.stop()

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
			snap_pos = _compute_snap_position(ray_result, dragged_palette_type)
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
							snap_pos = _compute_snap_position(ray_result, current_primitive_type)
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
							snap_pos = _compute_snap_position(ray_result, current_primitive_type)
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

	# Self-built gizmo (NOT the shared Gizmo3D.tscn prefab used by the Design
	# Lab - see _build_axis_handle()/_build_scale_handle()/_build_rotate_ring()
	# below). Two reasons to keep this fully separate rather than reusing the
	# shared prefab:
	#   1. This editor drives every drag manually via _raycast_gizmo() +
	#      _input() (see below) - it never relies on gizmo_handle.gd's own
	#      signal-emitting _input()/start_drag(), so there was never any real
	#      need to share that scene's wiring, only its visuals.
	#   2. The shared prefab's own script (gizmo_3d.gd) is Design-Lab-specific
	#      (module scaling/tweaks, /root/MainLab lookups) and auto-wires
	#      itself to whatever children it finds on _ready() - adding new
	#      handle types to that shared scene would have silently changed
	#      Design Lab's gizmo too.
	# Three independent handle KINDS, all attached and grabbable at once (no
	# G/R/S mode gate to remember): translate arrows (near), scale cubes
	# (far, same axis colour so the pairing reads clearly), rotate ring.
	var root := Node3D.new()
	root.name = "HullBuilderGizmo"
	prim.node.add_child(root)
	_gizmo_root = root

	# Three clearly-separated radii so the rotate ring's collision (a ring of
	# small cubes around RING_RADIUS_FRAC * giz_r - see _build_rotate_ring())
	# can't overlap either handle tier's collision - that overlap (the old
	# single-solid-disc ring collider swallowed the whole area out to its
	# radius) is what made translate/rotate fight over the same click before.
	var giz_r := 0.9
	_build_axis_handle(root, "TranslateX", Vector3(giz_r * 0.4, 0, 0), Vector3.RIGHT, COL_X, giz_r, "translate")
	_build_axis_handle(root, "TranslateY", Vector3(0, giz_r * 0.4, 0), Vector3.UP, COL_Y, giz_r, "translate")
	_build_axis_handle(root, "TranslateZ", Vector3(0, 0, giz_r * 0.4), Vector3.BACK, COL_Z, giz_r, "translate")
	_build_scale_handle(root, "ScaleX", Vector3(giz_r * 1.25, 0, 0), Vector3.RIGHT, COL_X)
	_build_scale_handle(root, "ScaleY", Vector3(0, giz_r * 1.25, 0), Vector3.UP, COL_Y)
	_build_scale_handle(root, "ScaleZ", Vector3(0, 0, giz_r * 1.25), Vector3.BACK, COL_Z)
	# Three rings, one per rotation axis (pitch/yaw/roll) - same per-axis
	# colour convention as the translate arrows/scale cubes so it's clear
	# which ring turns which way.
	_build_rotate_ring(root, giz_r, Vector3.RIGHT, "RotateX", COL_X)
	_build_rotate_ring(root, giz_r, Vector3.UP, "RotateY", COL_Y)
	_build_rotate_ring(root, giz_r, Vector3.BACK, "RotateZ", COL_Z)

func _detach_gizmo() -> void:
	if _gizmo_root and is_instance_valid(_gizmo_root):
		_gizmo_root.queue_free()
	_gizmo_root = null
	_gizmo_drag_handle = null

func _build_axis_handle(parent: Node3D, handle_name: String,
		offset: Vector3, axis: Vector3,
		color: Color, giz_r: float, kind: String) -> void:
	var area := Area3D.new()
	area.name = handle_name
	area.set_meta("axis", axis)
	area.set_meta("kind", kind)
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

# Small cube, further out along the axis than the matching translate arrow
# (see _attach_gizmo()'s offsets) so the two never overlap and read as
# distinct grabbable things - same colour-per-axis convention as the arrows,
# cube shape (vs. the arrow's elongated box) is the "this one scales" tell,
# the same visual language Blender/Unity's combined move+scale gizmos use.
func _build_scale_handle(parent: Node3D, handle_name: String,
		offset: Vector3, axis: Vector3, color: Color) -> void:
	var area := Area3D.new()
	area.name = handle_name
	area.set_meta("axis", axis)
	area.set_meta("kind", "scale")
	area.collision_layer = GIZMO_LAYER
	area.collision_mask  = 0

	var cube_size := 0.2
	var col := CollisionShape3D.new()
	var bs  := BoxShape3D.new()
	bs.size = Vector3.ONE * cube_size
	col.shape = bs
	area.add_child(col)

	var mi   := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * cube_size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color    = color
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test   = true
	mat.render_priority = 1
	mi.material_override = mat
	area.add_child(mi)

	area.position = offset
	parent.add_child(area)

# One rotation ring per world axis (pitch/yaw/roll) - see _attach_gizmo()'s
# 3 call sites. Geometry is always authored flat in the ring's own LOCAL XZ
# plane (normal local +Y, exactly the old single-ring shape); `area.rotation`
# at the end reorients that whole flat ring - mesh AND collision together, so
# they can never disagree - into whichever plane actually corresponds to
# `axis`. The "axis" meta stays the real WORLD axis regardless of how the
# ring itself is oriented, since that's what _on_gizmo_drag_motion() actually
# rotates the primitive around - the ring's own local rotation only affects
# where it's drawn/clickable, not which axis a drag on it maps to.
func _build_rotate_ring(parent: Node3D, giz_r: float, axis: Vector3, ring_name: String, color: Color) -> void:
	var area := Area3D.new()
	area.name = ring_name
	area.set_meta("axis", axis)
	area.set_meta("kind", "rotate")
	area.collision_layer = GIZMO_ROTATE_LAYER
	area.collision_mask  = 0

	# A single big CylinderShape3D here (the old collider) is a SOLID DISC,
	# not a ring - it covers the entire area out to its radius, including
	# the translate/scale handles sitting at smaller radii along each axis,
	# so any click anywhere near them hit this "rotate" collider first
	# instead. Approximate the actual hollow ring (matching the TorusMesh
	# visual below) with small cube colliders spaced around the circumference
	# instead, sized to stay clear of both the translate tier (giz_r * 0.4,
	# ~giz_r * 0.6 outer edge) and the scale tier (giz_r * 1.25) - a small
	# gap between consecutive segments is an acceptable tradeoff for that
	# clearance (better a few dead spots on the ring than the ring stealing
	# every other handle's clicks again).
	var ring_radius := giz_r * 0.85
	var segment_count := 24
	var cube_size := giz_r * 0.16
	for i in range(segment_count):
		var ang := 2.0 * PI * i / segment_count
		var seg := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(cube_size, 0.12, cube_size)
		seg.shape = bs
		seg.position = Vector3(cos(ang) * ring_radius, 0, sin(ang) * ring_radius)
		area.add_child(seg)

	var mi   := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	# Centered on ring_radius so the visual ring lines up with where it's
	# actually clickable.
	mesh.inner_radius = ring_radius - cube_size * 0.5
	mesh.outer_radius = ring_radius + cube_size * 0.5
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color    = color
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test   = true
	mat.render_priority = 1
	mi.material_override = mat
	area.add_child(mi)

	# axis == UP: already correct, ring is flat in local XZ as authored.
	if axis.is_equal_approx(Vector3.RIGHT):
		area.rotation = Vector3(0, 0, PI / 2.0)   # -> flat in the YZ plane
	elif axis.is_equal_approx(Vector3.BACK):
		area.rotation = Vector3(PI / 2.0, 0, 0)   # -> flat in the XY plane

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

	# Two passes, translate/scale (GIZMO_LAYER) queried first and preferred
	# whenever both are plausibly hit - see GIZMO_ROTATE_LAYER's own comment
	# for why: viewed edge-on (which the default camera angle actually is),
	# the flat rotate ring can sit nearer the camera than a translate/scale
	# handle along the exact same ray, so plain nearest-hit would pick the
	# ring regardless of on-screen position. The rotate ring is still fully
	# reachable - it's just the fallback when nothing on the first pass hit.
	var hit := _raycast_gizmo_layer(space, from, to, GIZMO_LAYER)
	if hit == null:
		hit = _raycast_gizmo_layer(space, from, to, GIZMO_ROTATE_LAYER)
	return hit

func _raycast_gizmo_layer(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int) -> Node3D:
	var params := PhysicsRayQueryParameters3D.new()
	params.from                = from
	params.to                  = to
	params.collision_mask      = mask
	# THE bug that made every gizmo handle ungrabbable: PhysicsRayQueryParameters3D
	# defaults collide_with_areas to FALSE and collide_with_bodies to TRUE.
	# Every handle here is an Area3D (not a StaticBody3D) - collision_layer/
	# collision_mask matching is irrelevant if the query never even considers
	# Area3D nodes as hittable in the first place, which is exactly what was
	# happening (confirmed directly: an intersect_ray() aimed straight through
	# a handle's own known world position returned empty until this was set).
	params.collide_with_areas  = true
	params.collide_with_bodies = false
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

	# Self-built handles (see _build_axis_handle()/_build_scale_handle()/
	# _build_rotate_ring()) carry their own "kind" - translate/scale/rotate
	# are three separate, simultaneously-grabbable handle types now, so which
	# one to do is read directly off the handle grabbed, not off a G/R/S mode
	# toggle the player would otherwise have to remember to switch first.
	var kind: String = handle.get_meta("kind") if handle.has_meta("kind") else "translate"
	var axis_val = handle.get_meta("axis") if handle.has_meta("axis") else Vector3.ZERO
	var local_axis: Vector3 = axis_val if axis_val != null else Vector3.ZERO
	_gizmo_drag_local_axis = local_axis

	if selected_primitive >= 0 and selected_primitive < primitives.size():
		_gizmo_drag_start_pos = primitives[selected_primitive].position
		_gizmo_drag_start_rot = primitives[selected_primitive].rotation
		_gizmo_drag_start_scale = primitives[selected_primitive].scale

	# Every handle is a child of the primitive's own node, so its VISUAL
	# position already rotates along with the primitive automatically (plain
	# Godot scene-graph inheritance) - but the axis stored in each handle's
	# "axis" meta is just the fixed original local direction (RIGHT/UP/BACK),
	# never adjusted for the primitive's current rotation. Without rotating
	# it here too, dragging a handle that's now visually pointing wherever
	# the object's rotated local axis actually points would still translate/
	# scale/rotate along the ORIGINAL, un-rotated world axis - exactly the
	# "X handle moves it in Z instead" mismatch.
	var world_axis: Vector3 = local_axis
	if selected_primitive >= 0 and selected_primitive < primitives.size() and local_axis != Vector3.ZERO:
		world_axis = (Basis.from_euler(_gizmo_drag_start_rot) * local_axis).normalized()
	_gizmo_drag_axis = world_axis

	if kind == "rotate":
		_gizmo_drag_mode = "rotate"
		var prim_pos := Vector3.ZERO
		if selected_primitive >= 0 and selected_primitive < primitives.size():
			prim_pos = primitives[selected_primitive].position
		_gizmo_drag_start_angle = _mouse_angle_in_xz(mouse_pos, prim_pos)
	elif kind == "scale":
		_gizmo_drag_mode = "scale"
	else:
		_gizmo_drag_mode = "translate"

# Projects the mouse's on-screen movement (since the drag started) onto a
# world-space axis, via the same "plane most face-on to the camera that
# still contains the axis" trick used by both translate and scale dragging.
func _compute_axis_world_delta(event: InputEventMouseMotion, axis: Vector3, pivot: Vector3) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return Vector3.ZERO
	var from_old := camera.project_ray_origin(_gizmo_drag_start_mouse)
	var to_old   := from_old + camera.project_ray_normal(_gizmo_drag_start_mouse) * 500.0
	var from_new := camera.project_ray_origin(event.position)
	var to_new   := from_new + camera.project_ray_normal(event.position) * 500.0

	var cam_dir := (to_new - from_new).normalized()
	var perp1   := axis.cross(cam_dir).normalized()
	var plane_n := axis.cross(perp1).normalized()

	var old_t := _ray_plane_t(from_old, (to_old - from_old).normalized(), pivot, plane_n)
	var new_t := _ray_plane_t(from_new, (to_new - from_new).normalized(), pivot, plane_n)

	if old_t < 0.0 or new_t < 0.0:
		return Vector3.ZERO

	var old_world := from_old + (to_old - from_old).normalized() * old_t
	var new_world := from_new + (to_new - from_new).normalized() * new_t
	return (new_world - old_world).dot(axis) * axis

func _on_gizmo_drag_motion(event: InputEventMouseMotion) -> void:
	if selected_primitive < 0 or selected_primitive >= primitives.size():
		return
	var prim = primitives[selected_primitive]

	if _gizmo_drag_mode == "translate":
		var delta := _compute_axis_world_delta(event, _gizmo_drag_axis, _gizmo_drag_start_pos)
		prim.position = _gizmo_drag_start_pos + delta
		if prim.node:
			prim.node.position = prim.position
		_update_properties_panel()

	elif _gizmo_drag_mode == "scale":
		# Project mouse movement onto the ROTATED world-space axis (matches
		# where the handle is actually being dragged on screen), but decide
		# WHICH of scale.x/y/z to change using the raw LOCAL axis identity -
		# prim.scale is inherently local-space (it's applied directly as
		# prim.node.scale), so "which component" must stay tied to the
		# handle's own local identity even though "how far" is measured in
		# rotated world space.
		var delta := _compute_axis_world_delta(event, _gizmo_drag_axis, _gizmo_drag_start_pos)
		var axis_delta: float = delta.dot(_gizmo_drag_axis)
		var new_scale: Vector3 = _gizmo_drag_start_scale
		if _gizmo_drag_local_axis.x != 0.0:
			new_scale.x = max(0.05, _gizmo_drag_start_scale.x + axis_delta)
		elif _gizmo_drag_local_axis.y != 0.0:
			new_scale.y = max(0.05, _gizmo_drag_start_scale.y + axis_delta)
		elif _gizmo_drag_local_axis.z != 0.0:
			new_scale.z = max(0.05, _gizmo_drag_start_scale.z + axis_delta)
		prim.scale = new_scale
		if prim.node:
			prim.node.scale = new_scale
		_update_properties_panel()

	elif _gizmo_drag_mode == "rotate":
		# Free-form rotation around whichever ring was grabbed.
		# _gizmo_drag_axis here is that ring's local axis (RIGHT/UP/BACK)
		# already rotated into the primitive's own current orientation (see
		# _on_gizmo_drag_start()) - i.e. this is a LOCAL/gimbal-style
		# rotation: a second rotation always turns around the object's
		# CURRENT axis (matching where its ring is actually drawn), not the
		# original fixed world axis. The screen-space angle-around-pivot
		# technique itself doesn't care which ring is in use - only which
		# axis the resulting delta gets applied around here.
		var cur_angle := _mouse_angle_in_xz(event.position, prim.position)
		var delta_ang := cur_angle - _gizmo_drag_start_angle

		# Composed on top of the orientation the primitive had when the drag
		# started, not accumulated component-by-component into Euler angles -
		# Euler components don't commute/compose correctly once more than one
		# axis is in play (that was fine for a Y-only ring, not for 3
		# independent rings), so this goes through a Basis and only converts
		# back to Euler (prim.rotation is stored as Euler for the
		# properties-panel spinboxes and sdf_mesh_baker.gd's
		# Basis.from_euler()) at the end.
		var start_basis := Basis.from_euler(_gizmo_drag_start_rot)
		var new_basis := Basis(_gizmo_drag_axis, delta_ang) * start_basis
		prim.rotation = new_basis.get_euler()
		if prim.node:
			prim.node.rotation = prim.rotation
		_update_properties_panel()

func _on_gizmo_drag_end() -> void:
	_gizmo_drag_handle = null
	_gizmo_drag_mode   = ""
	_update_status("Ready")

# Helper: signed angle from world position to mouse ray in XZ plane
func _mouse_angle_in_xz(mouse_pos: Vector2, pivot: Vector3) -> float:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return 0.0
	# Screen-space angle around the pivot's own 2D projection, NOT a 3D
	# ray/rotation-plane intersection - the previous version intersected the
	# mouse ray with the y=pivot.y plane, which is only well-conditioned
	# when the camera looks down at a real angle. The default designer_
	# camera.gd starting angle looks almost perfectly horizontally (near-zero
	# vertical component), which is exactly the degenerate case that guard
	# clause caught by returning 0.0 unconditionally - meaning every rotate
	# drag computed start angle = current angle = 0 and always produced a
	# zero delta, silently doing nothing, for the single most common camera
	# angle a player would actually be looking from. A 2D screen-space angle
	# has no such blind spot (robust to any camera orientation short of the
	# degenerate "camera sitting exactly on the pivot" case).
	var pivot_screen := camera.unproject_position(pivot)
	var rel := mouse_pos - pivot_screen
	if rel.length_squared() < 0.0001:
		return 0.0
	return atan2(rel.x, rel.y)

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
		PrimitiveType.CAPSULE:
			# Godot already builds this exactly - no authored asset needed.
			var cap := CapsuleMesh.new()
			cap.radius = 0.25
			cap.height = 1.0
			return cap
		PrimitiveType.HEX_PRISM:
			# A 6-radial-segment CylinderMesh IS a hex prism - no authored
			# asset needed (matches sdf_mesh_baker.gd's _sdf_hex_prism).
			var hex := CylinderMesh.new()
			hex.height = 1.0
			hex.top_radius = 0.5
			hex.bottom_radius = 0.5
			hex.radial_segments = 6
			return hex
		PrimitiveType.PYRAMID:
			# A 4-radial-segment CylinderMesh tapered to a point IS a
			# 4-sided pyramid - same technique as HEX_PRISM.
			var pyr := CylinderMesh.new()
			pyr.height = 1.0
			pyr.bottom_radius = 0.5
			pyr.top_radius = 0.0
			pyr.radial_segments = 4
			return pyr
		_:
			if AUTHORED_PRIMITIVE_SHAPES.has(type):
				var authored = MeshAssetLoader.get_hull_primitive_mesh(AUTHORED_PRIMITIVE_SHAPES[type])
				if authored:
					return authored
			return BoxMesh.new()

func _build_collision_for_type(type: PrimitiveType) -> Shape3D:
	match type:
		PrimitiveType.SPHERE, PrimitiveType.HEMISPHERE:
			var s := SphereShape3D.new()
			s.radius = 0.5
			return s
		PrimitiveType.CYLINDER, PrimitiveType.CONE, PrimitiveType.HEX_PRISM, PrimitiveType.PYRAMID, PrimitiveType.HALF_CYLINDER:
			var s := CylinderShape3D.new()
			s.height = 1.0
			s.radius = 0.5
			return s
		PrimitiveType.TORUS, PrimitiveType.RING, PrimitiveType.FENDER:
			var s := SphereShape3D.new()
			s.radius = 0.6
			return s
		PrimitiveType.CAPSULE:
			var s := CapsuleShape3D.new()
			s.radius = 0.25
			s.height = 1.0
			return s
		_:  # BOX, WEDGE, SLOPE, FRUSTUM, CHAMFER_BOX, I_BEAM, L_BEAM, CANOPY, fallback
			var s := BoxShape3D.new()
			s.size = Vector3.ONE
			return s

# Magnetic-ish attach-point snapping: before offsetting off the hit surface
# along its normal (unchanged from before), pull the in-plane hit position
# toward "reasonable" points on the target primitive's face - its centerline
# (dead center), half-marks (halfway from center to the edge), and quarter-
# marks (only offered on faces big enough that a quarter-mark isn't crammed
# right next to the half-mark/center). Falls through to the raw hit position
# untouched if nothing in the primitives array line the far cursor is close
# enough to.
const FACE_SNAP_CAPTURE_RADIUS := 0.22
const FACE_SNAP_MIN_SIZE_FOR_QUARTERS := 0.8

func _compute_snap_position(ray_result: Dictionary, _target_type: PrimitiveType) -> Vector3:
	var hit_position: Vector3 = ray_result.get("position", Vector3.ZERO)
	var hit_normal: Vector3 = ray_result.get("normal", Vector3.UP)
	var face_snapped := _snap_to_face_grid(ray_result, hit_position, hit_normal)
	return face_snapped + hit_normal * (snap_distance * 0.5)

func _snap_to_face_grid(ray_result: Dictionary, hit_position: Vector3, hit_normal: Vector3) -> Vector3:
	var prim_idx := _hit_existing_primitive(ray_result)
	if prim_idx < 0:
		return hit_position
	var prim = primitives[prim_idx]
	if not prim.node:
		return hit_position

	var xform: Transform3D = prim.node.global_transform
	var xform_inv := xform.affine_inverse()
	var local_pos: Vector3 = xform_inv * hit_position
	var local_normal: Vector3 = (xform_inv.basis * hit_normal).normalized()

	# Every primitive here is built at unit size in _build_mesh_for_type() -
	# scale IS the primitive's full-size, so half-extent is just scale/2.
	var he: Vector3 = prim.node.scale * 0.5
	var he_arr := [he.x, he.y, he.z]
	var pos_arr := [local_pos.x, local_pos.y, local_pos.z]

	# Snap the two axes THAT LIE IN the hit face (i.e. not the axis the hit
	# normal points along) to that face's attach-point grid.
	var abs_n: Vector3 = local_normal.abs()
	var axis_n := 0
	if abs_n.y > abs_n.x and abs_n.y >= abs_n.z:
		axis_n = 1
	elif abs_n.z > abs_n.x and abs_n.z > abs_n.y:
		axis_n = 2

	for axis in range(3):
		if axis == axis_n:
			continue
		pos_arr[axis] = _snap_axis_to_grid(pos_arr[axis], he_arr[axis])

	var snapped_local := Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
	return xform * snapped_local

func _snap_axis_to_grid(value: float, half_extent: float) -> float:
	if half_extent < 0.001:
		return value
	# Center, half-marks, and the face's own edges are always offered;
	# quarter-marks only join in once the face is big enough that a
	# quarter-mark and a half-mark/center aren't sitting on top of each other.
	var fractions: Array = [0.0, 0.5, -0.5, 1.0, -1.0]
	if half_extent * 2.0 >= FACE_SNAP_MIN_SIZE_FOR_QUARTERS:
		fractions.append_array([0.25, -0.25, 0.75, -0.75])

	var best := value
	var best_dist := FACE_SNAP_CAPTURE_RADIUS
	for f in fractions:
		var candidate: float = f * half_extent
		var d: float = abs(value - candidate)
		if d < best_dist:
			best_dist = d
			best = candidate
	return best

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
	dup_btn.custom_minimum_size = Vector2(0, 44)
	dup_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dup_btn.add_theme_font_size_override("font_size", 15)
	dup_btn.pressed.connect(_duplicate_selected)
	properties_panel.add_child(dup_btn)

	var mirror_btn := Button.new()
	mirror_btn.text = "[↔] Mirror Across X"
	mirror_btn.tooltip_text = "Create a mirrored copy on the opposite side of X axis"
	mirror_btn.custom_minimum_size = Vector2(0, 44)
	mirror_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mirror_btn.add_theme_font_size_override("font_size", 15)
	mirror_btn.pressed.connect(_mirror_selected_x)
	properties_panel.add_child(mirror_btn)

	var del_btn := Button.new()
	del_btn.text = "[x] Delete  (Del)"
	del_btn.tooltip_text = "Remove this primitive"
	del_btn.custom_minimum_size = Vector2(0, 44)
	del_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	del_btn.add_theme_font_size_override("font_size", 15)
	del_btn.pressed.connect(_delete_selected)
	properties_panel.add_child(del_btn)

func _mirror_selected_x() -> void:
	if selected_primitive < 0 or selected_primitive >= primitives.size():
		_update_status("Nothing selected to mirror")
		return
	if primitives.size() >= max_primitives:
		_show_warning("Maximum primitives reached (" + str(max_primitives) + ")")
		return

	var src = primitives[selected_primitive]
	var new_pos := Vector3(-src.position.x, src.position.y, src.position.z)
	var new_rot := Vector3(src.rotation.x, -src.rotation.y, -src.rotation.z)

	var mi := _make_primitive_node(src.type)
	mi.position = new_pos
	mi.rotation = new_rot
	mi.scale    = src.scale

	for child in mi.get_children():
		if child is MeshInstance3D:
			var mat = child.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color = src.color

	var prim := {
		type     = src.type,
		position = new_pos,
		rotation = new_rot,
		scale    = src.scale,
		color    = src.color,
		node     = mi,
	}

	hull_container.add_child(mi)
	primitives.append(prim)
	_select_primitive(primitives.size() - 1)
	_update_status("Mirrored " + _def_name(src.type) + " across X axis")

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
	# AcceptDialog extends Window in Godot 4, not Control - it has no
	# custom_minimum_size (that assignment silently aborted this whole
	# function before add_child(dialog)/popup_centered() ever ran, which is
	# why Export did nothing). `size` is the Window-side equivalent.
	dialog.size = Vector2i(400, 450)

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
	var hp = snapped(100.0 + volume * 20.0, 0.1)
	var weight = snapped(50.0 + volume * 15.0, 0.1)
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
	var aabb: AABB = dialog.get_meta("aabb")
	var volume: float = dialog.get_meta("volume")

	var display_name = name_edit.text.strip_edges()
	var hull_name = display_name
	if hull_name == "":
		hull_name = "custom_hull_%d" % Time.get_ticks_msec()
	hull_name = hull_name.to_lower().replace(" ", "_")
	if display_name == "":
		display_name = hull_name

	var domain = domain_option.get_item_text(domain_option.selected)
	# Capture everything from `dialog` above this point - it's about to be
	# freed, and the bake below awaits a frame, so any deferred queue_free()
	# would otherwise land before we're done reading from its children.
	dialog.queue_free()

	_update_status("Baking hull mesh...")
	# Let the status label repaint before the (synchronous) bake blocks the thread.
	await get_tree().process_frame

	var mesh := SDFMeshBaker.bake(primitives, smoothness, bake_resolution, bake_method, fit_percent, facet_angle, crystallinity)
	if mesh == null:
		_show_error("Bake produced no geometry - try lowering Smoothness or adding more primitives")
		return

	var mod_dir = "user://mods/hulls"
	DirAccess.make_dir_recursive_absolute(mod_dir)

	var mesh_path = "%s/%s.res" % [mod_dir, hull_name]
	var save_err = ResourceSaver.save(mesh, mesh_path)
	if save_err != OK:
		_show_error("Failed to save baked mesh: error %d" % save_err)
		return

	var hp = snapped(100.0 + volume * 20.0, 0.1)
	var weight = snapped(50.0 + volume * 15.0, 0.1)
	var metal = int(20 + volume * 5.0)
	var crystal = int(5 + volume * 1.0)
	var sidecar = {
		"name": display_name,
		"hp": hp,
		"weight": weight,
		"metal": metal,
		"crystal": crystal,
		"size": [aabb.size.x, aabb.size.y, aabb.size.z],
		"color": [0.7, 0.7, 0.8, 1.0],
		"domain": domain,
		"category": "hull",
	}
	var write_err = _write_hull_sidecar(hull_name, sidecar)
	if not write_err:
		return

	# Sidecars are scanned once and cached (see hull_loader.gd) - force a
	# rescan so the newly baked hull shows up in the Design Lab immediately
	# instead of only after a restart.
	HullLoader.reset_cache_for_tests()

	# The real bake just landed on disk - the low-res preview overlay's job
	# (showing an approximation before committing) is done.
	_hide_smoothness_preview()

	var tri_count = mesh.get_faces().size() / 3
	_update_status("Exported '%s' - %d triangles baked to user://mods/hulls/" % [hull_name, tri_count])

func _write_hull_sidecar(hull_name: String, data: Dictionary) -> bool:
	var json = JSON.new()
	var text = json.stringify(data, "\t")
	var path = "user://mods/hulls/%s.json" % hull_name
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		_show_error("Failed to write hull sidecar to %s" % path)
		return false
	file.store_string(text)
	file.close()
	return true

func _calculate_aabb() -> AABB:
	var aabb := AABB()
	var first := true
	if primitives.is_empty():
		return aabb

	for prim in primitives:
		if not prim.node:
			continue
		for mi in _find_mesh_instances(prim.node):
			if not mi.mesh:
				continue
			# AABB has no merge_with() in Godot 4 (that's Rect2's name for
			# it) - AABB's own method is merge(), and it RETURNS a new AABB
			# rather than mutating in place. The old merge_with() calls here
			# were silent no-ops (a nonexistent-method script error that
			# doesn't halt execution), so this always returned an empty
			# AABB(), which meant every exported hull's sidecar "size" was
			# [0,0,0] - degenerate/invisible wherever get_hull_mesh_fit()
			# tried to fit a real mesh into it. Transform3D * AABB (used via
			# mi.global_transform here) also fixes a second bug: the old code
			# only added mi.global_position, ignoring the primitive's
			# rotation/scale entirely, so even a working merge would have
			# undersized any rotated or scaled primitive.
			var world_aabb: AABB = mi.global_transform * mi.mesh.get_aabb()
			if first:
				aabb = world_aabb
				first = false
			else:
				aabb = aabb.merge(world_aabb)

	return aabb

func _find_mesh_instances(node: Node3D) -> Array:
	var result = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		# Skip the selection gizmo (see _attach_gizmo()) - it's added as a
		# child of the SELECTED primitive's own node, so without this guard
		# _calculate_aabb() (export size/stats, and the forward-arrow
		# position) silently balloons/skews to include the gizmo's own
		# handle meshes (offset ~0.75 units out) whenever a primitive
		# happens to be selected - which is most of the time, since
		# selecting is how the player interacts with a primitive at all.
		if child == _gizmo_root:
			continue
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

func _delete_primitive_at_position(index: int) -> void:
	if index < 0 or index >= primitives.size():
		return
	var prim = primitives[index]
	if selected_primitive == index:
		_detach_gizmo()
	if prim.node:
		prim.node.queue_free()
	primitives.remove_at(index)
	if selected_primitive == index:
		selected_primitive = -1
	elif selected_primitive > index:
		selected_primitive -= 1
	if primitives.is_empty():
		has_origin = false
	_update_properties_panel()

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
# Saved assemblies store a primitive's type as its NAME, never its raw int
# enum value: PrimitiveType's numbering already shifted once (the kit grew
# from 6 shapes to 19), and any assembly saved before that would silently
# have come back as an entirely different shape. Names are stable across
# insertions/reordering.
#
# Both directions are derived from the enum by reflection rather than a
# hand-written match block - the previous hand-written versions still only
# listed the original 6 shapes and would have quietly mapped all 13 new ones
# to BOX.
func _primitive_type_to_string(type: PrimitiveType) -> String:
	var names := PrimitiveType.keys()
	if type >= 0 and type < names.size():
		return names[type]
	return "BOX"

func _string_to_primitive_type(type_name: String) -> PrimitiveType:
	var key := type_name.to_upper()
	if PrimitiveType.has(key):
		return PrimitiveType[key]
	push_warning("HullBuilder: unknown primitive type '%s' in assembly - falling back to BOX" % type_name)
	return PrimitiveType.BOX

# ── Hull assembly save / load ────────────────────────────────────────────────
# The EDITABLE SOURCE for a hull, as distinct from the baked output (.res mesh
# + sidecar .json). Without this the builder was one-shot - you could export a
# hull but never reopen or iterate it, which is fine for a throwaway custom
# hull but disqualifying for the built-in roster, whose sources need to live
# in version control and be re-bakeable (see tools/bake_hull_roster.gd).
const ASSEMBLY_SCHEMA_VERSION := 1
const ASSEMBLY_DIR := "user://hull_assemblies"

func serialize_assembly(hull_name: String = "", sidecar: Dictionary = {}) -> Dictionary:
	var prims := []
	for prim in primitives:
		prims.append({
			"type": _primitive_type_to_string(prim.type),
			"position": [prim.position.x, prim.position.y, prim.position.z],
			"rotation": [prim.rotation.x, prim.rotation.y, prim.rotation.z],
			"scale": [prim.scale.x, prim.scale.y, prim.scale.z],
			"color": [prim.color.r, prim.color.g, prim.color.b, prim.color.a],
		})
	return {
		"schema_version": ASSEMBLY_SCHEMA_VERSION,
		"hull_name": hull_name,
		# Bake params travel WITH the assembly so a re-bake reproduces the
		# same mesh instead of depending on whatever the sliders happen to
		# be set to at the time.
		"bake": {
			"smoothness": smoothness,
			"resolution": bake_resolution,
			"method": bake_method,
			"fit_percent": fit_percent,
			"facet_angle": facet_angle,
			"crystallinity": crystallinity
		},
		# Verbatim gameplay stats. Deliberately NOT recomputed from volume on
		# load/bake the way the interactive export dialog does it - the
		# built-in hulls carry hand-tuned hp/weight/metal/crystal and a
		# load-bearing `size`, and silently re-deriving those would rebalance
		# the game and shift every module mount zone.
		"sidecar": sidecar,
		"primitives": prims,
	}

# Rebuilds the live editor state from an assembly dict. Returns false (and
# leaves the existing assembly untouched) if the data is unusable.
func deserialize_assembly(data: Dictionary) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("primitives"):
		_show_error("Not a valid hull assembly file")
		return false
	var version := int(data.get("schema_version", 0))
	if version > ASSEMBLY_SCHEMA_VERSION:
		_show_error("Assembly was saved by a newer version (schema %d)" % version)
		return false

	_on_clear_clicked()

	for entry in data["primitives"]:
		var type := _string_to_primitive_type(str(entry.get("type", "BOX")))
		var pos := _to_vec3(entry.get("position", [0, 0, 0]))
		_add_primitive_at_position(type, pos)
		var prim = primitives[primitives.size() - 1]
		# _add_primitive_at_position() forces the FIRST primitive to the
		# origin (its has_origin rule) - override that here so a saved
		# assembly round-trips exactly rather than getting re-centered.
		prim.position = pos
		prim.rotation = _to_vec3(entry.get("rotation", [0, 0, 0]))
		prim.scale = _to_vec3(entry.get("scale", [1, 1, 1]))
		var c = entry.get("color", [0.7, 0.7, 0.8, 1.0])
		if typeof(c) == TYPE_ARRAY and c.size() >= 3:
			prim.color = Color(c[0], c[1], c[2], c[3] if c.size() > 3 else 1.0)
		if prim.node:
			prim.node.position = prim.position
			prim.node.rotation = prim.rotation
			prim.node.scale = prim.scale
			for child in prim.node.get_children():
				if child is MeshInstance3D:
					var mat = child.material_override as StandardMaterial3D
					if mat:
						mat.albedo_color = prim.color

	var bake: Dictionary = data.get("bake", {})
	smoothness = float(bake.get("smoothness", smoothness))
	bake_resolution = int(bake.get("resolution", bake_resolution))
	bake_method = str(bake.get("method", bake_method))
	fit_percent = float(bake.get("fit_percent", fit_percent))
	facet_angle = float(bake.get("facet_angle", facet_angle))
	crystallinity = float(bake.get("crystallinity", crystallinity))
	if smoothness_slider:
		smoothness_slider.value = smoothness
	if bake_quality_option:
		var res_idx := BAKE_RESOLUTIONS.find(bake_resolution)
		if res_idx >= 0:
			bake_quality_option.selected = res_idx

	_deselect()
	return true

static func _to_vec3(arr) -> Vector3:
	if typeof(arr) == TYPE_ARRAY and arr.size() >= 3:
		return Vector3(arr[0], arr[1], arr[2])
	return Vector3.ZERO

func _on_save_assembly_clicked() -> void:
	if primitives.is_empty():
		_show_error("Nothing to save")
		return
	DirAccess.make_dir_recursive_absolute(ASSEMBLY_DIR)
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.current_dir = ProjectSettings.globalize_path(ASSEMBLY_DIR)
	dialog.add_filter("*.json", "Hull Assembly")
	dialog.size = Vector2i(700, 500)
	dialog.file_selected.connect(func(path: String):
		var stem := path.get_file().get_basename()
		var data := serialize_assembly(stem)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if not f:
			_show_error("Could not write %s" % path)
			return
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
		_update_status("Saved assembly: %s (%d primitives)" % [stem, primitives.size()])
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()

func _on_load_assembly_clicked() -> void:
	DirAccess.make_dir_recursive_absolute(ASSEMBLY_DIR)
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.current_dir = ProjectSettings.globalize_path(ASSEMBLY_DIR)
	dialog.add_filter("*.json", "Hull Assembly")
	dialog.size = Vector2i(700, 500)
	dialog.file_selected.connect(func(path: String):
		var f := FileAccess.open(path, FileAccess.READ)
		if not f:
			_show_error("Could not read %s" % path)
			return
		var text := f.get_as_text()
		f.close()
		var json := JSON.new()
		if json.parse(text) != OK:
			_show_error("Bad JSON: %s (line %d)" % [json.get_error_message(), json.get_error_line()])
			return
		if deserialize_assembly(json.get_data()):
			_update_status("Loaded assembly: %s (%d primitives)" % [path.get_file().get_basename(), primitives.size()])
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()

func _on_clear_clicked() -> void:
	_detach_gizmo()
	for p in primitives:
		if p.node:
			p.node.queue_free()
	primitives.clear()
	selected_primitive = -1
	has_origin = false
	_hide_smoothness_preview()
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
