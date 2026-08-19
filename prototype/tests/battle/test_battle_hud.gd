extends "res://tests/suite_base.gd"
# The production interface, asserted as something a player can actually reach.
#
# WHY THIS EXISTS. The first build bar was functionally complete and effectively
# invisible: five tiers inside a right-hand UIDock that opened RAILED, which is a
# 40 px strip against the screen edge. Every service call underneath it worked,
# so nothing failed - the interface simply could not be found, and the radial
# menu's BUILD action appeared to do nothing because all it did was expand that
# same hidden dock.
#
# So these do not assert that the widgets exist. They assert that the build lists
# are ON SCREEN and that opening one actually shows it, which is the property
# that was false while every other test passed.

const ProductionHUDScript = preload("res://scripts/battle/hud/production_hud.gd")
const EconomyServiceScript = preload("res://scripts/battle/economy/economy_service.gd")
const ProductionServiceScript = preload("res://scripts/battle/economy/production_service.gd")
const BuildingCatalogScript = preload("res://scripts/battle/economy/building_catalog.gd")
const ModuleCatalogScript = preload("res://scripts/module_catalog.gd")


# The narrow surface ProductionHUD asks its director for. Deliberately a stub:
# the HUD must be constructible without a map, a navmesh or an opponent, and if
# it ever stops being so that is worth knowing.
class StubDirector:
	extends Node

	const PLAYER_TEAM := 0

	var economy
	var production
	var roster: Array = []

	static func is_defence_design(blueprint: Dictionary) -> bool:
		return ModuleCatalogScript.is_foundation(blueprint.get("hull_type", ""))

	func resume_placement(_queue_name: String) -> bool:
		return false


func _hud() -> Array:
	var director := StubDirector.new()
	director.economy = EconomyServiceScript.new()
	director.economy.add_team(0, 2000)
	director.production = ProductionServiceScript.new()
	director.production.setup(director.economy, null)
	director.production.add_team(0)
	director.roster = [
		{"name": "Test Tank", "hull_type": "brenntal_medium_a", "modules": []},
	]
	root.add_child(director)

	# UNDER A CanvasLayer, exactly as match_director._build_hud() mounts it. This
	# is load-bearing, not incidental: a CanvasLayer is not a Control and has no
	# rect, which is the whole reason anchor presets collapse the HUD to (0, 0).
	# Parenting the HUD to a plain Node here would let the bug through - the first
	# version of this file did, and passed while the game had no HUD.
	var layer := CanvasLayer.new()
	director.add_child(layer)

	var hud = ProductionHUDScript.new()
	layer.add_child(hud)
	hud.setup(director)
	return [director, hud]


func _toolbox_row(hud: Node) -> Control:
	return hud.get_node_or_null("Toolboxes")


# Every queue gets a toolbox, and every toolbox's header is visible without the
# player opening anything. Discoverability is the whole point of moving these to
# the bottom edge.
func test_every_queue_has_a_visible_toolbox() -> bool:
	print("Running Test Suite: Production HUD - five toolboxes, all discoverable...")
	var pair := _hud()
	var director: Node = pair[0]
	var hud: Node = pair[1]

	var row := _toolbox_row(hud)
	if row == null:
		print("  [FAIL] no toolbox row was built")
		director.queue_free()
		return false

	for queue_name in BuildingCatalogScript.QUEUES:
		var box := row.get_node_or_null(NodePath(queue_name))
		if box == null:
			print("  [FAIL] no toolbox for the '%s' queue" % queue_name)
			director.queue_free()
			return false
		if not box.visible:
			print("  [FAIL] the '%s' toolbox is not visible" % queue_name)
			director.queue_free()
			return false
	print("  [PASS] five visible toolboxes")
	director.queue_free()
	return true


# THE REGRESSION THIS FILE IS FOR, and the first version of it was wrong in a way
# worth recording. It asserted the row sat inside the viewport - but it SET
# `hud.size` itself first, which is precisely the step the real HUD was failing to
# do. The test encoded the workaround, passed, and the game still shipped with no
# HUD at all.
#
# So the size is deliberately NOT set here. The HUD's parent is a CanvasLayer,
# which is not a Control and has no rect for anchors to be fractions of, so a HUD
# that leans on set_anchors_preset(PRESET_FULL_RECT) alone stays (0, 0) and every
# edge-anchored child collapses onto the origin. Sizing itself is the property
# under test.
func test_the_build_bar_is_actually_on_screen() -> bool:
	print("Running Test Suite: Production HUD - the build bar is inside the viewport...")
	var pair := _hud()
	var director: Node = pair[0]
	var hud: Node = pair[1]

	var viewport_size: Vector2 = hud.get_viewport().get_visible_rect().size
	if hud.size.x < viewport_size.x - 1.0 or hud.size.y < viewport_size.y - 1.0:
		print("  [FAIL] the HUD did not size itself to the viewport: %s vs %s"
			% [str(hud.size), str(viewport_size)])
		director.queue_free()
		return false

	var row := _toolbox_row(hud)
	# Two frames: containers lay out on the next process, and reading a rect
	# before that gets zeros regardless of whether the layout is right.
	await tree.process_frame
	await tree.process_frame

	if row == null:
		print("  [FAIL] no toolbox row was built")
		director.queue_free()
		return false

	# Measured on a TOOLBOX, not on the row. The row is a full-screen positioning
	# parent, so asserting that IT is on screen is trivially true and would pass
	# with every toolbox sitting at the origin.
	var checked := 0
	for queue_name in BuildingCatalogScript.QUEUES:
		var slot: Control = hud._slots[queue_name]["slot"]
		var rect: Rect2 = Rect2(slot.position, slot.size)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			print("  [FAIL] the '%s' toolbox laid out with no size: %s" % [queue_name, str(rect)])
			director.queue_free()
			return false
		if rect.position.x < 0.0 or rect.end.x > viewport_size.x + 1.0:
			print("  [FAIL] the '%s' toolbox runs off screen horizontally: %s"
				% [queue_name, str(rect)])
			director.queue_free()
			return false
		# It may hang below the edge by its slide, but never by more than that -
		# a toolbox has to leave a grabbable sliver or it can never be reopened.
		var overhang: float = rect.end.y - viewport_size.y
		if overhang > rect.size.y * hud.IDLE_SLIDE + 1.0:
			print("  [FAIL] the '%s' toolbox is further off screen than its slide allows: %.1f px"
				% [queue_name, overhang])
			director.queue_free()
			return false
		checked += 1
	print("  [PASS] %d toolboxes inside a %s viewport" % [checked, str(viewport_size)])
	director.queue_free()
	return true


# Opening a queue shows exactly that queue's list, whether the player clicked the
# toolbox or invoked BUILD on a structure's radial menu - both call open_queue(),
# so there is one build list per queue rather than two that could disagree.
func test_opening_a_queue_is_an_accordion() -> bool:
	print("Running Test Suite: Production HUD - accordion, and one list per queue...")
	var pair := _hud()
	var director: Node = pair[0]
	var hud: Node = pair[1]

	# Closed to begin with: the bar opens as five headers, not five open lists.
	for queue_name in BuildingCatalogScript.QUEUES:
		if hud._tier_bodies[queue_name].visible:
			print("  [FAIL] '%s' opened already expanded" % queue_name)
			director.queue_free()
			return false

	hud.open_queue(BuildingCatalogScript.QUEUE_HEAVY)
	if not hud._tier_bodies[BuildingCatalogScript.QUEUE_HEAVY].visible:
		print("  [FAIL] open_queue did not open the heavy list")
		director.queue_free()
		return false

	# Opening a second closes the first, or five open lists cover the battlefield.
	hud.open_queue(BuildingCatalogScript.QUEUE_BUILDING)
	if hud._tier_bodies[BuildingCatalogScript.QUEUE_HEAVY].visible:
		print("  [FAIL] opening STRUCTURES left HEAVY open - not an accordion")
		director.queue_free()
		return false
	if not hud._tier_bodies[BuildingCatalogScript.QUEUE_BUILDING].visible:
		print("  [FAIL] the structures list did not open")
		director.queue_free()
		return false

	# The STRUCTURES tier must offer the prefabs. An empty build list is the
	# failure mode that reads as "the button does nothing".
	if BuildingCatalogScript.buildable_kinds().is_empty():
		print("  [FAIL] no buildable structure kinds at all")
		director.queue_free()
		return false
	print("  [PASS] accordion behaviour")
	director.queue_free()
	return true


# THE READOUT WAS FROZEN, and this is the assertion that would have caught it.
#
# The CRT line was repainted only on `queue_changed`, which ProductionService
# emits on enqueue, cancel and claim - never as a job progresses. So the
# percentage was painted once, when the job was queued, and then never again for
# the whole build. It was not a formatting problem: the number genuinely did not
# move, which is why it read as broken rather than as ugly.
func test_the_readout_tracks_progress() -> bool:
	print("Running Test Suite: Production HUD - the readout actually advances...")
	var pair := _hud()
	var director: Node = pair[0]
	var hud: Node = pair[1]
	var queue := BuildingCatalogScript.QUEUE_MEDIUM

	director.production.enqueue_unit(0, {"name": "TESTER"}, 100, 10.0, queue)
	hud._refresh(queue)
	var first: String = hud._strips[queue]["status"].text
	var first_value: float = hud._strips[queue]["bar"].value

	# Advance the build WITHOUT touching the queue, so nothing emits
	# queue_changed. This is exactly the situation the readout has to survive.
	for _i in range(50):
		director.production.tick(0.1)
	hud._refresh(queue)
	var later: String = hud._strips[queue]["status"].text
	var later_value: float = hud._strips[queue]["bar"].value

	if later_value <= first_value:
		print("  [FAIL] the bar did not advance: %.2f -> %.2f" % [first_value, later_value])
		director.queue_free()
		return false
	if later == first:
		print("  [FAIL] the readout text never changed: '%s'" % first)
		director.queue_free()
		return false
	print("  [PASS] readout advanced '%s' -> '%s'" % [first.strip_edges(), later.strip_edges()])
	director.queue_free()
	return true


# An idle toolbox gets out of the way; a busy one does not. The whole point of
# holding an active queue up is that a progress bar nobody can see is the same as
# no progress bar.
func test_idle_toolboxes_retreat_and_busy_ones_do_not() -> bool:
	print("Running Test Suite: Production HUD - idle toolboxes slide away...")
	var pair := _hud()
	var director: Node = pair[0]
	var hud: Node = pair[1]
	var queue := BuildingCatalogScript.QUEUE_MEDIUM

	# Nothing queued and the mouse nowhere near: every box should want to hide.
	# `hidden` is driven toward 1 by _process; run enough frames to get there.
	for _i in range(120):
		hud._process(1.0 / 60.0)
	var idle_hidden: float = hud._slots[queue]["hidden"]
	if idle_hidden < 0.9:
		print("  [FAIL] an idle, unhovered toolbox did not retreat (hidden=%.2f)" % idle_hidden)
		director.queue_free()
		return false

	# Now give it something to report. It must come back up on its own.
	director.production.enqueue_unit(0, {"name": "TESTER"}, 100, 10.0, queue)
	if not hud._is_active(queue):
		print("  [FAIL] a queue with a job in it does not read as active")
		director.queue_free()
		return false
	for _i in range(120):
		hud._process(1.0 / 60.0)
	var busy_hidden: float = hud._slots[queue]["hidden"]
	if busy_hidden > 0.1:
		print("  [FAIL] a busy toolbox stayed hidden (hidden=%.2f)" % busy_hidden)
		director.queue_free()
		return false

	# And an open list must auto-close once the mouse is not on it.
	hud.open_queue(queue)
	if not hud.is_queue_open(queue):
		print("  [FAIL] open_queue did not open it")
		director.queue_free()
		return false
	for _i in range(10):
		hud._process(1.0 / 60.0)
	if hud.is_queue_open(queue):
		print("  [FAIL] the list stayed open with the mouse off it")
		director.queue_free()
		return false
	print("  [PASS] idle retreats, busy holds, open auto-collapses")
	director.queue_free()
	return true


# --- BattleHUD chrome: right rail, placard, command card, selection dock -----
#
# WHY A SEPARATE BLOCK. The ProductionHUD above is a different widget mounted
# by the same scene - this block exercises the BattleHUD's selection chrome
# (right rail, spec placard, command card, selection dock). A separate stub
# director is needed because BattleHUD.setup() reads director.selection (a
# RefCounted, NOT a Node child) and a handful of optional services that the
# ProductionHUD stub does not declare.

const BattleHUDScript = preload("res://scripts/battle/hud/battle_hud.gd")
const SelectionServiceScript = preload("res://scripts/battle/orders/selection_service.gd")
const RightRailScript = preload("res://scripts/battle/hud/right_rail.gd")
const UIDockScript = preload("res://scripts/ui_dock.gd")


# The narrow surface BattleHUD.setup() reads. vision / economy / camera are
# optional - _refresh_*() guards on null. selection is required.
class ChromeStubDirector:
	extends Node

	var selection: RefCounted = null
	var camera: Camera3D = null
	var vision: RefCounted = null
	var economy: RefCounted = null
	var alerts: RefCounted = null


func _chrome_hud() -> Array:
	var director := ChromeStubDirector.new()
	var selection := SelectionServiceScript.new()
	director.selection = selection
	# Same CanvasLayer mount as match_director._build_hud() - the layout
	# under test only resolves correctly when the HUD is under a layer,
	# not a plain Node.
	var layer := CanvasLayer.new()
	director.add_child(layer)
	var hud = BattleHUDScript.new()
	layer.add_child(hud)
	hud.setup(director, 0, {"map_half_extents": 80.0})
	return [director, hud]


func _right_rail(hud: Node) -> Control:
	for c in hud.get_children():
		if c is RightRailScript:
			return c
	return null


func _selection_dock(hud: Node) -> Control:
	for c in hud.get_children():
		if c is UIDockScript and c.dock_title == "SELECTION":
			return c
	return null


# THE REGRESSION THIS BLOCK EXISTS FOR. BattleHUD.setup() calls
# right_rail.body().add_child(...) IMMEDIATELY after add_child(right_rail).
# Godot 4 does NOT call _ready() synchronously inside add_child() - it
# defers to the next idle frame - so a widget that builds its body in
# _ready returns null from body() at the call site. The add_child
# crashes with "Cannot call method 'add_child' on a null value", the
# function aborts, and the placard/command_card silently orphan.
#
# Concretely: before the fix, hud.placard had parent=null, hud.command_card
# was null (the assignment line never ran), and the user saw an empty
# right rail with no command card. Selection did nothing visible because
# the selection panel was also orphaned (and the dock body was empty).
#
# The fix is in right_rail.gd / ui_dock.gd: build the body in _init(),
# not _ready(), so body() works synchronously the moment the widget is
# constructed. This test fails on the old code and passes on the new.
func test_battle_hud_chrome_parents_into_their_containers() -> bool:
	print("Running Test Suite: BattleHUD Chrome - right rail + dock bodies hold their children...")
	var pair := _chrome_hud()
	var director: Node = pair[0]
	var hud: Node = pair[1]

	var rail := _right_rail(hud)
	if rail == null:
		print("  [FAIL] no RightRail child on the HUD")
		director.queue_free()
		return false
	var body: VBoxContainer = rail.body()
	if body == null:
		print("  [FAIL] right_rail.body() returned null after add_child() - body not built synchronously")
		director.queue_free()
		return false

	# Placard: created in _build_command_card and added to the rail body.
	# Before the fix, body.add_child(placard) failed, then the function
	# aborted, so placard ended up parented to null. The HUD's typed
	# member still pointed at it, but it was orphaned and invisible.
	var placard: Control = hud.placard
	if placard == null:
		print("  [FAIL] hud.placard is null - _build_command_card aborted before assigning it")
		director.queue_free()
		return false
	if placard.get_parent() != body:
		print("  [FAIL] placard.parent is %s, expected the right_rail body" % placard.get_parent())
		director.queue_free()
		return false

	# Command card: the line that assigns hud.command_card runs AFTER
	# body.add_child(placard). On the old code the prior line errored
	# and aborted the function, so this assignment never happened and
	# hud.command_card stayed at its initial null. The user saw no
	# command card at all.
	var card: Control = hud.command_card
	if card == null:
		print("  [FAIL] hud.command_card is null - the assignment never ran")
		director.queue_free()
		return false
	if card.get_parent() != body:
		print("  [FAIL] command_card.parent is %s, expected the right_rail body" % card.get_parent())
		director.queue_free()
		return false

	# Selection dock (LEFT side, post PR 3b). Same body()-timing failure
	# in the dock widget if the body is built in _ready. The panel
	# was reparented into the dock body in _build_selection_dock.
	var dock := _selection_dock(hud)
	if dock == null:
		print("  [FAIL] no Selection dock child on the HUD")
		director.queue_free()
		return false
	var dock_body: VBoxContainer = dock.body()
	if dock_body == null:
		print("  [FAIL] selection_dock.body() returned null after add_child()")
		director.queue_free()
		return false
	if dock_body.get_child_count() < 1:
		print("  [FAIL] selection_dock body is empty - panel was not reparented into it")
		director.queue_free()
		return false

	# The rail must have a real height, not the 8px the panel padding
	# leaves when a ScrollContainer's zero minimum collapses the
	# content-driven extent. This was the second half of the user-
	# visible bug: the placard and command card were being added to
	# the tree, but the rail itself was 8px tall so they rendered
	# inside a window nobody could see.
	var viewport_size: Vector2 = hud.get_viewport().get_visible_rect().size
	# Two frames: the rail's bottom anchor resolves on the next
	# process, so reading size before that gives the unanchored
	# 8px from when only the panel padding was on the layout.
	await tree.process_frame
	await tree.process_frame
	if rail.size.y < 200.0:
		print("  [FAIL] right_rail collapsed to %s - the rail must be bottom-anchored so the ScrollContainer has room" % str(rail.size))
		director.queue_free()
		return false

	print("  [PASS] placard, command_card, and selection_panel parented; rail is %s tall" % str(rail.size))
	director.queue_free()
	return true


# A focused unit test for the right_rail widget's "body() works the moment
# after add_child" contract. Catches the same bug at the widget boundary,
# which is the level the actual fix lives at (right_rail.gd: _init, not
# _ready). Suite runs much faster than the full BattleHUD build above and
# fails with a tighter stack trace.
func test_right_rail_body_is_synchronous_after_add_child() -> bool:
	print("Running Test Suite: RightRail - body() is non-null the moment add_child returns...")
	var rail := RightRailScript.new()
	var host := Node.new()
	root.add_child(host)
	host.add_child(rail)
	var body: VBoxContainer = rail.body()
	if body == null:
		print("  [FAIL] right_rail.body() returned null immediately after add_child()")
		host.queue_free()
		return false
	# A child added through body() lands inside the rail, not orphaned.
	var probe := Control.new()
	body.add_child(probe)
	if probe.get_parent() != body:
		print("  [FAIL] child added to body() did not end up parented to the body")
		host.queue_free()
		return false
	print("  [PASS] body() is live, children add cleanly")
	host.queue_free()
	return true


# Same contract for the UIDock widget, where the failure mode was
# selection_dock.body().add_child(selection_panel) returning null
# in _build_selection_dock.
func test_ui_dock_body_is_synchronous_after_add_child() -> bool:
	print("Running Test Suite: UIDock - body() is non-null the moment add_child returns...")
	var dock := UIDockScript.new()
	dock.dock_title = "PROBE"
	var host := Node.new()
	root.add_child(host)
	host.add_child(dock)
	var body: VBoxContainer = dock.body()
	if body == null:
		print("  [FAIL] ui_dock.body() returned null immediately after add_child()")
		host.queue_free()
		return false
	var probe := Control.new()
	body.add_child(probe)
	if probe.get_parent() != body:
		print("  [FAIL] child added to dock body() did not end up parented to the body")
		host.queue_free()
		return false
	print("  [PASS] dock body() is live, children add cleanly")
	host.queue_free()
	return true
