class_name HUDAlertLog
extends VBoxContainer
# Top-right event log. Transient by design.
#
# WHAT THIS REPLACES AND WHY. intel_feed.gd was a collapsible teletype panel,
# always on screen, that printed every structure built, every structure lost and
# every new contact into a scrolling log with a timestamp and a sector reference.
# The information was right and the framing was wrong: a permanent log is a thing
# you read, and the player is not reading during a fight. It also polled for new
# contacts on its own timer, in parallel with VisionService already knowing.
#
# So: no panel when there is nothing to say, entries that expire, and a click
# that takes you to where it happened. An alert whose only purpose is to be
# noticed does not need to persist after it has been noticed.
#
# THE ONE THING THAT IS NOT TRANSIENT is "under attack". That is the alert a
# player must not miss, so it holds the top slot and reasserts itself rather than
# scrolling away under construction chatter.

const Style = preload("res://scripts/hud/hud_style.gd")
const Icons = preload("res://scripts/hud/hud_icons.gd")

const MAX_ENTRIES := 5
const LIFETIME := 9.0
const FADE_TAIL := 1.5
# Repeat suppression. Ten harvesters finishing at once is one event, and losing
# the same base to sustained fire posts every hit.
const DEDUPE_WINDOW := 4.0

signal jump_requested(world_pos: Vector3)

var _director: Node = null
var _local_team: int = 0
var _entries: Array = []       # [{row, t, key}]
var _recent: Dictionary = {}   # key -> age


func _init() -> void:
	name = "AlertLog"
	custom_minimum_size = Vector2(300, 0)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", Style.SP_XS)
	# The container is a pass-through; the rows themselves take clicks. So a
	# gap between alerts is not a dead zone over the battlefield.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(director: Node, local_team: int) -> void:
	_director = director
	_local_team = local_team
	var alerts = director.alerts if "alerts" in director else null
	if alerts != null and alerts.has_signal("alert_posted"):
		alerts.alert_posted.connect(_on_alert_posted)
	if director.has_signal("structure_built"):
		director.structure_built.connect(_on_structure_built)
	if director.has_signal("structure_lost"):
		director.structure_lost.connect(_on_structure_lost)
	var production = director.production if "production" in director else null
	if production != null and production.has_signal("structure_ready"):
		production.structure_ready.connect(_on_structure_ready)


# --- Sources ----------------------------------------------------------------

func _on_alert_posted(type: String, world_pos: Vector3) -> void:
	var icon := "alert"
	var color := Style.WARN
	var text := type.replace("_", " ").to_upper()
	if type.contains("attack"):
		icon = "alert"
		color = Style.BAD
		text = "UNDER ATTACK"
	elif type.contains("contact") or type.contains("spotted"):
		icon = "contact"
		color = Style.WARN
		text = "ENEMY CONTACT"
	elif type.contains("complete") or type.contains("ready"):
		icon = "ready"
		color = Style.OK
	post(text, icon, color, world_pos)


func _on_structure_built(team: int, kind: String) -> void:
	if team != _local_team:
		return
	post("%s ONLINE" % str(kind).replace("_", " ").to_upper(), "ready", Style.OK)


func _on_structure_lost(team: int, kind: String) -> void:
	if team != _local_team:
		return
	post("%s LOST" % str(kind).replace("_", " ").to_upper(), "alert", Style.BAD)


func _on_structure_ready(team: int, _queue: String, job: Dictionary) -> void:
	if team != _local_team:
		return
	post("%s READY TO SITE" % str(job.get("label", "STRUCTURE")).to_upper(),
		"ready", Style.OK)


# --- Posting ----------------------------------------------------------------

func post(text: String, icon: String = "alert", color: Color = Style.WARN,
		world_pos = null) -> void:
	if _recent.has(text):
		return
	_recent[text] = 0.0

	var row := _make_row(text, icon, color, world_pos)
	add_child(row)
	move_child(row, 0)
	_entries.push_front({"row": row, "t": 0.0})

	while _entries.size() > MAX_ENTRIES:
		var oldest: Dictionary = _entries.pop_back()
		if is_instance_valid(oldest["row"]):
			oldest["row"].queue_free()


func _make_row(text: String, icon: String, color: Color, world_pos) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 26)
	Style.style_button(b, color)
	# The edge carries the severity, not the fill: a wall of coloured blocks in
	# the corner of the screen competes with the battlefield for attention.
	var normal := Style.panel_box(true, color)
	b.add_theme_stylebox_override("normal", normal)
	if world_pos != null:
		b.tooltip_text = "Click to jump there"
		b.pressed.connect(func(): jump_requested.emit(world_pos))
	else:
		# No location to jump to. Made non-interactive by dropping mouse input
		# rather than by `disabled` - a disabled Button renders greyed out, and
		# most alerts (structure built, structure lost) carry no position, so
		# disabling them would dim the majority of the log for no reason.
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_right = -6
	h.add_theme_constant_override("separation", Style.SP_SM)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	h.add_child(Icons.rect(icon, 14, color))
	var lbl := Style.label(text, Style.SZ_MICRO, Style.TEXT)
	lbl.clip_text = true
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(lbl)
	return b


# --- Ageing -----------------------------------------------------------------

func refresh(delta: float) -> void:
	for key in _recent.keys():
		_recent[key] += delta
		if _recent[key] > DEDUPE_WINDOW:
			_recent.erase(key)

	if _entries.is_empty():
		return
	var survivors: Array = []
	for e in _entries:
		e["t"] += delta
		var row: Control = e["row"]
		if not is_instance_valid(row):
			continue
		if e["t"] >= LIFETIME:
			row.queue_free()
			continue
		# Fade only over the tail. Fading from the moment it appears makes a
		# fresh alert look like an old one.
		var remaining: float = LIFETIME - e["t"]
		row.modulate.a = 1.0 if remaining > FADE_TAIL else remaining / FADE_TAIL
		survivors.append(e)
	_entries = survivors


func clear_all() -> void:
	for e in _entries:
		if is_instance_valid(e["row"]):
			e["row"].queue_free()
	_entries.clear()
	_recent.clear()
