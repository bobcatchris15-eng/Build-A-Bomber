extends SceneTree
# Headless behavioural check for the phase-6 primitives: the radial action
# ring, the dock's three states, and the flyout's edge clamping.
#
# These assert BEHAVIOUR, not existence. "The class loads" would have passed
# against the half-built callout system this pass exists to finish, so each
# check here drives the thing and looks at where it actually ended up.
#
# Run: Godot_v4.3-stable_win64_console.exe --headless --script scratch/VerifyRadialAndDock.gd

const UIRadialMenuScript = preload("res://scripts/ui_radial_menu.gd")
const UIDockScript = preload("res://scripts/ui_dock.gd")
const UIFlyoutScript = preload("res://scripts/ui_flyout.gd")

var _pass := 0
var _fail := 0


func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s" % label)
	else:
		_fail += 1
		print("  [FAIL] %s" % label)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("\n=== Radial ring ===")
	await _test_ring()
	print("\n=== Dock ===")
	await _test_dock()
	print("\n=== Flyout ===")
	await _test_flyout()

	print("\n%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _test_ring() -> void:
	var host = Control.new()
	host.size = Vector2(1600, 900)
	root.add_child(host)

	var ring = UIRadialMenuScript.new()
	ring.subject_label = "AUTOCANNON"
	ring.add_action("rotate", "Rotate")
	ring.add_action("mirror", "Mirror")
	ring.add_action("detail", "Detail")
	ring.add_action("discard", "Discard")
	host.add_child(ring)
	ring.open_at(Vector2(800, 450))
	await process_frame

	_ok(ring.is_open(), "ring reports open after open_at()")

	# Centred on the point it was opened at, not anchored by its corner.
	var centre = ring.position + ring.size * 0.5
	_ok(centre.distance_to(Vector2(800, 450)) < 1.0,
		"ring centres on its open point (got %s)" % centre)

	# The hub is a dead zone: a click there must cancel, not invoke.
	var c = ring.size * 0.5
	_ok(ring._sector_at(c) == -1, "hub centre is a dead zone")
	_ok(ring._sector_at(c + Vector2(ring.RING_OUTER + 30.0, 0)) == -1,
		"outside the outer radius is a dead zone")

	# Four actions, first centred at TOP and going clockwise.
	var r = (ring.RING_INNER + ring.RING_OUTER) * 0.5
	var up = ring._sector_at(c + Vector2(0, -r))
	var right = ring._sector_at(c + Vector2(r, 0))
	var down = ring._sector_at(c + Vector2(0, r))
	var left = ring._sector_at(c + Vector2(-r, 0))
	_ok(up == 0, "action 0 sits at the top (got %d)" % up)
	_ok(right == 1, "action 1 sits to the right (got %d)" % right)
	_ok(down == 2, "action 2 sits at the bottom (got %d)" % down)
	_ok(left == 3, "action 3 sits to the left (got %d)" % left)

	# Every one of the four is reachable and they are all distinct - the check
	# that would catch an off-by-one in the half-sector rotation.
	var seen := {}
	for i in 4:
		seen[ring._sector_at(c + Vector2(0, -r).rotated(TAU * i / 4.0))] = true
	_ok(seen.size() == 4, "all four sectors are distinct and reachable")

	# _has_point rejects the bounding-box corners, so the viewport behind the
	# ring stays clickable.
	_ok(not ring._has_point(Vector2.ZERO), "bounding-box corner is not part of the ring")
	_ok(ring._has_point(c + Vector2(r, 0)), "a point on the band IS part of the ring")

	# Invoking emits before the node frees itself.
	var got := []
	ring.action_invoked.connect(func(id): got.append(id))
	var ev = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = c + Vector2(0, -r)
	ring._gui_input(ev)
	_ok(got == ["rotate"], "clicking the top sector emits its action (got %s)" % [got])
	_ok(not ring.is_open(), "ring closes after an action")

	host.queue_free()
	await process_frame


func _test_dock() -> void:
	var host = Control.new()
	host.size = Vector2(1600, 900)
	root.add_child(host)

	var dock = UIDockScript.new()
	dock.dock_title = "CATALOG"
	dock.side = UIDockScript.Side.LEFT
	dock.expanded_size = 320.0
	dock.persist_key = ""   # no writes to user://ui_layout.cfg from a test
	host.add_child(dock)
	await process_frame

	var content = Label.new()
	content.text = "x"
	content.custom_minimum_size = Vector2(300, 800)
	dock.body().add_child(content)
	await process_frame

	_ok(dock.get_dock_state() == UIDockScript.State.EXPANDED, "starts expanded")

	dock.set_dock_state(UIDockScript.State.RAILED, false)
	await process_frame
	_ok(dock.custom_minimum_size.x == UIDockScript.RAIL_SIZE,
		"railed dock reports the RAIL width as its minimum, not its expanded width (got %.1f)"
			% dock.custom_minimum_size.x)
	# THE Container PROPAGATION TRAP: a collapsed dock whose body is a Container
	# would still demand the body's full width here.
	_ok(dock.get_combined_minimum_size().x < 200.0,
		"collapsed dock does not propagate its body's width (got %.1f)"
			% dock.get_combined_minimum_size().x)
	_ok(dock._clip.get_meta("ui_audit_clip_ok", false),
		"clip wrapper carries the audit opt-out")

	dock.set_dock_state(UIDockScript.State.HIDDEN, false)
	await process_frame
	_ok(dock.custom_minimum_size.x == UIDockScript.TAB_SIZE, "hidden dock shrinks to a tab")

	dock.set_dock_state(UIDockScript.State.EXPANDED, false)
	await process_frame
	_ok(is_equal_approx(dock.custom_minimum_size.x, 320.0), "expands back to its stored size")

	# toggle() must be a round trip, never a one-way trip into HIDDEN.
	dock.toggle()
	_ok(dock.get_dock_state() == UIDockScript.State.RAILED, "toggle from expanded rails it")
	dock.toggle()
	_ok(dock.get_dock_state() == UIDockScript.State.EXPANDED, "toggle again restores it")

	host.queue_free()
	await process_frame


func _test_flyout() -> void:
	var host = Control.new()
	host.size = Vector2(1600, 900)
	root.add_child(host)

	var f = UIFlyoutScript.create(host, "ARMOR MATERIAL")
	# Pin the bounds the placement logic measures against, so these assertions
	# are about the flyout and not about whatever window size the project
	# settings happen to give a headless run.
	f.screen_bounds_override = Rect2(Vector2.ZERO, Vector2(1600, 900))
	var b = Button.new()
	b.text = "Hardened Steel"
	b.custom_minimum_size = Vector2(220, 32)
	f.body().add_child(b)
	await process_frame
	await process_frame

	# A source hard against the bottom-right corner: the flyout must stay fully
	# inside the viewport rather than hanging off it.
	var src = Control.new()
	src.position = Vector2(1560, 880)
	src.size = Vector2(40, 20)
	host.add_child(src)
	await process_frame

	f.position = f._clamp_to_screen(f._rect_for_source(src, UIFlyoutScript.Align.BELOW))
	var r = Rect2(f.position, f.size)
	var vp = Rect2(Vector2.ZERO, Vector2(1600, 900))
	_ok(vp.encloses(r), "flyout near the bottom-right corner stays on screen (%s)" % r)

	# Anchored below a source at the top, it should actually be below it.
	var src2 = Control.new()
	src2.position = Vector2(100, 100)
	src2.size = Vector2(120, 24)
	host.add_child(src2)
	await process_frame
	var p2 = f._rect_for_source(src2, UIFlyoutScript.Align.BELOW)
	_ok(p2.y >= src2.position.y + src2.size.y, "opens below a source with room beneath it")

	# ...and flip above when there is no room below.
	var src3 = Control.new()
	src3.position = Vector2(100, 880)
	src3.size = Vector2(120, 24)
	host.add_child(src3)
	await process_frame
	var p3 = f._rect_for_source(src3, UIFlyoutScript.Align.BELOW)
	_ok(p3.y < src3.position.y, "flips above a source with no room beneath it")

	host.queue_free()
	await process_frame
