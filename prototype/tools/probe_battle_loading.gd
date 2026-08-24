extends SceneTree
# Proves the loading screen holds until the world exists, and that DEPLOY
# hands over the pre-built Battle without re-instantiating it.
#
# THE FLOW THIS ASSERTS (2026-08-23 revision - matches SceneRouter +
# loading_screen.gd's owned handoff, which replaced the deploy gate):
#
#   1. goto(Battle.tscn) lands on Loading.tscn as the current scene.
#   2. The router instantiates the Battle as a HIDDEN child of /root
#      ("BattlePending"); the tree pauses while it builds.
#   3. world_is_ready flips only after terrain/navmesh/HUD exist, and the
#      loading screen reveals its DEPLOY button (swapped into the preview
#      slot) at the same beat.
#   4. Pressing DEPLOY unpauses the tree, makes the ALREADY-BUILT instance
#      the current scene, and frees the loading screen. A re-instantiated
#      scene would re-run the multi-second world build, so step 4 also
#      asserts the instance is the same object.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_battle_loading.gd

const StampedButtonScript = preload("res://scripts/ui_stamped_button.gd")
const LIMIT := 3600

var _fails: int = 0


func _init():
	var menu = load("res://scenes/MainMenu.tscn")
	root.add_child(menu.instantiate())
	for _i in range(30):
		await process_frame

	var router = root.get_node_or_null("SceneRouter")
	if router == null:
		print("[FAIL] SceneRouter autoload missing")
		quit(1)
		return
	router.goto("res://scenes/Battle.tscn")

	# --- Phase 1: the loading screen owns the wait ---------------------------
	var screen = await _wait_for_loading_screen()
	_check("Loading.tscn became the current scene", screen != null)

	var battle: Node = await _wait_for_battle()
	if battle == null:
		print("[FAIL] Battle was never instantiated behind the loading screen")
		quit(1)
		return
	_check("Battle waits hidden", not battle.visible)
	_check("world is NOT ready yet (the whole point)", not battle.world_is_ready)

	# --- Phase 2: the world build ---------------------------------------------
	var ticks := 0
	while not battle.world_is_ready and ticks < LIMIT:
		await process_frame
		ticks += 1
		# Heartbeat: Godot block-buffers stdout when piped, but these lines
		# at least show where the wait ended up if the run is killed.
		if ticks % 600 == 0:
			print("[probe] still building... frame %d" % ticks)
	_check("world_is_ready fired", battle.world_is_ready)
	if battle.world_is_ready:
		_check("HUD exists by then", battle.hud != null)
	_check("match is paused behind the loading screen", paused)

	# --- Phase 3: DEPLOY -------------------------------------------------------
	# Search ONLY the loading screen's own subtree: the probe parked a
	# MainMenu instance under /root, and that screen is full of StampedButtons
	# that are none of this probe's business.
	var button = await _find_deploy(screen)
	_check("DEPLOY button revealed", button != null)
	if button != null:
		button.pressed.emit()
		var handed_over := false
		for _i in range(300):
			await process_frame
			if current_scene == battle and not paused:
				handed_over = true
				break
		_check("pressing DEPLOY unpauses and swaps in the SAME instance",
			handed_over)
		_check("loading screen freed after handover",
			screen == null or not is_instance_valid(screen)
				or screen.is_queued_for_deletion())

	print("")
	if _fails == 0:
		print("PASS - the curtain now holds until the match is built and deployed")
	else:
		print("%d CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


# Polls until the current scene is the loading screen (it owns
# attach_battle_scene).
func _wait_for_loading_screen():
	for _i in range(LIMIT):
		await process_frame
		var scene = current_scene
		if scene != null and scene.has_method("attach_battle_scene"):
			return scene
	return null


# The Battle enters the tree as a hidden child of /root named "BattlePending";
# it is NOT current_scene until DEPLOY. Scan root's children for the one
# carrying the director's world_ready signal.
func _wait_for_battle():
	for _i in range(LIMIT):
		await process_frame
		for child in root.get_children():
			if child != current_scene and child.has_signal("world_ready"):
				return child
	return null


func _find_deploy(from: Node):
	for _i in range(LIMIT):
		await process_frame
		var found = _deploy_button(from)
		if found != null:
			return found
	return null


func _deploy_button(node):
	# Match the loading screen's own button specifically: StampedButton draws
	# its legend through a StampedLabel child, so test the legend property,
	# falling back to Button text.
	if node.get_script() == StampedButtonScript \
			and "legend" in node and String(node.legend).begins_with("DEPLOY"):
		return node
	if node is Button and String(node.text).begins_with("DEPLOY"):
		return node
	for child in node.get_children():
		var found = _deploy_button(child)
		if found != null:
			return found
	return null


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1
