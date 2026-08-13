class_name CommandRegistry
extends Node
# The single source of truth for what commands the command card, the
# marking menu (Phase 7) and the tutorial may show.
#
# Before it, command_card.gd hand-rolled its own list of which actions
# the card surfaces and in which order - a list that was already wrong
# once (it claimed A and S were the keys while InputService had them on
# F and G, the X1 fix). Folding the action set into one registry means
# the card, the marking menu and any future surface read the same
# shape, with no chance to disagree about which commands exist.
#
# WHY 3x4. The Tactile Interface Programme Part 1, D6 settled this:
# row 1 = R F G T, row 2 = Z X C V, row 3 = mouse-only overflow, no
# default keys. The number row stays control-group recall.
#
# WHY A NODE, NOT A PURE STATIC CLASS. A few reasons, all of them real:
#   * the `registry_changed` signal needs an instance to emit on
#   * the design system wants the registry to be reachable as an
#     autoload (`/root/CommandRegistry`) so call sites read
#     `CommandRegistry.action_at(...)` without keeping a handle
#   * tests instantiate one freely; nothing forces it to live in the tree
#
# Entries are POSITIONAL AND STABLE - the same command lives in the
# same (row, col) across every selection. An unavailable command renders
# as a disabled cell, not a gap. That invariant is what makes the
# positional binding work: muscle memory for "F is attack-move" only
# pays off if F is attack-move every time you reach for it.

signal registry_changed

# The static action set, in (row, col) order. Phase 8 ships the eight
# keyboard cells D6 calls for plus a row 3 of four mouse-only placeholders
# so the card's geometry is 3x4 = 12 from day one - the row 3 cells are
# reserved for future mouse-only verbs (formation presets, etc.) and
# render as disabled placeholders until those actions land.
#
# Each entry:
#   id                  stable id used by tests and the tutorial
#   action              the InputService action id this command issues
#                       ("" for the row-3 placeholders; they have no
#                       binding)
#   label               the title the card prints under the icon
#   icon                the UIIcons key for the cell's icon
#   row, col            1-indexed position on the 3x4 grid
#   enabled_predicate   optional Callable(selected: Array) -> bool; when
#                       absent, the entry is always available for a
#                       non-empty selection
#
# ORDERING: read this list by (row, col) ascending to render the card
# in physical order. entries() preserves ENTRIES order.
const ENTRIES: Array = [
	{"id": "patrol", "action": "cmd_patrol", "label": "Patrol", "icon": "cmd_patrol", "row": 1, "col": 1},
	{"id": "attack_move", "action": "cmd_attack_move", "label": "Attack-move", "icon": "cmd_attack_move", "row": 1, "col": 2},
	{"id": "stop", "action": "cmd_stop", "label": "Stop", "icon": "cmd_stop", "row": 1, "col": 3},
	{"id": "set_rally", "action": "cmd_set_rally", "label": "Set rally", "icon": "cmd_rally", "row": 1, "col": 4},

	{"id": "stance_aggressive", "action": "cmd_stance_aggressive", "label": "Aggressive", "icon": "cmd_stance_aggressive", "row": 2, "col": 1},
	{"id": "stance_return_fire", "action": "cmd_stance_return_fire", "label": "Return Fire", "icon": "cmd_stance_return_fire", "row": 2, "col": 2},
	{"id": "hold", "action": "cmd_hold", "label": "Hold", "icon": "cmd_hold", "row": 2, "col": 3},
	{"id": "stance_hold_fire", "action": "cmd_hold_fire", "label": "Hold Fire", "icon": "cmd_stance_hold", "row": 2, "col": 4},

	# Row 3: mouse-only overflow. No default key bindings; the cell is
	# reserved for verbs the next phase (formation presets, etc.) will
	# define. action="" so the cell has no InputService entry to claim
	# a binding from.
	{"id": "formation_wedge", "action": "", "label": "Wedge", "icon": "menu", "row": 3, "col": 1},
	{"id": "formation_line", "action": "", "label": "Line", "icon": "menu", "row": 3, "col": 2},
	{"id": "formation_column", "action": "", "label": "Column", "icon": "menu", "row": 3, "col": 3},
	{"id": "spread", "action": "", "label": "Spread", "icon": "menu", "row": 3, "col": 4},
]


# Every registered entry, with the per-entry `enabled` field filled in by
# the current selection's predicate. Order matches ENTRIES.
#
# A command whose action is "" (the row-3 placeholders) is reported as
# `enabled = false` regardless of selection: there is no keybinding and no
# order path; the cell is reserved space, not a working verb.
func entries() -> Array[Dictionary]:
	return _entries_for([])


# The same set as entries(), but for a real selection. This is the call
# the card uses; `entries()` exists for callers that want the static
# shape (a tutorial overlay, a debug inspector, the marking menu's
# pre-filter pass) and is implemented as a no-selection entries_for.
func entries_for_selection(selected: Array) -> Array[Dictionary]:
	return _entries_for(selected)


# Public selection-aware predicate. Mirrors the per-entry logic in
# _is_enabled; exposed so a UI layer can ask "is this single command
# available right now" without rebuilding the full entries list.
func is_action_available(action: String, selected: Array) -> bool:
	if action == "":
		return false
	for e in ENTRIES:
		if String(e["action"]) == action:
			return _is_enabled(e, selected)
	return false


# What action id occupies the given (row, col), or "" if no entry does.
# Used by the card to map a clicked cell back to an action without
# keeping its own (row, col) -> action table.
static func action_at(row: int, col: int) -> String:
	for e in ENTRIES:
		if int(e["row"]) == row and int(e["col"]) == col:
			return String(e["action"])
	return ""


# Inverse of action_at: the (row, col) for a given action id, or (-1, -1)
# if the action is not registered. Useful for tests and for the tutorial
# when it needs to point at a specific cell.
static func row_col_for_action(action: String) -> Vector2i:
	for e in ENTRIES:
		if String(e["action"]) == action:
			return Vector2i(int(e["row"]), int(e["col"]))
	return Vector2i(-1, -1)


# All (row, col) pairs in physical render order. The card uses this to
# size its grid; the test suite uses it to assert uniqueness.
static func all_positions() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for e in ENTRIES:
		out.append(Vector2i(int(e["row"]), int(e["col"])))
	return out


# The number of rows / columns on the card. Currently 3 rows by 4 columns
# per D6. The card reads these rather than hardcoding 3 / 4 so a future
# addition (a row 4, a row 3 that grows to 5 columns) is a one-line
# change here.
const ROWS: int = 3
const COLUMNS: int = 4


func _entries_for(selected: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in ENTRIES:
		var entry: Dictionary = e.duplicate()
		entry["enabled"] = _is_enabled(entry, selected)
		out.append(entry)
	return out


func _is_enabled(entry: Dictionary, selected: Array) -> bool:
	# Reserved row-3 placeholders: never enabled until an action lands.
	if String(entry.get("action", "")) == "":
		return false
	# Per-entry predicate takes precedence if present. The interface is
	# stable for future phases to extend without changing this file.
	if entry.has("enabled_predicate") and entry["enabled_predicate"] is Callable:
		return bool((entry["enabled_predicate"] as Callable).call(selected))
	# Default: any non-empty selection can issue any registered command.
	# Per-unit gating (harvesters can't hold position, etc.) lands with
	# the selection-panel work in Phase 9.
	return not selected.is_empty()
