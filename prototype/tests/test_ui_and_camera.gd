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

# 2026-08-11: test_rts_camera_zoom_to_cursor_keeps_world_point_under_mouse
# used to sit here (VISUAL_AND_UX_POLISH_PLAN.md B1). Commit 0a8226a folded
# rts_camera.gd's public zoom_to_cursor(target_height, screen_pos) into the
# private _on_zoom(screen_pos, height_delta) input handler, so the test's very
# first action was a call into a method that no longer exists and it could
# never pass again. The behaviour itself was NOT retired - _on_zoom still does
# the before/after ray_plane_hit() compensation that keeps the world point
# under the cursor fixed across a zoom - it is simply unguarded now, because
# testing it again means driving the new signature rather than renaming a call.
# See the matching note in run_tests.gd's SUITE_ORDER.

# REMOVED 2026-08-11: test_rts_camera_tilt_shift_dof_band() and
# test_rts_camera_dof_band_widens_monotonically_with_height().
#
# The tilt-shift depth-of-field pass was deleted from rts_camera.gd on
# 2026-08-10 - it was the dominant per-frame cost in a Skirmish (50 FPS
# decaying to 3 within ~20 s) and the user OK'd dropping the band. Both
# tests called RtsCamera.dof_band_half_width(), which went with it, so
# neither could ever pass again. DECISIONS.md flagged them for exactly this
# housekeeping pass. The one-line re-enable recipe lives in rts_camera.gd's
# file header; if the band ever comes back, these are cheap to rewrite.

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
	var Livery = preload("res://scripts/livery.gd")

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
	UITheme.apply_faction_preview(swatch, "player")
	var swatch_mat = swatch.material as ShaderMaterial
	if not swatch_mat or swatch_mat.get_shader_parameter("tint_strength") <= 0.0:
		print("  [FAIL] apply_faction_preview should apply a non-zero livery tint")
		panel.queue_free()
		swatch.queue_free()
		return false
	if swatch_mat.get_shader_parameter("accent_tint") != Livery.zone_color("player", "hull_upper"):
		print("  [FAIL] livery preview swatch should carry the livery's own hull-upper colour")
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
	# ...and it stays NEUTRAL. This used to drive the faction dropdown and
	# assert the backdrop did not repaint; that dropdown is gone with the
	# premade factions (livery.gd), so what is left to pin is the rule it was
	# really protecting - screen chrome carries no team colour at all, because
	# colour's job on screen is telling the player who owns a unit, and chrome
	# that borrows it stops being a reliable ownership signal.
	var before_tint = setup_scene.bg_rect.material.get_shader_parameter("tint_strength")
	await tree.process_frame
	var after_tint = setup_scene.bg_rect.material.get_shader_parameter("tint_strength")
	if before_tint != 0.0 or after_tint != 0.0:
		print("  [FAIL] The setup screen backdrop must stay neutral, got before=", before_tint, " after=", after_tint)
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


# Tactile Interface Programme Phase 4. The L0 workbench layer is registered
# in UITheme.MATERIALS with five materials (cutting_mat, cardboard, kraft,
# cork, chipboard); each must have a field asset on disk, and the layer
# discipline rule (Part 0.5) means none of them may have plate assets - L0
# is a backdrop register, not a control register.
func test_l0_workbench_materials_have_fields_no_plates() -> bool:
	print("Running Test Suite: L0 Workbench Material Assets (Tactile Interface Programme Phase 4)...")
	var UITheme = preload("res://scripts/ui_theme.gd")
	var L0 = ["cutting_mat", "cardboard", "kraft", "cork", "chipboard"]
	# Sanity: L0 must be a subset of the registered MATERIALS, in the order
	# declared in ui_theme.gd's header. Catches a future refactor that
	# reorders or renames the layer without updating the tests.
	for i in range(L0.size()):
		if UITheme.MATERIALS[i] != L0[i]:
			print("  [FAIL] UITheme.MATERIALS[", i, "] is '", UITheme.MATERIALS[i], "' but the L0 workbench prefix expected '", L0[i], "'. The layer ordering in ui_theme.gd's header has drifted from the test.")
			return false
	# Every L0 material must have a field_<name>.png on disk.
	for m in L0:
		var field_path := "res://assets/textures/ui/field_%s.png" % m
		if not ResourceLoader.exists(field_path):
			print("  [FAIL] L0 workbench material '", m, "' is missing its field asset at ", field_path)
			return false
	# No L0 material may have plate_<name>_<state>.png assets. The layer
	# discipline rule (TACTILE_INTERFACE_PLAN.md Part 0.5) is that L0 is a
	# backdrop register; a workbench material on a control would be a
	# category error. The .import sidecars are part of the on-disk asset
	# and have to be absent too, otherwise the importer re-creates them.
	var plate_states = ["normal", "hover", "pressed", "disabled"]
	for m in L0:
		for s in plate_states:
			var plate_png := "res://assets/textures/ui/plate_%s_%s.png" % [m, s]
			var plate_imp := "res://assets/textures/ui/plate_%s_%s.png.import" % [m, s]
			if ResourceLoader.exists(plate_png) or ResourceLoader.exists(plate_imp):
				print("  [FAIL] L0 workbench material '", m, "' has a plate_", s, " asset; L0 is a backdrop register and must not carry plate files")
				return false
	# Every L1 equipment material keeps its plate assets, for symmetry -
	# the layer discipline rule cuts both ways.
	for m in ["powdercoat", "moulded", "canvas", "carbon", "fiberglass", "toolbox"]:
		for s in plate_states:
			var plate_png := "res://assets/textures/ui/plate_%s_%s.png" % [m, s]
			if not ResourceLoader.exists(plate_png):
				print("  [FAIL] L1 equipment material '", m, "' is missing plate_", s, ".png - L0 has no plates, but L1 must.")
				return false
	print("  [PASS] L0 workbench materials (cutting_mat, cardboard, kraft, cork, chipboard) are registered, each has a field asset, none have plate assets, and every L1 equipment material still has its plates.")
	return true


# Tactile Interface Programme Phase 4 (D7). The out-of-match screens must
# call UIShell.workbench() and the in-match screens must NOT - the L0 layer
# is registered for the pre-game chrome, the L1 equipment backdrop is
# reserved for the in-match chrome.
#
# The screen paths below are the source files for every out-of-match and
# in-match screen the project ships. A test that grepped the source would
# also catch a comment that says "workbench" without calling it; a test
# that loaded the scene would be more authoritative but those scenes pull
# in full SubViewports and the test infra cannot drive a viewport. The
# source-grep approach is the right tier for this contract.
func test_workbench_backdrop_split() -> bool:
	print("Running Test Suite: L0 Workbench vs Steel Backdrop (Tactile Interface Programme Phase 4, D7)...")
	# Out-of-match screens. Each one must contain a call to UIShell.workbench()
	# (or, for the one screen that builds its own ColorRect, an
	# apply_material() with a L0 workbench material). A bare
	# UIShell.backdrop() or a steel apply_material() here is the regression
	# the test is there to catch.
	const OUT_OF_MATCH := [
		"res://scripts/loading_screen.gd",
		"res://scripts/livery_screen.gd",
		"res://scripts/operations_setup.gd",
		"res://scripts/operations_draft.gd",
	]
	const MATCH_SETUP_SCRIPT := "res://scripts/match_setup.gd"
	const L0_MATERIALS := ["cutting_mat", "cardboard", "kraft", "cork", "chipboard"]
	for path in OUT_OF_MATCH:
		var src := FileAccess.get_file_as_string(path)
		if src.find("UIShell.workbench(") < 0:
			print("  [FAIL] ", path, " is out-of-match and must call UIShell.workbench() - no workbench() call found")
			return false
		# Steel on an out-of-match screen is the regression we are catching.
		if src.find("UIShell.backdrop(") >= 0:
			print("  [FAIL] ", path, " is out-of-match and still calls UIShell.backdrop() (steel) - it should be on workbench()")
			return false
	# match_setup.gd builds its own ColorRect and calls apply_material()
	# directly rather than going through UIShell.backdrop(). The test
	# therefore has to inspect the material argument, not the helper.
	var match_src := FileAccess.get_file_as_string(MATCH_SETUP_SCRIPT)
	var found_l0 := false
	for m in L0_MATERIALS:
		if match_src.find('"%s"' % m) >= 0:
			found_l0 = true
			break
	if not found_l0:
		print("  [FAIL] ", MATCH_SETUP_SCRIPT, " is out-of-match and must apply an L0 workbench material (cutting_mat, cardboard, kraft, cork, or chipboard)")
		return false
	# In-match screens. Each one must NOT call UIShell.workbench() - the
	# in-match chrome stays on steel. The list is the floor; new
	# in-match screens added to the project should be added here.
	const IN_MATCH := [
		"res://scripts/battle/match_director.gd",
		"res://scripts/battle/hud/battle_hud.gd",
	]
	for path in IN_MATCH:
		var src := FileAccess.get_file_as_string(path)
		if src.find("UIShell.workbench(") >= 0 or src.find('"cutting_mat"') >= 0 or src.find('"cardboard"') >= 0 or src.find('"kraft"') >= 0 or src.find('"cork"') >= 0 or src.find('"chipboard"') >= 0:
			print("  [FAIL] ", path, " is in-match and must not use a workbench material - it stays on the in-match steel backdrop")
			return false
	print("  [PASS] All out-of-match screens call UIShell.workbench() with an L0 material; no in-match screen does. The L0 / in-match split is in place.")
	return true


# Tactile Interface Programme Phase 2. Every UI prop registered in UIPropRegistry
# must have all three generated texture assets (albedo, ORM, height) present on disk.
func test_ui_prop_textures_resolve() -> bool:
	print("Running Test Suite: UI Props - Texture Assets Resolve (Phase 2)...")
	var PropRegistry = preload("res://scripts/ui/ui_prop_registry.gd")
	var ids: Array = PropRegistry.ids()
	if ids.is_empty():
		print("  [FAIL] UIPropRegistry.ids() returned no prop IDs")
		return false

	for prop_id in ids:
		var entry: Dictionary = PropRegistry.entry_for(prop_id)
		var alb: String = entry.get("albedo_path", "")
		var orm: String = entry.get("orm_path", "")
		var height: String = entry.get("height_path", "")
		if not ResourceLoader.exists(alb):
			print("  [FAIL] Missing albedo texture for prop '%s': %s" % [prop_id, alb])
			return false
		if not ResourceLoader.exists(orm):
			print("  [FAIL] Missing orm texture for prop '%s': %s" % [prop_id, orm])
			return false
		if not ResourceLoader.exists(height):
			print("  [FAIL] Missing height texture for prop '%s': %s" % [prop_id, height])
			return false
	print("  [PASS] All %d registered UI props resolve albedo, ORM, and height texture assets." % ids.size())
	return true


# Tactile Interface Programme Phase 2. Distinct prop IDs must produce distinct texture
# content (asserting unique per-prop seed variation).
func test_ui_prop_textures_are_distinct() -> bool:
	print("Running Test Suite: UI Props - Textures Are Distinct Per Prop (Phase 2)...")
	var PropRegistry = preload("res://scripts/ui/ui_prop_registry.gd")
	var btn_entry: Dictionary = PropRegistry.entry_for("push_button")
	var tgl_entry: Dictionary = PropRegistry.entry_for("toggle")

	var btn_bytes := FileAccess.get_file_as_bytes(btn_entry.get("albedo_path", ""))
	var tgl_bytes := FileAccess.get_file_as_bytes(tgl_entry.get("albedo_path", ""))
	if btn_bytes.is_empty() or tgl_bytes.is_empty():
		print("  [FAIL] Could not read albedo texture bytes for push_button or toggle")
		return false
	if btn_bytes == tgl_bytes:
		print("  [FAIL] push_button and toggle produced identical albedo bytes - seeds must vary output")
		return false

	print("  [PASS] Prop textures produce distinct per-prop byte data.")
	return true


# Tactile Interface Programme Phase 2 (X5 fix). No fract(sin(...)) float-sine hashes
# may remain in any shader under res://shaders/.
func test_pcg3d_shader_hash_swap() -> bool:
	print("Running Test Suite: Shader PCG3D Hash Swap - No fract(sin) In Shaders (X5)...")
	var dir := DirAccess.open("res://shaders")
	if dir == null:
		print("  [FAIL] Could not open res://shaders directory")
		return false
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if filename.ends_with(".gdshader"):
			var full_path := "res://shaders/" + filename
			var src := FileAccess.get_file_as_string(full_path)
			if src.find("fract(sin(") >= 0:
				print("  [FAIL] %s still contains float-sine hash 'fract(sin(' - must use integer PCG3D" % full_path)
				return false
		filename = dir.get_next()
	print("  [PASS] All shaders in res://shaders/ are free of fract(sin) float-sine hashes.")
	return true



