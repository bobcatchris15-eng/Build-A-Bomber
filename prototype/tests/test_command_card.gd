extends "res://tests/suite_base.gd"
# Phase 8 command card suites. Registration order lives in run_tests.gd's
# SUITE_ORDER, not here.
#
# WHAT THIS FILE GUARDS.
#
# The X1 fix in commit 7ee68e0 made the card data-driven and bound its
# on-cell key text to InputService.binding_label. The X1 fix in code
# had happened earlier; what 7ee68e0 killed was the lying UI - the
# card was claiming A and S were the keys while the action table had
# moved attack-move and stop to F and G. The first test in this file
# is the regression guard for that, and it is the one that must outlive
# this phase.
#
# The remaining tests pin Phase 8's load-bearing invariants:
#   * CommandRegistry is the single source of the action set
#   * the card renders 3x4 = 12 cells
#   * a rebind is reflected on the card without restart
#   * the lying "(A)"/"(S)" suffixes are gone from every cell's label
#     and tooltip
#   * attack-move arming actually changes the cursor (X7)

const InputServiceScript = preload("res://scripts/core/input_service.gd")
const CursorManagerScript = preload("res://scripts/cursor_manager.gd")
const CommandCardScript = preload("res://scripts/ui/command_card.gd")
const CommandRegistryScript = preload("res://scripts/battle/orders/command_registry.gd")


# THE X1 REGRESSION GUARD. The card used to ship the literal strings
# "Attack Move (A)" and "Stop (S)" while InputService had those actions
# on F and G. A-Move and Stop are the two highest-traffic commands in
# the build, and the card was the only source a player had for the key
# claim, so the lie was the entire bug. No cell in the rebuilt card
# may carry those suffixes; a card that ever does, again, is a card
# that is back to lying.
func test_command_card_lying_labels_are_gone() -> bool:
	print("Running Test Suite: CommandCard - No Lying '(A)' / '(S)' Suffixes (X1)...")
	var card = _make_card()
	if card == null:
		return false

	for i in range(card._grid.get_child_count()):
		var cell: Control = card._grid.get_child(i) as Control
		var key_label: Label = cell.get_node_or_null("Key") as Label
		if key_label == null and cell.has_meta("vbox"):
			var vbox = cell.get_meta("vbox")
			if vbox is Node and vbox.has_node("Key"):
				key_label = vbox.get_node("Key") as Label
		var label_node = cell.get_node_or_null("Label")
		var label_text = label_node.text if label_node is Label else ("" if not "legend" in cell else cell.legend)
		var key_text = key_label.text if key_label != null else ""
		var tooltip_text = cell.tooltip_text if "tooltip_text" in cell else ""
		if cell.has_meta("button"):
			var b = cell.get_meta("button")
			if b is Button and b.tooltip_text != "":
				tooltip_text = b.tooltip_text

		for text in [label_text, key_text, tooltip_text]:
			if text == null:
				continue
			if text.contains(" (A)") or text.contains(" (S)"):
				print("  [FAIL] cell %d still carries the stale key suffix: '%s'" % [i, text])
				card.queue_free()
				await tree.process_frame
				return false

	card.queue_free()
	await tree.process_frame
	print("  [PASS] No cell label or tooltip ends in ' (A)' or ' (S)'.")
	return true


# Every CommandRegistry entry must occupy a unique (row, col) cell. Two
# commands on the same cell is the kind of bug that breaks the card's
# whole reason to be: positional binding is only worth building if the
# position is stable, and "stable" means the same command at the same
# (row, col) every time.
func test_command_card_row_col_is_unique_per_entry() -> bool:
	print("Running Test Suite: CommandRegistry - (row, col) Unique Per Entry...")
	var seen: Dictionary = {}
	for e in CommandRegistryScript.ENTRIES:
		var pos := Vector2i(int(e["row"]), int(e["col"]))
		if seen.has(pos):
			print("  [FAIL] Two entries share (row=", pos.x, ", col=", pos.y,
				"): '%s' and '%s'" % [seen[pos], e["id"]])
			return false
		seen[pos] = e["id"]
	print("  [PASS] ", seen.size(), " unique (row, col) cells across the registry.")
	return true


# The card's cells must be drawn from CommandRegistry, not from a
# hand-rolled list. The lie in the pre-Phase-8 card was a hand-rolled
# list disagreeing with InputService; a registry-driven card can't
# drift because it is reading the same source as the action table's
# bindings.
#
# And the cell labels must come from InputService.binding_label, not
# from a hardcoded string. Asserting that means walking every cell
# and checking its key label against InputService.binding_label for
# the action CommandRegistry puts in that cell.
func test_command_card_cells_are_data_driven() -> bool:
	print("Running Test Suite: CommandCard - Cells Are Registry-Driven And Labeled From InputService...")
	var card = _make_card()
	if card == null:
		return false
	var input_svc := _resolve_input_service()
	if input_svc == null:
		print("  [FAIL] No InputService autoload and could not instantiate one")
		card.queue_free()
		await tree.process_frame
		return false

	var reg = _resolve_registry()
	if reg == null:
		print("  [FAIL] No CommandRegistry available")
		card.queue_free()
		await tree.process_frame
		return false

	# Wire a stub selection so the card is not in the "no selection"
	# state. The card reads selection.selected; the test does not care
	# about its contents, only that the cells are non-empty.
	card._director.selection = _StubSelection.new()

	# Refresh manually rather than going through selection_changed so the
	# test does not depend on signal connection timing.
	card._on_selection_changed([Node.new()])
	await tree.process_frame

	var entries: Array = reg.entries_for_selection([Node.new()])
	var by_pos: Dictionary = {}
	for e in entries:
		by_pos[Vector2i(int(e["row"]), int(e["col"]))] = e

	var positions: Array = CommandRegistryScript.all_positions()
	for i in range(positions.size()):
		var pos: Vector2i = positions[i]
		var cell: Control = card._grid.get_child(i) as Control
		var key_label: Label = cell.get_node_or_null("Key") as Label
		if key_label == null and cell.has_meta("vbox"):
			var vbox = cell.get_meta("vbox")
			if vbox is Node and vbox.has_node("Key"):
				key_label = vbox.get_node("Key") as Label
		var button: Button = cell.get_meta("button") as Button if cell.has_meta("button") else cell as Button
		if not by_pos.has(pos):
			print("  [FAIL] cell (", pos.x, ",", pos.y, ") has no registry entry backing it")
			card.queue_free()
			await tree.process_frame
			return false
		var entry: Dictionary = by_pos[pos]
		var action: String = String(entry["action"])
		if action == "":
			# Reserved row-3 placeholder: no key expected.
			if key_label != null and key_label.text != "":
				print("  [FAIL] placeholder cell (", pos.x, ",", pos.y,
					") should have empty key label, got '", key_label.text, "'")
				card.queue_free()
				await tree.process_frame
				return false
			continue
		var expected_key: String = input_svc.binding_label(action)
		var actual_key: String = key_label.text if key_label != null else ""
		if actual_key != expected_key:
			print("  [FAIL] cell (", pos.x, ",", pos.y, ") for action '", action,
				"' shows key '", actual_key, "' but InputService says '", expected_key, "'")
			card.queue_free()
			await tree.process_frame
			return false
		var expected_tooltip: String = "%s (%s)" % [String(entry["label"]), input_svc.binding_label_all(action)]
		var actual_tooltip: String = button.tooltip_text if button != null else cell.tooltip_text
		if actual_tooltip != expected_tooltip:
			print("  [FAIL] cell (", pos.x, ",", pos.y, ") tooltip '", actual_tooltip,
				"' does not match '", expected_tooltip, "'")
			card.queue_free()
			await tree.process_frame
			return false

	card.queue_free()
	await tree.process_frame
	print("  [PASS] Every cell is registry-driven and labeled from InputService.")
	return true


# THE BINDING REFRESH TEST. A player who rebinds F to H must see H on
# the card immediately - the whole point of the data-driven refactor
# is that the card and the action table are the same source. Without
# the bindings_changed subscription, a rebind would be invisible on
# the card until the next selection change.
func test_command_card_rebind_refreshes_label() -> bool:
	print("Running Test Suite: CommandCard - Rebind Refreshes The Cell Label...")
	var input_svc := _resolve_input_service()
	if input_svc == null:
		print("  [FAIL] No InputService autoload and could not instantiate one")
		return false

	var card = _make_card()
	if card == null:
		return false

	card._director.selection = _StubSelection.new()
	card._on_selection_changed([Node.new()])
	await tree.process_frame

	# The attack-move cell is at (1, 2) per the registry; verify it shows
	# the current binding before and after a rebind.
	var attack_pos := CommandRegistryScript.row_col_for_action("cmd_attack_move")
	if attack_pos.x < 0:
		print("  [FAIL] cmd_attack_move is not in the registry at all")
		card.queue_free()
		await tree.process_frame
		return false
	var cell_index := CommandRegistryScript.all_positions().find(attack_pos)
	var cell: Control = card._grid.get_child(cell_index) as Control
	var key_label: Label = cell.get_node_or_null("Key") as Label
	if key_label == null and cell.has_meta("vbox"):
		var vbox = cell.get_meta("vbox")
		if vbox is Node and vbox.has_node("Key"):
			key_label = vbox.get_node("Key") as Label

	# Pre-rebind: F is the canonical default.
	if key_label.text != "F":
		print("  [FAIL] Pre-rebind cell label was '", key_label.text,
			"', expected 'F' (the X1 fix put cmd_attack_move on F)")
		card.queue_free()
		await tree.process_frame
		return false

	# Rebind and confirm the signal subscriber re-renders the cell.
	input_svc.rebind("cmd_attack_move", [{"key": KEY_H}])
	await tree.process_frame

	if key_label.text != "H":
		print("  [FAIL] Post-rebind cell label was '", key_label.text,
			"', expected 'H' (the card did not refresh from bindings_changed)")
		input_svc.reset_action("cmd_attack_move")
		card.queue_free()
		await tree.process_frame
		return false

	input_svc.reset_action("cmd_attack_move")
	card.queue_free()
	await tree.process_frame
	print("  [PASS] Rebinding cmd_attack_move to H was reflected on the card without restart.")
	return true


# The card must be 3 rows by 4 columns = 12 cells. D6. The rows and
# columns are documented in CommandRegistry.ROWS and .COLUMNS so this
# test can read them rather than hardcoding 3 / 4 - any future change
# to the geometry lands in the registry and the test follows.
func test_command_card_geometry_is_3_by_4() -> bool:
	print("Running Test Suite: CommandCard - 3x4 Geometry (D6)...")
	var card = _make_card()
	if card == null:
		return false

	var child_count: int = card._grid.get_child_count()
	var expected: int = CommandRegistryScript.ROWS * CommandRegistryScript.COLUMNS
	if child_count != expected:
		print("  [FAIL] Expected ", expected, " cells (",
			CommandRegistryScript.ROWS, "x", CommandRegistryScript.COLUMNS,
			"), got ", child_count)
		card.queue_free()
		await tree.process_frame
		return false

	# The grid's columns property must match. A GridContainer with the
	# wrong columns count silently reshapes the layout.
	if card._grid.columns != CommandRegistryScript.COLUMNS:
		print("  [FAIL] grid.columns = ", card._grid.columns,
			", expected ", CommandRegistryScript.COLUMNS)
		card.queue_free()
		await tree.process_frame
		return false

	card.queue_free()
	await tree.process_frame
	print("  [PASS] ", child_count, " cells in a ", CommandRegistryScript.ROWS,
		"x", CommandRegistryScript.COLUMNS, " grid.")
	return true


# THE X7 TEST. The pre-Phase-8 cursor was text-only. After Phase 8,
# arming attack-move (the F key OR the (1, 2) cell on the card) sets
# the cursor to ATTACK immediately. This drives the arming path
# directly: a real Battle, a real selection, then a direct call to
# match_director._set_armed(true).
#
# Using the seam directly keeps the test honest about what the
# contract is: X7 is "arming changes the cursor", not "any key
# press changes the cursor", so the test exercises the actual
# arming function and asserts the cursor's resulting type.
func test_attack_move_arming_changes_cursor() -> bool:
	print("Running Test Suite: X7 - Arming Attack-Move Changes The Cursor...")
	var cursor_mgr := _resolve_cursor_manager()
	if cursor_mgr == null:
		print("  [FAIL] No CursorManager autoload")
		return false

	var battle = preload("res://scenes/Battle.tscn").instantiate()
	battle.map_id = "open_plains"
	root.add_child(battle)
	current_scene = battle
	var guard := 0
	while not battle.world_is_ready and guard < 3000:
		await tree.process_frame
		guard += 1
	if not battle.world_is_ready:
		print("  [FAIL] Battle never finished building open_plains.")
		battle.queue_free()
		return false

	# A baseline cursor state: DEFAULT. The pre-arm state the test starts
	# from. A battle where the cursor is already ATTACK before the test
	# arms attack-move is a battle the test cannot interpret, so fail
	# loudly rather than silently.
	if cursor_mgr._current_cursor == cursor_mgr.CursorType.ATTACK:
		print("  [FAIL] Cursor was already ATTACK before arming - the test starts from a wrong state")
		battle.queue_free()
		return false

	# Drive the exact arming seam. The pre-Phase-8 _set_armed() only
	# updated the hint label; the post-Phase-8 _set_armed() also
	# writes the cursor. A test that drives the press handler instead
	# would couple to InputMap events, which is more than X7 is about.
	battle._set_armed(true)
	if cursor_mgr._current_cursor != cursor_mgr.CursorType.ATTACK:
		print("  [FAIL] _set_armed(true) did not set the cursor to ATTACK; cursor is ",
			cursor_mgr._current_cursor)
		battle._set_armed(false)
		battle.queue_free()
		return false

	battle._set_armed(false)
	if cursor_mgr._current_cursor == cursor_mgr.CursorType.ATTACK:
		# On disarm the cursor re-resolves from the current hover. In a
		# headless run the mouse position is (0, 0) and the resolution
		# may pick ATTACK again if a hostile happens to be under the
		# origin; that is not a regression of the X7 fix, it is the
		# hover path being right. Print a note rather than fail.
		print("  [NOTE] Cursor is still ATTACK after disarm (the hover path picked it up). The X7 fix is still verified by the arming-side assertion.")
	battle.queue_free()
	await tree.process_frame
	print("  [PASS] Arming attack-move switched the cursor to ATTACK.")
	return true


# --- helpers ---------------------------------------------------------------

# The card constructor needs a `director` with a selection service and a
# call to setup(). Both the test_input_and_settings and test_battle_hud
# files use stub classes for this; we do the same with a minimal
# SelectionService-shaped node.
class _StubSelection:
	extends Node

	signal selection_changed(units: Array)
	var selected: Array = []

	func add(_units: Array) -> void:
		pass

	func clear() -> void:
		pass


class _StubDirector:
	extends Node

	var selection = _StubSelection.new()
	var orders = null
	var camera = null


func _make_card() -> CommandCardScript:
	# Headless tests instantiate the card directly. Adding to root is
	# required for Godot's "is inside tree" checks the card's _ready()
	# and the GridContainer layout code both lean on.
	var card = CommandCardScript.new()
	root.add_child(card)
	var director = _StubDirector.new()
	root.add_child(director)
	# Add the selection service as a child of the director so setup()
	# can find it via _director.selection.
	director.add_child(director.selection)
	card.setup(director)
	return card


func _resolve_input_service() -> Node:
	var existing := root.get_node_or_null("/root/InputService")
	if existing != null:
		return existing
	var s = InputServiceScript.new()
	root.add_child(s)
	return s


func _resolve_registry() -> Node:
	var existing := root.get_node_or_null("/root/CommandRegistry")
	if existing != null:
		return existing
	var r = CommandRegistryScript.new()
	root.add_child(r)
	return r


func _resolve_cursor_manager() -> Node:
	var existing := root.get_node_or_null("/root/CursorManager")
	if existing != null:
		return existing
	var cm = CursorManagerScript.new()
	root.add_child(cm)
	return cm
