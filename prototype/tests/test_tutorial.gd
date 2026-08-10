extends "res://tests/suite_base.gd"
# Tutorial suites. Registration order lives in run_tests.gd's SUITE_ORDER, not
# here.
#
# WHAT THESE ARE ACTUALLY PROTECTING: the tutorial reaches into the Design Lab's
# UI from outside it - part cards, dock states, toolbar buttons that
# stat_calculator reparents at runtime. None of that is a stable API, and the Lab
# gets rebuilt regularly. If the tutorial silently stops resolving a target, the
# symptom in-game is a card pointing at nothing, or worse, a step whose condition
# can never be met and which therefore strands the player. Suite 3 is the one
# that catches that class of break at build time instead.

const TutorialSteps = preload("res://scripts/tutorial/tutorial_steps.gd")
const TutorialOverlay = preload("res://scripts/tutorial/tutorial_overlay.gd")
const TutorialManagerScript = preload("res://scripts/tutorial/tutorial_manager.gd")


# The step table is data, so it can be checked without instantiating anything.
# A typo'd advance id is the worst failure this feature has - the step's
# condition would simply never be met and the only way out is the Skip button.
func test_tutorial_step_table_is_well_formed() -> bool:
	print("Running Test Suite: Tutorial - Step Table Integrity...")
	var ok := true

	if TutorialSteps.count() < 1:
		print("  [FAIL] the step table is empty")
		return false

	var scenes := [TutorialSteps.SCENE_LAB, TutorialSteps.SCENE_ARENA]
	for i in range(TutorialSteps.count()):
		var step: Dictionary = TutorialSteps.step(i)
		var label := "step %d" % (i + 1)

		for key in ["scene", "title", "body", "target", "advance"]:
			if not step.has(key):
				print("  [FAIL] %s is missing '%s'" % [label, key])
				ok = false

		if str(step.get("scene", "")) not in scenes:
			print("  [FAIL] %s names scene '%s', which the tutorial never visits"
				% [label, step.get("scene", "")])
			ok = false

		if str(step.get("advance", "")) not in TutorialSteps.ADVANCE_IDS:
			print("  [FAIL] %s advances on '%s', which is not in ADVANCE_IDS"
				% [label, step.get("advance", "")])
			ok = false

		var target := str(step.get("target", ""))
		if not target.begins_with(TutorialSteps.PART_CARD_PREFIX) \
				and target not in TutorialSteps.TARGET_IDS:
			print("  [FAIL] %s targets '%s', which is not in TARGET_IDS"
				% [label, target])
			ok = false

		# A part_card step naming a part the catalog does not have would show a
		# highlight over nothing at all.
		if target.begins_with(TutorialSteps.PART_CARD_PREFIX):
			var type_id := target.substr(TutorialSteps.PART_CARD_PREFIX.length())
			if ModuleCatalog.get_module_data(type_id).is_empty():
				print("  [FAIL] %s points at part '%s', which is not in the catalog"
					% [label, type_id])
				ok = false

		if str(step.get("title", "")).strip_edges() == "":
			print("  [FAIL] %s has an empty title" % label)
			ok = false
		if str(step.get("body", "")).strip_edges() == "":
			print("  [FAIL] %s has an empty body" % label)
			ok = false

		# The standing no-dingbats rule. test_ui_tone_no_decorative_glyphs only
		# walks instantiated scenes, and this copy lives in a script - so this is
		# the only place it can be enforced.
		for text in [str(step.get("title", "")), str(step.get("body", ""))]:
			for c in text:
				if _is_decorative_glyph(c.unicode_at(0)):
					print("  [FAIL] %s contains decorative glyph '%s'" % [label, c])
					ok = false

	# Both directions: an id declared but never reached is dead vocabulary that
	# will rot, and the manager's match statement is written against these lists.
	var used_advance := {}
	var used_target := {}
	for i in range(TutorialSteps.count()):
		used_advance[str(TutorialSteps.step(i).get("advance", ""))] = true
		var t := str(TutorialSteps.step(i).get("target", ""))
		used_target[TutorialSteps.PART_CARD_PREFIX if t.begins_with(
			TutorialSteps.PART_CARD_PREFIX) else t] = true
	for id in TutorialSteps.ADVANCE_IDS:
		if not used_advance.has(id):
			print("  [FAIL] ADVANCE_IDS declares '%s' but no step uses it" % id)
			ok = false
	for id in TutorialSteps.TARGET_IDS:
		if not used_target.has(id):
			print("  [FAIL] TARGET_IDS declares '%s' but no step uses it" % id)
			ok = false

	# The loop has to actually close: start in the Lab, reach the Arena, come
	# back. A table that never leaves one screen is not the thing that was asked
	# for, however well-formed each entry is.
	var visited := []
	for i in range(TutorialSteps.count()):
		var s := str(TutorialSteps.step(i).get("scene", ""))
		if visited.is_empty() or visited[-1] != s:
			visited.append(s)
	if visited != [TutorialSteps.SCENE_LAB, TutorialSteps.SCENE_ARENA,
			TutorialSteps.SCENE_LAB]:
		print("  [FAIL] scene order is %s, expected Lab -> Arena -> Lab" % [visited])
		ok = false

	if ok:
		print("  [PASS] %d steps, all well-formed, closing the Lab -> Arena -> Lab loop."
			% TutorialSteps.count())
	return ok


# reveal_part() has to get through the closed layers between the player and
# the part: every family is closed by default, and the sub-family drawer
# holding the card is closed.
func test_tutorial_reveal_part_opens_the_catalog() -> bool:
	print("Running Test Suite: Tutorial - reveal_part() Opens The Catalog...")

	root.size = Vector2i(1280, 720)
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await tree.process_frame
	await tree.process_frame

	var parts = scene.get_node_or_null("UI_PartsMenu")
	if parts == null or not parts.has_method("reveal_part"):
		print("  [FAIL] MainLab has no UI_PartsMenu exposing reveal_part()")
		scene.queue_free()
		return false

	# The dock is gone. The strip is always visible; only the per-family
	# accordion has open/close state.
	if parts.get_dock() != null:
		print("  [FAIL] parts menu should not expose a UIDock anymore")
		scene.queue_free()
		return false
	# The precondition the whole method exists to defeat.
	parts.collapse_all_drawers()

	var ok := true
	var card = parts.reveal_part("medium_hull")
	if card == null:
		print("  [FAIL] reveal_part('medium_hull') found no card")
		ok = false
	else:
		if card.module_type_id != "medium_hull":
			print("  [FAIL] returned card is for '%s'" % card.module_type_id)
			ok = false
		# The card's own drawer has to be open, or the card is parented into a
		# hidden grid and has no on-screen rect to point at.
		var grid = card.get_parent()
		if not grid.visible:
			print("  [FAIL] the card's drawer was left closed")
			ok = false

	# An unknown part degrades to null rather than taking the screen down.
	if parts.reveal_part("no_such_part_exists") != null:
		print("  [FAIL] reveal_part() invented a card for an unknown type_id")
		ok = false

	scene.queue_free()
	if ok:
		print("  [PASS] reveal_part() opens the family, the tier and drawer, and returns the card.")
	return ok


# The suite that earns its keep. Every Design Lab target the tutorial names has
# to resolve to a real on-screen rect against the real scene - this fails the
# moment the Lab's UI is rebuilt out from under the tutorial.
func test_tutorial_lab_targets_all_resolve() -> bool:
	print("Running Test Suite: Tutorial - Every Target Resolves...")

	root.size = Vector2i(1280, 720)
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await tree.process_frame
	root.size = Vector2i(1280, 720)
	await tree.process_frame

	var layer := CanvasLayer.new()
	scene.add_child(layer)
	var overlay = TutorialOverlay.new()
	layer.add_child(overlay)
	await tree.process_frame

	var ok := true
	var checked := 0
	for i in range(TutorialSteps.count()):
		var step: Dictionary = TutorialSteps.step(i)
		if str(step.get("scene", "")) != TutorialSteps.SCENE_LAB:
			continue
		var target := str(step.get("target", ""))
		if target == "":
			continue

		overlay._reveal_target_host(target)
		# Docks animate; the rect is meaningless until that has settled.
		for _f in range(6):
			await tree.process_frame

		var rect: Rect2 = overlay._resolve_target(target)
		checked += 1
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			print("  [FAIL] step %d target '%s' resolved to an empty rect"
				% [i + 1, target])
			ok = false

	# The Arena's two targets are checked structurally rather than by
	# instantiating Battlefield.tscn, which spawns a vehicle off a user:// file
	# and is not reproducible headless.
	var arena_scene = load("res://scenes/Battlefield.tscn").instantiate()
	if arena_scene.get_node_or_null("UI/ReturnButton") == null:
		print("  [FAIL] Battlefield.tscn has no UI/ReturnButton for 'arena_return'")
		ok = false
	if not ("target_dummies" in arena_scene):
		print("  [FAIL] battlefield.gd no longer exposes target_dummies")
		ok = false
	if not ("target_destination" in arena_scene):
		print("  [FAIL] battlefield.gd no longer exposes target_destination")
		ok = false
	arena_scene.queue_free()

	scene.queue_free()
	if ok:
		print("  [PASS] %d Design Lab targets resolve to real rects; Arena hooks intact."
			% checked)
	return ok


# The conditions read live game state, so drive the real state and check they
# notice. hull_replaced is the subtle one: the Lab ships a placeholder Hull and
# stamps 'medium_hull' onto it, so a naive "a hull exists" check is true before
# the player has done anything and the step would self-satisfy instantly.
func test_tutorial_advances_on_real_state() -> bool:
	print("Running Test Suite: Tutorial - Conditions Track Real State...")

	root.size = Vector2i(1280, 720)
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await tree.process_frame
	await tree.process_frame

	var mgr = TutorialManagerScript.new()
	root.add_child(mgr)
	await tree.process_frame

	var ok := true

	# Walk to the hull step without letting _process advance us past it.
	mgr.active = true
	mgr.set_process(false)
	mgr._step = _step_index_for("hull_replaced")
	mgr._enter_step()

	if mgr._condition_met():
		print("  [FAIL] 'hull_replaced' was already satisfied by the placeholder hull")
		ok = false

	scene.clear_hull()
	scene._place_hull_from_ui("medium_hull")
	await tree.process_frame
	if not mgr._condition_met():
		print("  [FAIL] 'hull_replaced' did not fire after a hull was placed")
		ok = false

	# Locomotion, and the looseness the step promises: fitting Legs instead of
	# the highlighted Wheels still counts.
	mgr._step = _step_index_for("locomotion_placed")
	mgr._enter_step()
	if mgr._condition_met():
		print("  [FAIL] 'locomotion_placed' fired on a hull with no drive")
		ok = false
	scene.update_locomotion("legs", scene.default_locomotion_settings.duplicate(true))
	await tree.process_frame
	if not mgr._condition_met():
		print("  [FAIL] 'locomotion_placed' did not accept Legs in place of Wheels")
		ok = false

	# Weapons, and that a drive does NOT count as one.
	mgr._step = _step_index_for("weapon_placed")
	mgr._enter_step()
	if mgr._condition_met():
		print("  [FAIL] 'weapon_placed' counted a locomotion part as a weapon")
		ok = false
	scene._place_weapon_from_ui("basic_cannon", Vector3(0, 1.0, 0), Vector3.UP)
	await tree.process_frame
	if not mgr._condition_met():
		print("  [FAIL] 'weapon_placed' did not fire after a cannon was placed")
		ok = false

	# Naming, via the real is_named() the save path uses - so the placeholder
	# "Untitled Design" must not satisfy it.
	mgr._step = _step_index_for("design_named")
	mgr._enter_step()
	var edit = mgr._stat_member("blueprint_name_edit")
	if edit == null:
		print("  [FAIL] could not reach the blueprint name field")
		ok = false
	else:
		edit.text = "Untitled Design"
		if mgr._condition_met():
			print("  [FAIL] 'design_named' accepted the placeholder name")
			ok = false
		edit.text = "Tutorial Test Rig"
		if not mgr._condition_met():
			print("  [FAIL] 'design_named' rejected a real name")
			ok = false

	# Button steps must not advance on their own.
	mgr._step = _step_index_for("next_button")
	mgr._enter_step()
	if mgr._condition_met():
		print("  [FAIL] a button step advanced without the button being pressed")
		ok = false
	mgr.notify_button()
	if not mgr._condition_met():
		print("  [FAIL] a button step ignored notify_button()")
		ok = false

	mgr.active = false
	mgr.queue_free()
	scene.queue_free()
	if ok:
		print("  [PASS] Conditions track real game state, and none self-satisfy.")
	return ok


func test_tutorial_skip_clears_state() -> bool:
	print("Running Test Suite: Tutorial - Skip Leaves Nothing Behind...")

	root.size = Vector2i(1280, 720)
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await tree.process_frame

	var mgr = TutorialManagerScript.new()
	root.add_child(mgr)
	await tree.process_frame

	var ok := true
	var results := []
	mgr.finished.connect(func(completed: bool): results.append(completed))

	mgr.begin()
	await tree.process_frame
	if not mgr.active:
		print("  [FAIL] begin() did not arm the tutorial")
		ok = false
	if not is_instance_valid(mgr._overlay):
		print("  [FAIL] begin() spawned no overlay in the Design Lab")
		ok = false

	# Skipping is reachable from the card itself, not just from the API - a
	# player mid-arena has to be able to leave.
	var skip_btn = mgr._overlay.get_node_or_null("CoachCard").find_child(
		"SkipButton", true, false)
	if skip_btn == null:
		print("  [FAIL] the coach card has no SKIP button")
		ok = false
	else:
		skip_btn.pressed.emit()

	await tree.process_frame
	if mgr.active:
		print("  [FAIL] the tutorial stayed active after skip")
		ok = false
	if is_instance_valid(mgr._overlay):
		print("  [FAIL] the overlay outlived the skip")
		ok = false
	if results != [false]:
		print("  [FAIL] finished emitted %s, expected [false]" % [results])
		ok = false

	# begin() while already active must not restart or stack a second overlay.
	mgr.begin()
	var first = mgr._overlay
	mgr.begin()
	if mgr._overlay != first:
		print("  [FAIL] a second begin() replaced the running overlay")
		ok = false
	mgr.skip()

	mgr.queue_free()
	scene.queue_free()
	if ok:
		print("  [PASS] Skip deactivates, frees the overlay and reports not-completed.")
	return ok


# First index whose advance id matches. Keeps the condition suites keyed to
# MEANING rather than to a step number, so reordering or inserting a step does
# not silently point them at the wrong thing.
func _step_index_for(advance: String) -> int:
	for i in range(TutorialSteps.count()):
		if str(TutorialSteps.step(i).get("advance", "")) == advance:
			return i
	return 0
