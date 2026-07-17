extends SceneTree
# Debug: inspect drawer header styling and visibility

func _init():
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 800)
	for i in range(8): await process_frame

	var parts_menu = scene.get_node_or_null("UI_PartsMenu")
	var tab_hulls_container = parts_menu.get_node_or_null("PanelContainer/VBoxContainer/TabContainer/Hulls/VBoxContainer")

	print("\n=== DRAWER HEADER DEBUG ===")

	for i in range(tab_hulls_container.get_child_count()):
		var drawer = tab_hulls_container.get_child(i)
		if drawer.has_meta("drawer_category"):
			var header_btn = drawer.get_meta("header_btn")
			var category = drawer.get_meta("drawer_category")

			print("\nCategory: %s" % category)
			print("  Drawer visible: %s" % drawer.visible)
			print("  Drawer size: %s" % drawer.size)
			print("  Drawer custom_min_size: %s" % drawer.custom_minimum_size)

			print("  Header button:")
			print("    Text: '%s'" % header_btn.text)
			print("    Visible: %s" % header_btn.visible)
			print("    Size: %s" % header_btn.size)
			print("    Custom min size: %s" % header_btn.custom_minimum_size)
			print("    Modulate: %s" % header_btn.modulate)

			# Check style
			var style = header_btn.get_theme_stylebox("normal")
			if style:
				print("    Has style box: yes")
				print("    Style bg_color: %s" % style.bg_color)
			else:
				print("    Has style box: NO")

			# Check parent
			var parent = header_btn.get_parent()
			print("    Parent: %s (visible: %s, size: %s)" % [parent.name, parent.visible, parent.size])

	print("\n=== END DEBUG ===\n")
	quit(0)
