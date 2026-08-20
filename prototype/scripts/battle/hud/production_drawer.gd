class_name ProductionDrawer
extends PanelContainer
# Slide-up production drawer from tab bar.
# Accordion lists per tier, ports ProductionHUD logic.

const Tokens = preload("res://scripts/ui_tokens.gd")
const FoldedPaperPanel = preload("res://scripts/ui/folded_paper_panel.gd")
const BuildingCatalog = preload("res://scripts/battle/economy/building_catalog.gd")
const DesignCosting = preload("res://scripts/battle/economy/design_costing.gd")
const ResourceCatalog = preload("res://scripts/battle/economy/resource_catalog.gd")
const UIFeedback = preload("res://scripts/ui_feedback.gd")

const QUEUE_LABELS = {
	"light": "LIGHT",
	"medium": "MEDIUM",
	"heavy": "HEAVY",
	"building": "STRUCTURES",
	"defense": "DEFENCES",
}

var _director: Node = null
var _container: VBoxContainer = null
var _tier_sections: Dictionary = {}
var _item_buttons: Array = []
var _current_tier: String = ""
var current_tier: String:
	get: return _current_tier
var _expanded: bool = false

const MAX_HEIGHT_RATIO := 0.5
const ANIM_DURATION := 0.22
const LIST_MAX_HEIGHT := 320.0

func _init() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	custom_minimum_size = Vector2(0, 0)
	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = false
	_build()

func setup(director: Node) -> void:
	_director = director
	FoldedPaperPanel.apply(self)
	var shader := load("res://shaders/crt_warmup.gdshader") as Shader
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("progress", 0.0)
		material = mat

func _build() -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = Tokens.SPACE_SM
	scroll.offset_left = Tokens.SPACE_SM
	scroll.offset_right = -Tokens.SPACE_SM
	scroll.offset_bottom = -Tokens.SPACE_SM
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and (
				event.button_index == MOUSE_BUTTON_WHEEL_UP
				or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			scroll.accept_event())
	add_child(scroll)

	_container = VBoxContainer.new()
	_container.add_theme_constant_override("separation", Tokens.SPACE_SM)
	_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_container)

	for queue_name in BuildingCatalog.QUEUES:
		_build_tier_section(queue_name)

func _build_tier_section(queue_name: String) -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", Tokens.SPACE_XS)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_container.add_child(section)

	# Header with progress
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", Tokens.SPACE_SM)
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	section.add_child(header)

	var label := Label.new()
	label.text = QUEUE_LABELS[queue_name]
	label.add_theme_font_override("font", preload("res://assets/fonts/UIFont-Bold.ttf"))
	label.add_theme_font_size_override("font_size", Tokens.FONT_HEADING)
	label.add_theme_color_override("font_color", Tokens.TEXT_PRIMARY)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)

	var progress := ProgressBar.new()
	progress.name = "Progress"
	progress.custom_minimum_size = Vector2(100, 8)
	progress.show_percentage = false
	progress.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Tokens.PHOSPHOR_AMBER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Tokens.PHOSPHOR_AMBER_DIM
	progress.add_theme_stylebox_override("fill", fill)
	progress.add_theme_stylebox_override("background", bg)
	header.add_child(progress)

	var depth_label := Label.new()
	depth_label.name = "Depth"
	depth_label.add_theme_font_override("font", preload("res://assets/fonts/MonoFont-Regular.ttf"))
	depth_label.add_theme_font_size_override("font_size", Tokens.FONT_MICRO)
	depth_label.add_theme_color_override("font_color", Tokens.TEXT_SECONDARY)
	header.add_child(depth_label)

	# Collapsible list
	var list_container := VBoxContainer.new()
	list_container.name = "List"
	list_container.add_theme_constant_override("separation", Tokens.SPACE_XS)
	list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_container.visible = false
	section.add_child(list_container)

	_tier_sections[queue_name] = {
		"section": section,
		"header": header,
		"progress": progress,
		"depth_label": depth_label,
		"list": list_container,
		"visible": false,
	}

func open_tier(queue_name: String) -> void:
	if not _tier_sections.has(queue_name):
		return
	_current_tier = queue_name
	_expanded = true
	visible = true
	_animate_open()
	_rebuild_tier(queue_name)

	for qn in _tier_sections:
		var data = _tier_sections[qn]
		var open = (qn == queue_name)
		data["visible"] = open
		data["list"].visible = open
		if open:
			data["header"].add_theme_color_override("font_color", Tokens.SIGNAL_HAZARD)
		else:
			data["header"].add_theme_color_override("font_color", Tokens.TEXT_PRIMARY)

func close_tier(queue_name: String) -> void:
	if not _tier_sections.has(queue_name):
		return
	if _current_tier == queue_name:
		_current_tier = ""
		_expanded = false
		_animate_close()

func rebuild_tier(queue_name: String) -> void:
	if not _tier_sections.has(queue_name):
		return
	_rebuild_tier(queue_name)

func _rebuild_tier(queue_name: String) -> void:
	var data = _tier_sections[queue_name]
	var list = data["list"]

	for child in list.get_children():
		child.queue_free()

	var items = _items_for(queue_name)
	if items.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = "HintLabel"
		empty.text = "NOTHING AVAILABLE"
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		list.add_child(empty)
	else:
		for item in items:
			_add_item_button(list, queue_name, item)

	# Update header progress/depth
	var status = _director.production.status(_director.PLAYER_TEAM, queue_name)
	var contributors = _director.production.contributor_count(_director.PLAYER_TEAM, queue_name)
	data["progress"].value = status.get("progress", 0.0)
	data["depth_label"].text = "x%d" % status.get("depth", 0)
	if contributors <= 0:
		data["progress"].value = 0.0
		data["depth_label"].text = "NO SOURCE"

	list.custom_minimum_size = Vector2(0, minf(LIST_MAX_HEIGHT, 40.0 * float(maxi(1, items.size()))))

func re_evaluate_gates() -> void:
	if _director == null:
		return
	for entry in _item_buttons:
		var btn: Button = entry["btn"]
		var item: Dictionary = entry["item"]
		var queue_name: String = entry["queue_name"]
		var design: Dictionary = item.get("blueprint", {})
		var missing: Array = []
		if not design.is_empty() or item.get("structure", false):
			missing = _director.production.missing_required_buildings(
				_director.PLAYER_TEAM, design)
		var was_blocked: bool = btn.disabled
		var is_blocked: bool = not missing.is_empty()
		if was_blocked == is_blocked:
			continue
		if is_blocked:
			for c in btn.pressed.get_connections():
				btn.pressed.disconnect(c["callable"])
			var names: Array = []
			for kind in missing:
				names.append(_format_building_name(str(kind)))
			btn.disabled = true
			btn.tooltip_text = "Requires: %s" % ", ".join(names)
		else:
			btn.disabled = false
			btn.tooltip_text = ""
			btn.pressed.connect(func(): _enqueue(queue_name, item))

func _items_for(queue_name: String) -> Array:
	if queue_name == BuildingCatalog.QUEUE_BUILDING:
		var out: Array = []
		for kind in BuildingCatalog.buildable_kinds():
			out.append({
				"kind": kind,
				"label": _format_building_name(kind).to_upper(),
				"cost": ResourceCatalog.credits_from_materials(Vector2i(
					BuildingCatalog.get_stat(kind, "cost_metal", 0),
					BuildingCatalog.get_stat(kind, "cost_crystal", 0))),
				"time": BuildingCatalog.get_stat(kind, "build_time", 10.0),
				"structure": true,
			})
		return out
	if queue_name == BuildingCatalog.QUEUE_DEFENSE:
		var defences: Array = []
		for design in _director.roster:
			if not _director.is_defence_design(design):
				continue
			var dcost: int = DesignCosting.blueprint_cost(design)
			defences.append({
				"blueprint": design,
				"kind": "defense",
				"label": str(design.get("name", "DEFENCE")).to_upper(),
				"cost": dcost,
				"time": DesignCosting.build_time_for_cost(dcost),
				"structure": true,
				"missing": _director.production.missing_required_buildings(
					_director.PLAYER_TEAM, design),
			})
		return defences
	var out: Array = []
	for design in _director.roster:
		if _director.is_defence_design(design):
			continue
		if DesignCosting.queue_for_design(design) != queue_name:
			continue
		var cost: int = DesignCosting.blueprint_cost(design)
		out.append({
			"blueprint": design,
			"label": str(design.get("name", "DESIGN")).to_upper(),
			"cost": cost,
			"time": DesignCosting.build_time_for_cost(cost),
			"structure": false,
			"missing": _director.production.missing_required_buildings(
				_director.PLAYER_TEAM, design),
		})
	return out

static func _format_building_name(kind: String) -> String:
	return kind.replace("_", " ").capitalize()

func _add_item_button(parent: Control, queue_name: String, item: Dictionary) -> void:
	var btn := Button.new()
	var time_s := int(item["time"])
	btn.text = "%s  %d cr  %ds" % [item["label"], item["cost"], time_s]
	btn.custom_minimum_size = Vector2(0, 32)
	btn.focus_mode = Control.FOCUS_NONE
	btn.theme_type_variation = "QueueItemButton"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.tooltip_text = "Click: queue 1\nShift+Click: queue 5\nCost: %d cr  Time: %ds" % [item["cost"], time_s]
	parent.add_child(btn)
	UIFeedback.wire(btn)

	var missing: Array = item.get("missing", [])
	if not missing.is_empty():
		var names: Array = []
		for kind in missing:
			names.append(_format_building_name(str(kind)))
		btn.disabled = true
		btn.tooltip_text = "Requires: %s" % ", ".join(names)
	else:
		btn.button_down.connect(_on_item_button_down.bind(btn, queue_name, item))

	_item_buttons.append({"btn": btn, "queue_name": queue_name, "item": item})

func _on_item_button_down(btn: Button, queue_name: String, item: Dictionary) -> void:
	var count := 1
	if Input.is_key_pressed(KEY_SHIFT):
		count = 5
	for i in count:
		_enqueue_one(queue_name, item)

func _enqueue(queue_name: String, item: Dictionary) -> void:
	_enqueue_one(queue_name, item)

func _enqueue_one(queue_name: String, item: Dictionary) -> void:
	var team: int = _director.PLAYER_TEAM
	if item["structure"]:
		_begin_rally_placement(queue_name, item)
	else:
		_director.production.enqueue_unit(
			team, item["blueprint"], item["cost"], item["time"], queue_name)

signal rally_placement_started()
signal rally_placement_completed(pos: Vector3)
signal rally_placement_cancelled()

var _pending_rally: Dictionary = {}
var _pending_rally_queue: String = ""

func is_rally_pending() -> bool:
	return not _pending_rally.is_empty()

func _begin_rally_placement(queue_name: String, item: Dictionary) -> void:
	_pending_rally = item
	_pending_rally_queue = queue_name
	rally_placement_started.emit()

func complete_rally(pos: Vector3) -> void:
	var item := _pending_rally
	var queue_name := _pending_rally_queue
	_pending_rally = {}
	_pending_rally_queue = ""
	if item.is_empty():
		return
	var team: int = _director.PLAYER_TEAM
	_director.production.enqueue_structure(
		team, queue_name, item["kind"], item["cost"], item["time"],
		item.get("blueprint", {}), pos)
	rally_placement_completed.emit(pos)

func cancel_rally() -> void:
	_pending_rally = {}
	_pending_rally_queue = ""
	rally_placement_cancelled.emit()

func _animate_open() -> void:
	var max_h = get_viewport_rect().size.y * MAX_HEIGHT_RATIO
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "custom_minimum_size:y", max_h, ANIM_DURATION)
	if material != null and material is ShaderMaterial:
		tween.tween_property(material, "shader_parameter/progress", 1.0, ANIM_DURATION)

func _animate_close() -> void:
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "custom_minimum_size:y", 0, ANIM_DURATION)
	if material != null and material is ShaderMaterial:
		tween.tween_property(material, "shader_parameter/progress", 0.0, ANIM_DURATION)
	tween.finished.connect(_on_close_finished)

func _on_close_finished() -> void:
	if not _expanded:
		visible = false