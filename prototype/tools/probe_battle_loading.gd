extends SceneTree
# Proves the fix for "the loading screen goes away before the world exists".
#
# THE BUG. match_director._ready() awaits its terrain bake, which makes _ready()
# a coroutine: it returns to the engine at that await and finishes many frames
# later. SceneRouter waited two frames and lifted its fade, so the player arrived
# on a match with bases already spawned (they are created BEFORE the await) and
# no terrain, no navmesh and no HUD - "a blank white square and the base
# pre-rendered floating in front of me".
#
# WHAT THIS ASSERTS, in order:
#   1. The fade is still opaque when the Battle scene first enters the tree.
#   2. world_is_ready goes true only after terrain and HUD exist.
#   3. The DEPLOY gate appears, and the match is PAUSED behind it.
#   4. Pressing it unpauses and clears the curtain.
#
# Step 3 is the one worth the trouble: the match is live from frame one, so a
# gate that showed a button without stopping the clock would let the AI take its
# opening moves while the player was still reading it.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --path . \
#          --script tools/probe_battle_loading.gd

const LIMIT := 1200

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

	# --- Wait for the Battle scene itself ------------------------------------
	var battle = await _wait_for_battle()
	if battle == null:
		print("[FAIL] Battle scene never became current")
		quit(1)
		return
	_check("curtain is opaque when Battle enters the tree",
		router._fade_rect.visible and router._fade_rect.modulate.a > 0.99)
	_check("world is NOT ready yet (the whole point)", not battle.world_is_ready)

	# --- Wait for the world ---------------------------------------------------
	var ticks := 0
	while not battle.world_is_ready and ticks < LIMIT:
		await process_frame
		ticks += 1
	_check("world_is_ready fired", battle.world_is_ready)
	_check("terrain exists by then", battle.get_node_or_null("Terrain") != null
		or battle.ground_nav_map != null)
	_check("HUD exists by then", battle.production_hud != null)

	# --- The gate -------------------------------------------------------------
	var button = await _find_deploy(router)
	_check("DEPLOY gate appeared", button != null)
	if button != null:
		_check("match is paused behind the gate", paused)
		button.pressed.emit()
		for _i in range(20):
			await process_frame
		_check("pressing DEPLOY unpauses", not paused)
		_check("curtain lifted", router._fade_rect.modulate.a < 0.01)

	print("")
	if _fails == 0:
		print("PASS - the curtain now holds until the match is built and deployed")
	else:
		print("%d CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


func _wait_for_battle():
	for _i in range(LIMIT):
		await process_frame
		var scene = current_scene
		if scene != null and scene.has_signal("world_ready"):
			return scene
	return null


func _find_deploy(router):
	for _i in range(240):
		await process_frame
		for node in router._fade_layer.get_children():
			var found = _deploy_button(node)
			if found != null:
				return found
	return null


func _deploy_button(node):
	if node is Button and node.text == "DEPLOY":
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
