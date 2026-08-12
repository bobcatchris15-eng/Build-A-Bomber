extends SceneTree
# Headless probe: boots into the test range, dumps what HUD/UI exists.
# Read-only - no scene changes. Used to verify the menu gap.

const MatchRuleSetScript = preload("res://scripts/match_rule_set.gd")

func _initialize() -> void:
	# Simulate TestRangeLauncher.
	var BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")

	var mgr = BlueprintManagerScript.new()
	root.add_child(mgr)
	var scratch: Dictionary = mgr.load_blueprint("user://lab_scratch.json")
	if not scratch.is_empty():
		print("PROBE: scratch blueprint present")
	else:
		print("PROBE: no scratch, using fallback")
	mgr.queue_free()

	# The engine autoloads MatchConfig on boot; use that one, not a fresh node
	# (a same-named second child would be retrievable but the engine's autoload
	# is what `get_node_or_null("MatchConfig")` returns everywhere else).
	var mc := root.get_node_or_null("MatchConfig")
	if mc == null:
		var MatchConfigScript = preload("res://scripts/match_config.gd")
		mc = Node.new()
		mc.name = "MatchConfig"
		mc.set_script(MatchConfigScript)
		root.add_child(mc)
	mc.selected_map_id = "test_range"
	mc.rule_set = MatchRuleSetScript.test_range(
		"res://data/loadout/bulwark_mbt.json",
		["res://data/loadout/bulwark_mbt.json",
		 "res://data/loadout/rattler_scout.json",
		 "res://data/loadout/wasp_rocket_buggy.json"])

	change_scene_to_file("res://scenes/Battle.tscn")

func _process(delta: float) -> bool:
	# Wait for the match to build. match_director.gd sets world_is_ready = true
	# in _ready() after terrain bake.
	var scene := current_scene
	if scene == null:
		return false
	if "world_is_ready" in scene and scene.world_is_ready:
		print("PROBE: world is ready")
		_dump(scene)
		# Test if pressing Escape would open SystemLayer menu.
		print("PROBE: ui_cancel action exists? ",
			InputMap.has_action("ui_cancel"))
		# Print all input actions.
		for a in InputMap.get_actions():
			var events = InputMap.action_get_events(a)
			var keys := []
			for e in events:
				if e is InputEventKey:
					keys.append(OS.get_keycode_string(e.keycode))
			if keys.size() > 0:
				print("  action %s -> %s" % [a, ", ".join(keys)])
		# Check SystemLayer state.
		var sl = root.get_node_or_null("SystemLayer")
		if sl:
			print("PROBE: SystemLayer present, is_open=", sl.is_open())
		else:
			print("PROBE: SystemLayer NOT mounted")
			quit()
			return true
		# Directly call open() - the simulated Escape path is too easy to
		# intercept on the headless boot we use for this probe.
		# Debug: dump what _in_test_range sees.
		var mc := root.get_node_or_null("MatchConfig")
		if mc:
			print("PROBE DEBUG: MatchConfig present, rule_set=", mc.get("rule_set"))
			if mc.get("rule_set") != null:
				var rs = mc.get("rule_set")
				var mode_v: Variant = rs.get("mode", -1)
				var test_range_v: Variant = MatchRuleSetScript.Mode.TEST_RANGE
				print("PROBE DEBUG: mode_v=", mode_v, " (", typeof(mode_v), ") test_range_v=", test_range_v, " (", typeof(test_range_v), ") equal=", mode_v == test_range_v)
		else:
			print("PROBE DEBUG: MatchConfig NOT found")
		print("PROBE DEBUG: _in_test_range()=", sl._in_test_range())
		sl.open()
		await process_frame
		print("PROBE: after open(), is_open=", sl.is_open())
		if sl._menu_box != null:
			for child in sl._menu_box.get_children():
				var desc: String = str(child.name) + " [" + child.get_class() + "]"
				if child is Button:
					desc += " text='" + str(child.text) + "'"
				print("  menu child: " + desc)
		quit()
		return true
	return false

func _dump(node: Node, depth: int = 0) -> void:
	var prefix := "  ".repeat(depth)
	var desc := "%s [%s]" % [node.name, node.get_class()]
	if node is Control:
		desc += " visible=%s mouse_filter=%d" % [str(node.visible), node.mouse_filter]
	if node.has_meta("faction"):
		desc += " faction=%s" % node.get_meta("faction")
	print(prefix + desc)
	for child in node.get_children():
		_dump(child, depth + 1)
