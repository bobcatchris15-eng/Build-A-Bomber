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
# THE LAYOUT, to Chris's spec: five floating toolboxes along the BOTTOM of the
# screen, one per queue, each accordion-opening upward into its build list.
#
# WHAT THIS REPLACES AND WHY. The first cut put all five tiers inside a single
# right-hand UIDock opening in its RAILED state. Railed, that is a 40 px strip
# against the screen edge, so in practice the production interface read as no UI
# at all - and the radial menu's BUILD action, which only expanded that dock,
# appeared to do nothing. A build bar the player cannot find is the same as a
# build bar that does not exist.
#
# Bottom-edge toolboxes instead: five always-visible headers, so every queue is
# discoverable without opening anything, and one click puts a build list on
# screen. Accordion, so only one list is up at a time and the bottom of the
# screen never fills with buttons.
#
# The header buttons, the feedback wiring and the material language are existing
# components; nothing here invents chrome.

const UIRadialScript = preload("res://scripts/ui_radial_menu.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const BuildingCatalogScript = preload("res://scripts/battle/economy/building_catalog.gd")
const DesignCostingScript = preload("res://scripts/battle/economy/design_costing.gd")
const ResourceCatalogScript = preload("res://scripts/battle/economy/resource_catalog.gd")
const ToolboxPlateScript = preload("res://scripts/battle/hud/toolbox_plate.gd")
const StampedLabelScript = preload("res://scripts/battle/hud/stamped_label.gd")
# NOT a preload of match_director.gd: it preloads this file, and the pair is a
# cyclic reference. `is_defence_design` is reached through the director instance
# instead, which keeps one definition of what makes a design a turret rather than
# duplicating the foundation check here.

const QUEUE_LABELS := {
	"light": "LIGHT",
	"medium": "MEDIUM",
	"heavy": "HEAVY",
	"building": "STRUCTURES",
	"defense": "DEFENCES",
}

# Width of one toolbox, plate included. Wide enough for a design name plus its
# cost line without wrapping, and five of them plus separators still sit inside a
# 1280 px viewport - which is the real ceiling on "make them larger".
const TOOLBOX_WIDTH := 264.0
# The plate is drawn behind the toolbox's controls and has to be visible around
# them, or the chamfer and bevel are covered by the very buttons they frame.
const PLATE_PADDING := 10.0
# Usable width inside the plate.
const CONTENT_WIDTH := TOOLBOX_WIDTH - PLATE_PADDING * 2.0
# Header height. Above HIT_TARGET_MIN on purpose: this is the face of the plate
# and it carries the stamped lettering, so it needs room to read as a plate
# rather than as a tab.
const HEADER_HEIGHT := 44.0
const HEADER_FONT_SIZE := 19
# How tall a build list is allowed to get before it scrolls rather than growing
# up off the top of the screen. The STRUCTURES tier already lists four prefabs
# and the roster tiers grow with whatever the player has designed.
const LIST_MAX_HEIGHT := 320.0

var _director: Node = null
var _strips: Dictionary = {}
var _tier_bodies: Dictionary = {}
var _ring: UIRadialMenu = null


func setup(director: Node) -> void:
	_director = director
	# TOP_LEFT, not FULL_RECT. FULL_RECT leaves the opposite anchors unequal (0
	# and 1), and Godot then recomputes size from the parent's rect after _ready()
	# - overriding whatever fit_to_viewport() set. The parent is a CanvasLayer with
	# no rect, so that recomputation lands on zero. Anchors all at zero means the
	# explicit size sticks.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fit_to_viewport()
	# Follows the window. Without this the HUD is laid out once at whatever size
	# it happened to have and never tracks a resize.
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(fit_to_viewport):
		vp.size_changed.connect(fit_to_viewport)
	_build_toolbar()
	_director.production.queue_changed.connect(_on_queue_changed)
	_refresh_all()


# Sizes this Control to the viewport by hand.
#
# WHY THIS IS NOT set_anchors_preset(PRESET_FULL_RECT)'s job. Anchors are
# fractions of the PARENT's rect, and this HUD's parent is a CanvasLayer, which
# is not a Control and therefore has no rect. So the anchors resolved against
# nothing, the node kept its default size of (0, 0), and every child anchored to
# an edge collapsed onto the origin: the bottom-anchored build bar landed at the
# TOP of the screen with zero width, and the top-RIGHT resource readout rendered
# at the far left on top of the key bindings.
#
# Which is exactly what "still no HUD" looked like. A Control parented to a
# CanvasLayer has to be sized explicitly - only a direct child of a Viewport gets
# resized for free.
func fit_to_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	position = Vector2.ZERO
	size = vp.get_visible_rect().size


# --- Toolbar -----------------------------------------------------------------
#
# Five toolboxes on the bottom edge, positioned BY HAND rather than by an
# HBoxContainer. A container owns its children's positions, and these have to
# slide vertically off the screen edge independently, so a container would fight
# every frame of that animation.

# How much of its own collapsed height a toolbox slides below the screen edge
# when it is idle and unhovered. Dormant queues get out of the way of the
# battlefield, which is the thing the player is actually trying to watch.
const IDLE_SLIDE := 0.8
# How fast a toolbox slides, as a fraction of remaining distance per second.
# Quick enough not to lag a mouse sweep, slow enough to read as motion.
const SLIDE_SPEED := 6.3
# Extra grab room around a toolbox when deciding whether the mouse is on it.
# Without it a box retreats the instant the cursor clips its boundary, which
# reads as the UI running away from the player.
const HOVER_PADDING := 12.0

# CRT readout colours. Deliberately NOT the theme's signal palette: this is a
# self-lit instrument face read against its own black ground, not a status tint
# applied to a themed surface.
const CRT_BLACK := Color(0.04, 0.05, 0.04, 0.92)
const CRT_GREEN := Color(0.42, 1.0, 0.45, 1.0)
const CRT_GREEN_DIM := Color(0.12, 0.30, 0.14, 1.0)
const CRT_FONT := preload("res://assets/fonts/MonoFont-Regular.ttf")
const CRT_FONT_SIZE := 12

var _toolbar: Control = null
var _slots: Dictionary = {}
var _plates: Dictionary = {}

func _build_toolbar() -> void:
	_toolbar = Control.new()
	_toolbar.name = "Toolboxes"
	_toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toolbar)

	# ALL PLATES FIRST, THEN ALL SLOTS. Godot picks siblings in REVERSE child
	# order, so an interleaved plate/slot/plate/slot arrangement puts one
	# toolbox's decorative plate ahead of the NEXT toolbox's controls in the pick
	# order - measured: a point inside the open STRUCTURES list resolved to
	# defensePlate, so the list never saw the wheel and the camera did. Two passes
	# guarantee every plate is behind every control.
	for queue_name in BuildingCatalogScript.QUEUES:
		var plate: Control = ToolboxPlateScript.new()
		plate.name = queue_name + "Plate"
		_plates[queue_name] = plate
		_toolbar.add_child(plate)
	for queue_name in BuildingCatalogScript.QUEUES:
		_build_toolbox(queue_name)
	_layout_toolboxes()


func _build_toolbox(queue_name: String) -> void:
	# The plate goes in FIRST so it draws behind this toolbox's controls. Sibling
	# order is draw order, and all five plates precede all five slots - which is
	# safe only because the slots never overlap each other.
	var plate: Control = _plates[queue_name]

	var slot := VBoxContainer.new()
	slot.name = queue_name
	slot.custom_minimum_size = Vector2(CONTENT_WIDTH, 0)
	slot.add_theme_constant_override("separation", 0)
	# PASS, not STOP: the buttons inside still need their clicks. Hover is
	# resolved geometrically in _process() instead, because mouse_entered and
	# mouse_exited on a parent are unreliable once children with their own filters
	# sit on top of it - the parent reports "exited" the moment the cursor crosses
	# onto one of its own buttons.
	# STOP, NOT PASS - and this is what decouples list scrolling from world zoom.
	#
	# ScrollContainer accepts a wheel event ONLY when the scroll value actually
	# changes (Godot compares the value before and after and calls accept_event()
	# on a difference). So a list that fits its window, or one already at its top
	# or bottom, DECLINES the wheel - and an unaccepted GUI event continues up the
	# ANCESTOR chain, not to whatever is drawn behind. With PASS here it walked
	# straight past the toolbox, past the IGNORE'd HUD root, and arrived at the
	# camera's _unhandled_input as a zoom.
	#
	# STOP ends that walk at the toolbox. Children are still picked first, so the
	# list scrolls normally whenever it has anywhere to scroll to; only the
	# leftovers are absorbed.
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	# ...AND THE EVENT HAS TO BE ACCEPTED, not merely received. A STOP filter ends
	# the walk up the ancestor chain, but the viewport only marks an event handled
	# when some control ACCEPTS it - so an unaccepted wheel still fell through to
	# _unhandled_input and zoomed. Measured: with STOP alone, a wheel in the middle
	# of a scrollable list was absorbed (the ScrollContainer accepted it) while the
	# same wheel at the BOTTOM of that list, where the ScrollContainer declines,
	# still zoomed the world.
	slot.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and (
				event.button_index == MOUSE_BUTTON_WHEEL_UP
				or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			slot.accept_event())
	_toolbar.add_child(slot)

	# THE LIST IS FIRST IN CHILD ORDER so it renders ABOVE the header. These sit
	# on the bottom edge; a list added after the header would open downward, off
	# the screen.
	var panel := PanelContainer.new()
	panel.visible = false
	# A recess, not another raised surface. The list opens INTO the plate, so it
	# is darker than the plate body with a hairline rim rather than a bevel.
	var well := StyleBoxFlat.new()
	well.bg_color = Tokens.BASE_900
	well.border_color = Tokens.BASE_500
	well.set_border_width_all(Tokens.BORDER_HAIRLINE)
	well.set_content_margin_all(Tokens.SPACE_XS)
	panel.add_theme_stylebox_override("panel", well)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", Tokens.SPACE_XS)
	scroll.add_child(body)
	slot.add_child(panel)

	var header := Button.new()
	# NO `text` ON THE BUTTON. The lettering is a StampedLabel drawn on top of it
	# - a Button can only render one flat fill with one outline, and that is
	# exactly the "printed on" look this replaced.
	header.alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.toggle_mode = true
	header.focus_mode = Control.FOCUS_NONE
	header.custom_minimum_size = Vector2(0, HEADER_HEIGHT)
	_engrave(header)
	slot.add_child(header)

	var stamp: Control = StampedLabelScript.new()
	stamp.text = QUEUE_LABELS.get(queue_name, queue_name.to_upper())
	stamp.font_size = HEADER_FONT_SIZE
	stamp.set_anchors_preset(Control.PRESET_FULL_RECT)
	header.add_child(stamp)
	UIFeedbackScript.wire(header, "select")
	header.toggled.connect(func(pressed: bool):
		if pressed:
			_close_all_except(queue_name)
		panel.visible = pressed
		_layout_toolboxes())

	var crt := _build_crt(slot)

	_slots[queue_name] = {
		"slot": slot, "panel": panel, "header": header, "plate": plate,
		"hidden": 1.0, "index": _slots.size(),
	}
	_strips[queue_name] = {"bar": crt["bar"], "status": crt["label"], "header": header}
	_tier_bodies[queue_name] = panel

	var items := _items_for(queue_name)
	for item in items:
		_add_item_button(body, queue_name, item)
	if items.is_empty():
		# An empty tier says so rather than opening onto nothing. DEFENCES is empty
		# until the player saves a foundation design, and silence there reads as a
		# broken button.
		var empty := Label.new()
		empty.theme_type_variation = "HintLabel"
		empty.text = "NOTHING AVAILABLE"
		body.add_child(empty)
	scroll.custom_minimum_size = Vector2(
		CONTENT_WIDTH, minf(LIST_MAX_HEIGHT, 48.0 * float(maxi(1, items.size()))))


# Strips the header Button back to a bare hit target.
#
# The drawn plate behind it already IS the surface and the StampedLabel on top of
# it is already the lettering, so everything the theme would contribute here is a
# second copy of something that exists: a themed button body over a drawn plate
# is two plates, and the button's own `text` render is the flat printed-on fill
# the stamped lettering replaced.
func _engrave(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var empty := StyleBoxEmpty.new()
		button.add_theme_stylebox_override(state, empty)


# The readout under each header: a small black CRT with a green monospace line
# and a progress bar, to Chris's spec.
#
# WHY IT IS NOT THE THEMED HintLabel IT WAS. That rendered body-text colour on
# the ambient panel, at a size chosen for prose, showing a number that changes
# every frame - and it was unreadable. A readout is not prose. It wants a
# fixed-width face so a climbing percentage does not reflow the line, contrast
# against its own dark ground rather than against whatever terrain is behind it,
# and a bar that can be read without being read.
func _build_crt(parent: Control) -> Dictionary:
	var crt := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = CRT_BLACK
	box.border_color = CRT_GREEN_DIM
	box.set_border_width_all(1)
	box.content_margin_left = Tokens.SPACE_XS
	box.content_margin_right = Tokens.SPACE_XS
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	crt.add_theme_stylebox_override("panel", box)
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(crt)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	crt.add_child(col)

	var label := Label.new()
	label.add_theme_font_override("font", CRT_FONT)
	label.add_theme_font_size_override("font_size", CRT_FONT_SIZE)
	label.add_theme_color_override("font_color", CRT_GREEN)
	label.text = "IDLE"
	label.clip_text = true
	col.add_child(label)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 6)
	bar.show_percentage = false
	bar.max_value = 1.0
	var under := StyleBoxFlat.new()
	under.bg_color = CRT_GREEN_DIM
	var over := StyleBoxFlat.new()
	over.bg_color = CRT_GREEN
	bar.add_theme_stylebox_override("background", under)
	bar.add_theme_stylebox_override("fill", over)
	col.add_child(bar)
	return {"label": label, "bar": bar}


func _close_all_except(queue_name: String) -> void:
	for other in _slots:
		if other == queue_name:
			continue
		_slots[other]["panel"].visible = false
		# set_pressed_no_signal, or closing a sibling re-enters this function
		# through that sibling's own toggled handler.
		_slots[other]["header"].set_pressed_no_signal(false)


# Opens one queue's list, from anywhere. This is what the radial menu's BUILD
# action calls, so the ring and the toolbox are one flow rather than two.
func open_queue(queue_name: String) -> void:
	if not _slots.has(queue_name):
		return
	_close_all_except(queue_name)
	_slots[queue_name]["panel"].visible = true
	_slots[queue_name]["header"].set_pressed_no_signal(true)
	_layout_toolboxes()


func is_queue_open(queue_name: String) -> bool:
	return _slots.has(queue_name) and _slots[queue_name]["panel"].visible


# Places every toolbox along the bottom edge, applying each one's current slide.
# Called on any change of size or open state, and every frame a slide is still
# animating.
func _layout_toolboxes() -> void:
	if _toolbar == null:
		return
	_toolbar.position = Vector2.ZERO
	_toolbar.size = size

	var count: int = _slots.size()
	if count == 0:
		return
	var span: float = TOOLBOX_WIDTH * float(count) + float(Tokens.SPACE_SM) * float(count - 1)
	var left: float = (size.x - span) * 0.5

	for queue_name in _slots:
		var entry: Dictionary = _slots[queue_name]
		var slot: Control = entry["slot"]
		# The container has to be re-measured, or a list that just opened still
		# reports the height it had while it was hidden.
		slot.size = Vector2(CONTENT_WIDTH, slot.get_combined_minimum_size().y)
		var x: float = left + float(entry["index"]) * (TOOLBOX_WIDTH + float(Tokens.SPACE_SM))
		# ONLY THE COLLAPSED PART SLIDES. An open list never retreats, or the act
		# of opening one would walk it straight off the bottom of the screen.
		var panel: Control = entry["panel"]
		var list_height: float = panel.size.y if panel.visible else 0.0
		var collapsed: float = maxf(0.0, slot.size.y - list_height)
		var y: float = size.y - slot.size.y - float(Tokens.SPACE_MD) \
			+ float(entry["hidden"]) * collapsed * IDLE_SLIDE
		slot.position = Vector2(x + PLATE_PADDING, y)

		# The plate wraps the slot. It is positioned from the slot's final rect
		# rather than computed alongside it, so the two can never disagree about
		# where a mid-slide toolbox actually is.
		var plate: Control = entry["plate"]
		plate.position = slot.position - Vector2(PLATE_PADDING, PLATE_PADDING)
		plate.size = slot.size + Vector2(PLATE_PADDING, PLATE_PADDING) * 2.0
		plate.queue_redraw()


# --- Per-frame behaviour ------------------------------------------------------
#
# THREE THINGS THAT ALL NEED A FRAME TICK, and one of them is a bug fix.
#
# The readouts were repainted only on `queue_changed`, which ProductionService
# emits on enqueue, cancel and claim - never as a job PROGRESSES. So the
# percentage under each toolbox was painted once when the job was queued and then
# sat there, frozen, for the entire build. It was not a formatting problem; the
# number genuinely never updated.
#
# Hover is resolved here rather than through mouse_entered/mouse_exited because
# those fire against a parent unreliably once children with their own mouse
# filters sit on top of it, and every toolbox is full of buttons.
func _process(delta: float) -> void:
	if _director == null or _slots.is_empty():
		return
	_refresh_all()

	var mouse := get_global_mouse_position()
	var moved := false
	for queue_name in _slots:
		var entry: Dictionary = _slots[queue_name]
		# Measured against the PLATE, not the slot: the plate is what the player
		# sees and it is PLATE_PADDING larger on every side, so hovering the visible
		# chamfered edge has to count as hovering the toolbox.
		# Untyped: `accent` lives on the plate script, and a `: Control` annotation
		# makes that property access a parse error.
		var plate = entry["plate"]
		var hot := Rect2(plate.position, plate.size).grow(HOVER_PADDING)
		var hovered: bool = hot.has_point(mouse)

		# A toolbox stays up while the mouse is on it, while its list is open, or
		# while its queue has something to report - a progress bar nobody can see
		# is the same as no progress bar.
		var active: bool = _is_active(queue_name)
		var wants_up: bool = hovered or is_queue_open(queue_name) or active

		# A running queue lights its rim, so "something is being built here" is
		# legible from across the screen without reading the CRT line.
		var rim: Color = Tokens.SIGNAL_HAZARD if active else Color(0, 0, 0, 0)
		if plate.accent != rim:
			plate.accent = rim
			plate.queue_redraw()

		# AUTO-COLLAPSE. Moving off an open toolbox closes it, so the build list
		# does not stay parked over the battlefield after the player has finished
		# with it.
		if not hovered and is_queue_open(queue_name):
			entry["panel"].visible = false
			entry["header"].set_pressed_no_signal(false)
			moved = true

		var target: float = 0.0 if wants_up else 1.0
		var current: float = entry["hidden"]
		if not is_equal_approx(current, target):
			entry["hidden"] = move_toward(current, target, SLIDE_SPEED * delta)
			moved = true

	# UNCONDITIONALLY, not `if moved`.
	#
	# A VBoxContainer's combined minimum size does not update in the same frame a
	# child's `visible` changes, so the _layout_toolboxes() call inside the toggle
	# handler measured the slot as though the list were still closed. If nothing
	# was animating that frame, `moved` stayed false and the layout was never
	# recomputed - so an opened list kept the collapsed slot's height and was
	# positioned hanging off the BOTTOM of the screen. Measured: the list panel
	# landed at y=1053 with a height of 248 in a 1080px viewport, which is why a
	# wheel over it found no Control at all and fell through to the camera.
	#
	# Five slots of arithmetic per frame is not worth guarding against.
	_layout_toolboxes()


# Is this queue doing anything the player would want to watch? Used to hold a
# toolbox up while it has a bar worth showing.
func _is_active(queue_name: String) -> bool:
	var status: Dictionary = _director.production.status(_director.PLAYER_TEAM, queue_name)
	return not status.get("empty", true)


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
				# Buildings still author their price as materials, same as modules
				# do, and convert at the till - see ResourceCatalog.
				"cost": ResourceCatalogScript.credits_from_materials(Vector2i(
					BuildingCatalogScript.get_stat(kind, "cost_metal", 0),
					BuildingCatalogScript.get_stat(kind, "cost_crystal", 0))),
				"time": BuildingCatalogScript.get_stat(kind, "build_time", 10.0),
				"structure": true,
			})
		return out
	if queue_name == BuildingCatalogScript.QUEUE_DEFENSE:
		# Defence designs are foundation-hulled blueprints - the same roster the
		# unit tiers read, filtered the other way. This tier used to return []
		# with a note that nothing was bundled; five turret designs ship in
		# data/loadout/ now (Sentinel SAM, Bastion Gun, Rampart Bunker among them),
		# so an empty list here was hiding buildable content rather than reporting
		# its absence.
		var defences: Array = []
		for design in _director.roster:
			if not _director.is_defence_design(design):
				continue
			var dcost: int = DesignCostingScript.blueprint_cost(design)
			defences.append({
				"blueprint": design,
				"kind": "defense",
				"label": str(design.get("name", "DEFENCE")).to_upper(),
				"cost": dcost,
				"time": DesignCostingScript.build_time_for_cost(dcost),
				"structure": true,
			})
		return defences
	var out: Array = []
	for design in _director.roster:
		# Foundation designs are turrets and belong to the DEFENCES tier. Without
		# this they also appear under their hull's weight tier, where ordering one
		# produces an immobile structure that tries to drive out of a factory exit.
		if _director.is_defence_design(design):
			continue
		if DesignCostingScript.queue_for_design(design) != queue_name:
			continue
		var cost: int = DesignCostingScript.blueprint_cost(design)
		out.append({
			"blueprint": design,
			"label": str(design.get("name", "DESIGN")).to_upper(),
			"cost": cost,
			"time": DesignCostingScript.build_time_for_cost(cost),
			"structure": false,
		})
	return out


func _add_item_button(parent: Control, queue_name: String, item: Dictionary) -> void:
	var btn := Button.new()
	btn.text = "%s\n%d cr" % [item["label"], item["cost"]]
	btn.custom_minimum_size = Vector2(0, 44)
	btn.focus_mode = Control.FOCUS_NONE
	parent.add_child(btn)
	UIFeedbackScript.wire(btn)
	btn.pressed.connect(func(): _enqueue(queue_name, item))


func _enqueue(queue_name: String, item: Dictionary) -> void:
	var team: int = _director.PLAYER_TEAM
	if item["structure"]:
		# The blueprint rides along for defences and is empty for prefab kinds -
		# that is what _on_structure_ready reads to decide between a catalog
		# building and a design-built turret. Dropping it here produced a power
		# plant where the player ordered a gun turret.
		_director.production.enqueue_structure(
			team, queue_name, item["kind"], item["cost"], item["time"],
			item.get("blueprint", {}))
	else:
		_director.production.enqueue_unit(
			team, item["blueprint"], item["cost"], item["time"], queue_name)


# NO RESOURCE READOUT HERE. There used to be one, anchored top-right, showing
# credits and power - the same numbers BattleHUD's top strip already
# shows. Two readouts of one ledger is one too many: they cost a signal
# connection each, they can disagree while one is mid-update, and on screen they
# simply competed. BattleHUD keeps it, because its version also carries the power
# BAR and the status line.


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
	# The readout is a fixed-width instrument line, so it is built to a fixed
	# SHAPE: a right-aligned three-character percentage that does not jitter as it
	# crosses 9 to 10 to 100, then the label, then the queue depth. On a
	# monospace face that gives a column the eye can track without reading.
	if contributors <= 0:
		widgets["bar"].value = 0.0
		widgets["status"].text = "--- NO %s" % _contributor_hint(queue_name)
		return
	if status["empty"]:
		widgets["bar"].value = 0.0
		widgets["status"].text = "--- IDLE  x%d" % contributors
		return
	# A finished structure BLOCKS its own line until it is placed, so "100%" and
	# nothing else describes a queue that has apparently stopped for no reason.
	# Naming it as waiting on the player is the difference between a bug report
	# and an instruction.
	if status.get("done", false):
		widgets["bar"].value = 1.0
		widgets["status"].text = "RDY %s - PLACE IT" % status["label"]
		return
	widgets["bar"].value = status["progress"]
	var suffix := " HALT" if status["stalled"] else ""
	widgets["status"].text = "%3d%% %s x%d%s" % [
		int(status["progress"] * 100.0), status["label"], status["depth"], suffix]


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
	# The way back to a building the player held or ignored. Enabled only when the
	# head of this line is genuinely a finished structure waiting on a site.
	_ring.add_action("place", "PLACE", "", status.get("done", false))
	_ring.add_action("pause", "HOLD", "", not status["empty"])
	_ring.add_action("cancel", "CANCEL", "", not status["empty"])
	_ring.add_action("rally", "RALLY", "", BuildingCatalogScript.is_manufactory(structure.kind))
	add_child(_ring)
	_ring.action_invoked.connect(func(id: String): _on_ring_action(id, queue_name))
	_ring.open_at(screen_pos)


func _on_ring_action(id: String, queue_name: String) -> void:
	match id:
		"open":
			# Opens the SAME toolbox the bottom bar opens - one build list per
			# queue, reachable two ways, never two lists that could disagree.
			open_queue(queue_name)
		"place":
			_director.resume_placement(queue_name)
		"pause":
			var status: Dictionary = _director.production.status(_director.PLAYER_TEAM, queue_name)
			_director.production.set_paused(_director.PLAYER_TEAM, queue_name, not status.get("paused", false))
		"cancel":
			_director.production.cancel(_director.PLAYER_TEAM, queue_name, 0)
		"rally":
			# Rally-point placement is a click-to-place mode and belongs with the
			# ghost placement flow, which lands with building placement.
			pass
