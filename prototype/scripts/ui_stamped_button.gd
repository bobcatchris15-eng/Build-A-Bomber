class_name StampedButton
extends Button
# A primary action button rendered as a real piece of 3D industrial hardware
# - a low-profile, chunky push button with a slightly dished top, the same
# way a factory control-panel button reads. The "worn toolbox and stamped
# enamelled label" the design lab and battle production HUD already carry,
# taken one step further: the button itself is a real mesh, not a flat
# plate with a 2D label on top.
#
# CREATED 2026-08-10 in Phase 1 of the chrome unification. The motivation
# is the same as the 2D prototype this replaced: the out-of-match screens
# (livery / match_setup / operations_setup / operations_draft /
# blueprint_library / loading) all hand-rolled a flat Button +
# UIFeedbackScript.wire() and had no primitive combining the chamfered
# metal face + the enamel legend + the real-button state changes. The 2D
# version (ToolboxPlate + StampedLabel) closed that gap. This 3D version
# closes it better: the mesh carries the chunkiness, the dish catches the
# key light, the chamfer reads as a machined edge - all things a flat
# 2D plate could only fake.
#
# THE MESH is ui_push_button.glb, authored in tools/blender/build_ui_props.py
# alongside the toggle, rocker, knurled dial, dzus fastener and latch
# meshes that the Design Lab settings panel and stat calculator already
# use as 3D icons next to native controls. The build script pattern is the
# one Chris set up for the other six; adding the seventh was a single
# new function call.
#
# COMPOSITION:
#
#   StampedButton (extends Button, the hit target + focus owner)
#   +-- SubViewportContainer (FULL_RECT, MOUSE_FILTER_IGNORE, stretch)
#   |   +-- SubViewport (transparent_bg, UPDATE_WHEN_VISIBLE)
#   |       +-- WorldEnvironment (transparent, ACES, ambient)
#   |       +-- DirectionalLight3D (key from top-left)
#   |       +-- Camera3D (3/4 view, FOV 28)
#   |       +-- MeshInstance3D (the push button mesh, scaled to fit)
#   +-- StampedLabel (FULL_RECT, MOUSE_FILTER_IGNORE, the legend in enamel)
#
# The Button is the structural root. The SubViewportContainer shows the
# rendered mesh; the StampedLabel overlays the legend. The Button's own
# theme styleboxes are blanked in _init, so the procedural bakelite the
# theme assigns to Button does not double-paint on top of the mesh.
#
# STATE-TO-LOOK PIPELINE:
#   * variant -> material body color (albedo + roughness + metallic)
#   * hover   -> the dish catches more light (a brighter key), the body
#                brightens slightly so the chamfer highlight grows
#   * pressed -> the body darkens, the dish looks receded (the user's
#                finger is "pushing it down")
#   * disabled -> the body desaturates, the label dims
#
# HD TEXTURES (Phase 3) layer onto the same mesh. The procedural material
# is the rendering default; the HD material swaps in via
# `set_hd_material_override(material)`. The hit-test geometry, label
# position, and state pipeline are unchanged, so Phase 3 is a no-call-
# site-change swap at every existing call site of this primitive.
#
# EVERY BUTTON GETS THE HD TREATMENT - that is the Phase 3 directive, not
# an 8-10 shortcut. The procedural mesh + variant material is what we
# have today. The HD authoring (manufacturer mark stamped into the dish,
# part number stamp near the rim, real chamfered screws) is the upgrade
# that makes every visible button look like a real piece of hardware.

const Tokens = preload("res://scripts/ui_tokens.gd")
const StampedLabelScript = preload("res://scripts/ui_stamped_label.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")

const MESH_PATH := "res://assets/models/ui/ui_push_button.glb"

enum Variant {
	DEFAULT,    # standard action
	PRIMARY,    # the one primary action a screen commits to (green tint)
	DANGER,     # destructive (red tint)
	GHOST,      # back / return / cancel (subtle, dimmed)
	COMPACT,    # toolbar / family toolbox (shorter, smaller)
}

const MIN_WIDTH := 132.0
const MIN_HEIGHT := 44.0
const COMPACT_HEIGHT := 36.0
# The SubViewport renders at 2x the button's pixel size for sharp edges.
# 2x is the sweet spot: 1x aliases the chamfer, 3x is wasted GPU on a
# 132x44 button. UPDATE_WHEN_VISIBLE means it only re-renders on state
# change, not every frame.
const RENDER_SCALE := 2
# How much the material brightens on hover. Kept small - a chamfered mesh
# that jumps brightness reads as a screen-mode change, not as a surface
# catching more light. 0.12 is roughly the lift a real factory button
# shows when the operator's hand approaches.
const HOVER_LIFT := 0.12
# Symmetric with HOVER_LIFT so a press reads as "the button moved down
# into the frame", not as "it dimmed".
const PRESS_DROP := 0.14

var _viewport: SubViewport = null
var _mesh_instance: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _label: Control = null
var _variant: int = Variant.DEFAULT
# Cached per-variant BASE values, so hover/press apply deltas to a known
# state rather than chaining lerps from a mutable field. _apply_state reads
# from these; _apply_variant writes them.
var _base_albedo: Color = Color(0.42, 0.43, 0.45)
var _base_metallic: float = 0.55
var _base_roughness: float = 0.42
var _base_emission: Color = Color(0, 0, 0, 0)
var _base_emission_energy: float = 0.0


# The button's legend. Routed into the StampedLabel child, NOT the Button's
# own `text` (which would draw a second copy in the theme's stencil face -
# the exact "printed on" look the stamped lettering replaced).
var legend: String = "":
	set(value):
		legend = value
		if _label != null:
			_label.text = value


# The button's role. Setting this re-colours the mesh immediately, so a
# screen can hot-swap a button's meaning without rebuilding it.
var variant: int = Variant.DEFAULT:
	set(value):
		_variant = value
		_apply_variant()
		_apply_state()
		if _viewport != null:
			_invalidate()


# Optional override of the procedural material. Phase 3 hook for the HD
# plates (engraved manufacturer mark, part number stamp, screws). When
# set, the procedural material is replaced and the variant system no
# longer drives colour - the override owns the look. Empty = procedural.
#
# The override is a fully constructed Material (the same type the engine
# renders), not a path - the caller has the asset already loaded. This
# keeps the primitive ignorant of resource loading.
var hd_material_override: Material = null:
	set(value):
		hd_material_override = value
		if _mesh_instance != null:
			if value != null:
				_mesh_instance.material_override = value
			else:
				_mesh_instance.material_override = _material
			_invalidate()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(MIN_WIDTH, MIN_HEIGHT)
	focus_mode = Control.FOCUS_ALL
	# Blank out the theme's procedural bakelite. The mesh in the SubViewport
	# IS the face; drawing a Button stylebox on top of it would double-paint.
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())


func _ready() -> void:
	_build_viewport()
	_build_label()
	_build_focus_ring()
	_apply_variant()
	_apply_state()

	pressed.connect(_on_pressed_changed)
	toggled.connect(_on_toggled_changed)
	mouse_entered.connect(_apply_state)
	mouse_exited.connect(_apply_state)
	focus_entered.connect(_apply_state)
	focus_exited.connect(_apply_state)
	resized.connect(_on_resized)


func _build_viewport() -> void:
	var container := SubViewportContainer.new()
	container.name = "MeshViewport"
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	_viewport = SubViewport.new()
	# Sized in _on_resized(); 2x the button's pixel size for sharpness.
	_viewport.size = Vector2i(int(MIN_WIDTH * RENDER_SCALE), int(MIN_HEIGHT * RENDER_SCALE))
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(_viewport)

	var rig := Node3D.new()
	rig.name = "Rig"
	_viewport.add_child(rig)

	# STUDIO ENVIRONMENT. ACES tonemapping, neutral ambient, transparent
	# background. The ambient colour is a low-saturation warm grey - same
	# family as the rest of the chrome so the buttons do not read as
	# belonging to a different lighting setup than the rest of the UI.
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.58)
	env.ambient_light_energy = 0.85
	env_node.environment = env
	rig.add_child(env_node)

	# KEY LIGHT from the top-left, matching the chamfer direction in the
	# existing 2D ToolboxPlate so a button on the Livery screen and a
	# button on the battle HUD read as lit by the same source.
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.97, 0.90)
	key.light_energy = 1.4
	key.rotation_degrees = Vector3(-48, -32, 0)
	rig.add_child(key)

	# A COOL FILL from the opposite side at low intensity, so the chamfer's
	# shaded edge is not black - same trick the Livery preview viewport
	# uses, scaled down so the dish still reads as a clear top surface.
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.65, 0.72, 0.82)
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-22, 145, 0)
	rig.add_child(fill)

	# CAMERA at a 3/4 view, slightly above and to the front. The angle
	# shows the dish on the top, the chamfer on the top edge, and the
	# chunky body in profile - all three reads a real push button gives
	# in a product shot. FOV 28 keeps the perspective low so the
	# button does not distort at the edges.
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.55, 0.95)
	cam.look_at(Vector3(0.0, 0.10, 0.0), Vector3.UP)
	cam.fov = 28.0
	rig.add_child(cam)

	# MESH + MATERIAL. The procedural material is the default; Phase 3
	# swaps it out via hd_material_override without touching anything else.
	_material = StandardMaterial3D.new()
	_material.albedo_color = _base_albedo
	_material.metallic = _base_metallic
	_material.roughness = _base_roughness
	_material.emission_enabled = false

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "ButtonMesh"
	_mesh_instance.material_override = _material
	_load_mesh()


# Loads ui_push_button.glb as a PackedScene, instantiates it, copies out
# the mesh, and frees the instance. Same pattern MeshIcon uses for the
# other six UI hardware meshes.
func _load_mesh() -> void:
	if not ResourceLoader.exists(MESH_PATH):
		push_warning("StampedButton: missing mesh at %s" % MESH_PATH)
		return
	var packed := load(MESH_PATH) as PackedScene
	if packed == null:
		return
	var instance := packed.instantiate()
	var src := _find_mesh(instance)
	if src != null and src.mesh != null:
		_mesh_instance.mesh = src.mesh
	instance.free()


static func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


func _build_label() -> void:
	_label = StampedLabelScript.new()
	_label.name = "Label"
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	if not legend.is_empty():
		_label.text = legend


# Keyboard focus ring. Drawn as a thin hazard-coloured border around the
# button's rect, hidden otherwise. Lives in its own child Control so a
# Phase 3 caller can swap the visual (e.g. a hard-edged machine-engraved
# ring instead of a flat line) without reaching into this file.
#
# The theme's `focus` stylebox would normally draw this. We blanked that
# in _init so the 3D mesh is not double-painted - which also dropped the
# focus ring. A keyboard user has no way to see which button is selected
# without this, so it is non-optional.
const _FOCUS_RING_INSET := 2.0
const _FOCUS_RING_WIDTH := 2.0
var _focus_ring: Control = null

func _build_focus_ring() -> void:
	_focus_ring = Control.new()
	_focus_ring.name = "FocusRing"
	_focus_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_focus_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_focus_ring.visible = false
	_focus_ring.draw.connect(_draw_focus_ring)
	add_child(_focus_ring)


func _draw_focus_ring() -> void:
	if _focus_ring == null:
		return
	var rect := Rect2(
		_FOCUS_RING_INSET, _FOCUS_RING_INSET,
		size.x - _FOCUS_RING_INSET * 2.0,
		size.y - _FOCUS_RING_INSET * 2.0)
	_focus_ring.draw_rect(rect, Tokens.SIGNAL_HAZARD, false, _FOCUS_RING_WIDTH)


func _on_resized() -> void:
	if _viewport == null:
		return
	_viewport.size = Vector2i(
		maxi(int(size.x * RENDER_SCALE), int(MIN_WIDTH * RENDER_SCALE)),
		maxi(int(size.y * RENDER_SCALE), int(MIN_HEIGHT * RENDER_SCALE)))
	_invalidate()


func _on_pressed_changed() -> void:
	_apply_state()


func _on_toggled_changed(_pressed: bool) -> void:
	_apply_state()


# Re-render the SubViewport. With UPDATE_WHEN_VISIBLE the engine only
# redraws when this fires, so an idle button costs nothing.
func _invalidate() -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE


# THE STATE-TO-LOOK PIPELINE.
#
# Variant sets the BASE material values. Hover / pressed / disabled apply
# deltas on top, so a press during a hover still reads as the button
# moving down into the frame - not as a colour reset.
#
# Read order: BaseVariant -> Disabled -> Pressed -> Hover -> Focus. Last
# writer wins.
func _apply_state() -> void:
	if _material == null or hd_material_override != null:
		# An HD override owns the look; the procedural state pipeline is
		# off. Phase 3 is responsible for its own hover/press treatment.
		# Even so, the focus ring is OUR responsibility - the theme
		# focus stylebox is blanked, so without this, keyboard users
		# have no visual feedback at all on an HD-override'd button.
		_apply_focus_ring()
		return
	if disabled:
		_material.albedo_color = _base_albedo.darkened(0.20).lerp(Color(0.30, 0.30, 0.30), 0.5)
		_material.roughness = clampf(_base_roughness + 0.15, 0.0, 1.0)
		_material.emission_enabled = false
		if _label != null:
			_label.set_live(false)
			_label.modulate.a = 0.45
		_apply_focus_ring()
		_invalidate()
		return
	if _label != null:
		_label.set_live(true)
		_label.modulate.a = 1.0

	if button_pressed:
		_material.albedo_color = _base_albedo.darkened(PRESS_DROP)
		_material.roughness = _base_roughness
		_material.emission_enabled = _base_emission_energy > 0.0
		_material.emission = _base_emission
		_material.emission_energy_multiplier = _base_emission_energy
		_apply_focus_ring()
		_invalidate()
		return

	# Hover. Brighten the body so the mesh reads as catching more light.
	# The chamfer's bevel is what the eye locks onto; a small lift there
	# is a clear "ready" cue.
	var hovered := get_global_rect().has_point(get_viewport().get_mouse_position()) or has_focus()
	if hovered:
		_material.albedo_color = _base_albedo.lightened(HOVER_LIFT)
		_material.roughness = _base_roughness
		_material.emission_enabled = _base_emission_energy > 0.0
		_material.emission = _base_emission
		_material.emission_energy_multiplier = _base_emission_energy
		_apply_focus_ring()
		_invalidate()
		return

	# At rest.
	_material.albedo_color = _base_albedo
	_material.metallic = _base_metallic
	_material.roughness = _base_roughness
	_material.emission_enabled = _base_emission_energy > 0.0
	_material.emission = _base_emission
	_material.emission_energy_multiplier = _base_emission_energy
	_apply_focus_ring()
	_invalidate()


# Focus ring is a separate state from hover, so a keyboard user who tabs
# through the screen gets a ring even when the cursor is somewhere else.
# Hidden on disabled - a control you cannot activate does not deserve
# focus feedback, and the focus ring would mislead the user into thinking
# they can press it.
func _apply_focus_ring() -> void:
	if _focus_ring == null:
		return
	_focus_ring.visible = has_focus() and not disabled


func _apply_variant() -> void:
	# Caches the BASE values for the active variant. _apply_state reads
	# from these so the per-state deltas are stable.
	match _variant:
		Variant.DEFAULT:
			_base_albedo = Color(0.42, 0.43, 0.45)
			_base_metallic = 0.55
			_base_roughness = 0.42
			_base_emission = Color(0, 0, 0, 0)
			_base_emission_energy = 0.0
		Variant.PRIMARY:
			# Darker body, gentle green emission so the chamfer reads as
			# glowing slightly - the "ready" signal carried by the plate
			# rather than by the legend, which stays amber for consistency.
			_base_albedo = Color(0.20, 0.28, 0.22)
			_base_metallic = 0.45
			_base_roughness = 0.48
			_base_emission = Tokens.SIGNAL_GO
			_base_emission_energy = 0.15
		Variant.DANGER:
			_base_albedo = Color(0.32, 0.18, 0.18)
			_base_metallic = 0.45
			_base_roughness = 0.48
			_base_emission = Tokens.SIGNAL_ALERT
			_base_emission_energy = 0.18
		Variant.GHOST:
			# Lighter, less metallic, no signal glow. A back/return
			# button should sit back, not commit.
			_base_albedo = Color(0.55, 0.56, 0.58)
			_base_metallic = 0.30
			_base_roughness = 0.55
			_base_emission = Color(0, 0, 0, 0)
			_base_emission_energy = 0.0
		Variant.COMPACT:
			_base_albedo = Color(0.42, 0.43, 0.45)
			_base_metallic = 0.55
			_base_roughness = 0.42
			_base_emission = Color(0, 0, 0, 0)
			_base_emission_energy = 0.0
			custom_minimum_size = Vector2(custom_minimum_size.x, COMPACT_HEIGHT)
