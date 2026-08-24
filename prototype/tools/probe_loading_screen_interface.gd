extends SceneTree
# Smoke test for the loading-screen interface contract.
#
# WHY SCENETREE, NOT NODE: this used to extend Node and be driven by the
# deleted run_tests.gd suite wrapper, which owned both the tree insertion and
# the quit. Standalone under --script a Node script never runs, so the probe
# hung forever after the wrapper went away. As a SceneTree script it drives
# itself, same as probe_battle_loading.gd.
#
# CONTRACTS:
#   1-4. Loading.tscn root is a Control with PROCESS_MODE_ALWAYS,
#        attach_battle_scene(), and a one-arg deploy_requested signal.
#   5.   The DEPLOY StampedButton exists OFF-TREE and disabled until
#        world_ready (it swaps into the preview slot at ready - see
#        loading_screen.gd's _on_world_ready).
#   6.   A LoadingPreview child exists with set_roster (only created when the
#        router's target is Battle.tscn).
#   7.   Calling _on_world_ready() arms DEPLOY inside a CenterContainer slot,
#        flips the status text, and turns the status label SIGNAL_GO green.
#
# Run:
#   ./Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script res://tools/probe_loading_screen_interface.gd

const LoadingScene = preload("res://scenes/Loading.tscn")
const StampedButtonScript = preload("res://scripts/ui_stamped_button.gd")
const SceneRouterScript = preload("res://scripts/scene_router.gd")
const LoadingPreviewScript = preload("res://scripts/loading_preview.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")

const BATTLE_PATH := "res://scenes/Battle.tscn"

var _ok: bool = true


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_ok = false


func _init():
	_run()


func _run() -> void:
	# Let the loop start ticking before touching the tree.
	await process_frame

	# The probe needs a SceneRouter whose current_target_path() is the Battle
	# path so the loading screen instantiates the LoadingPreview. Under a real
	# project boot the autoload already exists - reuse it; standalone, build a
	# stand-in.
	var router: Node = root.get_node_or_null("SceneRouter")
	if router == null:
		router = Node.new()
		router.name = "SceneRouter"
		router.set_script(SceneRouterScript)
		root.add_child(router)
	router._target_path = BATTLE_PATH

	var screen: Control = LoadingScene.instantiate()
	root.add_child(screen)
	for _i in range(6):
		await process_frame

	# Contract 1: it's a Control.
	if not (screen is Control):
		print("[FAIL] Loading.tscn root is not a Control: ", screen.get_class())
		_ok = false
	else:
		print("[OK]   Loading.tscn root is a Control")

	# Contract 2: process_mode = ALWAYS (lamps/preview tick through the pause).
	if screen.process_mode != Node.PROCESS_MODE_ALWAYS:
		print("[FAIL] process_mode = %d, expected ALWAYS (%d)" \
			% [screen.process_mode, Node.PROCESS_MODE_ALWAYS])
		_ok = false
	else:
		print("[OK]   process_mode = ALWAYS")

	# Contract 3: attach_battle_scene method.
	_check("attach_battle_scene method present", screen.has_method("attach_battle_scene"))

	# Contract 4: deploy_requested signal with one arg.
	var sig_found := false
	var sig_args := -1
	for s in screen.get_signal_list():
		if s.name == "deploy_requested":
			sig_found = true
			sig_args = s.args.size()
			break
	_check("deploy_requested signal present with one arg",
		sig_found and sig_args == 1)

	# Contract 5: DEPLOY built but off-tree and disabled until world_ready.
	var stamped: Node = screen.get("_deploy_button")
	if stamped == null:
		_check("loading screen has a _deploy_button member", false)
	elif stamped.is_inside_tree():
		_check("DEPLOY button stays out of the tree before world_ready", false)
	elif not stamped.disabled:
		_check("DEPLOY button disabled until world_ready", false)
	else:
		_check("DEPLOY button present off-tree, disabled", true)

	# Contract 6: LoadingPreview child with set_roster.
	var preview := _find_loading_preview(screen)
	_check("LoadingPreview has set_roster method",
		preview != null and preview.has_method("set_roster"))

	# Contract 7: world_ready swaps DEPLOY into a centred slot, green status.
	var status: Label = screen.get("_status_label")
	screen.call("_on_world_ready")
	await process_frame
	if stamped == null or not stamped.is_inside_tree():
		_check("world_ready put the DEPLOY button in the tree", false)
	elif not (stamped.get_parent() is CenterContainer):
		_check("DEPLOY button is centred in a slot container", false)
	elif stamped.disabled or not stamped.visible:
		_check("DEPLOY button armed at world_ready", false)
	elif status != null and status.text != "ALL SYSTEMS READY":
		_check("status text reads ALL SYSTEMS READY ('%s')" % status.text, false)
	elif status != null and status.get_theme_color("font_color") != Tokens.SIGNAL_GO:
		_check("status label turned SIGNAL_GO green at ready", false)
	else:
		_check("world_ready swaps DEPLOY into the preview slot, green", true)

	# Contract 8 (2026-08-23): auto-deploy. Arming starts a countdown that
	# shows on the legend, and expiring it drives the same handler a click
	# would (the probe has no attached Battle, so the deploy itself stops at
	# the null guard - but the latch proves the path fired).
	var remaining = screen.get("_auto_deploy_remaining")
	if remaining == null or float(remaining) <= 0.0:
		_check("auto-deploy countdown armed at ready", false)
	elif not String(stamped.legend).begins_with("DEPLOY FORCES - 10"):
		_check("countdown legend reads 'DEPLOY FORCES - 10' ('%s')" % stamped.legend, false)
	else:
		_check("auto-deploy countdown armed with legend", true)
	screen.set("_auto_deploy_remaining", 0.05)
	screen.call("_process", 0.1)
	if bool(screen.get("_deploy_started")) and screen.get("_auto_deploy_remaining") == -1.0:
		_check("expired countdown fires the deploy path once", true)
	else:
		_check("expired countdown fires the deploy path once", false)
	# The latch must hold against a second tick.
	screen.call("_process", 0.1)
	_check("deploy latch blocks re-entry",
		bool(screen.get("_deploy_started")) and screen.get("_auto_deploy_remaining") == -1.0)

	print("")
	if _ok:
		print("[probe] PASS - all contracts satisfied")
	else:
		print("[probe] FAIL - at least one contract broken")
	quit(0 if _ok else 1)


func _find_loading_preview(node: Node) -> Node:
	if node.get_script() == LoadingPreviewScript:
		return node
	for child in node.get_children():
		var found := _find_loading_preview(child)
		if found != null:
			return found
	return null
