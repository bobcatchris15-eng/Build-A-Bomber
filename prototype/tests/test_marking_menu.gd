extends "res://tests/suite_base.gd"

# Tactile Interface Programme Phase 7 Tests (Marking Menu, D9, D14)

const MarkingMenuScript = preload("res://scripts/ui/marking_menu.gd")
const RingDrawScript = preload("res://scripts/ui/ring_draw.gd")


func test_marking_menu_fast_flick_commits_without_drawing() -> bool:
	print("Running Test Suite: Marking Menu - Fast Flick Commits Without Drawing (Phase 7, D9)...")
	var menu = MarkingMenuScript.new()
	root.add_child(menu)

	var actions := [
		{"id": "north", "label": "NORTH", "enabled": true},
		{"id": "east", "label": "EAST", "enabled": true},
		{"id": "south", "label": "SOUTH", "enabled": true},
		{"id": "west", "label": "WEST", "enabled": true},
	]

	var res := {"committed": ""}
	menu.action_committed.connect(func(id: String): res["committed"] = id)

	var origin := Vector2(200, 200)
	menu.start_stroke(origin, actions, "NAV")

	# Move 40 px East (+X)
	var flick_pos := origin + Vector2(40, 0)
	menu.update_stroke(flick_pos)

	if menu.visible:
		print("  [FAIL] MarkingMenu became visible during rapid stroke (< 200ms)")
		menu.queue_free()
		return false

	menu.end_stroke(flick_pos)

	if res["committed"] != "east":
		print("  [FAIL] Fast flick (+X) did not commit 'east', got: '%s'" % res["committed"])
		return false

	print("  [PASS] Fast flick committed 'east' without ever setting visible=true.")
	return true


func test_marking_menu_hold_reveals_dial() -> bool:
	print("Running Test Suite: Marking Menu - Hold Reveals Ring (Phase 7)...")
	var menu = MarkingMenuScript.new()
	root.add_child(menu)

	var actions := [
		{"id": "a", "label": "A"},
		{"id": "b", "label": "B"},
	]
	menu.start_stroke(Vector2(200, 200), actions)
	# Artificial time warp to exceed 200ms
	menu._press_time_msec -= 250
	menu.update_stroke(Vector2(205, 200))

	if not menu.visible or not menu._revealed:
		print("  [FAIL] MarkingMenu did not reveal after >= 200ms hold")
		menu.queue_free()
		return false

	menu.queue_free()
	print("  [PASS] Hold >= 200ms revealed the radial ring dial.")
	return true


func test_marking_menu_hub_release_cancels() -> bool:
	print("Running Test Suite: Marking Menu - Hub Release Cancels (Phase 7)...")
	var menu = MarkingMenuScript.new()
	root.add_child(menu)

	var actions := [{"id": "cmd", "label": "CMD"}]
	var res := {"committed": "", "dismissed": false}
	menu.action_committed.connect(func(id: String): res["committed"] = id)
	menu.dismissed.connect(func(): res["dismissed"] = true)

	var origin := Vector2(200, 200)
	menu.start_stroke(origin, actions)
	menu._press_time_msec -= 250
	menu.update_stroke(origin + Vector2(5, 5))

	# Release inside hub (< 30 px)
	menu.end_stroke(origin + Vector2(10, 10))

	if res["committed"] != "" or not res["dismissed"]:
		print("  [FAIL] Hub release committed '%s' instead of cancelling" % res["committed"])
		return false

	print("  [PASS] Releasing inside the hub correctly cancels the action.")
	return true


func test_marking_menu_unbounded_sector_release_commits() -> bool:
	print("Running Test Suite: Marking Menu - Unbounded Sector Release Commits (Phase 7)...")
	var menu = MarkingMenuScript.new()
	root.add_child(menu)

	var actions := [
		{"id": "north", "label": "NORTH", "enabled": true},
		{"id": "east", "label": "EAST", "enabled": true},
		{"id": "south", "label": "SOUTH", "enabled": true},
		{"id": "west", "label": "WEST", "enabled": true},
	]

	var res := {"committed": ""}
	menu.action_committed.connect(func(id: String): res["committed"] = id)

	var origin := Vector2(200, 200)
	menu.start_stroke(origin, actions)
	menu._press_time_msec -= 250
	menu.update_stroke(origin + Vector2(0, 150))

	# Release far to the South (+Y, 300px out, far beyond outer radius)
	menu.end_stroke(origin + Vector2(0, 300))

	if res["committed"] != "south":
		print("  [FAIL] Unbounded sector release did not commit 'south', got: '%s'" % res["committed"])
		return false

	print("  [PASS] Releasing beyond outer radius commits the angular sector.")
	return true


func test_marking_menu_short_stroke_cancels() -> bool:
	print("Running Test Suite: Marking Menu - Short Stroke Cancels (Phase 7)...")
	var menu = MarkingMenuScript.new()
	root.add_child(menu)

	var actions := [{"id": "act", "label": "ACTION"}]
	var res := {"committed": "", "dismissed": false}
	menu.action_committed.connect(func(id: String): res["committed"] = id)
	menu.dismissed.connect(func(): res["dismissed"] = true)

	var origin := Vector2(200, 200)
	menu.start_stroke(origin, actions)
	# Short stroke: 8px (< 24px) released at 100ms
	menu.end_stroke(origin + Vector2(8, 0))

	if res["committed"] != "" or not res["dismissed"]:
		print("  [FAIL] Short stroke should cancel without committing, got committed: '%s'" % res["committed"])
		return false

	print("  [PASS] Short stroke (< 24px) cancels safely.")
	return true
