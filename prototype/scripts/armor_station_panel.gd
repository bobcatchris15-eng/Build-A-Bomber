extends Control
# The Armor Station's LEFT-SIDE TOOLKIT. A permanent vertical panel that
# replaces the parts bin when the player enters the paint workspace.
#
# NOT A SEPARATE SCREEN. The MainLab scene is the only one the player
# ever sees for both build AND paint workflows. The toolbar's "PAINT
# STATION" button plays a horizontal pan_blur sweep; behind that blur,
# three things swap simultaneously:
#   1. UI_PartsMenu hides, UI_ArmorStationPanel shows (this file)
#   2. LabEnvironment's cutting mat hides, PaintStationEnvironment's
#      wood desktop + paint supplies show
#   3. The module_placer strips the hull's modules and accepts paint
#      input on the bare hull instead
# The reverse pan undoes all three. The player reads it as a single
# "turn to the workbench" gesture rather than three discrete changes.
#
# WHY NO PREVIEW SUBVIEWPORT. The old armor_bay_screen.gd built its own
# SubViewport with a stripped hull, dedicated camera rig, and the wood
# environment. The redesign drops all of that: the MainLab SubViewport
# is the only one, the same Hull node the placer manages, the same
# Camera3D. The only thing that changes is which environment renders
# below it and which inputs are active.
#
# The paint itself is still armor_paint_visual.gd doing the same work it
# has always done - the plan is on the hull's `armor_plan` meta, the
# visual reads it. The only NEW thing is the click-to-paint path: this
# panel installs an _unhandled_input on MainLab while paint mode is
# active, raycasts the camera into the world, and dispatches to
# _paint_at() exactly the way armor_bay_screen.gd used to on its
# preview SubViewport.

signal back_requested

const Tokens = preload("res://scripts/ui_tokens.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")
const StampedLabelScript = preload("res://scripts/ui_stamped_label.gd")
const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const ArmorPaint = preload("res://scripts/armor_paint.gd")
const ArmorPaintVisual = preload("res://scripts/armor_paint_visual.gd")
const HullFacets = preload("res://scripts/hull_facets.gd")
const HullSurface = preload("res://scripts/hull_surface.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const LiveryScript = preload("res://scripts/livery.gd")
const PanTransitionOverlayScript = preload("res://scripts/pan_transition.gd")

const TYPE_LABELS := {
	"armor_plating": "PLATE",
	"slat_armor": "SLAT",
	"spaced_composite": "COMPOSITE",
	"ablative_foam": "ABLATIVE",
}
const MATERIAL_LABELS := {
	"hardened_steel": "HARDENED STEEL",
	"reactive_armor": "REACTIVE",
	"ablative_ceramic": "ABLATIVE CERAMIC",
	"carbon_fiber": "CARBON FIBRE",
	"titanium_plate": "TITANIUM",
}
const MATERIAL_HINTS := {
	"hardened_steel": "Flat rolled plate. No relief - the baseline.",
	"reactive_armor": "Staggered explosive blocks. Best against explosive, poor against kinetic.",
	"ablative_ceramic": "Small square tiles. The thermal answer.",
	"carbon_fiber": "Fine weave, barely raised. Light, but shatters under kinetic.",
	"titanium_plate": "Large panels, pronounced seams. The kinetic answer, and heavy.",
}
const PRESETS := {
	"FRONTAL": ["front"],
	"ALL-ROUND": ["front", "back", "left", "right", "top", "bottom"],
	"FLANKS": ["left", "right"],
	"TURTLE": ["front", "left", "right", "top"],
}

# The wood theme constants are local to this script. See armor_bay_screen.gd's
# old wood styling for the rationale; the same palette carries over so the
# new panel looks like the same workstation the player entered the old way.
const _WOOD_PANEL_BG := Color(0.180, 0.140, 0.092)
const _WOOD_BORDER := Color(0.290, 0.225, 0.140)
const _WOOD_BASE := Color(0.115, 0.092, 0.062)

# External handles wired in by MainLab / the placer via enter()/exit().
# The placer is responsible for stripping modules and routing clicks
# while paint mode is active. This panel only knows about paint state;
# it does not know the placer exists, beyond the call signatures below.
var _hull: Node3D = null
var _placer: Node = null
var _bp_manager: Node = null

# Paint state
var _assignments: Dictionary = {}        # facet_id -> assignment dict
var _brush_type: String = "armor_plating"
var _brush_material: String = "hardened_steel"
var _brush_thickness: float = 1.0
var _refine: bool = false                # false = whole side, true = one facet
var _erase: bool = false

# Saved/restored state on enter/exit so the build workflow comes back
# exactly as the player left it. The placer REPARENTS the modules to
# a holding node on entry and re-parents them back to the hull on
# exit; we hold the references across the session so the round trip
# is identity-preserving (no queue_free, no re-instantiation).
var _modules_before_strip: Array = []

# Coverage labels
var _coverage_label: Label = null
var _side_strip: Label = null
var _weight_label: Label = null
var _status_label: Label = null

# Public state
var is_paint_mode: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Built in the same shape as the parts menu (left vertical dock) so
	# when the swap happens, the player's eye doesn't have to re-find the
	# controls.
	_build_header()
	_build_dock()


# Public API. Called by the placer when the toolbar's "PAINT STATION"
# button is pressed (forward pan) and by the same call site when the
# player clicks "BACK TO WORKBENCH" (reverse pan).
#
# enter() takes a hull node (the live StaticBody3D in MainLab) and
# the placer (for module strip + restore and click routing).
func enter(hull: Node3D, placer: Node) -> void:
	_hull = hull
	_placer = placer
	_bp_manager = get_node_or_null("/root/MainLab/BlueprintManager")
	is_paint_mode = true
	# Tell the placer to back off its own _unhandled_input. The placer
	# reads this on every input event and returns early if true. The
	# panel's _unhandled_input then runs unimpeded.
	if _placer and "paint_mode_active" in _placer:
		_placer.paint_mode_active = true
	# Capture the live module list, then ask the placer to detach them
	# from the hull. We hold the references across the session and the
	# placer re-parents them back on exit. The capture must succeed
	# before the strip so we can re-add in the same order.
	if _placer and _placer.has_method("capture_modules_for_paint"):
		_modules_before_strip = _placer.capture_modules_for_paint()
	if _placer and _placer.has_method("strip_modules_for_paint"):
		_placer.strip_modules_for_paint(_modules_before_strip)
	# Pre-warm the segment cache so the first click doesn't pay the
	# cost of the live facet computation.
	if _hull:
		var mesh_instance := _find_hull_mesh(_hull)
		if mesh_instance and mesh_instance.mesh:
			HullFacets.cached_segment(mesh_instance.mesh)
		# Load any existing assignments from the hull's meta so a saved
		# paint plan comes back.
		for a in _hull.get_meta("armor_assignments", []):
			if a is Dictionary:
				_assignments[int(a.get("facet_id", -1))] = a
	_refresh_readout()


func exit() -> void:
	is_paint_mode = false
	# Hand input back to the placer BEFORE restoring modules, so the
	# placer's _unhandled_input is re-enabled for any click during the
	# restore.
	if _placer and "paint_mode_active" in _placer:
		_placer.paint_mode_active = false
	# Persist the paint plan back to the hull and the scratch file so
	# the placer's next save_scratch() picks it up.
	_persist_assignments()
	# Re-parent the modules back to the hull. The placer handles the
	# actual reparent + state re-eval; we just hand back the list.
	if _placer and _placer.has_method("restore_modules_after_paint"):
		_placer.restore_modules_after_paint(_modules_before_strip)
	# Free any held references so a re-enter() doesn't double-capture.
	_modules_before_strip.clear()
	_hull = null
	_placer = null


# Public, called by the placer so this panel can stay out of the
# placer's input-dispatch logic. We do the raycast + paint here.
func _unhandled_input(event: InputEvent) -> void:
	if not is_paint_mode:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_paint_at_world(event.position)
			get_viewport().set_input_as_handled()


# --- Layout -----------------------------------------------------------------

func _build_header() -> void:
	# Reserved for future header text above the dock (workstation
	# name, save status, etc.). The toolbar owns the screen title
	# ("PAINT STATION") so this is a placeholder. Kept as a function
	# so the future addition is one-line.
	pass


func _build_dock() -> void:
	var dock := PanelContainer.new()
	dock.add_theme_stylebox_override("panel", _make_wood_panel_style())
	# Left-edge anchor + full height, narrower than the parts menu.
	# DOCK_LEFT_INSET mirrors parts_menu.gd's number (20) so the swap
	# keeps the left edge stationary.
	var dlc := Control.new()
	dlc.set_anchors_preset(Control.PRESET_TOP_LEFT)
	dlc.offset_left = 20.0
	dlc.offset_top = 76.0
	dlc.offset_right = 340.0
	dlc.offset_bottom = 0.0
	dlc.anchor_bottom = 1.0
	dlc.add_child(dock)
	add_child(dlc)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", Tokens.SPACE_SM)
	dock.add_child(inner)

	# Back-to-workbench button at the top of the dock. The toolbar
	# listener that triggered the swap binds to the "back_requested"
	# signal; the panel doesn't know about the placer or the pan
	# transition, it just signals intent.
	var back := Button.new()
	back.text = "BACK TO WORKBENCH"
	back.custom_minimum_size = Vector2(0, Tokens.HIT_TARGET_MIN)
	UIFeedbackScript.wire(back)
	back.pressed.connect(func():
		if not is_paint_mode:
			return
		back_requested.emit())
	inner.add_child(back)
	inner.add_child(HSeparator.new())

	# Section: brush
	inner.add_child(_section_label("BRUSH"))
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", Tokens.SPACE_XS)
	inner.add_child(mode_row)
	var side_btn := _toggle(mode_row, "SIDE", not _refine)
	var facet_btn := _toggle(mode_row, "FACET", _refine)
	side_btn.pressed.connect(func():
		_refine = false
		side_btn.button_pressed = true
		facet_btn.button_pressed = false)
	facet_btn.pressed.connect(func():
		_refine = true
		facet_btn.button_pressed = true
		side_btn.button_pressed = false)

	var erase := Button.new()
	erase.text = "ERASE"
	erase.toggle_mode = true
	erase.custom_minimum_size = Vector2(0, Tokens.HIT_TARGET_MIN)
	erase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIFeedbackScript.wire(erase)
	erase.toggled.connect(func(p: bool): _erase = p)
	mode_row.add_child(erase)

	# Section: type
	inner.add_child(_section_label("TYPE"))
	inner.add_child(_swatch_grid(ArmorPaint.PAINT_TYPE_IDS, TYPE_LABELS,
		func(id: String): _brush_type = id, func(): return _brush_type))

	# Section: material
	inner.add_child(_section_label("MATERIAL"))
	var mat_hint := Label.new()
	mat_hint.theme_type_variation = "HintLabel"
	mat_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mat_hint.text = str(MATERIAL_HINTS.get(_brush_material, ""))
	inner.add_child(_swatch_grid(MATERIAL_LABELS.keys(), MATERIAL_LABELS,
		func(id: String):
			_brush_material = id
			mat_hint.text = str(MATERIAL_HINTS.get(id, "")),
		func(): return _brush_material))
	inner.add_child(mat_hint)

	# Section: thickness
	inner.add_child(_section_label("THICKNESS"))
	var thick_row := HBoxContainer.new()
	thick_row.add_theme_constant_override("separation", Tokens.SPACE_SM)
	inner.add_child(thick_row)
	var thick := HSlider.new()
	thick.min_value = 0.5
	thick.max_value = 3.0
	thick.step = 0.25
	thick.value = _brush_thickness
	thick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thick_row.add_child(thick)
	var thick_val := Label.new()
	thick_val.text = "1.00x"
	thick_row.add_child(thick_val)
	thick.value_changed.connect(func(v: float):
		_brush_thickness = v
		thick_val.text = "%.2fx" % v)

	# Section: schemes
	inner.add_child(_section_label("SCHEMES"))
	var preset_grid := GridContainer.new()
	preset_grid.columns = 2
	preset_grid.add_theme_constant_override("h_separation", Tokens.SPACE_XS)
	preset_grid.add_theme_constant_override("v_separation", Tokens.SPACE_XS)
	inner.add_child(preset_grid)
	for name in PRESETS.keys():
		var b := Button.new()
		b.text = str(name)
		b.custom_minimum_size = Vector2(0, Tokens.HIT_TARGET_MIN)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIFeedbackScript.wire(b)
		b.pressed.connect(_on_preset.bind(str(name)))
		preset_grid.add_child(b)

	var strip_all := Button.new()
	strip_all.text = "STRIP ALL ARMOR"
	strip_all.custom_minimum_size = Vector2(0, Tokens.HIT_TARGET_MIN)
	UIFeedbackScript.wire(strip_all)
	strip_all.pressed.connect(func():
		_assignments.clear()
		_apply_and_refresh("Stripped."))
	inner.add_child(strip_all)

	inner.add_child(HSeparator.new())
	inner.add_child(_section_label("COVERAGE"))
	_coverage_label = Label.new()
	_coverage_label.text = "ARMOR 0%"
	inner.add_child(_coverage_label)
	_side_strip = Label.new()
	_side_strip.theme_type_variation = "HintLabel"
	_side_strip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_side_strip)
	_weight_label = Label.new()
	_weight_label.theme_type_variation = "HintLabel"
	inner.add_child(_weight_label)

	_status_label = Label.new()
	_status_label.theme_type_variation = "HintLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_status_label)


func _make_wood_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _WOOD_PANEL_BG
	sb.border_color = _WOOD_BORDER
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 2
	sb.content_margin_left = Tokens.SPACE_SM
	sb.content_margin_top = Tokens.SPACE_SM
	sb.content_margin_right = Tokens.SPACE_SM
	sb.content_margin_bottom = Tokens.SPACE_SM
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	return sb


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "HeadingLabel"
	return l


func _toggle(parent: Control, text: String, on: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.custom_minimum_size = Vector2(0, Tokens.HIT_TARGET_MIN)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIFeedbackScript.wire(b)
	parent.add_child(b)
	return b


func _swatch_grid(ids: Array, labels: Dictionary, on_pick: Callable, get_current: Callable) -> Control:
	var well := PanelContainer.new()
	well.theme_type_variation = "InsetPanel"
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", Tokens.SPACE_XS)
	grid.add_theme_constant_override("v_separation", Tokens.SPACE_XS)
	well.add_child(grid)
	var buttons := []
	for id in ids:
		var b := Button.new()
		b.text = str(labels.get(id, id))
		b.toggle_mode = true
		b.button_pressed = (str(id) == str(get_current.call()))
		b.custom_minimum_size = Vector2(0, Tokens.HIT_TARGET_MIN)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIFeedbackScript.wire(b)
		grid.add_child(b)
		buttons.append(b)
		b.pressed.connect(func():
			on_pick.call(str(id))
			for other in buttons:
				other.button_pressed = (other == b))
	return well


# --- Paint logic ------------------------------------------------------------

func _paint_at_world(screen_pos: Vector2) -> void:
	if not is_instance_valid(_hull):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 200.0
	var space := get_viewport().get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = HullSurface.SURFACE_COLLISION_LAYER
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var mesh_instance := _find_hull_mesh(_hull)
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	var tri_index := int(hit.get("face_index", -1))
	var fid := HullFacets.facet_for_tri(mesh_instance.mesh, tri_index)
	if fid < 0:
		return

	if _refine:
		_paint_facet(fid)
		_apply_and_refresh("%s facet %d." % ["Stripped" if _erase else "Painted", fid])
	else:
		var seg := HullFacets.cached_segment(mesh_instance.mesh)
		var facet_sides = seg.get("facet_side", [])
		var side := str(facet_sides[fid]) if fid < facet_sides.size() else ""
		if side == "":
			return
		for f in HullFacets.facets_for_side_mesh(mesh_instance.mesh, side):
			_paint_facet(int(f))
		_apply_and_refresh("%s the %s." % ["Stripped" if _erase else "Painted", side])


func _paint_facet(fid: int) -> void:
	if _erase:
		_assignments.erase(fid)
		return
	if not is_instance_valid(_hull):
		return
	var mesh_instance := _find_hull_mesh(_hull)
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	var seg := HullFacets.cached_segment(mesh_instance.mesh)
	var normals: PackedVector3Array = seg.get("normal", PackedVector3Array())
	var centroids: PackedVector3Array = seg.get("centroid", PackedVector3Array())
	var areas: PackedFloat32Array = seg.get("area", PackedFloat32Array())
	var facet_sides = seg.get("facet_side", [])
	if fid < 0 or fid >= normals.size():
		return
	_assignments[fid] = {
		"facet_id": fid,
		"side": str(facet_sides[fid]) if fid < facet_sides.size() else "",
		"type_id": _brush_type,
		"material": _brush_material,
		"thickness": _brush_thickness,
		"normal": {"x": normals[fid].x, "y": normals[fid].y, "z": normals[fid].z},
		"centroid": {"x": centroids[fid].x, "y": centroids[fid].y, "z": centroids[fid].z},
		"area": float(areas[fid]) if fid < areas.size() else 0.0,
	}


func _on_preset(name: String) -> void:
	if not is_instance_valid(_hull):
		return
	var mesh_instance := _find_hull_mesh(_hull)
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	var mesh := mesh_instance.mesh
	for side in PRESETS.get(name, []):
		for fid in HullFacets.facets_for_side_mesh(mesh, str(side)):
			_paint_facet(int(fid))
	_apply_and_refresh("Applied the %s scheme." % name)


func _apply_and_refresh(status: String = "") -> void:
	if not is_instance_valid(_hull):
		return
	var mesh_instance := _find_hull_mesh(_hull)
	var mesh := mesh_instance.mesh if mesh_instance else null
	var xform := mesh_instance.transform if mesh_instance else Transform3D.IDENTITY
	var rows := _assignments.values()
	if mesh_instance:
		_hull.set_meta("armor_assignments", rows)
		_hull.set_meta("armor_plan", ArmorPaint.build_plan(
			"", rows, mesh, xform, str(_bp_manager.get_meta("player_faction", LiveryScript.PLAYER_ID) if _bp_manager else LiveryScript.PLAYER_ID)))
		ArmorPaintVisual.rebuild(_hull, mesh_instance)
	_persist_assignments()
	_refresh_readout()
	if status != "":
		_set_status(status)


func _persist_assignments() -> void:
	# The placer's save_scratch() reads current_blueprint, which it
	# maintains from a separate code path. The paint plan is on the
	# hull's `armor_assignments` and `armor_plan` meta (set by
	# _apply_and_refresh). When the player clicks "BACK TO WORKBENCH"
	# the toolbar calls save_scratch() AFTER the panel exits, so any
	# save_scratch() path here would race with the toolbar's call.
	#
	# The only contract this function has: ensure the hull's meta
	# reflects the live _assignments dict. _apply_and_refresh
	# already does that, so this is a no-op safety net.
	if not is_instance_valid(_hull):
		return
	_hull.set_meta("armor_assignments", _assignments.values())
	# Refresh the telemetry rail in real-time so the player sees updated
	# HP/weight/cost as they paint, rather than only after jumping back
	# to the design lab.
	var main_lab = get_parent()
	if is_instance_valid(main_lab):
		var rail: Control = main_lab.get_node_or_null("UI_StatBlock")
		if is_instance_valid(rail):
			rail.update_stats(_hull)


func _refresh_readout() -> void:
	if not is_instance_valid(_hull):
		return
	var stats: Dictionary = ArmorPaint.analyze(_hull)
	_coverage_label.text = "ARMOR %d%%" % int(round(float(stats["coverage"]) * 100.0))
	var parts := []
	for s in ArmorPaint.SIDES:
		parts.append("%s %d" % [s.substr(0, 1).to_upper(),
			int(round(float(stats["side_coverage"][s]) * 100.0))])
	var weakest := str(stats["weakest_side"])
	_side_strip.text = " · ".join(parts) + ("    weakest: %s" % weakest if weakest != "" else "")
	_weight_label.text = "+%.0f kg   %d metal / %d crystal" % [
		float(stats["weight"]), int(stats["cost_metal"]), int(stats["cost_crystal"])]


func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg


# --- Module strip / restore (delegated) ------------------------------------

# The placer owns the live module list. enter() calls
# capture_modules_for_paint() and strip_modules_for_paint(); exit() calls
# restore_modules_after_paint(). This panel only holds the captured
# reference list across the session.


# --- Helpers ----------------------------------------------------------------

func _find_hull_mesh(hull: Node3D) -> MeshInstance3D:
	# The MainLab Hull is a StaticBody3D. Its child MeshInstance3D is the
	# chassis (excluding the "PhysicsMesh" name collision proxy).
	for c in hull.get_children():
		if c is MeshInstance3D and c.name != "PhysicsMesh":
			return c
	return null