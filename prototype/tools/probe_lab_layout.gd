extends SceneTree
# Measures the Design Lab's toolbar and dock rects, to find what actually
# overlaps what. Written because reasoning about anchors/offsets from source was
# not resolving a reported "top bar side buttons are covered by the rails".

func _init():
	var packed = load("res://scenes/MainLab.tscn")
	var inst = packed.instantiate()
	root.add_child(inst)
	for _i in range(6):
		await process_frame

	var found := {}
	_walk(inst, found, 0)

	print("\n--- rects (x, y, w, h) ---")
	for name in found:
		var c: Control = found[name]
		print("  %-22s pos=(%6.1f,%6.1f) size=(%6.1f,%6.1f)  right=%6.1f  visible=%s"
			% [name, c.global_position.x, c.global_position.y, c.size.x, c.size.y,
			   c.global_position.x + c.size.x, c.visible])

	# The specific question: does either dock's rect cover any part of the
	# toolbar's vertical band?
	if found.has("Toolbar"):
		var tb: Control = found["Toolbar"]
		var tb_top := tb.global_position.y
		var tb_bot := tb.global_position.y + tb.size.y
		print("\n--- toolbar band y = %.1f .. %.1f ---" % [tb_top, tb_bot])
		for name in found:
			if name == "Toolbar":
				continue
			var c: Control = found[name]
			var top := c.global_position.y
			var bot := c.global_position.y + c.size.y
			if top < tb_bot and bot > tb_top:
				print("  OVERLAP: %s spans y %.1f..%.1f, x %.1f..%.1f"
					% [name, top, bot, c.global_position.x, c.global_position.x + c.size.x])
	quit(0)


func _walk(n: Node, out: Dictionary, depth: int) -> void:
	if depth > 6:
		return
	for child in n.get_children():
		if child is Control:
			var nm := str(child.name)
			if nm in ["Toolbar", "StatsDock"] or child.get_class() == "UIDock" \
					or (child.get_script() != null and str(child.get_script().resource_path).ends_with("ui_dock.gd")):
				out[nm] = child
		_walk(child, out, depth + 1)
