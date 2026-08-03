extends SceneTree
# Scratch: prints the width budget of the parts-catalogue dock subtree, to find
# what actually makes its content minimum 352px inside a 336px column.
# test_ui_no_overflow_or_offscreen reports the culprit node but not the arithmetic.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_parts_width.gd --path .
func _init():
	root.size = Vector2i(1280, 720)
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	for i in range(10):
		await process_frame

	var pm = scene.get_node_or_null("UI_PartsMenu")
	if pm == null:
		print("no UI_PartsMenu")
		quit(1)
		return
	print("UI_PartsMenu.size = ", pm.size, "  min=", pm.get_combined_minimum_size())
	_walk(pm, 0)
	print("DONE")
	quit(0)

func _walk(n: Node, depth: int) -> void:
	if n is Control:
		var c := n as Control
		var cmin := c.get_combined_minimum_size()
		# Only the ones that actually constrain width are interesting.
		if cmin.x > 300.0 or depth <= 3:
			print("%s%s [%s] size=%s cmin=%s flags_h=%d" % [
				"  ".repeat(depth), c.name, c.get_class(), c.size, cmin, c.size_flags_horizontal])
	if depth > 6:
		return
	for ch in n.get_children():
		_walk(ch, depth + 1)
