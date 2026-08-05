class_name ProductionHUD
extends Control
# The two ways into the five production queues.
#
# CHRIS'S MODEL: "one global tier per production type (Heavy, Medium, Light,
# Building, Defense), accessible both from a hovering toolbox for that build
# queue, and via radial menu by clicking on one of the contributing
# manufactories."
#
# So there are two entry points and ONE state. Both read and write
# ProductionService; neither owns a queue. That is the property worth protecting:
# the old build bar kept its own idea of what was queued, in parallel with the
# real queue, and they drifted whenever a factory died mid-build.
#
# The toolbox is a UIDock holding one collapsible tier per queue - the same
# two-level shape as the Design Lab's parts catalogue, so the two screens read as
# the same kind of object. The dock, the tier headers, the feedback wiring and
# the material language are all existing components; nothing here invents chrome.

const UIDockScript = preload("res://scripts/ui_dock.gd")
const UIRadialScript = preload("res://scripts/ui_radial_menu.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const BuildingCatalogScript = preload("res://scripts/battle/economy/building_catalog.gd")
const DesignCostingScript = preload("res://scripts/battle/economy/design_costing.gd")

const QUEUE_LABELS := {
	"light": "LIGHT",
	"medium": "MEDIUM",
	"heavy": "HEAVY",
	"building": "STRUCTURES",
	"defense": "DEFENCES",
}

var _director: Node = null
var _dock: UIDock = null
var _strips: Dictionary = {}
var _tier_bodies: Dictionary = {}
var _ring: UIRadialMenu = null
var _resource_label: Label = null


func setup(director: Node) -> void:
	_director = director
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_dock()
	_build_resource_readout()
	_director.production.queue_changed.connect(_on_queue_changed)
	_director.economy.resources_changed.connect(_on_resources_changed)
	_refresh_all()


func _build_dock() -> void:
	_dock = UIDockScript.new()
	_dock.dock_title = "PRODUCTION"
	_dock.side = UIDockScript.Side.RIGHT
	_dock.expanded_size = 300.0
	_dock.default_state = UIDockScript.State.RAILED
	# No persist_key. A match HUD reading user://ui_layout.cfg would open in
	# whatever state the Design Lab was last left in, which is not the same
	# screen and not the same question.
	_dock.persist_key = ""
	_dock.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	add_child(_dock)

	for queue_name in BuildingCatalogScript.QUEUES:
		_build_tier(queue_name)


func _build_tier(queue_name: String) -> void:
	var tier := VBoxContainer.new()
	tier.name = queue_name
	tier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dock.body().add_child(tier)

	var header := Button.new()
	# TabButton matches the Design Lab's family headers, so a tier here and a
	# tier there are visibly the same kind of control.
	header.theme_type_variation = "TabButton"
	header.text = QUEUE_LABELS.get(queue_name, queue_name.to_upper())
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.toggle_mode = true
	header.focus_mode = Control.FOCUS_NONE
	header.custom_minimum_size = Vector2(0, Tokens.HIT_TARGET_MIN)
	tier.add_child(header)
	UIFeedbackScript.wire(header, "select")

	var body := VBoxContainer.new()
	body.visible = false
	body.add_theme_constant_override("separation", Tokens.SPACE_XS)
	tier.add_child(body)
	header.toggled.connect(func(pressed: bool): body.visible = pressed)
	_tier_bodies[queue_name] = body

	# One progress strip per queue - the whole point of a global queue is that
	# there is exactly one thing in progress per type, so one strip says it all.
	var strip := ProgressBar.new()
	strip.custom_minimum_size = Vector2(0, 14)
	strip.show_percentage = false
	strip.max_value = 1.0
	body.add_child(strip)

	var status := Label.new()
	status.theme_type_variation = "HintLabel"
	status.text = "IDLE"
	body.add_child(status)
	_strips[queue_name] = {"bar": strip, "status": status, "header": header}

	for item in _items_for(queue_name):
		_add_item_button(body, queue_name, item)


# What can be ordered from this queue. Units come from the player's roster,
# filtered by the weight tier their hull puts them in; the Building queue lists
# the prefab structures.
func _items_for(queue_name: String) -> Array:
	if queue_name == BuildingCatalogScript.QUEUE_BUILDING:
		var out: Array = []
		for kind in BuildingCatalogScript.buildable_kinds():
			out.append({
				"kind": kind,
				"label": kind.replace("_", " ").to_upper(),
				"metal": BuildingCatalogScript.get_stat(kind, "cost_metal", 0),
				"crystal": BuildingCatalogScript.get_stat(kind, "cost_crystal", 0),
				"time": BuildingCatalogScript.get_stat(kind, "build_time", 10.0),
				"structure": true,
			})
		return out
	if queue_name == BuildingCatalogScript.QUEUE_DEFENSE:
		# Defence designs are foundation-hulled blueprints from the Design Lab.
		# Nothing is bundled, so this tier is legitimately empty until the player
		# saves one - shown rather than hidden, so the queue's existence is
		# discoverable.
		return []
	var out: Array = []
	for design in _director.roster:
		if DesignCostingScript.queue_for_design(design) != queue_name:
			continue
		var cost: Vector2i = DesignCostingScript.blueprint_cost(design)
		out.append({
			"blueprint": design,
			"label": str(design.get("name", "DESIGN")).to_upper(),
			"metal": cost.x,
			"crystal": cost.y,
			"time": DesignCostingScript.build_time_for_cost(cost),
			"structure": false,
		})
	return out


func _add_item_button(parent: Control, queue_name: String, item: Dictionary) -> void:
	var btn := Button.new()
	btn.text = "%s\n%d M  %d C" % [item["label"], item["metal"], item["crystal"]]
	btn.custom_minimum_size = Vector2(0, 44)
	btn.focus_mode = Control.FOCUS_NONE
	parent.add_child(btn)
	UIFeedbackScript.wire(btn)
	btn.pressed.connect(func(): _enqueue(queue_name, item))


func _enqueue(queue_name: String, item: Dictionary) -> void:
	var team: int = _director.PLAYER_TEAM
	if item["structure"]:
		_director.production.enqueue_structure(
			team, queue_name, item["kind"], item["metal"], item["crystal"], item["time"])
	else:
		_director.production.enqueue_unit(
			team, item["blueprint"], item["metal"], item["crystal"], item["time"], queue_name)


func _build_resource_readout() -> void:
	_resource_label = Label.new()
	# HUDValueLabel is the monospace readout variation, so a rising count does
	# not shove everything beside it sideways every tick.
	_resource_label.theme_type_variation = "HUDValueLabel"
	_resource_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_resource_label.position = Vector2(-260, Tokens.SPACE_MD)
	add_child(_resource_label)
	_on_resources_changed(_director.PLAYER_TEAM)


func _on_resources_changed(team: int) -> void:
	if team != _director.PLAYER_TEAM or _resource_label == null:
		return
	var e = _director.economy
	var power := "LOW POWER" if e.is_low_power(team) else "%d/%d PWR" % [
		int(e.power_draw(team)), int(e.power_capacity(team))]
	_resource_label.text = "%d M   %d C   %s" % [e.metal(team), e.crystal(team), power]


func _on_queue_changed(team: int, queue_name: String) -> void:
	if team == _director.PLAYER_TEAM:
		_refresh(queue_name)


func _refresh_all() -> void:
	for queue_name in BuildingCatalogScript.QUEUES:
		_refresh(queue_name)


func _refresh(queue_name: String) -> void:
	if not _strips.has(queue_name):
		return
	var widgets: Dictionary = _strips[queue_name]
	var status: Dictionary = _director.production.status(_director.PLAYER_TEAM, queue_name)
	var contributors: int = _director.production.contributor_count(_director.PLAYER_TEAM, queue_name)

	# A queue with no contributing structure is dead, and saying so is more use
	# than an empty strip - "why can't I build tanks" is the question this
	# answers before it gets asked.
	if contributors <= 0:
		widgets["bar"].value = 0.0
		widgets["status"].text = "NO %s" % _contributor_hint(queue_name)
		return
	if status["empty"]:
		widgets["bar"].value = 0.0
		widgets["status"].text = "IDLE  (x%d)" % contributors
		return
	widgets["bar"].value = status["progress"]
	var suffix := "  STALLED" if status["stalled"] else ""
	widgets["status"].text = "%s  %d%%  [%d]%s" % [
		status["label"], int(status["progress"] * 100.0), status["depth"], suffix]


func _contributor_hint(queue_name: String) -> String:
	var kinds: Array = BuildingCatalogScript.contributors_for(queue_name)
	if kinds.is_empty():
		return "SOURCE"
	return str(kinds[0]).replace("_", " ").to_upper()


# --- Radial menu on a structure ----------------------------------------------

# The second entry point. Clicking a contributing structure raises a ring over it
# with that queue's actions, so a player working in the world does not have to
# travel to the dock and back.
func open_structure_ring(structure: Node3D, screen_pos: Vector2) -> void:
	if _ring != null and is_instance_valid(_ring):
		_ring.close()
	var queue_name: String = BuildingCatalogScript.queue_for_kind(structure.kind)
	if queue_name == "":
		return

	_ring = UIRadialScript.new()
	_ring.target_node = structure
	_ring.subject_label = str(structure.kind).replace("_", " ").to_upper()
	_ring.add_action("open", "BUILD", "", true)
	# Pause and cancel act on the head of the queue, which for a global queue is
	# unambiguous - there is only one thing in progress per type.
	var status: Dictionary = _director.production.status(_director.PLAYER_TEAM, queue_name)
	_ring.add_action("pause", "HOLD", "", not status["empty"])
	_ring.add_action("cancel", "CANCEL", "", not status["empty"])
	_ring.add_action("rally", "RALLY", "", BuildingCatalogScript.is_manufactory(structure.kind))
	add_child(_ring)
	_ring.action_invoked.connect(func(id: String): _on_ring_action(id, queue_name))
	_ring.open_at(screen_pos)


func _on_ring_action(id: String, queue_name: String) -> void:
	match id:
		"open":
			# Reveal the dock with this queue's tier already open, so the ring
			# and the toolbox are one flow rather than two.
			_dock.set_dock_state(UIDockScript.State.EXPANDED)
			for name in _tier_bodies:
				_tier_bodies[name].visible = (name == queue_name)
				if _strips.has(name):
					_strips[name]["header"].button_pressed = (name == queue_name)
		"pause":
			var status: Dictionary = _director.production.status(_director.PLAYER_TEAM, queue_name)
			_director.production.set_paused(_director.PLAYER_TEAM, queue_name, not status.get("paused", false))
		"cancel":
			_director.production.cancel(_director.PLAYER_TEAM, queue_name, 0)
		"rally":
			# Rally-point placement is a click-to-place mode and belongs with the
			# ghost placement flow, which lands with building placement.
			pass
