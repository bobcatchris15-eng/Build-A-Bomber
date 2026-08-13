class_name StampedButton
extends Button
# A primary action button rendered as a real piece of 3D industrial hardware
# - a low-profile, chunky push button with a slightly dished top, the same
# way a factory control-panel button reads. The "worn toolbox and stamped
# enamelled label" the design lab and battle production HUD already carry,
# taken one step further: the button itself is a real mesh, not a flat
# plate with a 2D label on top.
#
# CREATED 2026-08-10 in Phase 1 of the chrome unification. REWRITTEN
# 2026-08-13 in Phase 1 of the Tactile Interface Programme to use the
# shared UIPropStage (D2: one SubViewport per screen, not per button).
# Public API is unchanged: Variant enum, MIN_WIDTH / MIN_HEIGHT /
# COMPACT_HEIGHT, the legend and variant properties and their setters,
# the hd_material_override hook, the focus ring, the StampedLabel child.
# Every existing call site - deploy_gate, livery, match_setup,
# operations_draft, operations_setup, blueprint_library - continues
# to compile and to behave as before.
#
# THE STAGE PATH (production). On _ready() the button walks its
# ancestor chain for a UIPropStage. If one is found, the button
# registers itself with attach() and from then on the stage owns
# the mesh, the camera, the lights, and the render cycle. The
# button keeps its identity as a Control (hit-testing, focus,
# keyboard nav, every existing test that clicks it) and is a thin
# client of the stage for everything visual. The state pipeline
# (variant / hover / pressed / disabled) calls stage.set_prop_state
# and stage.set_prop_variant, which mutate the shared material and
# mark the shared viewport dirty.
#
# THE FALLBACK PATH (headless + not-yet-migrated screens). If no
# UIPropStage ancestor exists, the button renders as a plain Godot
# Button with the theme's procedural moulded. The StampedLabel
# child still draws the legend in the stamped-enamel style; the
# focus ring still works; the button's pressed/hover signals
# still fire. The only thing missing is the 3D mesh, which is the
# entire point of the fallback: a headless test that has no
# SubViewport must not depend on the 3D rendering. This is the
# one DOCUMENTED SILENT FALLBACK in this project, per Phase 1 of
# the Tactile Interface Programme.
#
# COMPOSITION (stage path):
#
#   StampedButton (extends Button, the hit target + focus owner)
#   +-- StampedLabel (FULL_RECT, MOUSE_FILTER_IGNORE, the legend)
#   +-- FocusRing (FULL_RECT, MOUSE_FILTER_IGNORE, the keyboard ring)
#   (no SubViewportContainer; the shared stage owns the viewport)
#
# COMPOSITION (fallback path):
#
#   StampedButton (extends Button)
#   +-- StampedLabel (legend in stamped enamel, over the theme face)
#   +-- FocusRing (keyboard ring on top of the theme face)
#   (no 3D mesh; the theme's procedural moulded IS the face)
#
# STATE-TO-LOOK PIPELINE (stage path):
#   * variant -> stage.set_prop_variant() -> the shared material's
#     base values (albedo / metallic / roughness / emission)
#   * hover   -> stage.set_prop_state("hover") -> the dish catches
#     more light, the body brightens
#   * pressed -> stage.set_prop_state("pressed") -> the body
#     darkens, the dish looks receded
#   * disabled -> stage.set_prop_state("disabled") -> the body
#     desaturates
# STATE-TO-LOOK PIPELINE (fallback path):
#   * the theme's procedural moulded, plus the StampedLabel's
#     stamped-enamel legend and the focus ring. Pressed/hover give
#     the standard Godot Button audio + stylebox swap.
#
# HD TEXTURES (Phase 3) layer onto the same mesh via
# hd_material_override. The override is pushed to the stage's
# per-handle MeshInstance3D; the procedural state pipeline is
# suspended for that prop until the override is cleared. The
# fallback path ignores the override - there is no 3D rendering
# to apply it to.

const Tokens = preload("res://scripts/ui_tokens.gd")
const StampedLabelScript = preload("res://scripts/ui_stamped_label.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")
const UIPropStageScript = preload("res://scripts/ui/ui_prop_stage.gd")

const MESH_PROP_ID := "push_button"

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

const UIPropRegistryScript = preload("res://scripts/ui/ui_prop_registry.gd")

var _stage: UIPropStage = null
var _stage_handle: int = -1
# The prop_id currently attached, so a legend change can tell whether it
# actually needs to re-point the stage or is a no-op.
var _attached_prop_id: String = ""
var _label: Control = null
var _focus_ring: Control = null
var _variant: int = Variant.DEFAULT
# State strings pushed to the stage. Kept here as constants so a
# typo in the call site (e.g. "hoover") is a name resolution error
# rather than a silent string mismatch. The four values match the
# ones UIPropStage._apply_state() expects.
const STAGE_STATE_NORMAL := "normal"
const STAGE_STATE_HOVER := "hover"
const STAGE_STATE_PRESSED := "pressed"
const STAGE_STATE_DISABLED := "disabled"
# Variant strings pushed to the stage. Same reasoning. The names
# are lowercase string forms of the Variant enum (Phase 1 ships
# the mapping here, not as a separate converter).
const STAGE_VARIANT_DEFAULT := "default"
const STAGE_VARIANT_PRIMARY := "primary"
const STAGE_VARIANT_DANGER := "danger"
const STAGE_VARIANT_GHOST := "ghost"
const STAGE_VARIANT_COMPACT := "compact"


# The button's legend. Routed into the StampedLabel child, NOT the Button's
# own `text` (which would draw a second copy in the theme's stencil face -
# the exact "printed on" look the stamped lettering replaced).
var legend: String = "":
	set(value):
		legend = value
		if _label != null:
			_label.text = value
		# The legend also picks the button's texture set (D1: unique
		# textures per button, on the one shared mesh). Re-resolve on
		# every change, because command_card.gd sets legend AFTER
		# _ready when a selection swaps a cell's command - a button
		# that only resolved at attach time would keep wearing the
		# previous command's scuffs.
		_resync_prop_variant()


# The button's role. Setting this re-colours the mesh immediately on the
# stage path, or adjusts the COMPACT height on the fallback path. Both
# paths always update the focus ring.
var variant: int = Variant.DEFAULT:
	set(value):
		_variant = value
		if _stage_handle != -1:
			_stage.set_prop_variant(_stage_handle, _variant_to_stage_string(_variant))
		_apply_variant_height()
		_apply_focus_ring()


# Optional override of the procedural material. Phase 3 hook for the HD
# plates (engraved manufacturer mark, part number stamp, screws). When
# set, the procedural material is replaced on the stage's per-handle
# MeshInstance3D and the state pipeline is suspended for that prop -
# the override owns the look. Empty / null = procedural.
#
# The override is a fully constructed Material (the same type the engine
# renders), not a path - the caller has the asset already loaded. This
# keeps the primitive ignorant of resource loading.
#
# On the fallback path there is no 3D rendering to apply the override
# to, so the value is stored but has no visible effect. The setter
# still runs (the contract is "set it and the look changes", which
# is the production path; the fallback degrades to no-op).
var hd_material_override: Material = null:
	set(value):
		hd_material_override = value
		if _stage_handle != -1:
			_stage.set_prop_material_override(_stage_handle, value)
		# The override owns the look; the procedural state pipeline is
		# off when an override is set. Even so, the focus ring is OUR
		# responsibility - the theme focus stylebox is blanked on the
		# stage path, so without this, keyboard users have no visual
		# feedback at all on an HD-override'd button.
		_apply_focus_ring()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(MIN_WIDTH, MIN_HEIGHT)
	focus_mode = Control.FOCUS_ALL
	# NOTE: stylebox blanking is now in _ready() and is GATED on the
	# presence of a stage. The original code blanked in _init; that
	# was safe then because every button had its own SubViewport, so
	# "I have a 3D mesh" was always true. The shared stage breaks
	# that invariant: a screen that has not yet been migrated to
	# the stage path (or a headless test) must keep the theme's
	# procedural moulded as the button face.


func _ready() -> void:
	_stage = _find_stage()
	_build_label()
	_build_focus_ring()
	if _stage != null:
		# Blank the theme's procedural moulded. The shared mesh IS
		# the face; drawing a Button stylebox on top of it would
		# double-paint. This is why the gating moved out of _init:
		# a no-stage button NEEDS the theme stylebox.
		_blank_styleboxes()
		_stage_handle = _stage.attach(self, _variant_prop_id())
		_attached_prop_id = _variant_prop_id()
		# Push the initial variant so the mesh starts in the right
		# colour, not the registry's default. attach() already set
		# it to "default"; this overwrites if the caller set
		# `variant` before _ready fired.
		_stage.set_prop_variant(_stage_handle, _variant_to_stage_string(_variant))
		_apply_state()
	elif hd_material_override != null:
		# Headless fallback with an override set: at least keep the
		# focus ring in sync, even though there is no 3D mesh to
		# push the override to.
		_apply_focus_ring()

	pressed.connect(_on_pressed_changed)
	toggled.connect(_on_toggled_changed)
	mouse_entered.connect(_apply_state)
	mouse_exited.connect(_apply_state)
	focus_entered.connect(_apply_state)
	focus_exited.connect(_apply_state)


# Which texture set this button wears. The legend is the identity: a
# button named DEPLOY gets btn_deploy's baked wear, grime and stamp
# placement, on the same ui_push_button.glb every other button uses.
#
# Falls back to the plain shared set for a legend with no baked variant
# (a new button, a runtime-formatted legend, a headless fixture). That
# fallback is deliberate - a button must never fail to render because
# nobody ran the generator - but ui_audit.check_button_prop_coverage()
# reports it, so the gap is visible rather than silent.
func _variant_prop_id() -> String:
	var variant_id := UIPropRegistryScript.variant_id_for_legend(legend)
	return variant_id if variant_id != "" else MESH_PROP_ID


# Re-point the stage at a different texture set when the legend changes
# after attach. Detach-then-attach rather than a stage-side swap: the
# mesh, material and host wiring are all built in attach(), and a
# partial re-point would have to duplicate that. Variant and state are
# re-pushed afterwards because a fresh attach starts at the defaults.
func _resync_prop_variant() -> void:
	if _stage == null or _stage_handle == -1:
		return
	var wanted := _variant_prop_id()
	if wanted == _attached_prop_id:
		return
	_stage.detach(_stage_handle)
	_stage_handle = _stage.attach(self, wanted)
	_attached_prop_id = wanted
	if _stage_handle != -1:
		_stage.set_prop_variant(_stage_handle, _variant_to_stage_string(_variant))
		_apply_state()


# Walk the ancestor chain for a UIPropStage. Stops at the first one
# found. Returns null on a not-yet-migrated screen, a headless test,
# or a button added directly to a Control without a stage in the
# chain. The walk is cheap (the chain is short and the predicate is
# a type check) and runs only on _ready(), so polling on resize is
# unnecessary.
func _find_stage() -> UIPropStage:
	var node: Node = get_parent()
	while node != null:
		if node is UIPropStage:
			return node
		node = node.get_parent()
	return null


# Clears every theme stylebox override so the theme's procedural
# moulded does not draw on top of the 3D mesh. Each state has its
# own stylebox, so they must all be cleared; a Button without a
# normal stylebox renders as a flat rectangle, which is exactly
# what the shared mesh wants underneath.
func _blank_styleboxes() -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())


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
# in _ready on the stage path so the 3D mesh is not double-painted -
# which also dropped the focus ring. A keyboard user has no way to see
# which button is selected without this, so it is non-optional.
const _FOCUS_RING_INSET := 2.0
const _FOCUS_RING_WIDTH := 2.0

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


# The state pipeline. One function, two backends:
#   * stage path: push a state string to the shared stage, which
#     mutates the per-handle material
#   * fallback path: no material to mutate; the focus ring is the
#     only thing the button itself owns visually
# Both paths always update the focus ring, because the focus ring
# lives on the Button and is independent of the 3D rendering.
#
# Read order is the same as the original: disabled -> pressed ->
# hover -> normal. Last writer (the first matching condition) wins.
func _apply_state() -> void:
	if _stage_handle != -1:
		_stage.set_prop_state(_stage_handle, _state_to_stage_string())
	_apply_focus_ring()
	# The fallback path does not push to a stage (there is none).
	# The Godot Button's own stylebox state swap and the audio
	# cue come through UIFeedbackScript.wire() the caller set up;
	# we are not duplicating that here.


# Returns the stage's state-string name for the current Button
# state. Pulled into a helper so the disabled/pressed/hover/normal
# precedence reads in one place. Unknown Button state (e.g. a
# future "selected") defaults to normal here and to a no-op at
# the stage - the stage warns on a state name it does not
# recognise but does not crash.
func _state_to_stage_string() -> String:
	if disabled:
		return STAGE_STATE_DISABLED
	if button_pressed:
		return STAGE_STATE_PRESSED
	# Hover: mouse over the button OR keyboard focus. The mouse
	# check matches the original (the visible hover lift should
	# only apply when the cursor is actually on the button) and
	# the focus check matches the original (a keyboard user tabs
	# to a button and expects the same lift as the cursor one).
	var hovered := get_global_rect().has_point(get_viewport().get_mouse_position()) or has_focus()
	if hovered:
		return STAGE_STATE_HOVER
	return STAGE_STATE_NORMAL


func _variant_to_stage_string(v: int) -> String:
	match v:
		Variant.DEFAULT:
			return STAGE_VARIANT_DEFAULT
		Variant.PRIMARY:
			return STAGE_VARIANT_PRIMARY
		Variant.DANGER:
			return STAGE_VARIANT_DANGER
		Variant.GHOST:
			return STAGE_VARIANT_GHOST
		Variant.COMPACT:
			return STAGE_VARIANT_COMPACT
	return STAGE_VARIANT_DEFAULT


# Sets the COMPACT height. The original code did this in
# _apply_variant; the height change is independent of the 3D
# rendering, so it is the only piece of variant handling that
# StampedButton keeps on both paths.
#
# Pre-existing bug preserved: the original sets the COMPACT height
# but does not reset it on a variant change away from COMPACT. A
# button that goes PRIMARY -> COMPACT -> DEFAULT stays at the
# COMPACT height. Out of scope for Phase 1; the call sites that
# use COMPACT are static toolbars that never change variant.
func _apply_variant_height() -> void:
	if _variant == Variant.COMPACT:
		custom_minimum_size = Vector2(custom_minimum_size.x, COMPACT_HEIGHT)


# Hidden so a Phase 3 caller can swap the visual (e.g. a hard-edged
# machine-engraved ring instead of a flat line) without reaching
# into this file.
func _apply_focus_ring() -> void:
	if _focus_ring == null:
		return
	_focus_ring.visible = has_focus() and not disabled


func _on_pressed_changed() -> void:
	_apply_state()


func _on_toggled_changed(_pressed: bool) -> void:
	_apply_state()
