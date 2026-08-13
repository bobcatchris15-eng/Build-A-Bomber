class_name UIPropStage
extends SubViewportContainer
# One shared 3D UI viewport per screen.
#
# The Tactile Interface Programme Part 3.2 contract. StampedButton used to
# own its own SubViewport per instance - 132 of them on the Settings
# screen, each re-rendering on every state change, with the camera and
# the light rig duplicated 132 times. This file replaces all of that
# with one viewport per screen, hosting every 3D UI prop on a single
# ortho camera, lit by one shared rig.
#
# D2: the largest single architectural item in the plan. Everything in
# Phases 2 and 3 hangs off this file existing; the texture pipeline
# (Phase 2) and the depth pipeline (Phase 3) both assume the prop
# already lives on a stage. Do not remove the per-control SubViewport
# fallback in StampedButton/MeshIcon - tests and any not-yet-migrated
# screen still depend on it - but in the production code path every
# visible 3D prop should be hosted here.
#
# SHAPE:
#
#   UIPropStage (extends SubViewportContainer, MOUSE_FILTER_IGNORE)
#   +-- SubViewport (transparent, UPDATE_ONCE, dirty-driven)
#   |   +-- WorldEnvironment (AgX tonemap, ambient warm grey)
#   |   +-- Camera3D (ortho, size = viewport_h/2, looks at -Z)
#   |   +-- Key DirectionalLight3D (top-left, matches plate bevels)
#   |   +-- Fill DirectionalLight3D (opposite side, low intensity)
#   |   +-- MeshInstance3D per attached control
#   +-- (no children; the container's stretch paints the viewport)
#
# MOUSE_FILTER_IGNORE IS LOAD-BEARING. SubViewportContainer defaults to
# MOUSE_FILTER_STOP and consumes clicks meant for the controls behind
# it. The plan's Part 4 Phase 1 traps call this out as the documented
# failure mode; a button under a populated stage is still clickable
# only because this filter is set, and `tests/test_ui_prop_stage.gd`
# pins the invariant by counting SubViewports in a real scene.
#
# ELEVATION TIER. The z-offset per prop is the shared elevation block
# from ui_tokens.gd (raised=1, floating=3, modal=6). Phase 3 will read
# the tier off the host control's theme variation; for now every prop
# lands at the raised tier's z=1, the same offset a Panel sitting on
# the same backdrop would have. Phase 1 does not differentiate by tier
# because there are no Modal-tier controls in the host set yet - the
# settings panel is the only thing above the panel tier, and it
# intentionally does not use the stage's 3D rendering at all.

const Tokens = preload("res://scripts/ui_tokens.gd")
const UIPropRegistryScript = preload("res://scripts/ui/ui_prop_registry.gd")

# Z-offset for any prop hosted on the stage. Aligned with the raised
# elevation tier in ui_tokens.gd so the cast shadow lands in the same
# plane the panels it sits next to land in.
const ELEVATION_Z := 1.0

# Variant -> base material params. The state pipeline (hover/press/
# disabled) applies deltas on top. Kept in this file rather than in
# ui_tokens.gd because the values are GLOSS-and-metallic PBR inputs,
# not palette tokens - the design system owns the look of a chrome
# Panel, not the gloss curve of a 3D mesh. Phase 2's per-prop
# texture set owns the body colour; these are the substrate's defaults
# underneath the bake.
const VARIANT_MATERIALS := {
	"default": {
		"albedo": Color(0.42, 0.43, 0.45),
		"metallic": 0.55,
		"roughness": 0.42,
		"emission": Color(0, 0, 0, 0),
		"emission_energy": 0.0,
	},
	"primary": {
		"albedo": Color(0.20, 0.28, 0.22),
		"metallic": 0.45,
		"roughness": 0.48,
		"emission": Tokens.SIGNAL_GO,
		"emission_energy": 0.15,
	},
	"danger": {
		"albedo": Color(0.32, 0.18, 0.18),
		"metallic": 0.45,
		"roughness": 0.48,
		"emission": Tokens.SIGNAL_ALERT,
		"emission_energy": 0.18,
	},
	"ghost": {
		"albedo": Color(0.55, 0.56, 0.58),
		"metallic": 0.30,
		"roughness": 0.55,
		"emission": Color(0, 0, 0, 0),
		"emission_energy": 0.0,
	},
	"compact": {
		"albedo": Color(0.42, 0.43, 0.45),
		"metallic": 0.55,
		"roughness": 0.42,
		"emission": Color(0, 0, 0, 0),
		"emission_energy": 0.0,
	},
}

# Hover/press deltas. Match the original StampedButton state pipeline
# so a control migrated off the per-button viewport has the same
# feedback behaviour. See ui_stamped_button.gd:90-93 for the original
# constants and the "0.12 is roughly the lift a real factory button
# shows" reasoning that picks the values.
const HOVER_LIFT := 0.12
const PRESS_DROP := 0.14
# Disabled desaturates and lifts roughness, same as the original. The
# numbers are kept as constants here so a future state (e.g. "selected"
# for a list item) is one new line rather than three lookups.
const DISABLED_DESATURATE := 0.50
const DISABLED_ROUGHNESS_LIFT := 0.15

# Per-attached-prop bookkeeping. The handle is the array index;
# the host control is the only way to recover a prop's stage-side
# identity (it is what `item_rect_changed` fires on), so it lives here
# as the key into transforms. Meshes are children of the rig; materials
# are owned by the meshes; states and variants are pushed through
# set_prop_state / set_prop_variant.
#
# Handle reuse: on detach the freed slot is appended to _free_handles
# and the next attach() pops it. Reuse is what keeps handle numbers
# stable across a screen's normal churn (open menu, close, reopen) so
# a per-handle cache in a client survives.
var _handles: Array = []  # Array[Dictionary]: mesh, host, prop_id, state, variant, transform_override
var _free_handles: Array = []  # Array[int]: popped indices, ready to reuse
var _mesh_by_host: Dictionary = {}  # Control -> {handle, mesh, material}
var _viewport: SubViewport = null
var _rig: Node3D = null
var _camera: Camera3D = null
# How many times request_render() has been called since the last
# _on_viewport_resized / _ready. Tests assert against this count; the
# public API does not promise a number, just "marks dirty".
var _render_count: int = 0


func _init() -> void:
	# The container IS the stage. SubViewportContainer is a Control, so
	# "the stage is a Control" holds - the plan's wording is satisfied
	# without a separate Control wrapper that would just add a node
	# level and a rect-to-rect copy. Stretch is on so the SubViewport's
	# pixel size matches the container's pixel size; mouse_filter is
	# IGNORE so the container does not swallow clicks meant for the
	# controls behind it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true


func _ready() -> void:
	if _viewport != null:
		# Defensive against a stage being added to the tree twice (it
		# shouldn't, but a misuse in a screen could).
		return
	_build_viewport()
	_build_rig()
	# Initial size sync. Subsequent resizes come through _on_viewport_resized.
	_sync_camera_to_viewport()
	get_viewport().size_changed.connect(_on_viewport_resized)


# --- Public API -------------------------------------------------------------

# Registers a Control as the host for a 3D prop. The control's rect
# becomes the prop's rect on screen; the stage positions the prop
# mesh every time the control resizes. Returns a handle the caller
# passes to set_prop_state / set_prop_variant / set_prop_transform /
# detach. A return of -1 means registration was refused (unknown
# prop_id, no mesh asset, or the host is already attached to this
# stage); the caller can keep rendering with its own fallback.
func attach(control: Control, prop_id: String) -> int:
	if control == null:
		push_warning("UIPropStage.attach: refusing null control")
		return -1
	if not UIPropRegistryScript.has(prop_id):
		push_warning("UIPropStage.attach: unknown prop_id '%s'" % prop_id)
		return -1
	if _mesh_by_host.has(control):
		# Idempotent: a second attach() of the same host is a no-op
		# that returns the existing handle. Saves every caller from
		# the "is this the first _ready or the second" book-keeping.
		return _mesh_by_host[control]["handle"]
	var entry: Dictionary = UIPropRegistryScript.entry_for(prop_id)
	var mesh_path: String = entry["mesh_path"]
	if not ResourceLoader.exists(mesh_path):
		push_warning("UIPropStage.attach: mesh asset missing at %s" % mesh_path)
		return -1

	var material := StandardMaterial3D.new()
	var alb_path: String = String(entry.get("albedo_path", ""))
	if alb_path != "" and ResourceLoader.exists(alb_path):
		material.albedo_texture = load(alb_path) as Texture2D
	var orm_path: String = String(entry.get("orm_path", ""))
	if orm_path != "" and ResourceLoader.exists(orm_path):
		var orm_tex = load(orm_path) as Texture2D
		material.ao_enabled = true
		material.ao_texture = orm_tex
		material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		material.roughness_texture = orm_tex
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		material.metallic_texture = orm_tex
		material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	_apply_variant(material, "default")

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Prop_%s_%d" % [prop_id, _handles.size()]
	mesh_instance.material_override = material
	_load_mesh_into(mesh_instance, mesh_path)

	_rig.add_child(mesh_instance)

	var handle: int
	if _free_handles.is_empty():
		handle = _handles.size()
		_handles.append({})
	else:
		handle = _free_handles.pop_back()
	_handles[handle] = {
		"mesh": mesh_instance,
		"material": material,
		"host": control,
		"prop_id": prop_id,
		"state": "normal",
		"variant": "default",
		"natural_size": entry["natural_size"],
		"transform_override": Transform3D.IDENTITY,
	}
	_mesh_by_host[control] = {
		"handle": handle,
		"mesh": mesh_instance,
		"material": material,
	}

	# React to the host's resize. Connecting here (not in bulk on the
	# stage's _ready) means a control that attaches, detaches, then
	# re-attaches is handled cleanly: the connection is tied to the
	# host's lifetime, and the connection is re-established on the
	# new attach.
	if not control.item_rect_changed.is_connected(_on_host_rect_changed):
		control.item_rect_changed.connect(_on_host_rect_changed.bind(handle))
	control.tree_exiting.connect(_on_host_exiting.bind(handle))
	# Apply the host's current rect to the prop's transform before
	# request_render(), so the first frame already shows the prop
	# in the right place.
	_apply_transform_for_handle(handle)
	request_render()
	return handle


# Stops hosting a prop. Safe to call with an unknown handle (no-op).
# The host's signals are disconnected so a control that is freed
# without an explicit detach() does not leak a callback.
func detach(handle: int) -> void:
	if handle < 0 or handle >= _handles.size():
		return
	var entry = _handles[handle]
	if entry == null:
		return
	var host: Control = entry["host"]
	var mesh: MeshInstance3D = entry["mesh"]
	if host != null and is_instance_valid(host):
		if host.item_rect_changed.is_connected(_on_host_rect_changed):
			host.item_rect_changed.disconnect(_on_host_rect_changed)
		if host.tree_exiting.is_connected(_on_host_exiting):
			host.tree_exiting.disconnect(_on_host_exiting)
		_mesh_by_host.erase(host)
	if mesh != null and is_instance_valid(mesh):
		mesh.queue_free()
	_handles[handle] = null
	_free_handles.append(handle)
	request_render()


# Pushes the prop's state into its material. One of
# "normal"/"hover"/"pressed"/"disabled"; unknown values are ignored
# (and warned) so a caller that mistypes a state name does not
# silently fall through to "normal".
func set_prop_state(handle: int, state: String) -> void:
	if handle < 0 or handle >= _handles.size():
		return
	var entry = _handles[handle]
	if entry == null:
		return
	if entry["state"] == state:
		return
	entry["state"] = state
	_apply_state(entry["material"], entry["variant"], state)
	if bool(entry.get("active", false)):
		_apply_active(entry["material"], true)
	request_render()


# Pushes the prop's variant into its material. One of
# "default"/"primary"/"danger"/"ghost"/"compact"; unknown values fall
# through to "default" so a renamed variant never renders the
# half-applied state.
func set_prop_variant(handle: int, variant: String) -> void:
	if handle < 0 or handle >= _handles.size():
		return
	var entry = _handles[handle]
	if entry == null:
		return
	if not VARIANT_MATERIALS.has(variant):
		push_warning("UIPropStage.set_prop_variant: unknown variant '%s', falling back to 'default'" % variant)
		variant = "default"
	if entry["variant"] == variant:
		return
	entry["variant"] = variant
	_apply_variant(entry["material"], variant)
	_apply_state(entry["material"], variant, entry["state"])
	if bool(entry.get("active", false)):
		_apply_active(entry["material"], true)
	request_render()


# Per-instance transform override. MeshIcon uses this for the
# set_turn_degrees() / set_turn_fraction() rotation; StampedButton
# does not need it. The transform is composed on top of the rect
# positioning, so the prop stays anchored to its host's rect even
# while a client rotates it.
func set_prop_transform(handle: int, xform: Transform3D) -> void:
	if handle < 0 or handle >= _handles.size():
		return
	var entry = _handles[handle]
	if entry == null:
		return
	entry["transform_override"] = xform
	_apply_transform_for_handle(handle)
	request_render()


# Per-instance material override. StampedButton uses this for the
# hd_material_override() hook (Phase 3 hero props), where a
# fully-baked material replaces the procedural variant+state pipeline
# wholesale. The override is a Material, not a path - the caller has
# the asset already loaded. Passing null restores the procedural
# material and re-applies the current variant+state to it.
func set_prop_material_override(handle: int, material: Material) -> void:
	if handle < 0 or handle >= _handles.size():
		return
	var entry = _handles[handle]
	if entry == null:
		return
	var mesh: MeshInstance3D = entry["mesh"]
	if mesh == null or not is_instance_valid(mesh):
		return
	if material != null:
		mesh.material_override = material
	else:
		# Restoring the procedural material: re-apply variant + state
		# so the values on disk match what would have been there if
		# the override had never been set. The state pipeline still
		# drives the procedural look, the override is just turned off.
		mesh.material_override = entry["material"]
		_apply_variant(entry["material"], entry["variant"])
		_apply_state(entry["material"], entry["variant"], entry["state"])
	request_render()


# Per-instance "active" flag. MeshIcon uses this for the toggle/rotary
# lit-vs-unlit look. The active look is the SIGNAL_GO emission on a
# gunmetal body (matches the original MeshIcon.set_active()); the
# inactive look is plain gunmetal with no emission. The flag is
# checked at render time and applied ON TOP of the current variant +
# state, so an active prop in the disabled state still desaturates
# (the disabled delta wins for body colour, the active flag only
# affects the emission).
func set_prop_active(handle: int, active: bool) -> void:
	if handle < 0 or handle >= _handles.size():
		return
	var entry = _handles[handle]
	if entry == null:
		return
	if bool(entry.get("active", false)) == active:
		return
	entry["active"] = active
	_apply_active(entry["material"], active)
	request_render()


# Marks the viewport dirty. One request_render per logical change is
# the documented pattern; clients should batch multiple state/variant
# changes and call request_render() once at the end. The dirty
# mechanism is the same one the per-button SubViewport used:
# render_target_update_mode = UPDATE_ONCE flipped on, then back. The
# second flip is the engine's signal to re-render; without it, the
# mode is already UPDATE_ONCE from a previous tick and the engine
# sees nothing to do.
func request_render() -> void:
	_render_count += 1
	if _viewport == null:
		return
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


# Test-visible: how many times request_render() has been called on
# this stage. Used by tests/test_ui_prop_stage.gd to assert that
# state changes mark the stage dirty exactly once. The public API
# does not promise a number; the count is a stable observation
# (no off-by-one from any deferred free, no batching), which is all
# the test needs.
func render_count() -> int:
	return _render_count


# Test-visible: the current world transform for a prop. Returns the
# MeshInstance3D's local transform within the rig, which is the
# stage's world space (the rig lives at the origin of the SubViewport).
# Used by tests/test_ui_prop_stage.gd to assert the rect-to-world
# mapping at the four viewport corners and at centre. The return
# value is the transform AFTER the transform_override has been
# composed, so a MeshIcon's set_turn_degrees() shows up in the
# returned basis.
func get_prop_transform(handle: int) -> Transform3D:
	if handle < 0 or handle >= _handles.size():
		return Transform3D.IDENTITY
	var entry = _handles[handle]
	if entry == null:
		return Transform3D.IDENTITY
	var mesh: MeshInstance3D = entry["mesh"]
	if mesh == null or not is_instance_valid(mesh):
		return Transform3D.IDENTITY
	return mesh.transform


# --- Construction -----------------------------------------------------------

func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "StageViewport"
	# Transparent background so the stage's content composites over
	# the existing backdrop rather than painting an opaque rectangle
	# over it. The 2D Control rendering of the host still draws on
	# top of the rendered mesh (the legend sits on top of the button);
	# both happen via the standard CanvasItem compositing order.
	_viewport.transparent_bg = true
	# OWN WORLD. Without this the SubViewport shares the host viewport's
	# World3D, so the rig - props, camera, key light, WorldEnvironment -
	# is also present in whatever 3D scene the UI is layered over. In the
	# Design Lab that reads as a tiny duplicate of the stage floating at
	# the world origin, i.e. inside the hull.
	_viewport.own_world_3d = true
	_viewport.world_3d = World3D.new()
	# Dirty-driven. UPDATE_ONCE is the engine's signal to render on
	# the next frame and then revert to "do not render"; the request_
	# render() method on the stage is the only path that flips it on.
	# UPDATE_WHEN_VISIBLE (what the per-button StampedButton used) is
	# the wrong choice for a single shared viewport - it would re-
	# render every frame the screen is on, defeating the entire point
	# of the unification.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.handle_input_locally = false
	add_child(_viewport)


func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	_viewport.add_child(_rig)

	# The ENVIRONMENT. AgX tonemapping - the unification StampedButton
	# and MeshIcon both call out (Part 3.2 of the plan). The previous
	# per-button setup used ACES; with the chrome now reading as part
	# of the same lighting pipeline as the in-match world (b2340f4
	# landed AgX globally), the buttons have to match. Transparent
	# background so the mesh composites over the 2D backdrop rather
	# than a coloured quad.
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.58)
	env.ambient_light_energy = 0.85
	env_node.environment = env
	_rig.add_child(env_node)

	# The KEY LIGHT. Top-left, matching the plate bevels in
	# assets/textures/ui/* authored in the plate pipeline. A 3D light
	# that disagrees with the 2D bevels makes both read as texture
	# noise (Part 3.2, in the plan).
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.97, 0.90)
	key.light_energy = 1.4
	key.rotation_degrees = Vector3(-48, -32, 0)
	_rig.add_child(key)

	# The FILL. Opposite side, low intensity, so the chamfer's shaded
	# edge is not black. Same trick the per-button MeshIcon used, but
	# only built once per screen now.
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.65, 0.72, 0.82)
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-22, 145, 0)
	_rig.add_child(fill)


# Sets the ortho camera's `size` (half the world height it covers) so
# the world-to-pixel ratio is 1:1. Called from _ready and from the
# viewport's size_changed signal. Not from _process: the viewport's
# size only changes on a window resize, and the engine's signal is
# the right hook for that.
func _sync_camera_to_viewport() -> void:
	if _camera == null:
		_camera = _build_camera()
		_rig.add_child(_camera)
	var viewport_size: Vector2i = _get_render_size()
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		# The viewport has not been sized yet (the container's rect
		# may be 0x0 at the time _ready fires). A 0-size camera is
		# valid but useless; skip and let the resize signal pick it
		# up. Tests that never resize still produce a valid result:
		# a control hosted on a stage whose container has zero size
		# is not a control a test can interact with, and the stage
		# never gets a non-degenerate render.
		return
	# Ortho size in Godot 4 is the half-height of the view. The
	# world-to-pixel mapping is 1:1 when the half-height equals
	# half the viewport height. The plan says "size set to the
	# viewport's pixel height"; reading the Godot 4 docs literally
	# this would make the world units 2x the pixels, which is
	# wrong. Half the height matches the formula in the test:
	# world_y = -(rect_y - viewport_h/2).
	_camera.size = viewport_size.y * 0.5
	# The camera sits on +Z looking at -Z. Position is 0,0,1000
	# (well in front of the props) so the camera is not inside any
	# of them and the camera frustum covers the whole visible plane.
	_camera.position = Vector3(0, 0, 1000)
	_camera.look_at(Vector3(0, 0, 0), Vector3.UP)


func _build_camera() -> Camera3D:
	var cam := Camera3D.new()
	cam.name = "OrthoCamera"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Near/far must clear every prop on the screen. With z=1 for
	# every prop and the camera at z=1000, the camera-to-prop
	# distance is 999. Near = 1 covers the prop, far = 5000 covers
	# the empty space behind it.
	cam.near = 1.0
	cam.far = 5000.0
	return cam


# Resolve the render size in pixels. The stage is full-bleed on its
# parent, so the container's size is the answer; on a stage that has
# not been added to a tree yet (tests, headless boot) fall back to
# the root viewport's size, which the test runner sets explicitly.
func _get_render_size() -> Vector2i:
	if size.x > 0 and size.y > 0:
		return Vector2i(int(size.x), int(size.y))
	var root_vp := get_viewport()
	if root_vp != null:
		var sz: Vector2i = root_vp.get_visible_rect().size
		if sz.x > 0 and sz.y > 0:
			return sz
	return Vector2i.ZERO


# --- Per-prop bookkeeping ---------------------------------------------------

# Reads the GLB off disk and copies its mesh resource into the
# MeshInstance3D. The instance itself is freed - we keep the
# shared mesh resource, which is what the engine actually renders
# and what a future swap (e.g. swapping `push_button` for a
# `push_button_hero` bake) would also want to share. A failing
# load leaves the MeshInstance3D with no mesh; the warning fires
# and the prop renders as a missing-mesh magenta, which is the
# right thing for a stage to show when its data is wrong.
func _load_mesh_into(mesh_instance: MeshInstance3D, mesh_path: String) -> void:
	var packed := load(mesh_path) as PackedScene
	if packed == null:
		push_warning("UIPropStage: failed to load PackedScene at %s" % mesh_path)
		return
	var instance := packed.instantiate()
	if instance == null:
		push_warning("UIPropStage: %s.instantiate() returned null" % mesh_path)
		return
	var src := _find_mesh(instance)
	if src != null and src.mesh != null:
		mesh_instance.mesh = src.mesh
	instance.free()


static func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


# Converts a host control's screen rect into a world transform on the
# prop's MeshInstance3D. The formula is the one in the plan, Part 3.2,
# and the test in tests/test_ui_prop_stage.gd asserts against it at
# the four viewport corners and at centre.
#
# world_x = (rect.position.x + rect.size.x * 0.5) - viewport_size.x * 0.5
# world_y = -((rect.position.y + rect.size.y * 0.5) - viewport_size.y * 0.5)
# world_z = ELEVATION_Z
#
# The mesh's scale is the control's pixel size divided by the prop's
# natural size (from the registry), so a 200x100 host renders a
# 200x100 pixel mesh at any natural_size choice - the registry's
# natural_size is what calibrates "100 units of natural size = 100
# pixels at scale 1.0".
func _apply_transform_for_handle(handle: int) -> void:
	var entry = _handles[handle]
	if entry == null:
		return
	var host: Control = entry["host"]
	var mesh: MeshInstance3D = entry["mesh"]
	if host == null or not is_instance_valid(host):
		return
	if mesh == null or not is_instance_valid(mesh):
		return
	var viewport_size: Vector2i = _get_render_size()
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		# The stage is not yet sized. Defer - the resize signal will
		# call _sync_camera_to_viewport() and trigger a re-apply for
		# every host.
		return
	var rect: Rect2 = host.get_global_rect()
	var natural: Vector2 = entry["natural_size"]
	var scale_x: float = rect.size.x / maxf(natural.x, 0.0001)
	var scale_y: float = rect.size.y / maxf(natural.y, 0.0001)
	var pos := Vector3(
		(rect.position.x + rect.size.x * 0.5) - viewport_size.x * 0.5,
		-((rect.position.y + rect.size.y * 0.5) - viewport_size.y * 0.5),
		ELEVATION_Z)
	mesh.transform = Transform3D(Basis().scaled(Vector3(scale_x, scale_y, 1.0)), pos) * entry["transform_override"]


# Connects to the viewport's size_changed so a window resize updates
# the ortho camera's size and re-applies every host's transform.
func _on_viewport_resized() -> void:
	_sync_camera_to_viewport()
	for i in range(_handles.size()):
		if _handles[i] != null:
			_apply_transform_for_handle(i)
	request_render()


func _on_host_rect_changed(handle: int) -> void:
	_apply_transform_for_handle(handle)
	request_render()


# The host is leaving the tree. We can't reach in and detach safely
# (the control's own free path is what brought us here), so just
# forget the stage-side book-keeping and let the meshes be cleaned
# up when the stage itself frees.
func _on_host_exiting(handle: int) -> void:
	if handle < 0 or handle >= _handles.size():
		return
	var entry = _handles[handle]
	if entry == null:
		return
	var host: Control = entry["host"]
	if host != null:
		_mesh_by_host.erase(host)
	_handles[handle] = null
	_free_handles.append(handle)
	# No request_render() - the viewport is being torn down or the
	# host is going away; either way a render call would race the
	# free.


# --- Material pipeline ------------------------------------------------------

func _apply_variant(material: StandardMaterial3D, variant: String) -> void:
	var m: Dictionary = VARIANT_MATERIALS.get(variant, VARIANT_MATERIALS["default"])
	material.albedo_color = m["albedo"]
	material.metallic = m["metallic"]
	material.roughness = m["roughness"]
	material.emission_enabled = float(m["emission_energy"]) > 0.0
	material.emission = m["emission"]
	material.emission_energy_multiplier = m["emission_energy"]


# State deltas are applied on top of the variant's BASE values, so
# hover-while-pressed still reads as the button moving down, not as a
# colour reset. The variant passed in is the one currently active;
# its base values are read from VARIANT_MATERIALS.
func _apply_state(material: StandardMaterial3D, variant: String, state: String) -> void:
	var m: Dictionary = VARIANT_MATERIALS.get(variant, VARIANT_MATERIALS["default"])
	var base_albedo: Color = m["albedo"]
	var base_metallic: float = m["metallic"]
	var base_roughness: float = m["roughness"]
	var base_emission: Color = m["emission"]
	var base_emission_energy: float = m["emission_energy"]
	match state:
		"disabled":
			material.albedo_color = base_albedo.darkened(0.20).lerp(Color(0.30, 0.30, 0.30), DISABLED_DESATURATE)
			material.roughness = clampf(base_roughness + DISABLED_ROUGHNESS_LIFT, 0.0, 1.0)
			material.metallic = base_metallic
			material.emission_enabled = false
		"pressed":
			material.albedo_color = base_albedo.darkened(PRESS_DROP)
			material.roughness = base_roughness
			material.metallic = base_metallic
			material.emission_enabled = base_emission_energy > 0.0
			material.emission = base_emission
			material.emission_energy_multiplier = base_emission_energy
		"hover":
			material.albedo_color = base_albedo.lightened(HOVER_LIFT)
			material.roughness = base_roughness
			material.metallic = base_metallic
			material.emission_enabled = base_emission_energy > 0.0
			material.emission = base_emission
			material.emission_energy_multiplier = base_emission_energy
		_:
			# "normal" and any unknown state lands here.
			material.albedo_color = base_albedo
			material.metallic = base_metallic
			material.roughness = base_roughness
			material.emission_enabled = base_emission_energy > 0.0
			material.emission = base_emission
			material.emission_energy_multiplier = base_emission_energy


# Active look. The body shifts to a slightly cooler gunmetal, the
# SIGNAL_GO emission turns on at moderate intensity. The active look
# is intentionally a small body delta + an emission; the variant
# already provides the body colour family, the active flag is what
# makes the prop read as "engaged" at a glance.
func _apply_active(material: StandardMaterial3D, active: bool) -> void:
	if active:
		material.albedo_color = Color(0.30, 0.34, 0.30, 1.0)
		material.emission_enabled = true
		material.emission = Tokens.SIGNAL_GO
		material.emission_energy_multiplier = 0.6
	else:
		material.albedo_color = Color(0.42, 0.43, 0.45, 1.0)
		material.emission_enabled = false
