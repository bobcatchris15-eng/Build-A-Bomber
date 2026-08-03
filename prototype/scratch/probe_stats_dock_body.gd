extends SceneTree
# Scratch: why is the expanded TELEMETRY dock's body empty? Prints the stats
# dock subtree with sizes and visibility so the empty panel can be attributed to
# a real node rather than guessed at.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_stats_dock_body.gd --path .
func _init():
	await process_frame
	root.size = Vector2i(1600, 900)
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	for i in range(10):
		await process_frame

	var stats = scene.get_node_or_null("UI_StatBlock")
	var UIDockScript = load("res://scripts/ui_dock.gd")
	stats.stats_dock.set_dock_state(UIDockScript.State.EXPANDED, false)
	for i in range(6):
		await process_frame

	_walk(stats.stats_dock, 0)
	print("DONE")
	quit(0)

func _walk(n: Node, d: int) -> void:
	if d > 7:
		return
	if n is Control:
		var c := n as Control
		print("%s%s [%s] size=%s cmin=%s vis=%s vis_in_tree=%s" % [
			"  ".repeat(d), c.name, c.get_class(), c.size,
			c.get_combined_minimum_size(), c.visible, c.is_visible_in_tree()])
	for ch in n.get_children():
		_walk(ch, d + 1)
