extends SceneTree
# Does a wheel over a toolbox stay OUT of the world camera?
#
# THE DEFECT. ScrollContainer accepts a wheel event only when the scroll value
# actually changes. A list that fits its window, or one already at its top or
# bottom, declines it - and an unaccepted GUI event walks up the ANCESTOR chain,
# so with a PASS-filtered toolbox it left the HUD entirely and reached the
# camera's _unhandled_input as a zoom. Both attempted fixes before this one
# failed in opposite directions (swallowing it in _input killed the list's own
# scrolling; a STOP-filtered plate never saw it, because a sibling drawn behind
# is not an ancestor), so this measures rather than reasons.
#
# NO HOVER SIMULATION. The toolboxes auto-collapse when the pointer leaves them,
# and get_global_mouse_position() reads the OS cursor, which a synthetic event
# cannot move - so a probe that tries to "hold the mouse over" a toolbox ends up
# testing its own plumbing. The list is opened directly and the wheel pushed
# before the next frame's auto-collapse can run.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --path . \
#          --script tools/probe_toolbox_scroll.gd

var _fails: int = 0


func _init():
	var battle = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	for _i in range(240):
		await process_frame

	var hud = battle.production_hud
	var entry: Dictionary = hud._slots["building"]
	# Opened TWICE on purpose. The first open lets the VBoxContainer re-measure
	# itself with the list visible - a container does not update its combined
	# minimum size in the same frame a child's `visible` changes - and the
	# auto-collapse then closes it again, because the OS cursor is at the origin.
	# The second open, its layout, and the wheel below all happen between frames,
	# so _process never gets a turn to close it.
	hud.open_queue("building")
	await process_frame
	await process_frame
	# Freeze the HUD's own _process. It drives auto-collapse and re-layout, and
	# the OS cursor sits at the origin in a headless run, so every awaited frame
	# closed the list and moved the rects out from under the measurement. What is
	# under test is INPUT ROUTING, which _process has nothing to do with.
	hud.set_process(false)
	hud.open_queue("building")
	hud._layout_toolboxes()

	var panel: Control = entry["panel"]
	var scroll = _find_scroll(panel)
	if scroll == null or not panel.visible:
		print("[FAIL] list did not open")
		quit(1)
		return

	var rect := Rect2(panel.global_position, panel.size)
	print("  list panel %s in a %s viewport" % [rect, hud.size])
	_check("list is fully on screen",
		rect.position.y >= 0.0 and rect.end.y <= hud.size.y)

	var target: Vector2 = rect.get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = root.get_final_transform() * target
	motion.global_position = motion.position
	root.push_input(motion)
	await process_frame
	for q in hud._slots:
		var pl = hud._slots[q]["plate"]
		print("    %-10s slot=%s plate=%s(%s)" % [q,
			Rect2(hud._slots[q]["slot"].position, hud._slots[q]["slot"].size),
			Rect2(pl.position, pl.size), pl.name])
	var hv = root.gui_get_hovered_control()
	print("  hovered at the list centre: %s" % [
		str(hv.get_path()) if hv != null else "<null>"])

	var before_height: float = battle.camera.height
	_wheel(target, MOUSE_BUTTON_WHEEL_DOWN)
	await process_frame
	_check("wheel over the list did NOT zoom the world",
		is_equal_approx(before_height, battle.camera.height))

	# The half that the FIRST attempted fix broke: absorbing the wheel is only
	# correct if the list still scrolls on the way.
	scroll.scroll_vertical = 0
	await process_frame
	_wheel(target, MOUSE_BUTTON_WHEEL_DOWN)
	await process_frame
	_check("list DID scroll", scroll.scroll_vertical > 0)

	# The same wheel at the END of the list, where the ScrollContainer has nowhere
	# left to go and declines outright. This is the case that leaked, and the one
	# a "the scroll container handles it" assumption misses.
	scroll.scroll_vertical = 1000000
	before_height = battle.camera.height
	_wheel(target, MOUSE_BUTTON_WHEEL_DOWN)
	await process_frame
	_check("wheel at the END of the list still did NOT zoom",
		is_equal_approx(before_height, battle.camera.height))

	# The control case. Absorbing everything everywhere would be its own bug.
	var ground := Vector2(60.0, hud.size.y * 0.4)
	before_height = battle.camera.height
	_wheel(ground, MOUSE_BUTTON_WHEEL_DOWN)
	await process_frame
	_check("wheel over the battlefield still zooms",
		not is_equal_approx(before_height, battle.camera.height))

	print("")
	print("PASS" if _fails == 0 else "%d CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


# Control rects live in stretched viewport space; push_input takes WINDOW pixels
# and applies the stretch itself, so a synthetic event has to be converted the
# other way with the FORWARD final transform. Verified against
# gui_get_hovered_control(): pushing a raw viewport coordinate landed 1.126x too
# far out - a point in the middle of the STRUCTURES list resolved to the DEFENCES
# plate two columns to its right, which is what made the first runs of this probe
# look like an input-routing bug when the aim was simply wrong.
func _wheel(at: Vector2, button: int) -> void:
	var window_pos: Vector2 = root.get_final_transform() * at
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = window_pos
		ev.global_position = window_pos
		ev.factor = 1.0
		root.push_input(ev)


func _find_scroll(node: Node):
	if node is ScrollContainer:
		return node
	for child in node.get_children():
		var found = _find_scroll(child)
		if found != null:
			return found
	return null


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1
