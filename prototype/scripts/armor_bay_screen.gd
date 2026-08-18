extends Control
# THE ARMOR BAY - painting armor onto a hull, one facet or one side at a time.
#
# WHY THIS IS ITS OWN SCREEN rather than a mode in the Design Lab. The Lab has
# no notion of an editing mode at all: every click goes through
# module_placer._unhandled_input, which raycasts mask 7, then dispatches to a
# gizmo drag, a module selection or a placement. Adding a paint mode there means
# gating that dispatch AND drag_drop_manager AND the tweak callouts AND the
# gizmos, four separate input owners, so that a click on the hull means
# something different in each. A separate screen has no gate to get wrong.
#
# It also wants the hull STRIPPED - you are looking at armor coverage, not at a
# turret - and the Lab cannot show that without hiding real modules.
#
# MODELLED ON livery_screen.gd, which already proved the shape in this codebase:
# a full-screen workbench with a plated control column and a recessed
# SubViewport turntable. The difference is navigation. Livery is a PROFILE
# screen (your colours, across your whole force) reached from a hardwired
# main-menu button and absent from Navigation.ROUTES, so it hardcodes its way
# home and gets no breadcrumb. Armor is per-BLUEPRINT and changes the vehicle's
# stats, so it belongs on the Lab's side of the map and is a real route.
#
# THE DESIGN IT EDITS is the Lab scratch (BlueprintManager.SCRATCH_PATH), the
# same handoff the Test Range uses: the Lab writes scratch on the way out, this
# screen paints it, the Lab restores it on the way back. Painting never touches
# a saved roster entry - only an explicit Save in the Lab does that.

const Tokens = preload("res://scripts/ui_tokens.gd")
const UIShell = preload("res://scripts/ui_shell.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")
const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const StampedLabelScript = preload("res://scripts/ui_stamped_label.gd")
const ArmorPaint = preload("res://scripts/armor_paint.gd")
const ArmorPaintVisual = preload("res://scripts/armor_paint_visual.gd")
const HullFacets = preload("res://scripts/hull_facets.gd")
const HullSurface = preload("res://scripts/hull_surface.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const LiveryScript = preload("res://scripts/livery.gd")
const NavigationScript = preload("res://scripts/core/navigation.gd")

const TYPE_LABELS := {
	"armor_plating": "PLATE",
	"slat_armor": "SLAT",
	"spaced_composite": "COMPOSITE",
	"ablative_foam": "ABLATIVE",
}
# The PAINTABLE materials, in roughly ascending tier.
#
# energy_shielding is deliberately absent. A shield is a projected field, not a
# surface you can paint onto a facet, and it already exists as a placeable
# module (energy_barrier_projector) - offering it here would be a second, worse
# way to get the same effect. It stays in DamageResolver.ARMOR_TABLE because it
# is still a valid hull-global material and older designs carry it.
#
# Each material is told apart by RELIEF, not colour: livery repaints the whole
# vehicle, so a tint identifies nothing. See HullFacets.MATERIAL_RELIEF.
const MATERIAL_LABELS := {
	"hardened_steel": "HARDENED STEEL",
	"reactive_armor": "REACTIVE",
	"ablative_ceramic": "ABLATIVE CERAMIC",
	"carbon_fiber": "CARBON FIBRE",
	"titanium_plate": "TITANIUM",
}
# Shown under the swatches so the relief is legible as a deliberate signature
# rather than as noise.
const MATERIAL_HINTS := {
	"hardened_steel": "Flat rolled plate. No relief - the baseline.",
	"reactive_armor": "Staggered explosive blocks. Best against explosive, poor against kinetic.",
	"ablative_ceramic": "Small square tiles. The thermal answer.",
	"carbon_fiber": "Fine weave, barely raised. Light, but shatters under kinetic.",
	"titanium_plate": "Large panels, pronounced seams. The kinetic answer, and heavy.",
}

# Curated schemes. These are the reason the screen is usable rather than a
# 22-click chore: a player who just wants "armor the front" gets it in one press.
const PRESETS := {
	"FRONTAL": ["front"],
	"ALL-ROUND": ["front", "back", "left", "right", "top", "bottom"],
	"FLANKS": ["left", "right"],
	"TURTLE": ["front", "left", "right", "top"],
}

var _blueprint: Dictionary = {}
var _assignments: Dictionary = {}       # facet_id -> assignment dict
var _hull_type: String = ""
var _bp_manager: Node = null

var _brush_type: String = "armor_plating"
var _brush_material: String = "hardened_steel"
var _brush_thickness: float = 1.0
var _refine: bool = false               # false = paint a whole side, true = one facet
var _erase: bool = false

var _preview_root: Node3D = null
var _preview_hull: Node3D = null
var _preview_cam: Camera3D = null
var _preview_mesh: MeshInstance3D = null
var _viewport: SubViewport = null
var _vp_container: SubViewportContainer = null

var _cam_yaw: float = 0.65
# Pitch range is deliberately wider than designer_camera.gd's +/-PI/2.5. That
# clamp makes the belly reachable only at a steep angle, which is fine when you
# are mounting a turret and useless when the underside is a paintable surface.
var _cam_pitch: float = 0.38
var _cam_dist: float = 8.5
var _is_dragging: bool = false
var _drag_moved: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO

var _coverage_label: Label = null
var _side_strip: Label = null
var _weight_label: Label = null
var _status_label: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UIShell.workbench(self, "cardboard")
	var frame := UIShell.screen_frame(self)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Tokens.SPACE_MD)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(col)

	_build_header(col)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", Tokens.SPACE_LG)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	_build_controls(body)
	_build_preview(body)

	_load_design()
	_refresh_readout()


# --- Layout -----------------------------------------------------------------

func _build_header(col: VBoxContainer) -> void:
	var header := PanelContainer.new()
	header.theme_type_variation = "HeaderPanel"
	col.add_child(header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.SPACE_MD)
	header.add_child(row)

	var title_holder := Control.new()
	title_holder.custom_minimum_size = Vector2(220, 40)
	row.add_child(title_holder)
	var title: Control = StampedLabelScript.new()
	title.text = "ARMOR BAY"
	title.font_size = 26
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_holder.add_child(title)

	var sub := Label.new()
	sub.text = "Paint armor onto the chassis. Weight and cost scale with the surface you cover, so a frontal scheme is not an all-round one."
	sub.theme_type_variation = "HintLabel"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sub)

	var back := Button.new()
	back.text = "BACK TO LAB"
	back.custom_minimum_size = Vector2(150, Tokens.HIT_TARGET_MIN)
	UIFeedbackScript.wire(back)
	back.pressed.connect(_on_back)
	row.add_child(back)


func _plate(parent: Control, heading: String, min_w: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "DockPanel"
	panel.custom_minimum_size = Vector2(min_w, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", Tokens.SPACE_SM)
	panel.add_child(inner)
	var h := Label.new()
	h.text = heading
	h.theme_type_variation = "HeadingLabel"
	inner.add_child(h)
	inner.add_child(HSeparator.new())
	return inner


func _build_controls(body: HBoxContainer) -> void:
	var deck := _plate(body, "ARMOR DECK", 380)

	deck.add_child(_section_label("BRUSH"))
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", Tokens.SPACE_XS)
	deck.add_child(mode_row)
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

	deck.add_child(_section_label("TYPE"))
	deck.add_child(_swatch_grid(ArmorPaint.PAINT_TYPE_IDS, TYPE_LABELS,
		func(id: String): _brush_type = id, func(): return _brush_type))

	deck.add_child(_section_label("MATERIAL"))
	var mat_hint := Label.new()
	mat_hint.theme_type_variation = "HintLabel"
	mat_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mat_hint.text = str(MATERIAL_HINTS.get(_brush_material, ""))
	deck.add_child(_swatch_grid(MATERIAL_LABELS.keys(), MATERIAL_LABELS,
		func(id: String):
			_brush_material = id
			mat_hint.text = str(MATERIAL_HINTS.get(id, "")),
		func(): return _brush_material))
	deck.add_child(mat_hint)

	deck.add_child(_section_label("THICKNESS"))
	var thick_row := HBoxContainer.new()
	thick_row.add_theme_constant_override("separation", Tokens.SPACE_SM)
	deck.add_child(thick_row)
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

	deck.add_child(_section_label("SCHEMES"))
	var preset_grid := GridContainer.new()
	preset_grid.columns = 2
	preset_grid.add_theme_constant_override("h_separation", Tokens.SPACE_XS)
	preset_grid.add_theme_constant_override("v_separation", Tokens.SPACE_XS)
	deck.add_child(preset_grid)
	for name in PRESETS.keys():
		var b := Button.new()
		b.text = name
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
	deck.add_child(strip_all)

	deck.add_child(HSeparator.new())
	deck.add_child(_section_label("COVERAGE"))
	_coverage_label = Label.new()
	_coverage_label.text = "ARMOR 0%"
	deck.add_child(_coverage_label)
	_side_strip = Label.new()
	_side_strip.theme_type_variation = "HintLabel"
	_side_strip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	deck.add_child(_side_strip)
	_weight_label = Label.new()
	_weight_label.theme_type_variation = "HintLabel"
	deck.add_child(_weight_label)

	_status_label = Label.new()
	_status_label.theme_type_variation = "HintLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	deck.add_child(_status_label)


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


# Swatches live inside a plate well so they read as CONTENT, not as interface
# state - UI_STYLE_GUIDE 1.1 reserves signal colour for state and says so in
# terms that "must not break".
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


func _build_preview(body: HBoxContainer) -> void:
	var right := _plate(body, "CHASSIS", 520)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", Tokens.SPACE_XS)
	right.add_child(bar)
	# Preset views, because a turntable alone makes the underside fiddly to
	# reach and the underside is paintable.
	for spec in [["FRONT", 0.0, 0.0], ["REAR", PI, 0.0], ["LEFT", -PI / 2.0, 0.0],
			["RIGHT", PI / 2.0, 0.0], ["TOP", 0.0, 1.35], ["UNDER", 0.0, -1.35]]:
		var b := Button.new()
		b.text = str(spec[0])
		b.custom_minimum_size = Vector2(0, Tokens.HIT_TARGET_MIN)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIFeedbackScript.wire(b)
		b.pressed.connect(func():
			_cam_yaw = float(spec[1])
			_cam_pitch = float(spec[2])
			if is_instance_valid(_preview_hull):
				_preview_hull.rotation.y = 0.0
			_update_camera())
		bar.add_child(b)

	var well := PanelContainer.new()
	well.theme_type_variation = "InsetPanel"
	well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(well)

	_vp_container = SubViewportContainer.new()
	_vp_container.custom_minimum_size = Vector2(480, 380)
	_vp_container.stretch = true
	_vp_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vp_container.gui_input.connect(_on_preview_input)
	well.add_child(_vp_container)

	_viewport = SubViewport.new()
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp_container.add_child(_viewport)

	_preview_root = Node3D.new()
	_viewport.add_child(_preview_root)

	_preview_cam = Camera3D.new()
	_preview_root.add_child(_preview_cam)
	_update_camera()

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	key.light_energy = 1.15
	_preview_root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24.0, -128.0, 0.0)
	fill.light_energy = 0.35
	_preview_root.add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Tokens.BASE_900
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.68, 0.65, 0.58)
	e.ambient_light_energy = 0.80
	env.environment = e
	_preview_root.add_child(env)


# --- Design load / save -----------------------------------------------------

func _load_design() -> void:
	_bp_manager = BlueprintManagerScript.new()
	add_child(_bp_manager)
	_blueprint = _bp_manager.load_blueprint(BlueprintManagerScript.SCRATCH_PATH)
	if _blueprint.is_empty():
		_set_status("No design in the workshop. Build one in the Design Lab first.")
		return
	_hull_type = str(_blueprint.get("hull_type", ""))

	# reconstruct_vehicle migrates pre-v3 armor and attaches the plan, so the
	# assignments we start from are whatever the design already had - including
	# a v2 design's plates, converted.
	_rebuild_hull()
	# Pre-warm the segment cache so all subsequent paint/readout calls hit it.
	if _preview_mesh and _preview_mesh.mesh:
		HullFacets.cached_segment(_preview_mesh.mesh)
	if is_instance_valid(_preview_hull):
		for a in _preview_hull.get_meta("armor_assignments", []):
			if a is Dictionary:
				_assignments[int(a.get("facet_id", -1))] = a
	_set_status("Click the chassis to paint. SIDE covers a whole face; FACET covers one panel.")


# Rebuilds the preview with ONLY the hull and its armor. Modules are stripped
# deliberately: this screen is about coverage, and a turret in the way is one
# more thing occluding the surface you are trying to read.
func _rebuild_hull() -> void:
	if is_instance_valid(_preview_hull):
		_preview_root.remove_child(_preview_hull)
		_preview_hull.queue_free()
		_preview_hull = null
	if _blueprint.is_empty() or _bp_manager == null:
		return

	var stripped := _blueprint.duplicate(true)
	stripped["modules"] = []
	_preview_hull = _bp_manager.reconstruct_vehicle(stripped, _preview_root, true)
	if not is_instance_valid(_preview_hull):
		return
	_preview_mesh = null
	for c in _preview_hull.get_children():
		if c is MeshInstance3D and c.name != "PhysicsMesh":
			_preview_mesh = c
			break
	if _preview_mesh:
		# The precise trimesh is what makes painting land on the panel you
		# clicked: face_index is only reported for a concave shape.
		HullSurface.rebuild(_preview_hull, _preview_mesh)


func _apply_and_refresh(status: String = "") -> void:
	if not is_instance_valid(_preview_hull):
		return
	var rows := _assignments.values()
	_preview_hull.set_meta("armor_assignments", rows)
	_preview_hull.set_meta("armor_plan", ArmorPaint.build_plan(
		_hull_type, rows,
		_preview_mesh.mesh if _preview_mesh else null,
		_preview_mesh.transform if _preview_mesh else Transform3D.IDENTITY,
		str(_blueprint.get("faction", LiveryScript.PLAYER_ID))))
	if _preview_mesh:
		ArmorPaintVisual.rebuild(_preview_hull, _preview_mesh)
	_write_back()
	_refresh_readout()
	if status != "":
		_set_status(status)


func _write_back() -> void:
	if _bp_manager == null or _blueprint.is_empty():
		return
	var seg := HullFacets.cached_segment(_preview_mesh.mesh if _preview_mesh else null)
	var rows := _assignments.values()
	rows.sort_custom(func(x, y): return int(x["facet_id"]) < int(y["facet_id"]))
	_blueprint["version"] = BlueprintManagerScript.CURRENT_BLUEPRINT_VERSION
	_blueprint["armor"] = {
		"hull_type": _hull_type,
		"hull_tri_count": int(seg.get("tri_count", 0)),
		"tri_count": int(seg.get("tri_count", 0)),
		"facet_count": int(seg.get("count", 0)),
		"assignments": rows,
	}
	var f = FileAccess.open(BlueprintManagerScript.SCRATCH_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_blueprint, "\t"))
		f.close()


func _refresh_readout() -> void:
	if not is_instance_valid(_preview_hull):
		return
	var stats: Dictionary = ArmorPaint.analyze(_preview_hull)
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


# --- Painting ---------------------------------------------------------------

func _on_preset(name: String) -> void:
	if _hull_type == "":
		return
	var mesh := _preview_mesh.mesh if _preview_mesh else null
	for side in PRESETS.get(name, []):
		for fid in HullFacets.facets_for_side_mesh(mesh, str(side)):
			_paint_facet(int(fid))
	_apply_and_refresh("Applied the %s scheme." % name)


func _paint_facet(fid: int) -> void:
	if _erase:
		_assignments.erase(fid)
		return
	if _preview_mesh == null or _preview_mesh.mesh == null:
		return
	var seg := HullFacets.cached_segment(_preview_mesh.mesh)
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


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_dragging = true
				_drag_moved = false
				_last_mouse_pos = event.position
			else:
				# A click paints; a drag orbits. Distinguished by whether the
				# pointer actually moved, so orbiting never paints by accident.
				if _is_dragging and not _drag_moved:
					_paint_at(event.position)
				_is_dragging = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = clampf(_cam_dist - 0.5, 3.0, 20.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = clampf(_cam_dist + 0.5, 3.0, 20.0)
			_update_camera()
	elif event is InputEventMouseMotion and _is_dragging:
		var delta: Vector2 = event.position - _last_mouse_pos
		if delta.length() > 2.0:
			_drag_moved = true
		_last_mouse_pos = event.position
		_cam_yaw -= delta.x * 0.012
		# Wider than the Lab camera's clamp so the belly is reachable head-on.
		_cam_pitch = clampf(_cam_pitch + delta.y * 0.012, -1.45, 1.45)
		_update_camera()


func _paint_at(pos: Vector2) -> void:
	if not is_instance_valid(_preview_hull) or _preview_cam == null:
		return
	var from := _preview_cam.project_ray_origin(pos)
	var to := from + _preview_cam.project_ray_normal(pos) * 200.0
	var space := _preview_root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = HullSurface.SURFACE_COLLISION_LAYER
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var mesh := _preview_mesh.mesh if _preview_mesh else null
	var tri_index := int(hit.get("face_index", -1))
	# Live facet lookup via cached segment -- replaces the old baked map.
	var fid := HullFacets.facet_for_tri(mesh, tri_index)
	if fid < 0:
		_set_status("Could not resolve a panel there.")
		return

	if _refine:
		_paint_facet(fid)
		_apply_and_refresh("%s facet %d." % ["Stripped" if _erase else "Painted", fid])
	else:
		# Side brush: the facet's OWN side, then every facet grouped with it.
		var seg := HullFacets.cached_segment(mesh)
		var facet_sides = seg.get("facet_side", [])
		var side := str(facet_sides[fid]) if fid < facet_sides.size() else ""
		if side == "":
			return
		for f in HullFacets.facets_for_side_mesh(mesh, side):
			_paint_facet(int(f))
		_apply_and_refresh("%s the %s." % ["Stripped" if _erase else "Painted", side])


func _update_camera() -> void:
	if _preview_cam == null:
		return
	var cp := Vector3(
		_cam_dist * cos(_cam_pitch) * sin(_cam_yaw),
		_cam_dist * sin(_cam_pitch) + 0.35,
		_cam_dist * cos(_cam_pitch) * cos(_cam_yaw))
	_preview_cam.look_at_from_position(cp, Vector3(0.0, 0.35, 0.0), Vector3.UP)


func _on_back() -> void:
	_write_back()
	var router = get_node_or_null("/root/SceneRouter")
	if router:
		router.goto(NavigationScript.ROUTES[NavigationScript.LAB]["scene"])
	else:
		get_tree().change_scene_to_file(NavigationScript.ROUTES[NavigationScript.LAB]["scene"])
