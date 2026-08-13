class_name MeshIcon
extends SubViewportContainer
# A small live 3D prop standing in for a flat control glyph - the toggle
# switch, rotary selector, rocker, knurled dial, DZUS fastener and latch
# authored in tools/blender/build_ui_props.py, mounted beside the REAL
# CheckBox/OptionButton/HSlider it illustrates.
#
# WHY A PROP NEXT TO THE CONTROL, NOT A REPLACEMENT FOR IT. Godot's native
# controls already carry keyboard focus, screen-reader-adjacent accessibility
# hooks, and every existing test that clicks a CheckBox or drags an HSlider.
# Rebuilding that on raw 3D geometry - hit-testing a rotated mesh inside a
# SubViewport, re-deriving focus order - is a much larger and riskier project
# than what was asked for: this game already treats hardware as real meshes
# everywhere else (every hull, every weapon), and the settings/Lab chrome
# should not be the one place that is flat glyphs pretending otherwise. The
# mesh reads the state; the native control still owns the input.
#
# REWRITTEN 2026-08-13 in Phase 1 of the Tactile Interface Programme to
# use the shared UIPropStage (D2: one SubViewport per screen, not per
# prop). The previous version built its own SubViewport with its own
# camera, lights and rig per instance - six SubViewports on the
# Settings screen, each a full 3D scene rendered to a small texture.
# Now MeshIcon is a thin client: it extends SubViewportContainer so
# existing layouts that put it as a child of a VBox or grid do not
# break, but it owns no SubViewport, no camera, no light. The
# UIPropStage handles all of that; MeshIcon just keeps a handle and
# pushes state.
#
# HEADLESS FALLBACK. If no UIPropStage ancestor exists (a not-yet-
# migrated screen, or a headless test that has no SubViewport),
# MeshIcon falls back to the per-instance SubViewport it used to
# always build. The fallback is the documented silent exception
# to the project's no-silent-fallback rule (Tactile Interface
# Programme Part 4 Phase 1); a headless test must not depend on
# the 3D render.
#
# PER-INSTANCE ROTATION. The set_turn_degrees() / set_turn_fraction()
# API is preserved verbatim. Under the stage, MeshIcon computes a
# Transform3D from the rotation and pushes it through
# UIPropStage.set_prop_transform(handle, xform) - the per-instance
# transform override the plan's API was missing for this case
# (Part 1 decision, wrinkle 5). MeshIcon keeps the rotation in
# degrees locally so a load_mesh() that swaps the prop can re-apply
# the same rotation to the new prop.
#
# CHEAP ON PURPOSE. Chris: "a fully modern and fluid UI/UX" does not mean a
# few dozen live-rendered dials eating a frame budget meant for the
# battlefield. The shared stage's dirty-driven render (UPDATE_ONCE
# flipped on every state change) means a settings row that never
# changes costs nothing to redraw - same property the previous
# MeshIcon had, just on a larger container.

const Tokens = preload("res://scripts/ui_tokens.gd")
const UIPropRegistryScript = preload("res://scripts/ui/ui_prop_registry.gd")
const UIPropStageScript = preload("res://scripts/ui/ui_prop_stage.gd")

@export var mesh_path: String = ""
@export var icon_size: Vector2i = Vector2i(40, 40)

# Per-instance rotation state. Kept here (not on the stage) so a
# load_mesh() that swaps the prop can re-apply the same rotation to
# the new prop, and so a screen can snapshot the rotation cheaply
# (read this field) without going through the stage's per-handle
# transform table.
var _turn_degrees: float = 0.0
var _active: bool = false
var _stage: UIPropStage = null
var _stage_handle: int = -1

# Fallback-path bookkeeping. The fallback path keeps the per-instance
# SubViewport/rig/environment/camera/light that the previous version
# always built. Only the fallback path touches any of these.
var _viewport: SubViewport = null
var _mesh_instance: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _rig: Node3D = null


func _ready() -> void:
	custom_minimum_size = Vector2(icon_size)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Decide at _ready time, not _init, because the stage lives in
	# the ancestor chain and the chain only exists once the node is
	# in a tree. A MeshIcon created in code and added to a parent
	# that contains a stage gets the stage path; one added to a tree
	# that does not gets the fallback.
	_stage = _find_stage()
	if _stage != null:
		_attach_to_stage()
	elif mesh_path != "":
		_build_fallback()
		load_mesh(mesh_path)


# Walks the ancestor chain for a UIPropStage. Same logic as
# StampedButton._find_stage(); not shared because the two clients
# are different scripts and a shared helper would have to live
# somewhere - the registry is data only, the stage is the only
# place a third copy could go, and a third copy that exists just
# to be a helper is the kind of thing that drifts. Keep the
# duplication tiny.
func _find_stage() -> UIPropStage:
	var node: Node = get_parent()
	while node != null:
		if node is UIPropStage:
			return node
		node = node.get_parent()
	return null


func _attach_to_stage() -> void:
	if mesh_path == "":
		# Nothing to attach; the caller can set mesh_path later and
		# call load_mesh to drive attach() then.
		return
	var prop_id: String = UIPropRegistryScript.prop_id_for_path(mesh_path)
	if prop_id == "":
		# An unregistered mesh path. Push a warning and stay on the
		# fallback path so the caller at least sees a 3D mesh (the
		# old per-instance SubViewport, rebuilt). Headless tests
		# never hit this; the warning tells the next reader why
		# their prop is not on the stage.
		push_warning("MeshIcon: '%s' is not in UIPropRegistry. Falling back to per-instance SubViewport." % mesh_path)
		_stage = null
		_build_fallback()
		load_mesh(mesh_path)
		return
	_stage_handle = _stage.attach(self, prop_id)
	if _stage_handle == -1:
		# The stage refused (e.g. the GLB did not load). Same
		# fallback: stay functional, lose the unification.
		push_warning("MeshIcon: stage.attach refused prop_id '%s'. Falling back to per-instance SubViewport." % prop_id)
		_stage = null
		_build_fallback()
		load_mesh(mesh_path)
		return
	# Re-apply any state set before _ready. load_mesh() before
	# _ready is a real call pattern (set mesh_path, then call
	# load_mesh) and the previous version handled it; the new
	# version handles it by re-applying on attach.
	if _turn_degrees != 0.0:
		set_turn_degrees(_turn_degrees)
	if _active:
		set_active(true)


func _build_fallback() -> void:
	# The previous MeshIcon's full per-instance build: SubViewport +
	# ACES-tonemap env + key light + camera + StandardMaterial3D +
	# MeshInstance3D. Copied verbatim (with the ACES stay - the
	# fallback path is a headless-test convenience, and changing
	# the tonemapper in two places is the kind of drift the
	# unification in Phase 1 was supposed to remove; keeping ACES
	# in the fallback makes "Phase 1 broke the headless test" an
	# easy diagnosis rather than a hard one).
	_viewport = SubViewport.new()
	_viewport.size = icon_size
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)

	_rig = Node3D.new()
	_viewport.add_child(_rig)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.58)
	env.ambient_light_energy = 0.9
	env_node.environment = env
	_rig.add_child(env_node)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.97, 0.9)
	key.light_energy = 1.2
	key.rotation_degrees = Vector3(-52, -35, 0)
	_rig.add_child(key)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.55, 1.4)
	cam.rotation_degrees = Vector3(-20, 0, 0)
	cam.fov = 28.0
	_rig.add_child(cam)

	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.42, 0.43, 0.45, 1.0)
	_material.metallic = 0.55
	_material.roughness = 0.35

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.position = Vector3(0, -0.05, 0)
	_mesh_instance.material_override = _material
	_rig.add_child(_mesh_instance)


func load_mesh(path: String) -> void:
	mesh_path = path
	if _stage != null:
		# Re-derive the prop_id and re-attach. load_mesh is the
		# supported way to swap a prop, and a swap that leaves
		# the old prop on the stage would be a leak.
		if _stage_handle != -1:
			_stage.detach(_stage_handle)
			_stage_handle = -1
		var prop_id: String = UIPropRegistryScript.prop_id_for_path(path)
		if prop_id == "":
			push_warning("MeshIcon.load_mesh: '%s' is not in UIPropRegistry. Dropping to fallback." % path)
			_stage = null
			_build_fallback()
			_load_fallback_mesh(path)
			return
		_stage_handle = _stage.attach(self, prop_id)
		# Re-apply state that the swap just nuked.
		if _turn_degrees != 0.0:
			set_turn_degrees(_turn_degrees)
		if _active:
			set_active(true)
	elif _mesh_instance != null:
		# Fallback path: load the mesh into the local MeshInstance3D
		# and re-render the per-instance SubViewport.
		_load_fallback_mesh(path)


func _load_fallback_mesh(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var instance := packed.instantiate()
	var src := _find_mesh(instance)
	if src != null:
		_mesh_instance.mesh = src.mesh
	instance.free()
	_redraw_fallback()


# ON/armed state - SIGNAL_GO amber-to-green accent versus neutral gunmetal,
# same signal vocabulary as every other affordance in the game rather than an
# invented "3D icon" palette.
func set_active(active: bool) -> void:
	_active = active
	if _stage != null and _stage_handle != -1:
		_stage.set_prop_active(_stage_handle, active)
	elif _material != null:
		# Fallback path. Same look as the previous MeshIcon had.
		if active:
			_material.albedo_color = Color(0.30, 0.34, 0.30, 1.0)
			_material.emission_enabled = true
			_material.emission = Tokens.SIGNAL_GO
			_material.emission_energy_multiplier = 0.6
		else:
			_material.albedo_color = Color(0.42, 0.43, 0.45, 1.0)
			_material.emission_enabled = false
		_redraw_fallback()


# For the rotary selector / knurled dial: turns the whole prop about its own
# Y axis, so a discrete choice (index/count) or a continuous value
# (fraction 0..1 over a fixed arc) both read as a real turned position rather
# than a redrawn glyph.
func set_turn_degrees(degrees: float) -> void:
	_turn_degrees = degrees
	if _stage != null and _stage_handle != -1:
		# Build a Y-axis rotation transform. Composed with the
		# stage's host-rect positioning so the prop stays anchored
		# to its control's rect while spinning. The stage applies
		# the transform_override AFTER the rect positioning, which
		# is what makes the rotation pivot the prop's own origin.
		var xform := Transform3D(Basis(Vector3.UP, deg_to_rad(degrees)), Vector3.ZERO)
		_stage.set_prop_transform(_stage_handle, xform)
	elif _mesh_instance != null:
		_mesh_instance.rotation_degrees.y = degrees
		_redraw_fallback()


func set_turn_fraction(fraction: float, arc_degrees: float = 270.0) -> void:
	set_turn_degrees((clampf(fraction, 0.0, 1.0) - 0.5) * arc_degrees)


func _redraw_fallback() -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


static func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
