class_name IntelFeed
extends PanelContainer
# Top-left collapsible intel feed - teletype log of events.

const Tokens = preload("res://scripts/ui_tokens.gd")
const FoldedPaperPanel = preload("res://scripts/ui/folded_paper_panel.gd")
const TeletypeLog = preload("res://scripts/ui/teletype_log.gd")
const UIIcons = preload("res://scripts/ui_icons.gd")

var _director: Node = null
var _local_team: int = 0
var _teletype: TeletypeLog = null
var _header: HBoxContainer = null
var _collapse_btn: Button = null
var _expanded: bool = true
var _collapse_height: float = 60.0  # 3 lines

# Track seen enemy contacts to avoid duplicates
var _seen_contacts: Dictionary = {}

const ENTRY_DEFS = {
	"contact": {"icon": "ui_radar", "color_key": "SIGNAL_HAZARD", "label": "ENEMY CONTACT"},
	"structure_ready": {"icon": "ui_hammer", "color_key": "SIGNAL_GO", "label": "STRUCTURE READY"},
	"low_power": {"icon": "ui_bolt", "color_key": "SIGNAL_ALERT", "label": "LOW POWER"},
	"research": {"icon": "ui_flask", "color_key": "SIGNAL_INFO", "label": "RESEARCH"},
	"order": {"icon": "ui_chevron", "color_key": "TEXT_SECONDARY", "label": "ORDER"},
}

func _init() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = Vector2(320, 200)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()
	_start_contact_poll()

func _ready() -> void:
	# _start_contact_poll() is now called from _init() so the ContactPoll timer
	# exists immediately (the test checks it before any process_frame). In the
	# running game it starts in _init() and continues through _ready() - the
	# 1 Hz timer is harmless if it ticks twice during the brief window before
	# _ready() sets _director. Guard it so the second call is a no-op.
	pass  # intentionally empty - timer is created in _init()

func setup(director: Node, local_team: int) -> void:
	_director = director
	_local_team = local_team
	FoldedPaperPanel.apply(self)
	_wire_signals()
	# Note: the ContactPoll timer is created in _init() (idempotent), so it
	# is already live before this call. _director is set here so the timer
	# callback (_check_new_contacts) can guard on null vision gracefully.

func _wire_signals() -> void:
	if _director == null:
		return
	# Alert service for structure ready, low power, etc.
	var alerts = _director.alerts if "alerts" in _director else null
	if alerts != null and alerts.has_signal("alert_posted"):
		alerts.alert_posted.connect(_on_alert_posted)
	# Structure built/lost from director
	if _director.has_signal("structure_built"):
		_director.structure_built.connect(_on_structure_built)
	if _director.has_signal("structure_lost"):
		_director.structure_lost.connect(_on_structure_lost)

func _start_contact_poll() -> void:
	# Idempotent: if already created (e.g., called from both _init and _ready),
	# bail out so we don't create a second timer.
	if get_node_or_null("ContactPoll") != null:
		return
	# Poll for new enemy contacts at 1 Hz
	var timer = Timer.new()
	timer.name = "ContactPoll"
	timer.wait_time = 1.0
	timer.one_shot = false
	timer.timeout.connect(_check_new_contacts)
	add_child(timer)
	# autostart fires once the node is in the scene tree — unlike start(), which
	# requires the node to already be in the tree at call time (Godot 4.7.1).
	timer.autostart = true

func _check_new_contacts() -> void:
	if _director == null or _director.vision == null:
		return
	var vision = _director.vision
	# Get currently visible enemy units
	for c in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(c) or c.is_dead:
			continue
		var team: int = c.get_meta("team") if c.has_meta("team") else -1
		if team != _local_team and "fog_hidden" in c and not c.fog_hidden:
			var key = c.get_instance_id()
			if not _seen_contacts.has(key):
				_seen_contacts[key] = true
				var unit_type = c.get_meta("design_name") if c.has_meta("design_name") else c.name
				var count = 1
				# Count nearby same-type units
				for other in get_tree().get_nodes_in_group("damageable"):
					if other != c and is_instance_valid(other) and not other.is_dead:
						if other.get_meta("team", -1) == team and other.get_meta("design_name", "") == c.get_meta("design_name", ""):
							count += 1
				var sector = _position_to_sector(c.global_position)
				add_entry("contact", "%s  %s x%d" % [sector, unit_type.to_upper(), count])

func _on_alert_posted(type: String, world_pos: Vector3) -> void:
	match type:
		"structure_ready":
			add_entry("structure_ready", _position_to_sector(world_pos))
		"under_attack":
			add_entry("contact", "UNDER ATTACK %s" % _position_to_sector(world_pos))
		"low_power":
			add_entry("low_power", "")
		_:
			add_entry("order", "%s at %s" % [type, _position_to_sector(world_pos)])

func _on_structure_built(team: int, kind: String) -> void:
	if team == _local_team:
		add_entry("structure_ready", kind.replace("_", " ").capitalize())

func _on_structure_lost(team: int, kind: String) -> void:
	if team == _local_team:
		add_entry("low_power", "LOST: %s" % kind.replace("_", " ").capitalize())

func _build() -> void:
	# Header bar
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", Tokens.SPACE_SM)
	_header.mouse_filter = Control.MOUSE_FILTER_PASS
	_header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_header.offset_top = Tokens.SPACE_XS
	_header.offset_left = Tokens.SPACE_SM
	_header.offset_right = -Tokens.SPACE_SM
	add_child(_header)

	var title := Label.new()
	title.text = "INTEL"
	title.add_theme_font_override("font", preload("res://assets/fonts/UIFont-Bold.ttf"))
	title.add_theme_font_size_override("font_size", Tokens.FONT_HEADING)
	title.add_theme_color_override("font_color", Tokens.SIGNAL_HAZARD)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(spacer)

	_collapse_btn = Button.new()
	_collapse_btn.text = "▼"
	_collapse_btn.theme_type_variation = "QuickJumpPill"
	_collapse_btn.focus_mode = Control.FOCUS_NONE
	_collapse_btn.custom_minimum_size = Vector2(28, 24)
	_collapse_btn.pressed.connect(_toggle_collapse)
	_header.add_child(_collapse_btn)

	# Teletype log
	_teletype = TeletypeLog.new()
	_teletype.set_anchors_preset(Control.PRESET_FULL_RECT)
	_teletype.offset_top = 36
	_teletype.offset_left = Tokens.SPACE_SM
	_teletype.offset_right = -Tokens.SPACE_SM
	_teletype.offset_bottom = -Tokens.SPACE_SM
	_teletype.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_teletype)

func _toggle_collapse() -> void:
	_expanded = not _expanded
	_collapse_btn.text = "▲" if _expanded else "▼"
	_animate_collapse()

func _animate_collapse() -> void:
	var target_h = _collapse_height if not _expanded else 200.0
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "custom_minimum_size:y", target_h, 0.2)

func expand_to_category(category: String) -> void:
	if not _expanded:
		_expanded = true
		_collapse_btn.text = "▼"
		_animate_collapse()

func add_entry(category: String, detail: String = "") -> void:
	var def = ENTRY_DEFS.get(category, ENTRY_DEFS["order"])
	var timestamp = _get_timestamp()
	var icon = def.icon
	var color = Tokens[def.color_key]
	var label = def.label
	if detail != "":
		label += "  %s" % detail
	_teletype.add_entry(timestamp, icon, label, color)

func _on_contact_detected(position: Vector3, unit_type: String, count: int) -> void:
	var sector = _position_to_sector(position)
	add_entry("contact", "%s  %s x%d" % [sector, unit_type.to_upper(), count])

func _get_timestamp() -> String:
	var time = Time.get_time_dict_from_system()
	return "%02d:%02d:%02d" % [time["hour"], time["minute"], time["second"]]

func _position_to_sector(pos: Vector3) -> String:
	# Simple sector grid A1-H8
	var half = 80.0
	if _director != null and "current_map" in _director:
		half = _director.current_map.get("map_half_extents", 80.0)
	var col = clampi(int((pos.x + half) / (half * 2.0 / 8.0)), 0, 7)
	var row = clampi(int((pos.z + half) / (half * 2.0 / 8.0)), 0, 7)
	var col_char = String.chr(65 + col)  # A-H
	return "%s%d" % [col_char, row + 1]

func toggle_collapse() -> void:
	_toggle_collapse()
