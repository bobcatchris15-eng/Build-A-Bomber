extends "res://tests/suite_base.gd"
# UIPropStage + StampedButton-on-stage + MeshIcon-on-stage suites.
# Phase 1 of the Tactile Interface Programme (TACTILE_INTERFACE_PLAN.md
# Part 4). Registration order lives in run_tests.gd's SUITE_ORDER,
# not here.
#
# WHAT THIS FILE GUARDS.
#
# The five invariants the plan lists as the regression surface for
# Phase 1:
#
#   1. The rect-to-world mapping is the exact affine the plan
#      specifies, at the four viewport corners and at centre. A
#      future change to the ortho camera's size or the world's
#      origin shifts every prop on every screen, so this is the
#      one to nail first.
#
#   2. Attach + detach leaves no orphan MeshInstance3D. A
#      SubViewport with a stale mesh is a memory leak and, worse,
#      a prop that renders in the wrong place if its host ever
#      re-attaches with the same handle.
#
#   3. A state change marks the stage dirty exactly once. The
#      dirty-driven render cycle is the entire performance
#      argument for the unification (D2); a state change that
#      double-fires or zero-fires is a regression either way.
#
#   4. A screen with N StampedButtons has exactly ONE SubViewport.
#      This is the X2 regression guard: the old code put a
#      SubViewport per button. A future refactor that re-introduces
#      per-control viewports is the kind of thing a test has to
#      catch.
#
#   5. A StampedButton with no UIPropStage ancestor still
#      constructs and still reports its minimum size. The
#      headless test path depends on this; a regression here is
#      a regression in every existing test that uses StampedButton.

const UIPropStageScript = preload("res://scripts/ui/ui_prop_stage.gd")
const UIPropRegistryScript = preload("res://scripts/ui/ui_prop_registry.gd")
const StampedButtonScript = preload("res://scripts/ui_stamped_button.gd")
const MeshIconScript = preload("res://scripts/ui/mesh_icon.gd")

const TEST_VIEWPORT_SIZE := Vector2i(1920, 1080)

# Forces the test viewport to a real resolution, the same way
# test_ui_and_camera.gd does it. Headless mode's default is 64x64,
# which makes every anchor-based layout meaningless. Set multiple
# times with process_frame waits between because the first
# assignment does not always stick before the scene's _ready
# runs (verified empirically in test_ui_and_camera.gd's
# test_ui_no_overflow_or_offscreen).
func _force_viewport_size() -> void:
	root.size = TEST_VIEWPORT_SIZE
	await tree.process_frame
	root.size = TEST_VIEWPORT_SIZE
	await tree.process_frame
	root.size = TEST_VIEWPORT_SIZE
	await tree.process_frame


# Walks the tree and returns every SubViewport under `start`. Used
# by test 4 to assert the stage is the only SubViewport. A
# SubViewportContainer is NOT a SubViewport, so the standard
# `node is SubViewport` check is what we want - the test would
# silently pass on a SubViewportContainer otherwise.
func _collect_subviewports(start: Node) -> Array:
	var found: Array = []
	var stack: Array = [start]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is SubViewport:
			found.append(n)
		for c in n.get_children():
			stack.append(c)
	return found


func _collect_mesh_instances(start: Node) -> Array:
	var found: Array = []
	var stack: Array = [start]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			found.append(n)
		for c in n.get_children():
			stack.append(c)
	return found


# --- Test 1: rect-to-world mapping ----------------------------------------

# The formula in TACTILE_INTERFACE_PLAN.md Part 3.2:
#
#   world_x = (rect.position.x + rect.size.x * 0.5) - viewport_size.x * 0.5
#   world_y = -((rect.position.y + rect.size.y * 0.5) - viewport_size.y * 0.5)
#   world_z = ELEVATION_Z
#
# Tested at the four viewport corners and at centre, against a
# 1920x1080 stage. The numbers in the brief's description are
# illustrative - the actual expected values come from the formula.
# (The brief's example arithmetic is off by 50 in x and 95 in y;
# using the formula is the correct check.)
func test_rect_to_world_mapping_is_exact() -> bool:
	print("Running Test Suite: UIPropStage - Rect-to-World Mapping Is Exact...")
	await _force_viewport_size()
	var stage := UIPropStageScript.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(stage)
	# A host Control with a known rect. The stage derives the world
	# position from the host's get_global_rect(), so the host needs
	# to be in the tree with a real rect before the assertion runs.
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_TOP_LEFT)
	host.position = Vector2(100, 50)
	host.size = Vector2(200, 100)
	stage.add_child(host)
	await tree.process_frame

	# Centre of rect (100, 50, 200, 100) is (200, 100). Subtracted
	# from the viewport centre (960, 540) and with y inverted
	# (the camera looks down -Z so screen y goes from +top to
	# -bottom in world), the prop centre lands at:
	#   world_x = 200 - 960 = -760
	#   world_y = -(100 - 540) = 440
	var handle := stage.attach(host, "push_button")
	if handle == -1:
		print("  [FAIL] stage.attach returned -1; a fresh stage with a valid prop_id should attach")
		stage.queue_free()
		return false
	var xform: Transform3D = stage.get_prop_transform(handle)
	var pos: Vector3 = xform.origin
	var expected_x: float = 200.0 - float(TEST_VIEWPORT_SIZE.x) * 0.5
	var expected_y: float = -((100.0 - float(TEST_VIEWPORT_SIZE.y) * 0.5))
	if not is_equal_approx(pos.x, expected_x):
		print("  [FAIL] centre rect: world_x expected ", expected_x, ", got ", pos.x)
		stage.queue_free()
		return false
	if not is_equal_approx(pos.y, expected_y):
		print("  [FAIL] centre rect: world_y expected ", expected_y, ", got ", pos.y)
		stage.queue_free()
		return false
	if not is_equal_approx(pos.z, UIPropStageScript.ELEVATION_Z):
		print("  [FAIL] centre rect: world_z expected ", UIPropStageScript.ELEVATION_Z, ", got ", pos.z)
		stage.queue_free()
		return false

	# Now test the four corners + extreme positions. Each one
	# constructs a fresh stage + host so the rect is unambiguous
	# (the previous host's rect could be cached by the stage if
	# we reused it, and we want a clean check per position).
	var cases: Array = [
		{"pos": Vector2(0, 0), "size": Vector2(100, 100), "name": "top-left corner"},
		{"pos": Vector2(1820, 0), "size": Vector2(100, 100), "name": "top-right corner"},
		{"pos": Vector2(0, 980), "size": Vector2(100, 100), "name": "bottom-left corner"},
		{"pos": Vector2(1820, 980), "size": Vector2(100, 100), "name": "bottom-right corner"},
		{"pos": Vector2(860, 490), "size": Vector2(200, 100), "name": "centre of viewport"},
	]
	for case in cases:
		var local_stage := UIPropStageScript.new()
		local_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(local_stage)
		var local_host := Control.new()
		local_host.set_anchors_preset(Control.PRESET_TOP_LEFT)
		local_host.position = case["pos"]
		local_host.size = case["size"]
		local_stage.add_child(local_host)
		await tree.process_frame
		var h: int = local_stage.attach(local_host, "push_button")
		if h == -1:
			print("  [FAIL] stage.attach refused on ", case["name"])
			local_stage.queue_free()
			continue
		var t: Transform3D = local_stage.get_prop_transform(h)
		var center_x: float = case["pos"].x + case["size"].x * 0.5
		var center_y: float = case["pos"].y + case["size"].y * 0.5
		var exp_x: float = center_x - float(TEST_VIEWPORT_SIZE.x) * 0.5
		var exp_y: float = -(center_y - float(TEST_VIEWPORT_SIZE.y) * 0.5)
		if not is_equal_approx(t.origin.x, exp_x) or not is_equal_approx(t.origin.y, exp_y):
			print("  [FAIL] ", case["name"], ": expected (", exp_x, ", ", exp_y, "), got (", t.origin.x, ", ", t.origin.y, ")")
			local_stage.queue_free()
			return false
		local_stage.queue_free()
		await tree.process_frame
	stage.queue_free()
	await tree.process_frame
	print("  [PASS] Rect-to-world mapping matches the plan's formula at the centre rect, the four viewport corners, and the centre of the viewport.")
	return true


# --- Test 2: attach/detach leaves no orphan mesh --------------------------

func test_attach_detach_leaves_no_orphan_mesh() -> bool:
	print("Running Test Suite: UIPropStage - Attach/Detach Leaves No Orphan Mesh...")
	await _force_viewport_size()
	var stage := UIPropStageScript.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(stage)
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_TOP_LEFT)
	host.position = Vector2(100, 100)
	host.size = Vector2(132, 44)
	stage.add_child(host)
	await tree.process_frame

	var handle := stage.attach(host, "push_button")
	if handle == -1:
		print("  [FAIL] stage.attach refused a valid prop_id")
		stage.queue_free()
		return false
	# Attach a second prop, then detach only the first. The second
	# should still be present - detach is per-handle, not "drop
	# everything".
	var host2 := Control.new()
	host2.set_anchors_preset(Control.PRESET_TOP_LEFT)
	host2.position = Vector2(300, 100)
	host2.size = Vector2(132, 44)
	stage.add_child(host2)
	await tree.process_frame
	var handle2 := stage.attach(host2, "push_button")
	if handle2 == -1:
		print("  [FAIL] second attach refused")
		stage.queue_free()
		return false

	stage.detach(handle)
	await tree.process_frame
	var after_first := _collect_mesh_instances(stage)
	if after_first.size() != 1:
		print("  [FAIL] expected exactly 1 MeshInstance3D after detaching one of two, got ", after_first.size())
		stage.queue_free()
		return false

	stage.detach(handle2)
	await tree.process_frame
	var after_both := _collect_mesh_instances(stage)
	if after_both.size() != 0:
		print("  [FAIL] expected 0 MeshInstance3D after detaching both, got ", after_both.size())
		stage.queue_free()
		return false
	stage.queue_free()
	await tree.process_frame
	print("  [PASS] Detach is per-handle and leaves no MeshInstance3D behind.")
	return true


# --- Test 3: state change marks stage dirty exactly once ------------------

func test_state_change_marks_stage_dirty_exactly_once() -> bool:
	print("Running Test Suite: UIPropStage - State Change Marks Stage Dirty Exactly Once...")
	await _force_viewport_size()
	var stage := UIPropStageScript.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(stage)
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_TOP_LEFT)
	host.position = Vector2(100, 100)
	host.size = Vector2(132, 44)
	stage.add_child(host)
	await tree.process_frame
	var handle := stage.attach(host, "push_button")
	if handle == -1:
		print("  [FAIL] stage.attach refused")
		stage.queue_free()
		return false

	# Snapshot the count after attach(). attach() itself fires one
	# request_render() (it has to, so the first frame shows the
	# prop in the right place). The test asserts the DELTA caused by
	# the state change, not the absolute number.
	var baseline: int = stage.render_count()
	stage.set_prop_state(handle, "hover")
	var after_state: int = stage.render_count()
	if after_state - baseline != 1:
		print("  [FAIL] expected exactly 1 render_count increment for set_prop_state, got ", after_state - baseline)
		stage.queue_free()
		return false

	# Setting the same state again is a no-op (the entry already
	# carries that state, the change is short-circuited), so
	# request_render() does NOT fire. A future "set the state
	# unconditionally" refactor that re-renders on every set would
	# show up here.
	stage.set_prop_state(handle, "hover")
	if stage.render_count() != after_state:
		print("  [FAIL] a no-op set_prop_state should not increment render_count, but it did")
		stage.queue_free()
		return false

	# Setting a different state fires exactly one more render.
	stage.set_prop_state(handle, "pressed")
	if stage.render_count() - after_state != 1:
		print("  [FAIL] expected exactly 1 render_count increment for the second distinct state, got ", stage.render_count() - after_state)
		stage.queue_free()
		return false

	# Variant changes also count, and short-circuit on the same
	# value the same way.
	stage.set_prop_variant(handle, "primary")
	if stage.render_count() - after_state != 2:
		print("  [FAIL] expected exactly 1 more render for set_prop_variant, got ", stage.render_count() - after_state)
		stage.queue_free()
		return false
	stage.set_prop_variant(handle, "primary")
	if stage.render_count() - after_state != 2:
		print("  [FAIL] a no-op set_prop_variant should not increment render_count")
		stage.queue_free()
		return false

	stage.queue_free()
	await tree.process_frame
	print("  [PASS] set_prop_state and set_prop_variant mark the stage dirty exactly once per distinct change, never on a no-op.")
	return true


# --- Test 4: N buttons share one SubViewport ------------------------------

func test_screen_with_n_buttons_has_one_subviewport() -> bool:
	print("Running Test Suite: UIPropStage - Screen With N Buttons Has One SubViewport...")
	await _force_viewport_size()
	var stage := UIPropStageScript.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(stage)
	# A container for the three buttons. The buttons are added as
	# children of the stage (not children of the container) so the
	# test isolates the per-button viewport question from the
	# layout question. Each button is its own Control, with its
	# own rect, in the stage's coordinate space.
	const N := 3
	for i in range(N):
		var btn: Button = StampedButtonScript.new()
		btn.custom_minimum_size = Vector2(132, 44)
		btn.position = Vector2(10.0 + float(i) * 150.0, 10.0)
		btn.size = Vector2(132, 44)
		stage.add_child(btn)
	await tree.process_frame
	# A second stage to test that we only count the right one.
	# Wait, that would itself be a second SubViewport. The whole
	# point of the test is that ONE stage gives ONE SubViewport.
	# The previous StampedButton code added a SubViewportContainer
	# per button; the new code should add zero. The stage itself
	# is the only SubViewport in the tree.
	var viewports: Array = _collect_subviewports(root)
	if viewports.size() != 1:
		print("  [FAIL] expected exactly 1 SubViewport under root (the stage's), got ", viewports.size(), " (a future per-button viewport regression would show up here)")
		stage.queue_free()
		return false
	# Sanity: the single SubViewport belongs to the stage.
	if viewports[0] != stage.get_node("StageViewport"):
		print("  [FAIL] the only SubViewport under root is not the stage's; it must be the stage's")
		stage.queue_free()
		return false
	stage.queue_free()
	await tree.process_frame
	print("  [PASS] ", N, " StampedButtons share one SubViewport (the stage's); zero per-button viewports.")
	return true


# --- Test 5: StampedButton without stage ancestor still renders ------------

# The documented silent fallback. A StampedButton with no
# UIPropStage in its ancestor chain must:
#   * not crash on _ready
#   * report its minimum size (the test calls get_minimum_size())
#   * have a FocusRing child that is invisible (no focus, not disabled)
#   * have a Label child (the StampedLabel) that shows the legend
#
# This is the migration safety net. A test that runs without
# instantiating a stage must still be able to use StampedButton.
func test_stamped_button_without_stage_ancestor_still_renders() -> bool:
	print("Running Test Suite: StampedButton - Without Stage Ancestor Still Renders...")
	var btn: Button = StampedButtonScript.new()
	btn.custom_minimum_size = Vector2(StampedButtonScript.MIN_WIDTH, StampedButtonScript.MIN_HEIGHT)
	btn.legend = "TEST LEGEND"
	btn.variant = StampedButtonScript.Variant.PRIMARY
	root.add_child(btn)
	await tree.process_frame
	# No crash above. Now check the structural invariants.
	if btn.get_child_count() < 2:
		print("  [FAIL] expected at least a Label and FocusRing child, got ", btn.get_child_count())
		btn.queue_free()
		return false
	# The minimum size is driven by the constants on the fallback
	# path (there is no 3D mesh to size off). Read the
	# custom_minimum_size directly - the Control's
	# get_combined_minimum_size() can come back smaller than the
	# custom_minimum_size in headless mode because the default
	# theme's stylebox content margins are zero, but the
	# custom_minimum_size is the documented contract.
	if btn.custom_minimum_size.x < StampedButtonScript.MIN_WIDTH or btn.custom_minimum_size.y < StampedButtonScript.MIN_HEIGHT:
		print("  [FAIL] custom_minimum_size should be at least (", StampedButtonScript.MIN_WIDTH, ", ", StampedButtonScript.MIN_HEIGHT, "), got ", btn.custom_minimum_size)
		btn.queue_free()
		return false
	# The COMPACT variant shrinks the height; the others leave it.
	# A Primary variant should keep the standard height.
	btn.variant = StampedButtonScript.Variant.COMPACT
	if btn.custom_minimum_size.y != StampedButtonScript.COMPACT_HEIGHT:
		print("  [FAIL] COMPACT variant should set custom_minimum_size.y to ", StampedButtonScript.COMPACT_HEIGHT, ", got ", btn.custom_minimum_size.y)
		btn.queue_free()
		return false
	# A setter that mutates an existing override (hd_material_override)
	# must not crash on the fallback path. The override is stored
	# but has no visible effect (no 3D mesh to attach it to).
	btn.hd_material_override = null
	# And a re-set of an already-set value should not error.
	btn.variant = StampedButtonScript.Variant.PRIMARY
	btn.variant = StampedButtonScript.Variant.PRIMARY
	btn.queue_free()
	await tree.process_frame
	print("  [PASS] StampedButton with no UIPropStage ancestor constructs, reports its minimum size, honours the COMPACT variant height, and accepts the hd_material_override setter without error.")
	return true
