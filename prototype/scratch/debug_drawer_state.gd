extends SceneTree
# Debug script: inspect Parts Catalog drawer state and node tree
# Shows what's actually in the scene tree at runtime

func _init():
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 800)
	for i in range(8): await process_frame

	# Get reference to parts menu
	var parts_menu = scene.get_node_or_null("UI_PartsMenu")
	print("\n=== PARTS MENU DEBUG ===")
	if not parts_menu:
		print("ERROR: UI_PartsMenu not found!")
		quit(1)

	print("Parts Menu found: %s" % parts_menu.name)
	print("Parts Menu script: %s" % parts_menu.get_script())

	# Check if _ready was called
	var tab_hulls_container = parts_menu.get_node_or_null("PanelContainer/VBoxContainer/TabContainer/Hulls/VBoxContainer")
	if not tab_hulls_container:
		print("ERROR: tab_hulls_container not found at expected path!")
		quit(1)

	print("\nTab Hulls Container found: %s" % tab_hulls_container.name)
	print("Tab Hulls Container child count: %d" % tab_hulls_container.get_child_count())

	# List all children in the container
	print("\nChildren in tab_hulls_container:")
	for i in range(tab_hulls_container.get_child_count()):
		var child = tab_hulls_container.get_child(i)
		print("  [%d] %s (type: %s, visible: %s, size: %s)" % [
			i, child.name, child.get_class(), child.visible, child.size
		])

		# If it's a drawer, inspect it
		if child.has_meta("drawer_category"):
			var category = child.get_meta("drawer_category")
			var content = child.get_meta("content_container")
			print("      → Drawer for '%s'" % category)
			print("        Content visible: %s" % content.visible)
			print("        Content child count: %d" % content.get_child_count())
			if content.get_child_count() > 0:
				print("        First child: %s" % content.get_child(0).name)

	print("\n=== END DEBUG ===\n")
	quit(0)
