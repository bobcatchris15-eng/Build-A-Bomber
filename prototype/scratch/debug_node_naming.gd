extends SceneTree

func _init():
	var parent = Node3D.new()
	root.add_child(parent)

	var pivot = Node3D.new()
	pivot.name = "RotorBlades"
	print("[DEBUG] pivot.name right after assignment (before add_child): ", pivot.name)
	parent.add_child(pivot)
	print("[DEBUG] pivot.name right after add_child: ", pivot.name)

	var found = parent.get_node_or_null("RotorBlades")
	print("[DEBUG] get_node_or_null result: ", found)

	quit(0)
