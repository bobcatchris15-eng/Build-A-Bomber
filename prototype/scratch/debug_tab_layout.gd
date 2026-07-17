extends SceneTree
# Debug: check ScrollContainer and layout sizes in the Hulls tab

func _init():
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 800)
	for i in range(8): await process_frame

	var parts_menu = scene.get_node_or_null("UI_PartsMenu")

	print("\n=== TAB LAYOUT DEBUG ===")

	var tab_container = parts_menu.get_node_or_null("PanelContainer/VBoxContainer/TabContainer")
	print("TabContainer size: %s" % tab_container.size)
	print("TabContainer custom_min_size: %s" % tab_container.custom_minimum_size)

	var scroll_container = parts_menu.get_node_or_null("PanelContainer/VBoxContainer/TabContainer/Hulls")
	print("\nScrollContainer size: %s" % scroll_container.size)
	print("ScrollContainer visible: %s" % scroll_container.visible)
	print("ScrollContainer custom_min_size: %s" % scroll_container.custom_minimum_size)
	print("ScrollContainer layout_mode: %s" % scroll_container.layout_mode)
	print("ScrollContainer size_flags_horizontal: %s" % scroll_container.size_flags_horizontal)
	print("ScrollContainer size_flags_vertical: %s" % scroll_container.size_flags_vertical)

	var vbox_container = scroll_container.get_child(0)
	print("\nVBoxContainer size: %s" % vbox_container.size)
	print("VBoxContainer custom_min_size: %s" % vbox_container.custom_minimum_size)
	print("VBoxContainer size_flags_horizontal: %s" % vbox_container.size_flags_horizontal)

	var first_drawer = vbox_container.get_child(0)
	print("\nFirst drawer (Ground):")
	print("  Size: %s" % first_drawer.size)
	print("  Visible: %s" % first_drawer.visible)
	print("  Custom min size: %s" % first_drawer.custom_minimum_size)
	print("  Position: %s" % first_drawer.position)

	# Check if any drawer is off-screen
	print("\nAll drawers positions:")
	for i in range(vbox_container.get_child_count()):
		var drawer = vbox_container.get_child(i)
		if drawer.has_meta("drawer_category"):
			var category = drawer.get_meta("drawer_category")
			print("  %s: pos=%s size=%s" % [category, drawer.position, drawer.size])

	print("\n=== END DEBUG ===\n")
	quit(0)
