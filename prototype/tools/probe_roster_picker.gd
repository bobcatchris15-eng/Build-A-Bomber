extends SceneTree
# Renders MatchSetup so the roster tray can be looked at.
#
# Layout intent - "larger slots, filling the whole bottom segment side by side" -
# is not something an assert can judge, but the two things that would make it
# fail ARE measurable, so both are checked as well as captured: the slots must be
# on one row, and they must between them span the tray rather than packing left
# and leaving it empty.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --path . \
#          --script tools/probe_roster_picker.gd

var _fails: int = 0


func _init():
	root.add_child(load("res://scenes/MatchSetup.tscn").instantiate())
	for _i in range(120):
		await process_frame

	var picker = _find(root, "RosterPicker")
	if picker == null:
		print("[FAIL] no RosterPicker in MatchSetup")
		quit(1)
		return

	var slots: Array = picker._slots
	print("  %d slots" % slots.size())
	if slots.is_empty():
		print("[FAIL] no slots built")
		quit(1)
		return

	var rows := {}
	for slot in slots:
		rows[int(slot.global_position.y)] = true
	print("  distinct rows: %d" % rows.size())
	_check("slots are on a single row", rows.size() == 1)

	var first: Control = slots[0]
	var last: Control = slots[slots.size() - 1]
	var span: float = last.global_position.x + last.size.x - first.global_position.x
	var tray: float = picker._slot_grid.size.x
	print("  slot size %s   span %.0f of a %.0f tray" % [first.size, span, tray])
	_check("slots span the tray", span >= tray - 4.0)
	_check("slots are larger than the old 96x78 fixed size",
		first.size.x >= 96.0 and first.size.y > 78.0)

	root.get_texture().get_image().save_png("user://roster_picker.png")
	print("  wrote user://roster_picker.png")
	print("")
	print("PASS" if _fails == 0 else "%d CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


func _find(node: Node, cls: String):
	if node.get_class() == cls or (node.get_script() != null
			and str(node.get_script().get_global_name()) == cls):
		return node
	for child in node.get_children():
		var found = _find(child, cls)
		if found != null:
			return found
	return null


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1
