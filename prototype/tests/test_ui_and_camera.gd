extends "res://tests/suite_base.gd"
# ui and camera suites, split out of the former single-file
# run_tests.gd. Registration order lives in run_tests.gd's SUITE_ORDER,
# not here - the runner drives that manifest so execution order is
# identical to the pre-split single file.

# VISUAL_AND_UX_POLISH_PLAN.md B1: rts_camera.gd had neither edge-scroll nor
# zoom-to-cursor - both core RTS camera expectations. compute_edge_scroll_
# direction() is a pure function (no Input/viewport reads) specifically so
# this can assert it directly without faking real OS mouse position.
func test_rts_camera_edge_scroll_direction() -> bool:
	print("Running Test Suite: RTS Camera - Edge-Scroll Direction (VISUAL_AND_UX_POLISH_PLAN.md B1)...")
	var RTSCam = preload("res://scripts/rts_camera.gd")
	var vp_size = Vector2(1280, 800)
	var margin = 18.0

	if RTSCam.compute_edge_scroll_direction(Vector2(640, 400), vp_size, margin) != Vector2.ZERO:
		print("  [FAIL] Mouse at screen center should produce zero edge-scroll")
		return false
	if RTSCam.compute_edge_scroll_direction(Vector2(5, 400), vp_size, margin).x >= 0.0:
		print("  [FAIL] Mouse near the left edge should scroll left (negative x)")
		return false
	if RTSCam.compute_edge_scroll_direction(Vector2(1275, 400), vp_size, margin).x <= 0.0:
		print("  [FAIL] Mouse near the right edge should scroll right (positive x)")
		return false
	if RTSCam.compute_edge_scroll_direction(Vector2(640, 5), vp_size, margin).y >= 0.0:
		print("  [FAIL] Mouse near the top edge should scroll up (negative y)")
		return false
	if RTSCam.compute_edge_scroll_direction(Vector2(640, 795), vp_size, margin).y <= 0.0:
		print("  [FAIL] Mouse near the bottom edge should scroll down (positive y)")
		return false
	# A corner should scroll diagonally (both axes set), not just one.
	var corner = RTSCam.compute_edge_scroll_direction(Vector2(2, 2), vp_size, margin)
	if corner.x >= 0.0 or corner.y >= 0.0:
		print("  [FAIL] Top-left corner should scroll both up AND left, got ", corner)
		return false

	print("  [PASS] Edge-scroll direction correctly reads all 4 edges and diagonal corners, and is zero at screen center.")
	return true

# VISUAL_AND_UX_POLISH_PLAN.md B1: zoom-to-cursor - the previous behavior
# changed height in place regardless of where the mouse pointed, unlike
# every modern map/RTS camera. Proves the real invariant: the world point
# under the cursor (on the flat-plane approximation ray_plane_hit() uses)
# should be the SAME before and after a zoom, not just that height changed.
func test_rts_camera_zoom_to_cursor_keeps_world_point_under_mouse() -> bool:
	print("Running Test Suite: RTS Camera - Zoom-To-Cursor Keeps The Same World Point Under The Mouse (VISUAL_AND_UX_POLISH_PLAN.md B1)...")
	root.size = Vector2i(1280, 800)
	var parent = Node3D.new()
	root.add_child(parent)
	var cam = Camera3D.new()
	cam.set_script(preload("res://scripts/rts_camera.gd"))
	parent.add_child(cam)
	cam.global_position = Vector3(20, 26, 40)
	# Explicit, not relying on _ready()'s own height = clamp(global_position.y,
	# ...) - whether _ready() reads global_position.y before or after the
	# line above runs is a real ordering race (whether Godot flushes the
	# queued NOTIFICATION_READY before or after this script's own synchronous
	# execution finishes isn't guaranteed) that bit an earlier version of
	# this test: it passed in isolation, then failed the exact same way the
	# real bug it was written to catch failed, inside a full-suite run,
	# because height silently ended up clamped to min_height (10) instead of
	# the intended 26.
	cam.height = 26.0
	cam._apply_pitch()
	await tree.process_frame

	# Off-center so a real XZ shift is actually required to compensate (the
	# screen center ray from directly above barely moves when height alone
	# changes, which would let a broken implementation pass by accident).
	var screen_pos = Vector2(950, 550)
	var before = cam.ray_plane_hit(screen_pos)
	if before == null:
		print("  [FAIL] Test setup: ray_plane_hit should hit the y=0 plane from this camera angle")
		parent.queue_free()
		return false

	cam.zoom_to_cursor(cam.height - cam.zoom_speed, screen_pos)
	if abs(cam.height - (26.0 - cam.zoom_speed)) > 0.01:
		print("  [FAIL] zoom_to_cursor should still change height like the old behavior, got ", cam.height)
		parent.queue_free()
		return false

	var after = cam.ray_plane_hit(screen_pos)
	if after == null:
		print("  [FAIL] ray_plane_hit should still hit the plane after zooming in")
		parent.queue_free()
		return false
	if before.distance_to(after) > 0.05:
		print("  [FAIL] The same screen point should hit the same world point before/after zoom-to-cursor, got before=", before, " after=", after, " (distance ", before.distance_to(after), ")")
		parent.queue_free()
		return false

	parent.queue_free()
	await tree.process_frame
	print("  [PASS] Zooming in/out keeps the world point under the cursor fixed, not just the camera's own XZ position.")
	return true

func test_rts_camera_tilt_shift_dof_band() -> bool:
	print("Running Test Suite: RTS Camera - Tilt-Shift DOF Band (CORE_DESIGN_LANGUAGE.md §2/§7.1)...")
	root.size = Vector2i(1280, 800)
	var parent = Node3D.new()
	root.add_child(parent)
	var cam = Camera3D.new()
	cam.set_script(preload("res://scripts/rts_camera.gd"))
	parent.add_child(cam)
	cam.global_position = Vector3(0, 26, 0)
	cam.height = 26.0
	cam._apply_pitch()
	await tree.process_frame

	# §2.1: the whole effect is a horizontal band of sharpness (near AND far
	# DOF working together), not a radial blur - both must be real Camera3D
	# attributes, not just one.
	if not cam.attributes is CameraAttributesPractical:
		print("  [FAIL] rts_camera should carry CameraAttributesPractical, like designer_camera.gd does, got ", cam.attributes)
		parent.queue_free()
		return false
	var attrs: CameraAttributesPractical = cam.attributes
	if not attrs.dof_blur_near_enabled or not attrs.dof_blur_far_enabled:
		print("  [FAIL] Both near and far DOF must be enabled - a band, not a one-sided blur.")
		parent.queue_free()
		return false

	# §2.1: keep the blur amount low - a strong blur at RTS zoom destroys unit
	# readability, and readability is a gameplay requirement.
	if attrs.dof_blur_amount > 0.08 + 0.0001:
		print("  [FAIL] dof_blur_amount should stay at designer_camera.gd's low 0.08, got ", attrs.dof_blur_amount)
		parent.queue_free()
		return false

	# The band must track the camera's real (lerped) altitude, not go stale -
	# same requirement zoom_to_cursor already has for the ray-plane hit test
	# above. Move the target height and let _process()'s lerp run.
	cam.height = 60.0
	for i in range(30):
		cam._process(0.1)
	var expected_half_width = cam.dof_band_half_width(cam.global_position.y, cam.min_height, cam.max_height)
	if abs(attrs.dof_blur_far_distance - (cam.global_position.y + expected_half_width)) > 0.01:
		print("  [FAIL] DOF far distance should track the camera's real altitude after zooming, got far=", attrs.dof_blur_far_distance, " altitude=", cam.global_position.y)
		parent.queue_free()
		return false
	if abs(attrs.dof_blur_near_distance - max(1.0, cam.global_position.y - expected_half_width)) > 0.01:
		print("  [FAIL] DOF near distance should track the camera's real altitude after zooming, got near=", attrs.dof_blur_near_distance, " altitude=", cam.global_position.y)
		parent.queue_free()
		return false

	parent.queue_free()
	await tree.process_frame
	print("  [PASS] The RTS camera carries a real tilt-shift DOF band that tracks altitude, resolving §7.1's designer-lab-only gap.")
	return true

func test_rts_camera_dof_band_widens_monotonically_with_height() -> bool:
	print("Running Test Suite: RTS Camera - DOF Band Widens Monotonically With Height (CORE_DESIGN_LANGUAGE.md §7.2)...")
	var RtsCameraScript = preload("res://scripts/rts_camera.gd")
	var min_h = 10.0
	var max_h = 160.0

	# §7.2: rather than a fixed band silently snapping between "miniature"
	# and "map view" at the zoom ceiling, the band must widen smoothly - so
	# sampling across the full height range should never produce a
	# narrower band at a greater height.
	var prev_width = -1.0
	var h = min_h
	while h <= max_h:
		var width = RtsCameraScript.dof_band_half_width(h, min_h, max_h)
		if width < prev_width - 0.0001:
			print("  [FAIL] DOF band width should be monotonically non-decreasing with height, got ", width, " at height ", h, " after ", prev_width, " at a lower height")
			return false
		prev_width = width
		h += 5.0

	# At min_height it should match designer_camera.gd's own fixed 4.0 -
	# the low end of the zoom range keeps the exact reference band.
	var width_at_min = RtsCameraScript.dof_band_half_width(min_h, min_h, max_h)
	if abs(width_at_min - RtsCameraScript.DOF_BAND_MIN_HALF_WIDTH) > 0.0001:
		print("  [FAIL] DOF band width at min_height should equal DOF_BAND_MIN_HALF_WIDTH, got ", width_at_min)
		return false

	# At max_height it should be strictly wider than at min_height - a real
	# widening, not a no-op constant dressed up as a function.
	var width_at_max = RtsCameraScript.dof_band_half_width(max_h, min_h, max_h)
	if width_at_max <= width_at_min:
		print("  [FAIL] DOF band width at max_height should be strictly wider than at min_height, got ", width_at_max, " vs ", width_at_min)
		return false

	# A degenerate range (max <= min) must not divide by zero or return
	# something nonsensical.
	var degenerate = RtsCameraScript.dof_band_half_width(20.0, 20.0, 20.0)
	if is_nan(degenerate) or is_inf(degenerate):
		print("  [FAIL] A degenerate min/max height range should not produce NaN/Inf, got ", degenerate)
		return false

	print("  [PASS] The DOF band widens monotonically with height, matches the reference band width at the zoom-in end, and is well-defined for a degenerate range.")
	return true

func test_rts_camera_world_scale_property_defaults_inert() -> bool:
	print("Running Test Suite: RTS Camera - world_scale Property Defaults To 1.0 (Chunk 18)...")
	# NOT a test of the actual pan-speed/middle-drag FEEL at a non-default
	# world_scale - both live inside _process()'s Input.is_key_pressed() poll
	# and _unhandled_input()'s Input.is_mouse_button_pressed() check, and
	# this codebase's own steering.gd header documents why headless Godot
	# cannot simulate held key/mouse-button state (confirmed empirically
	# 2026-07-12). What IS headlessly verifiable: the property exists,
	# defaults to the inert 1.0 (so a camera nothing ever sets it on - an
	# older scene, a test stub - behaves exactly as before this chunk), and
	# is real per-instance state rather than a shared/static value. Felt
	# pan/middle-drag speed at a real world_scale is a play-test, per this
	# plan's own verification note.
	var cam = Camera3D.new()
	cam.set_script(preload("res://scripts/rts_camera.gd"))
	if not is_equal_approx(cam.world_scale, 1.0):
		print("  [FAIL] world_scale should default to 1.0, got ", cam.world_scale)
		return false
	cam.world_scale = 4.0
	if not is_equal_approx(cam.world_scale, 4.0):
		print("  [FAIL] world_scale should be a plain settable field, got ", cam.world_scale, " after assigning 4.0")
		return false
	var cam2 = Camera3D.new()
	cam2.set_script(preload("res://scripts/rts_camera.gd"))
	if not is_equal_approx(cam2.world_scale, 1.0):
		print("  [FAIL] world_scale should be PER-INSTANCE, not shared - a second camera should still default to 1.0 after the first was set to 4.0, got ", cam2.world_scale)
		return false
	cam.free()
	cam2.free()
	print("  [PASS] rts_camera.gd carries a per-instance world_scale property defaulting to the inert 1.0.")
	return true

func test_ui_no_overflow_or_offscreen() -> bool:
	print("Running Test Suite: UI Overflow + Off-Screen Audit (headless, no windowed rendering needed)...")
	# Validated technique (see PROGRESS.md): compare each fixed-size panel's
	# actual size against its content's natural combined minimum size -
	# NOT a control's own size vs its own minimum, which is meaningless in
	# this codebase's auto-sizing VBoxContainer-heavy layout.
	var UIAuditScript = preload("res://scripts/ui_audit.gd")

	# Force the real project resolution - headless mode's default viewport
	# is a tiny 64x64 unless explicitly set, which would make every anchor-
	# based layout calculation meaningless. Confirmed empirically that this
	# needs to be re-asserted after a frame (the first assignment doesn't
	# reliably stick before the scene's own _ready() runs).
	root.size = Vector2i(1280, 720)
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	await tree.process_frame
	root.size = Vector2i(1280, 720)
	await tree.process_frame
	root.size = Vector2i(1280, 720)
	await tree.process_frame

	var overflow = UIAuditScript.find_overflowing_panels(scene)
	if not overflow.is_empty():
		for o in overflow:
			print("  [FAIL] UI overflow: ", o.path, " fixed_size=", o.fixed_size, " content_min=", o.content_min_size, " culprit=", o.culprit)
		scene.queue_free()
		return false

	var viewport_rect = Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var offscreen = UIAuditScript.find_offscreen_controls(scene, viewport_rect)
	if not offscreen.is_empty():
		for o in offscreen:
			print("  [FAIL] Off-screen control: ", o.path, " rect=", o.rect, " (viewport=", viewport_rect, ")")
		scene.queue_free()
		return false

	scene.queue_free()
	print("  [PASS] No UI panels have content wider/taller than their fixed size, and nothing is positioned off-screen (MainLab.tscn).")
	return true

func test_ui_audit_has_real_teeth() -> bool:
	print("Running Test Suite: UI Audit Tool Sanity Check (does it actually catch bugs?)...")
	# Guards against a future refactor silently making the checker a no-op -
	# the MainLab.tscn regression test above only proves today's UI is
	# clean, not that the tool would notice if it stopped being clean.
	var UIAuditScript = preload("res://scripts/ui_audit.gd")

	# --- Overflow: a fixed-size panel with a child that needs more room ---
	# Must use ScrollContainer, not PanelContainer/VBoxContainer: Godot
	# enforces an internal floor where a Container's own .size can never be
	# set smaller than its own computed minimum size, UNLESS that container
	# type is specifically designed to allow oversized content (that's the
	# entire point of ScrollContainer - clip/scroll rather than grow).
	# Confirmed empirically: a PanelContainer's forced .size silently
	# snapped back to its content's exact minimum on every attempt. This is
	# also *why* the real bug this tool caught used a ScrollContainer.
	var panel = ScrollContainer.new()
	panel.size = Vector2(100, 40)
	root.add_child(panel)
	var wide_label = Label.new()
	wide_label.text = "This label is deliberately far too wide for a 100px panel"
	panel.add_child(wide_label)
	await tree.process_frame
	await tree.process_frame
	panel.size = Vector2(100, 40)

	var overflow = UIAuditScript.find_overflowing_panels(panel)
	if overflow.is_empty():
		print("  [FAIL] UI audit tool failed to catch a deliberately injected overflow - it has no teeth")
		panel.queue_free()
		return false

	# A panel that's actually big enough should NOT be flagged.
	panel.size = Vector2(600, 40)
	await tree.process_frame
	var no_overflow = UIAuditScript.find_overflowing_panels(panel)
	if not no_overflow.is_empty():
		print("  [FAIL] UI audit tool false-positived on a panel that's actually large enough for its content: ", no_overflow)
		panel.queue_free()
		return false
	panel.queue_free()

	# --- Off-screen: a control positioned entirely outside the viewport ---
	var offscreen_control = ColorRect.new()
	offscreen_control.position = Vector2(5000, 5000)
	offscreen_control.size = Vector2(50, 50)
	root.add_child(offscreen_control)
	await tree.process_frame

	var viewport_rect = Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var offscreen_results = UIAuditScript.find_offscreen_controls(offscreen_control, viewport_rect)
	if offscreen_results.is_empty():
		print("  [FAIL] UI audit tool failed to catch a control positioned at (5000,5000), off-screen")
		offscreen_control.queue_free()
		return false
	offscreen_control.queue_free()

	print("  [PASS] UI audit tool correctly catches injected overflow/off-screen bugs and doesn't false-positive on legitimately-sized panels.")
	return true

# --- Skirmish mode test suites ---

func test_ui_dock_state_cycle() -> bool:
	print("Running Test Suite: UIDock expanded/railed/hidden widths...")
	# VISUAL/UI plan item 4's verification, plus the Container-propagation trap the
	# plan flags in that item: "a railed dock reports its rail width as minimum
	# size, not its expanded width". That one is invisible by inspection - a
	# collapsed dock LOOKS collapsed while still demanding its full expanded width
	# from the parent, which just squeezes whatever shares the row.
	var UIDockScript = preload("res://scripts/ui_dock.gd")

	var host = Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)

	var dock = UIDockScript.new()
	dock.dock_title = "CATALOG"
	dock.side = UIDockScript.Side.LEFT
	dock.expanded_size = 320.0
	dock.auto_reveal = false
	# No persist_key: a test must not read or write user://ui_layout.cfg, or it
	# picks up whatever width the developer last dragged and stops being a test.
	dock.persist_key = ""
	host.add_child(dock)

	var wide = Label.new()
	wide.text = "A PART NAME LONG ENOUGH TO NEED ROOM"
	dock.body().add_child(wide)
	await tree.process_frame
	await tree.process_frame

	dock.set_dock_state(UIDockScript.State.EXPANDED, false)
	await tree.process_frame
	var expanded_min := dock.get_combined_minimum_size().x
	if absf(expanded_min - 320.0) > 1.0:
		print("  [FAIL] Expanded dock outer minimum is ", expanded_min, ", expected 320 (expanded_size must mean OUTER width).")
		host.queue_free()
		return false
	if absf(dock.outer_extent() - 320.0) > 0.01:
		print("  [FAIL] outer_extent() reported ", dock.outer_extent(), " when expanded.")
		host.queue_free()
		return false

	dock.set_dock_state(UIDockScript.State.RAILED, false)
	await tree.process_frame
	var railed_min := dock.get_combined_minimum_size().x
	if railed_min > UIDockScript.RAIL_SIZE + 1.0:
		print("  [FAIL] Railed dock still demands ", railed_min, "px (rail is ", UIDockScript.RAIL_SIZE,
			"). The clip is propagating its children's minimum through the Container - see item 4's trap.")
		host.queue_free()
		return false
	if absf(dock.outer_extent() - UIDockScript.RAIL_SIZE) > 0.01:
		print("  [FAIL] outer_extent() reported ", dock.outer_extent(), " when railed.")
		host.queue_free()
		return false

	dock.set_dock_state(UIDockScript.State.HIDDEN, false)
	await tree.process_frame
	var hidden_min := dock.get_combined_minimum_size().x
	if hidden_min > UIDockScript.TAB_SIZE + 1.0:
		print("  [FAIL] Hidden dock still demands ", hidden_min, "px (tab is ", UIDockScript.TAB_SIZE, ").")
		host.queue_free()
		return false

	# Back to expanded, because a one-way collapse would still pass everything above.
	dock.set_dock_state(UIDockScript.State.EXPANDED, false)
	await tree.process_frame
	if absf(dock.get_combined_minimum_size().x - 320.0) > 1.0:
		print("  [FAIL] Dock did not return to its expanded width; got ", dock.get_combined_minimum_size().x)
		host.queue_free()
		return false

	# toggle() must never reach HIDDEN - losing a panel off the screen edge is not
	# something a double-click on a header should be able to do.
	dock.set_dock_state(UIDockScript.State.EXPANDED, false)
	dock.toggle()
	await tree.process_frame
	var after_one := dock.get_dock_state()
	dock.toggle()
	await tree.process_frame
	var after_two := dock.get_dock_state()
	if after_one == UIDockScript.State.HIDDEN or after_two == UIDockScript.State.HIDDEN:
		print("  [FAIL] toggle() reached HIDDEN (", after_one, " -> ", after_two, ").")
		host.queue_free()
		return false
	if after_two != UIDockScript.State.EXPANDED:
		print("  [FAIL] Two toggles did not return to EXPANDED; got ", after_two)
		host.queue_free()
		return false

	host.queue_free()
	await tree.process_frame
	print("  [PASS] Dock cycles expanded/railed/hidden with correct OUTER minimum widths, and toggle() never hides.")
	return true

func test_ui_tone_no_decorative_glyphs() -> bool:
	print("Running Test Suite: UI tone guard (no emoji/dingbats in shipped strings)...")
	# VISUAL/UI plan item 0's standing guard. The plan predicted exactly why this
	# is needed - "it stops item 0 from silently regressing the way main_menu.gd
	# already did once" - and it was right twice over: with no guard in place,
	# 🎨 survived in hull_builder.gd and 🏭/⛽/⚡ in skirmish.gd's build bar
	# through the whole material pass.
	#
	# Walks the real Control trees rather than grepping source, so it also catches
	# a glyph that arrives via a data table or a format string.
	var screens := [
		"res://scenes/MainMenu.tscn",
		"res://scenes/MainLab.tscn",
		"res://scenes/OperationsSetup.tscn",
		"res://scenes/HullBuilder.tscn",
	]
	var offenders := []
	for path in screens:
		if not ResourceLoader.exists(path):
			continue
		root.size = Vector2i(1280, 720)
		var scene = load(path).instantiate()
		root.add_child(scene)
		for i in range(6):
			await tree.process_frame
		_collect_glyph_offenders(scene, path, offenders)
		scene.queue_free()
		await tree.process_frame

	if not offenders.is_empty():
		for o in offenders:
			print("  [FAIL] Decorative glyph %s in %s -> %s : \"%s\"" % [o.glyph, o.screen, o.path, o.text])
		return false

	print("  [PASS] No emoji or dingbat characters in any shipped label/button text across %d screens." % screens.size())
	return true

func test_ui_icons_share_one_stroke_colour() -> bool:
	print("Running Test Suite: every UI icon is authored in one neutral stroke...")
	# The icon set is monochrome on purpose: colour belongs to the control's state,
	# not to the glyph (see tools/generate_icons.py's ICON_STROKE comment). Before
	# that rule, 35 icons carried 17 different cool-toned web colours between them,
	# which is how the build bar ended up rendering sky-blue factory glyphs on warm
	# powdercoat.
	#
	# Reads the .svg sources rather than the imported textures, because the source
	# is what a future hand-added icon would arrive as, and the failure mode is a
	# colour that looks fine in isolation and wrong in the interface.
	var expect := "#ADA9A0"  # = Tokens.TEXT_SECONDARY
	var dir := DirAccess.open("res://assets/icons")
	if dir == null:
		print("  [FAIL] Cannot open res://assets/icons")
		return false

	var re := RegEx.new()
	re.compile('stroke="(#[0-9A-Fa-f]{3,8})"')

	var checked := 0
	var offenders := []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".svg"):
			var src := FileAccess.get_file_as_string("res://assets/icons/" + f)
			var found := {}
			for m in re.search_all(src):
				found[m.get_string(1).to_upper()] = true
			checked += 1
			for c in found.keys():
				if c != expect:
					offenders.append({"file": f, "colour": c})
		f = dir.get_next()
	dir.list_dir_end()

	if checked == 0:
		print("  [FAIL] Found no .svg icons to check - the directory or the naming changed.")
		return false
	if not offenders.is_empty():
		for o in offenders:
			print("  [FAIL] %s strokes %s, expected %s. Re-run tools/generate_icons.py." % [o.file, o.colour, expect])
		return false

	print("  [PASS] All %d icons stroke %s; icon colour is left to the control's state." % [checked, expect])
	return true

func test_brushed_aluminum_ui_theme() -> bool:
	print("Running Test Suite: UI Chrome - Backdrop Shader & Faction/Chrome Separation...")
	var UITheme = preload("res://scripts/ui_theme.gd")
	var FactionCatalog = preload("res://scripts/faction_catalog.gd")

	# This suite used to assert the OPPOSITE of what it asserts now: that UI
	# chrome is repainted in the player's faction color. That behaviour was
	# removed deliberately, not accidentally. Faction color's job on screen
	# is to tell the player who owns a unit; if it is also the wallpaper it
	# stops being a reliable ownership signal, and the interface's own
	# contrast ratios end up depending on which faction was picked
	# (Technocrat white chrome and Bayou swamp-green chrome are not the same
	# UI). The assertions below are inverted on purpose, so the old
	# behaviour can't quietly come back.
	#
	# Now targets apply_backdrop() directly. It used to go through
	# apply_brushed_panel(), which took a faction argument and ignored it - a
	# back-compat shim kept while the call sites migrated. All of them have, so
	# the shim is gone and the faction arguments with it. The four assertions are
	# unchanged: they were always really about apply_backdrop's behaviour.

	var panel = Panel.new()
	panel.size = Vector2(400, 300)
	root.add_child(panel)
	UITheme.apply_backdrop(panel)
	var mat_a = panel.material as ShaderMaterial
	if not mat_a:
		print("  [FAIL] apply_backdrop should assign a ShaderMaterial to the node's .material")
		panel.queue_free()
		return false
	if mat_a.get_shader_parameter("tint_strength") != 0.0:
		print("  [FAIL] UI chrome must NOT be faction-tinted - tint_strength should be 0.0, got ", mat_a.get_shader_parameter("tint_strength"))
		panel.queue_free()
		return false

	# The shader's noise frequencies are in pixels, so it needs the node's
	# real size or its grain scales with the panel - the bug that produced
	# the giant smeared blobs behind every menu in the 2026-07-30 baseline.
	var pushed = mat_a.get_shader_parameter("panel_size")
	if pushed == null or pushed.x < 1.0 or pushed.y < 1.0:
		print("  [FAIL] apply_backdrop should push the node's pixel size into panel_size, got ", pushed)
		panel.queue_free()
		return false

	# Re-theming the SAME panel must reuse its ShaderMaterial rather than
	# allocating a new one on every call.
	UITheme.apply_backdrop(panel)
	var mat_b = panel.material as ShaderMaterial
	if mat_b != mat_a:
		print("  [FAIL] Re-theming the same panel should reuse its existing ShaderMaterial instance, not replace it")
		panel.queue_free()
		return false

	# The one surface where faction color IS the point: an explicit preview
	# swatch. Kept as its own entry point so ordinary chrome styling can't
	# reach it by accident.
	var swatch = Panel.new()
	swatch.size = Vector2(120, 80)
	root.add_child(swatch)
	UITheme.apply_faction_preview(swatch, "crimson_concordat")
	var swatch_mat = swatch.material as ShaderMaterial
	if not swatch_mat or swatch_mat.get_shader_parameter("tint_strength") <= 0.0:
		print("  [FAIL] apply_faction_preview should apply a non-zero faction tint")
		panel.queue_free()
		swatch.queue_free()
		return false
	if swatch_mat.get_shader_parameter("accent_tint") != FactionCatalog.get_visual_color("crimson_concordat"):
		print("  [FAIL] Faction preview swatch should carry the Crimson Concordat catalog color")
		panel.queue_free()
		swatch.queue_free()
		return false

	# Real screen check: MatchSetup still gets a backdrop on load...
	var setup_scene = preload("res://scenes/MatchSetup.tscn").instantiate()
	root.add_child(setup_scene)
	current_scene = setup_scene
	await tree.process_frame
	await tree.process_frame
	if not (setup_scene.bg_rect.material is ShaderMaterial):
		print("  [FAIL] MatchSetup.tscn's background should have the backdrop ShaderMaterial applied on load")
		panel.queue_free()
		swatch.queue_free()
		setup_scene.queue_free()
		return false
	# ...and changing faction must NOT repaint it.
	var before_tint = setup_scene.bg_rect.material.get_shader_parameter("tint_strength")
	var concordat_idx = setup_scene.FACTIONS.find("crimson_concordat")
	setup_scene.player_faction_btn.selected = concordat_idx
	setup_scene.player_faction_btn.item_selected.emit(concordat_idx)
	await tree.process_frame
	var after_tint = setup_scene.bg_rect.material.get_shader_parameter("tint_strength")
	if before_tint != 0.0 or after_tint != 0.0:
		print("  [FAIL] Changing the faction dropdown must leave the backdrop neutral, got before=", before_tint, " after=", after_tint)
		panel.queue_free()
		swatch.queue_free()
		setup_scene.queue_free()
		return false

	panel.queue_free()
	swatch.queue_free()
	setup_scene.queue_free()
	await tree.process_frame
	print("  [PASS] Backdrop applies a size-aware ShaderMaterial, reuses it on re-theme, stays neutral across faction changes, and tints only on an explicit faction-preview swatch.")
	return true

func test_screenshot_diff_tolerance() -> bool:
	print("Running Test Suite: Screenshot-Diff Comparison Logic (headless, synthetic images)...")
	# The actual screenshot CAPTURE needs windowed rendering (headless
	# Godot's dummy renderer doesn't rasterize - confirmed earlier this
	# week), so that lives in visual_regression/run_visual_regression.gd.
	# This tests the comparison algorithm itself against synthetic Image
	# objects, which works fine headlessly.
	var ScreenshotDiffScript = preload("res://scripts/screenshot_diff.gd")

	var size = Vector2i(64, 64)
	var base = Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	base.fill(Color(0.4, 0.5, 0.6))

	# Identical images must match.
	var identical = base.duplicate()
	var r1 = ScreenshotDiffScript.compare_images(base, identical)
	if not r1.match:
		print("  [FAIL] Identical images should match, got ", r1)
		return false

	# Small scattered noise (simulating anti-aliasing/font-hinting jitter)
	# within tolerance must still match.
	var noisy = base.duplicate()
	for i in range(20): # ~0.5% of 4096 pixels
		noisy.set_pixel(i % size.x, i / size.x, Color(0.42, 0.52, 0.61))
	var r2 = ScreenshotDiffScript.compare_images(base, noisy)
	if not r2.match:
		print("  [FAIL] A small amount of scattered near-identical noise should still match within tolerance, got ", r2)
		return false

	# A large solid differing region (simulating a missing panel/wrong
	# color/moved element) must NOT match.
	var broken = base.duplicate()
	broken.fill_rect(Rect2i(0, 0, 40, 40), Color(1.0, 0.0, 0.0))
	var r3 = ScreenshotDiffScript.compare_images(base, broken)
	if r3.match:
		print("  [FAIL] A large solid differing region should be flagged as a mismatch, got ", r3)
		return false

	# Different sizes must never match, with a clear reason.
	var wrong_size = Image.create(32, 32, false, Image.FORMAT_RGB8)
	var r4 = ScreenshotDiffScript.compare_images(base, wrong_size)
	if r4.match or r4.reason == "":
		print("  [FAIL] Different-sized images should never match and should explain why, got ", r4)
		return false

	print("  [PASS] Screenshot-diff tolerance correctly absorbs small rendering noise while catching large regressions and size mismatches.")
	return true

func test_2d_ui_chrome_overhaul() -> bool:
	print("Running Test Suite: 2D UI Chrome Overhaul Assets, Theme, Icons, Cursors & Shaders...")

	var theme_res = UIAudit.check_theme_resource_validity()
	if not theme_res.get("valid", false):
		print("  [FAIL] bomber_theme.tres invalid or missing core styleboxes: ", theme_res.get("reason", ""))
		return false

	var icons_res = UIAudit.check_icon_assets()
	if not icons_res.get("valid", false):
		print("  [FAIL] Missing SVG icon assets: ", icons_res.get("missing", []))
		return false

	var cursor_res = UIAudit.check_cursor_assets()
	if not cursor_res.get("valid", false):
		print("  [FAIL] Missing PNG cursor assets: ", cursor_res.get("missing", []))
		return false

	if not ResourceLoader.exists("res://shaders/inworld_hp_bar.gdshader"):
		print("  [FAIL] res://shaders/inworld_hp_bar.gdshader is missing.")
		return false
	if not ResourceLoader.exists("res://shaders/selection_ring.gdshader"):
		print("  [FAIL] res://shaders/selection_ring.gdshader is missing.")
		return false

	print("  [PASS] 2D UI Chrome Overhaul: bomber_theme.tres, 35 SVG icons, 7 PNG cursors, and in-world shaders all present and valid.")
	return true

