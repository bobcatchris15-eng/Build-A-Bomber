extends Node
# Node-based smoke test for the new loading-screen interface.
#
# Why this is a Node, not a SceneTree: the loading screen's _ready
# awaits two `get_tree().process_frame` ticks before calling
# `router.run_load()`, and `await` in SceneTree._init doesn't yield
# because the main loop isn't running yet. By running as a Node
# inside a SceneTree, the awaits fire correctly and we can verify
# the contract the SceneRouter depends on.
#
# Run from prototype/ via the wrapper:
#   ./Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script res://run_tests.gd  (this probe is added to SUITE_ORDER)
#
# Or as a one-shot SceneTree probe that instantiates THIS node:
#   ./Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script res://tools/probe_loading_screen_interface.gd

const LoadingScene = preload("res://scenes/Loading.tscn")
const StampedButtonScript = preload("res://scripts/ui_stamped_button.gd")
const SceneRouterScript = preload("res://scripts/scene_router.gd")
const LoadingPreviewScript = preload("res://scripts/loading_preview.gd")

const BATTLE_PATH := "res://scenes/Battle.tscn"

var _ok: bool = true
var _loading_screen: Control = null


func _ready() -> void:
	# The probe's parent (root) is busy setting up children while
	# _ready runs, so add_child fails synchronously. Defer the
	# actual setup to the next frame, by which time _ready is done.
	call_deferred("_setup")


func _setup() -> void:
	# We need a SceneRouter in the tree so the loading screen's
	# `if router` branches fire, AND its current_target_path() must
	# return BATTLE_PATH so the loading screen instantiates the
	# LoadingPreview (otherwise the preview branch is skipped and
	# the probe reports a contract failure on a legitimately working
	# loading screen).
	#
	# We set _target_path AFTER the script is attached and AFTER
	# the node is in the tree, so the script's _init has run and
	# the variable is a real member. set()'s name resolution can
	# race with script variable initialisation when the script was
	# just attached, hence the deferred sequence.
	var router: Node = Node.new()
	router.name = "SceneRouter"
	router.set_script(SceneRouterScript)
	get_tree().root.add_child(router)
	# Direct assignment bypasses any name-resolution races between
	# set() and the script's variable initialisation. The script
	# declares var _target_path: String = "" so the slot exists
	# from the moment the script is attached.
	router._target_path = BATTLE_PATH
	# Sanity: verify the assignment stuck.
	print("[probe] router._target_path = '%s' (expected '%s')" \
		% [str(router.get("_target_path")), BATTLE_PATH])

	# Now create and add the loading screen - the router's
	# current_target_path() returns BATTLE_PATH, so the loading
	# screen's _ready will instantiate the LoadingPreview.
	_loading_screen = LoadingScene.instantiate()
	get_tree().root.add_child(_loading_screen)

	# Loading screen's _ready awaits two process_frame ticks
	# before run_load(); the preview's own _ready builds the
	# first unit on the first tick of its _process. Wait enough
	# frames for both to settle. NOTE: the warm list inside
	# run_load() blocks the main thread for ~1s of script
	# compilation, which means the process_frame the await is
	# waiting on only fires AFTER the warm list returns. The
	# 6-frame loop here is therefore actually 6 frames past the
	# end of the warm list, not 6 wall-clock frames from now.
	for _i in range(6):
		await get_tree().process_frame

	_run_contracts()


func _run_contracts() -> void:
	# Contract 1: it's a Control.
	if not (_loading_screen is Control):
		print("[FAIL] Loading.tscn root is not a Control: ", _loading_screen.get_class())
		_ok = false
	else:
		print("[OK]   Loading.tscn root is a Control")

	# Contract 2: process_mode = ALWAYS.
	if _loading_screen.process_mode != Node.PROCESS_MODE_ALWAYS:
		print("[FAIL] process_mode = %d, expected ALWAYS (%d)" \
			% [_loading_screen.process_mode, Node.PROCESS_MODE_ALWAYS])
		_ok = false
	else:
		print("[OK]   process_mode = ALWAYS")

	# Contract 3: attach_battle_scene method.
	if not _loading_screen.has_method("attach_battle_scene"):
		print("[FAIL] attach_battle_scene method missing")
		_ok = false
	else:
		print("[OK]   attach_battle_scene method present")

	# Contract 4: deploy_requested signal with one arg.
	if not _loading_screen.has_signal("deploy_requested"):
		print("[FAIL] deploy_requested signal missing")
		_ok = false
	else:
		var sigs: Array = _loading_screen.get_signal_list()
		var found := false
		for s in sigs:
			if s.name == "deploy_requested":
				found = true
				if s.args.size() != 1:
					print("[FAIL] deploy_requested has %d args, expected 1" % s.args.size())
					_ok = false
				break
		if not found:
			print("[FAIL] deploy_requested not in signal_list()")
			_ok = false
		elif _ok:
			print("[OK]   deploy_requested signal present with one arg")

	# Contract 5: StampedButton exists, hidden, disabled.
	var stamped := _find_stamped_button(_loading_screen)
	if stamped == null:
		print("[FAIL] no StampedButton found in the loading screen tree")
		_ok = false
	elif stamped.visible:
		print("[FAIL] DEPLOY button is visible (should be hidden until world_ready)")
		_ok = false
	elif not stamped.disabled:
		print("[FAIL] DEPLOY button is enabled (should be disabled until world_ready)")
		_ok = false
	else:
		print("[OK]   DEPLOY button present, hidden, disabled")

	# Contract 6: LoadingPreview exists and has set_roster. The
	# preview is only created when the router's current_target_path
	# is the Battle path, so a missing preview here means the
	# SceneRouter's path was empty / wrong - exactly the case
	# that breaks the world_ready -> DEPLOY flow.
	#
	# First, see what the router reports NOW (after the loading
	# screen has had a chance to read it).
	var router := get_node_or_null("/root/SceneRouter")
	if router != null:
		print("[probe] after-load: router._target_path = '%s'" \
			% str(router.get("_target_path")))
		print("[probe] after-load: router.current_target_path() = '%s'" \
			% str(router.call("current_target_path")))
	var preview := _find_loading_preview(_loading_screen)
	if preview == null:
		print("[FAIL] no LoadingPreview found. Loading screen children:")
		for c in _loading_screen.get_children():
			print("       ", c.name, " (", c.get_class(), ")")
		_ok = false
	elif not preview.has_method("set_roster"):
		print("[FAIL] LoadingPreview has no set_roster method")
		_ok = false
	else:
		print("[OK]   LoadingPreview has set_roster method")

	# Final.
	if _ok:
		print("[OK]   all 6 contracts satisfied")
	else:
		print("[FAIL] at least one contract broken")
	print("[probe] " + ("PASS" if _ok else "FAIL"))


func _find_stamped_button(node: Node) -> Node:
	if node.get_script() == StampedButtonScript:
		return node
	for child in node.get_children():
		var found := _find_stamped_button(child)
		if found != null:
			return found
	return null


func _find_loading_preview(node: Node) -> Node:
	if node.get_script() == LoadingPreviewScript:
		return node
	for child in node.get_children():
		var found := _find_loading_preview(child)
		if found != null:
			return found
	return null
