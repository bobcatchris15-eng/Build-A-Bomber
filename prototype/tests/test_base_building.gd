extends "res://tests/suite_base.gd"
# base building suites, split out of the former single-file
# run_tests.gd. Registration order lives in run_tests.gd's SUITE_ORDER,
# not here - the runner drives that manifest so execution order is
# identical to the pre-split single file.

func test_centerline_placement_does_not_self_mirror() -> bool:
	print("Running Test Suite: Centerline Placement Doesn't Mirror Onto Itself (found while visually verifying face-based mounting)...")
	# A module placed dead-center (local x ~= 0) - e.g. a frame_built railgun
	# mounted on the front/back centerline, a very natural placement for
	# that weapon type - would previously mirror onto its own position,
	# producing a fully-overlapping duplicate that read as a clipping-red
	# bug. Not mount-style-specific: any module placed on the centerline
	# hit this.
	var placer = Node3D.new()
	placer.name = "MainLab"
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	await tree.process_frame

	placer._place_hull_from_ui("heavy_hull")
	await tree.process_frame
	placer._place_weapon_from_ui("gauss_railgun", Vector3(0, 0.75, 2.0), Vector3.UP)
	await tree.process_frame

	var railguns = []
	for c in placer.hull.get_children():
		if c.has_meta("module_data") and c.get_meta("module_data").type_id == "gauss_railgun":
			railguns.append(c)

	if railguns.size() != 1:
		print("  [FAIL] Centerline placement should produce exactly 1 module, not mirror onto itself, got ", railguns.size())
		placer.queue_free()
		return false
	if railguns[0].has_meta("mirrored_counterpart"):
		print("  [FAIL] Centerline-placed module should not have a mirrored_counterpart at all")
		placer.queue_free()
		return false

	placer.check_all_clipping()
	if placer.clipping_detected:
		print("  [FAIL] Centerline placement should not trigger a false-positive clipping flag")
		placer.queue_free()
		return false

	placer.queue_free()
	print("  [PASS] Centerline-placed modules no longer mirror onto their own position.")
	return true


func test_ui_flyout_placement() -> bool:
	print("Running Test Suite: UIFlyout edge flipping + viewport clamping...")
	# The flyout primitive's whole job is landing somewhere sensible relative to
	# the control that opened it. Placement is also the part most likely to
	# silently regress, because a mispositioned flyout still renders - it is just
	# in the wrong place, or half off the screen, which no smoke test notices.
	#
	# screen_bounds_override exists precisely so this can be asserted: headless
	# Godot's viewport is whatever project settings imply, not what a test set up,
	# so without an injectable rect every assertion here would measure the wrong
	# rectangle. See the property's comment in ui_flyout.gd.
	var UIFlyoutScript = preload("res://scripts/ui_flyout.gd")
	var BOUNDS := Rect2(Vector2.ZERO, Vector2(1280, 720))

	var host = Control.new()
	host.size = BOUNDS.size
	root.add_child(host)

	# A source button hard against the BOTTOM edge. Asking for BELOW there must
	# flip ABOVE rather than hang off the screen.
	var low_btn = Button.new()
	low_btn.text = "SPEC"
	low_btn.position = Vector2(80, 700)
	low_btn.size = Vector2(120, 20)
	host.add_child(low_btn)

	var f = UIFlyoutScript.create(host, "Hull Specification")
	f.screen_bounds_override = BOUNDS
	for i in range(6):
		var pad = Label.new()
		pad.text = "ARMOR MATERIAL ROW %d" % i
		f.body().add_child(pad)
	f.open_from(low_btn, UIFlyoutScript.Align.BELOW)
	# open_from defers placement by two frames on purpose (a container has no real
	# size until it has computed its minimum), so this must wait longer than that.
	for i in range(6):
		await tree.process_frame

	var r: Rect2 = f.get_rect()
	if r.size.y < 4.0:
		print("  [FAIL] Flyout never laid out (size=", r.size, ") - placement assertions would be meaningless.")
		host.queue_free()
		return false
	if not BOUNDS.encloses(r):
		print("  [FAIL] Flyout near the bottom edge left the viewport: rect=", r, " bounds=", BOUNDS)
		host.queue_free()
		return false
	# Flipped ABOVE means it must not cover the button that opened it.
	if r.intersects(low_btn.get_global_rect()):
		print("  [FAIL] Flyout overlaps its own trigger: flyout=", r, " trigger=", low_btn.get_global_rect())
		host.queue_free()
		return false

	# A source hard against the RIGHT edge, asked to open RIGHT_OF: same contract
	# on the other axis, which is a genuinely separate branch in _rect_for_source.
	var right_btn = Button.new()
	right_btn.text = "SPEC"
	right_btn.position = Vector2(1200, 300)
	right_btn.size = Vector2(70, 20)
	host.add_child(right_btn)

	var f2 = UIFlyoutScript.create(host, "Faction")
	f2.screen_bounds_override = BOUNDS
	for i in range(4):
		var pad2 = Label.new()
		pad2.text = "THE AERODROME CARTEL"
		f2.body().add_child(pad2)
	f2.open_from(right_btn, UIFlyoutScript.Align.RIGHT_OF)
	for i in range(6):
		await tree.process_frame

	var r2: Rect2 = f2.get_rect()
	if not BOUNDS.encloses(r2):
		print("  [FAIL] Flyout near the right edge left the viewport: rect=", r2, " bounds=", BOUNDS)
		host.queue_free()
		return false

	host.queue_free()
	await tree.process_frame
	print("  [PASS] Flyouts flip off both the bottom and right edges, stay inside the viewport, and never cover their own trigger.")
	return true

