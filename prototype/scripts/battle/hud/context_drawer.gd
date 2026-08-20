class_name ContextDrawer
extends PanelContainer
# Slide-up context drawer on unit selection.
# Tabbed: STATUS / WEAPONS / TARGETING / MOVE / SPECIAL

const Tokens = preload("res://scripts/ui_tokens.gd")
const FoldedPaperPanel = preload("res://scripts/ui/folded_paper_panel.gd")
const CRTReadout = preload("res://scripts/ui/crt_readout.gd")
const UIFeedback = preload("res://scripts/ui_feedback.gd")
const UIIcons = preload("res://scripts/ui_icons.gd")

signal subgroup_selected(design_id: String, units: Array)
signal primary_changed(primary_design_id: String, primary_units: Array)

var _director: Node = null
var _selection_service = null

var _tabs_container: HBoxContainer = null
var _stack: VBoxContainer = null
var _tab_buttons: Dictionary = {}
var _tab_pages: Dictionary = {}

var _groups: Dictionary = {}
var _primary_design_id: String = ""
var _pinned: bool = false
var _expanded: bool = false

var _anim_tween: Tween = null

const MAX_HEIGHT_RATIO := 0.4
const ANIM_DURATION := 0.22

func _init() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	custom_minimum_size = Vector2(0, 0)
	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = false
	_build()

func setup(director: Node) -> void:
	_director = director
	_selection_service = director.selection
	FoldedPaperPanel.apply(self)
	# CRT warmup shader for expand animation
	var shader := load("res://shaders/crt_warmup.gdshader") as Shader
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("progress", 0.0)
		material = mat

func _build() -> void:
	# Tab bar
	_tabs_container = HBoxContainer.new()
	_tabs_container.add_theme_constant_override("separation", Tokens.SPACE_SM)
	_tabs_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_tabs_container.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_tabs_container.offset_top = Tokens.SPACE_XS
	_tabs_container.offset_left = Tokens.SPACE_SM
	_tabs_container.offset_right = -Tokens.SPACE_SM
	add_child(_tabs_container)

	var tab_defs := [
		{"id": "status", "label": "STATUS", "icon": "ui_status"},
		{"id": "weapons", "label": "WEAPONS", "icon": "ui_cannon"},
		{"id": "targeting", "label": "TARGETING", "icon": "ui_crosshair"},
		{"id": "move", "label": "MOVE", "icon": "ui_move"},
		{"id": "special", "label": "SPECIAL", "icon": "ui_lightning"},
	]

	for def in tab_defs:
		var btn := Button.new()
		btn.name = "Tab_%s" % def.id
		btn.text = def.label
		btn.theme_type_variation = "DrawerTab"
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 32)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIFeedback.wire(btn, "select")
		btn.pressed.connect(_on_tab_pressed.bind(def.id))
		_tabs_container.add_child(btn)
		_tab_buttons[def.id] = btn

	# Container for tab pages (manual visibility management)
	_stack = VBoxContainer.new()
	_stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stack.offset_top = 40
	_stack.offset_left = Tokens.SPACE_SM
	_stack.offset_right = -Tokens.SPACE_SM
	_stack.offset_bottom = -Tokens.SPACE_SM
	_stack.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_stack)

	# Build tab pages
	_build_status_page()
	_build_weapons_page()
	_build_targeting_page()
	_build_move_page()
	_build_special_page()

	# Default to STATUS
	_switch_tab("status")

func _build_status_page() -> void:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", Tokens.SPACE_SM)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.add_child(page)

	# Header row: design name + count + health bar
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", Tokens.SPACE_MD)
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	page.add_child(header)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.add_theme_font_override("font", preload("res://assets/fonts/UIFont-Bold.ttf"))
	name_label.add_theme_font_size_override("font_size", Tokens.FONT_HEADING)
	name_label.add_theme_color_override("font_color", Tokens.TEXT_PRIMARY)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	var health_bar := ProgressBar.new()
	health_bar.name = "HealthBar"
	health_bar.custom_minimum_size = Vector2(120, 8)
	health_bar.show_percentage = false
	health_bar.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Tokens.SIGNAL_GO
	var bg := StyleBoxFlat.new()
	bg.bg_color = Tokens.SIGNAL_GO_DIM
	health_bar.add_theme_stylebox_override("fill", fill)
	health_bar.add_theme_stylebox_override("background", bg)
	header.add_child(health_bar)

	# Order + stance row
	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", Tokens.SPACE_LG)
	meta_row.mouse_filter = Control.MOUSE_FILTER_PASS
	page.add_child(meta_row)

	var order_label := Label.new()
	order_label.name = "OrderLabel"
	order_label.add_theme_font_override("font", preload("res://assets/fonts/MonoFont-Regular.ttf"))
	order_label.add_theme_font_size_override("font_size", Tokens.FONT_SMALL)
	order_label.add_theme_color_override("font_color", Tokens.TEXT_SECONDARY)
	meta_row.add_child(order_label)

	var stance_label := Label.new()
	stance_label.name = "StanceLabel"
	stance_label.add_theme_font_override("font", preload("res://assets/fonts/MonoFont-Regular.ttf"))
	stance_label.add_theme_font_size_override("font_size", Tokens.FONT_SMALL)
	stance_label.add_theme_color_override("font_color", Tokens.TEXT_SECONDARY)
	meta_row.add_child(stance_label)

	# Quick-jump pills
	var pills_row := HBoxContainer.new()
	pills_row.add_theme_constant_override("separation", Tokens.SPACE_SM)
	pills_row.mouse_filter = Control.MOUSE_FILTER_PASS
	page.add_child(pills_row)

	var pill_defs := ["weapons", "targeting", "move", "special"]
	for pid in pill_defs:
		var pill := Button.new()
		pill.name = "Pill_%s" % pid
		pill.text = pid.to_upper()
		pill.theme_type_variation = "QuickJumpPill"
		pill.focus_mode = Control.FOCUS_NONE
		pill.custom_minimum_size = Vector2(0, 24)
		pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		UIFeedback.wire(pill, "select")
		pill.pressed.connect(_on_pill_pressed.bind(pid))
		pills_row.add_child(pill)

	_tab_pages["status"] = page

func _build_weapons_page() -> void:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", Tokens.SPACE_SM)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.add_child(page)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)

	var container := VBoxContainer.new()
	container.name = "WeaponGroups"
	container.add_theme_constant_override("separation", Tokens.SPACE_SM)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(container)

	page.name = "WeaponsPage"
	_tab_pages["weapons"] = page

func _build_targeting_page() -> void:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", Tokens.SPACE_SM)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.add_child(page)

	# ROE radio buttons
	var roe_label := Label.new()
	roe_label.text = "RULES OF ENGAGEMENT"
	roe_label.add_theme_font_override("font", preload("res://assets/fonts/UIFont-Bold.ttf"))
	roe_label.add_theme_font_size_override("font_size", Tokens.FONT_SMALL)
	roe_label.add_theme_color_override("font_color", Tokens.TEXT_SECONDARY)
	page.add_child(roe_label)

	var roe_group := HBoxContainer.new()
	roe_group.name = "ROEGroup"
	roe_group.add_theme_constant_override("separation", Tokens.SPACE_MD)
	roe_group.mouse_filter = Control.MOUSE_FILTER_PASS
	page.add_child(roe_group)

	var roe_options := ["HOLD", "RETURN FIRE", "FIRE AT WILL"]
	var roe_bg := ButtonGroup.new()
	for opt in roe_options:
		var rb := CheckButton.new()
		rb.text = opt
		rb.theme_type_variation = "DrawerTab"
		rb.button_group = roe_bg
		roe_group.add_child(rb)

	# Engagement ranges per weapon group (placeholder)
	var ranges_label := Label.new()
	ranges_label.text = "ENGAGEMENT RANGES"
	ranges_label.add_theme_font_override("font", preload("res://assets/fonts/UIFont-Bold.ttf"))
	ranges_label.add_theme_font_size_override("font_size", Tokens.FONT_SMALL)
	ranges_label.add_theme_color_override("font_color", Tokens.TEXT_SECONDARY)
	page.add_child(ranges_label)

	_tab_pages["targeting"] = page

func _build_move_page() -> void:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", Tokens.SPACE_SM)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.add_child(page)

	var speed_label := Label.new()
	speed_label.name = "SpeedLabel"
	speed_label.add_theme_font_override("font", preload("res://assets/fonts/MonoFont-Regular.ttf"))
	speed_label.add_theme_font_size_override("font_size", Tokens.FONT_SMALL)
	speed_label.add_theme_color_override("font_color", Tokens.TEXT_SECONDARY)
	page.add_child(speed_label)

	var formation_label := Label.new()
	formation_label.text = "FORMATION"
	formation_label.add_theme_font_override("font", preload("res://assets/fonts/UIFont-Bold.ttf"))
	formation_label.add_theme_font_size_override("font_size", Tokens.FONT_SMALL)
	formation_label.add_theme_color_override("font_color", Tokens.TEXT_SECONDARY)
	page.add_child(formation_label)

	var form_group := HBoxContainer.new()
	form_group.name = "FormGroup"
	form_group.add_theme_constant_override("separation", Tokens.SPACE_MD)
	form_group.mouse_filter = Control.MOUSE_FILTER_PASS
	page.add_child(form_group)

	var formations := ["LINE", "WEDGE", "COLUMN", "BOX", "ECHELON"]
	var form_bg := ButtonGroup.new()
	for f in formations:
		var rb := CheckButton.new()
		rb.text = f
		rb.theme_type_variation = "DrawerTab"
		rb.button_group = form_bg
		form_group.add_child(rb)

	_tab_pages["move"] = page

func _build_special_page() -> void:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", Tokens.SPACE_SM)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.add_child(page)

	var abilities_container := VBoxContainer.new()
	abilities_container.name = "Abilities"
	abilities_container.add_theme_constant_override("separation", Tokens.SPACE_SM)
	abilities_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(abilities_container)

	_tab_pages["special"] = page

func _on_tab_pressed(pressed: bool, tab_id: String) -> void:
	if pressed:
		_switch_tab(tab_id)

func _on_pill_pressed(tab_id: String) -> void:
	_switch_tab(tab_id)

func _switch_tab(tab_id: String) -> void:
	for id in _tab_buttons:
		var btn = _tab_buttons[id]
		btn.set_pressed_no_signal(id == tab_id)
	for id in _tab_pages:
		_tab_pages[id].visible = (id == tab_id)

func update_selection(units: Array) -> void:
	_groups.clear()

	for u in units:
		if u == null or not is_instance_valid(u):
			continue
		var design_id := _get_unit_design_id(u)
		var design_name := _get_unit_design_name(u)
		if not _groups.has(design_id):
			_groups[design_id] = {
				"id": design_id,
				"name": design_name,
				"units": [],
				"priority": _compute_design_priority(u),
				"max_hp": 0.0,
				"current_hp": 0.0,
			}
		_groups[design_id]["units"].append(u)
		var hp: float = u.get("health") if "health" in u else 100.0
		var max_hp: float = u.get("max_health") if "max_health" in u else 100.0
		_groups[design_id]["current_hp"] += hp
		_groups[design_id]["max_hp"] += max_hp

	_determine_primary_group()
	_rebuild_status_page()
	_rebuild_weapons_page()
	_rebuild_targeting_page()
	_rebuild_move_page()
	_rebuild_special_page()

	if not _groups.is_empty() and not _expanded:
		expand()

func _get_unit_design_id(unit: Node) -> String:
	if unit.has_meta("blueprint_id"):
		return String(unit.get_meta("blueprint_id"))
	if "blueprint_id" in unit and unit.blueprint_id != "":
		return String(unit.blueprint_id)
	if unit.has_meta("design_id"):
		return String(unit.get_meta("design_id"))
	return unit.name

func _get_unit_design_name(unit: Node) -> String:
	if unit.has_meta("blueprint_name"):
		return String(unit.get_meta("blueprint_name"))
	if "blueprint_name" in unit and unit.blueprint_name != "":
		return String(unit.blueprint_name)
	if unit.has_meta("design_name"):
		return String(unit.get_meta("design_name"))
	return _get_unit_design_id(unit).capitalize()

func _compute_design_priority(unit: Node) -> int:
	if unit.has_meta("has_active_abilities") and bool(unit.get_meta("has_active_abilities")):
		return 100
	if unit.has_meta("is_harvester") and bool(unit.get_meta("is_harvester")):
		return 10
	if unit.has_meta("is_combat") and bool(unit.get_meta("is_combat")):
		return 50
	for child in unit.get_children():
		if child.has_meta("module_data"):
			var d = child.get_meta("module_data")
			var type_id: String = String(d.get("type_id", ""))
			if "cannon" in type_id or "rocket" in type_id or "laser" in type_id or "gun" in type_id:
				return 50
	return 25

func _determine_primary_group() -> void:
	if _groups.is_empty():
		_primary_design_id = ""
		primary_changed.emit("", [])
		return

	var best_id := ""
	var best_priority := -1
	for id in _groups.keys():
		var p: int = _groups[id]["priority"]
		if p > best_priority:
			best_priority = p
			best_id = id

	_primary_design_id = best_id
	primary_changed.emit(_primary_design_id, _groups[_primary_design_id]["units"])

func _rebuild_status_page() -> void:
	var page = _tab_pages["status"]
	if page == null:
		return

	var name_label = page.find_child("NameLabel")
	var health_bar = page.find_child("HealthBar")
	var order_label = page.find_child("OrderLabel")
	var stance_label = page.find_child("StanceLabel")

	if _groups.is_empty():
		name_label.text = "NO SELECTION"
		health_bar.value = 0.0
		order_label.text = "ORDER: —"
		stance_label.text = "STANCE: —"
		return

	# Show primary design
	var primary_data = _groups[_primary_design_id]
	var total_units = 0
	for g in _groups.values():
		total_units += g["units"].size()

	name_label.text = "%s (x%d)" % [primary_data["name"], total_units]
	if total_units > 1:
		name_label.add_theme_color_override("font_color", Tokens.SIGNAL_HAZARD)
	else:
		name_label.add_theme_color_override("font_color", Tokens.TEXT_PRIMARY)

	var max_hp = maxf(primary_data["max_hp"], 1.0)
	var cur_hp = clampf(primary_data["current_hp"], 0.0, max_hp)
	health_bar.max_value = max_hp
	health_bar.value = cur_hp

	# Get order/stance from primary unit
	var primary_unit = primary_data["units"][0]
	if primary_unit != null and is_instance_valid(primary_unit):
		var order_name = "IDLE"
		if "current_order_name" in primary_unit:
			order_name = str(primary_unit.current_order_name)
		elif "current_order" in primary_unit and primary_unit.current_order != null:
			if "name" in primary_unit.current_order:
				order_name = primary_unit.current_order.name
			else:
				order_name = str(primary_unit.current_order)
		order_label.text = "ORDER: %s" % order_name

		var stance_name = "HOLD"
		if "stance" in primary_unit:
			stance_name = str(primary_unit.stance)
		stance_label.text = "STANCE: %s" % stance_name

func _rebuild_weapons_page() -> void:
	var page = _tab_pages["weapons"]
	if page == null:
		return
	var container = page.find_child("WeaponGroups")
	if container == null:
		return
	
	for child in container.get_children():
		child.queue_free()
	
	if _groups.is_empty():
		var empty = Label.new()
		empty.theme_type_variation = "HintLabel"
		empty.text = "NO SELECTION"
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(empty)
		return
	
	# Show weapons for primary design
	var primary_data = _groups[_primary_design_id]
	var primary_unit = primary_data["units"][0]
	if primary_unit == null or not is_instance_valid(primary_unit):
		return
	
	# Get weapon groups from unit
	var weapon_groups = []
	if primary_unit.has_method("get_weapon_groups"):
		weapon_groups = primary_unit.get_weapon_groups()
	
	if weapon_groups.is_empty():
		var none = Label.new()
		none.theme_type_variation = "HintLabel"
		none.text = "NO WEAPONS"
		none.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(none)
		return
	
	for wg in weapon_groups:
		var group_box := VBoxContainer.new()
		group_box.add_theme_constant_override("separation", 2)
		group_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.add_child(group_box)
		
		# Header
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", Tokens.SPACE_SM)
		header.mouse_filter = Control.MOUSE_FILTER_PASS
		group_box.add_child(header)
		
		var name_label := Label.new()
		name_label.text = wg.get("name", "WEAPON")
		name_label.add_theme_font_override("font", preload("res://assets/fonts/UIFont-Bold.ttf"))
		name_label.add_theme_font_size_override("font_size", Tokens.FONT_SMALL)
		name_label.add_theme_color_override("font_color", Tokens.TEXT_PRIMARY)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(name_label)
		
		var range_label := Label.new()
		range_label.add_theme_font_override("font", preload("res://assets/fonts/MonoFont-Regular.ttf"))
		range_label.add_theme_font_size_override("font_size", Tokens.FONT_MICRO)
		range_label.add_theme_color_override("font_color", Tokens.TEXT_SECONDARY)
		range_label.text = "%dm" % wg.get("range", 0)
		header.add_child(range_label)
		
		# Ammo bar
		var ammo_current = wg.get("ammo_current", 0)
		var ammo_max = wg.get("ammo_max", 1)
		var ammo_bar := ProgressBar.new()
		ammo_bar.custom_minimum_size = Vector2(0, 6)
		ammo_bar.show_percentage = false
		ammo_bar.max_value = ammo_max
		ammo_bar.value = ammo_current
		var fill := StyleBoxFlat.new()
		fill.bg_color = Tokens.PHOSPHOR_AMBER
		var bg := StyleBoxFlat.new()
		bg.bg_color = Tokens.PHOSPHOR_AMBER_DIM
		ammo_bar.add_theme_stylebox_override("fill", fill)
		ammo_bar.add_theme_stylebox_override("background", bg)
		group_box.add_child(ammo_bar)
		
		var ammo_text := Label.new()
		ammo_text.add_theme_font_override("font", preload("res://assets/fonts/MonoFont-Regular.ttf"))
		ammo_text.add_theme_font_size_override("font_size", Tokens.FONT_MICRO)
		ammo_text.add_theme_color_override("font_color", Tokens.TEXT_SECONDARY)
		ammo_text.text = "AMMO: %d/%d" % [ammo_current, ammo_max]
		group_box.add_child(ammo_text)
		
		# Status
		var status_label := Label.new()
		status_label.add_theme_font_override("font", preload("res://assets/fonts/MonoFont-Regular.ttf"))
		status_label.add_theme_font_size_override("font_size", Tokens.FONT_MICRO)
		var status = wg.get("status", "READY")
		if status == "RELOADING":
			status_label.add_theme_color_override("font_color", Tokens.SIGNAL_HAZARD)
			status_label.text = "RELOADING %.1fs" % wg.get("reload_time", 0.0)
		elif status == "JAMMED":
			status_label.add_theme_color_override("font_color", Tokens.SIGNAL_ALERT)
			status_label.text = "JAMMED"
		else:
			status_label.add_theme_color_override("font_color", Tokens.SIGNAL_GO)
			status_label.text = "READY"
		group_box.add_child(status_label)

func _rebuild_targeting_page() -> void:
	var page = _tab_pages["targeting"]
	if page == null:
		return
	
	# Update ROE buttons based on primary unit
	var primary_data = _groups[_primary_design_id] if _groups.has(_primary_design_id) else null
	if primary_data == null:
		return
	var primary_unit = primary_data["units"][0]
	if primary_unit == null or not is_instance_valid(primary_unit):
		return
	
	# Find ROE radio buttons and update
	var roe_group = page.find_child("ROEGroup")
	if roe_group != null:
		var current_roe = "HOLD"
		if "stance" in primary_unit:
			current_roe = str(primary_unit.stance)
		for child in roe_group.get_children():
			if child is CheckButton:
				child.set_pressed_no_signal(child.text == current_roe)
	
	# Engagement ranges - placeholder for now
	# Would need weapon-specific range sliders

func _rebuild_move_page() -> void:
	var page = _tab_pages["move"]
	if page == null:
		return
	
	var primary_data = _groups[_primary_design_id] if _groups.has(_primary_design_id) else null
	if primary_data == null:
		return
	var primary_unit = primary_data["units"][0]
	if primary_unit == null or not is_instance_valid(primary_unit):
		return
	
	# Speed label
	var speed_label = page.find_child("SpeedLabel")
	if speed_label != null and primary_unit.has_method("get_max_speed"):
		var max_speed = primary_unit.get_max_speed()
		var current_speed = primary_unit.get_current_speed() if primary_unit.has_method("get_current_speed") else max_speed
		speed_label.text = "SPEED: %.0f/%.0f km/h" % [current_speed, max_speed]
	
	# Formation buttons
	var form_group = page.find_child("FormGroup")
	if form_group != null:
		var current_form = "LINE"
		if "formation" in primary_unit:
			current_form = str(primary_unit.formation)
		for child in form_group.get_children():
			if child is CheckButton:
				child.set_pressed_no_signal(child.text == current_form)

func _rebuild_special_page() -> void:
	var page = _tab_pages["special"]
	if page == null:
		return
	
	var abilities_container = page.find_child("Abilities")
	if abilities_container == null:
		return
	
	for child in abilities_container.get_children():
		child.queue_free()
	
	if _groups.is_empty():
		return
	
	var primary_data = _groups[_primary_design_id]
	var primary_unit = primary_data["units"][0]
	if primary_unit == null or not is_instance_valid(primary_unit):
		return
	
	# Get abilities from unit
	var abilities = []
	if primary_unit.has_method("get_abilities"):
		abilities = primary_unit.get_abilities()
	
	if abilities.is_empty():
		var none = Label.new()
		none.theme_type_variation = "HintLabel"
		none.text = "NO SPECIAL ABILITIES"
		none.mouse_filter = Control.MOUSE_FILTER_IGNORE
		abilities_container.add_child(none)
		return
	
	for ability in abilities:
		var btn := Button.new()
		btn.text = "%s (%ds)" % [ability.get("name", "ABILITY"), ability.get("cooldown", 0)]
		btn.theme_type_variation = "QueueItemButton"
		btn.custom_minimum_size = Vector2(0, 36)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIFeedback.wire(btn)
		
		var ready = ability.get("ready", true)
		if not ready:
			btn.disabled = true
			btn.tooltip_text = "Cooldown: %.1fs" % ability.get("cooldown_remaining", 0.0)
		else:
			btn.pressed.connect(func(): _activate_ability(ability))
		
		abilities_container.add_child(btn)

func _activate_ability(ability: Dictionary) -> void:
	if _director != null and _director.has_method("activate_ability"):
		_director.activate_ability(_primary_design_id, ability)

func expand() -> void:
	if _expanded:
		return
	_expanded = true
	visible = true
	_animate_open()

func collapse() -> void:
	if not _expanded:
		return
	_expanded = false
	_animate_close()

func toggle_pin() -> void:
	_pinned = not _pinned

func cycle_tab(direction: int) -> void:
	var tabs := ["status", "weapons", "targeting", "move", "special"]
	var current_idx := tabs.find(_get_current_tab())
	var next_idx := (current_idx + direction) % tabs.size()
	if next_idx < 0:
		next_idx += tabs.size()
	_switch_tab(tabs[next_idx])

func _get_current_tab() -> String:
	for id in _tab_buttons:
		var btn = _tab_buttons[id]
		if btn.button_pressed:
			return id
	return "status"

func _animate_open() -> void:
	if _anim_tween != null:
		_anim_tween.kill()
	var max_h = get_viewport_rect().size.y * MAX_HEIGHT_RATIO
	_anim_tween = create_tween()
	_anim_tween.set_ease(Tween.EASE_OUT)
	_anim_tween.set_trans(Tween.TRANS_CUBIC)
	_anim_tween.tween_property(self, "custom_minimum_size:y", max_h, ANIM_DURATION)
	if material != null and material is ShaderMaterial:
		_anim_tween.tween_property(material, "shader_parameter/progress", 1.0, ANIM_DURATION)

func _animate_close() -> void:
	if _anim_tween != null:
		_anim_tween.kill()
	_anim_tween = create_tween()
	_anim_tween.set_ease(Tween.EASE_IN)
	_anim_tween.set_trans(Tween.TRANS_CUBIC)
	_anim_tween.tween_property(self, "custom_minimum_size:y", 0, ANIM_DURATION)
	if material != null and material is ShaderMaterial:
		_anim_tween.tween_property(material, "shader_parameter/progress", 0.0, ANIM_DURATION)
	_anim_tween.finished.connect(_on_close_finished)

func _on_close_finished() -> void:
	if not _expanded and not _pinned:
		visible = false
		_groups.clear()
		_rebuild_status_page()
