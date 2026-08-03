extends SceneTree
# Scratch: boots MainLab headlessly and reports what the item-7 restructure
# produced, so a compile error or a stranded control is caught in seconds rather
# than at the end of an 8-minute suite run.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_lab_boot.gd --path .
func _init():
	root.size = Vector2i(1280, 720)
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	for i in range(8):
		await process_frame

	var stats = scene.get_node_or_null("UI_StatBlock")
	if stats == null:
		print("FAIL: no UI_StatBlock")
		quit(1)
		return

	print("dock          = ", stats.stats_dock)
	print("dock state    = ", stats.stats_dock.get_dock_state() if stats.stats_dock else "n/a")
	print("toolbar       = ", stats.toolbar)
	print("rail_vbox     = ", stats._rail_vbox)
	print("scroll parent = ", stats.get_node_or_null("ScrollContainer"))

	# Everything the toolbar was supposed to adopt.
	for pair in [
		["undo", stats._undo_btn], ["redo", stats._redo_btn],
		["mirror", stats.mirror_checkbox], ["hull_spec", stats.hull_spec_btn],
		["library", stats.library_button], ["save", stats.save_button],
		["test", stats.test_button],
	]:
		var n = pair[1]
		var ok = is_instance_valid(n) and stats.toolbar != null and stats.toolbar.is_ancestor_of(n)
		print("  toolbar has %-10s %s" % [pair[0], "YES" if ok else "NO  (parent=%s)" % (n.get_parent() if is_instance_valid(n) else "<null>")])

	# Still in the rail, and should be.
	for pair in [["hp", stats.hp_label], ["dps", stats.dps_label], ["delete", stats.delete_button], ["name", stats.blueprint_name_edit]]:
		var n = pair[1]
		var ok = is_instance_valid(n) and stats._rail_vbox != null and stats._rail_vbox.is_ancestor_of(n)
		print("  rail    has %-10s %s" % [pair[0], "YES" if ok else "NO"])

	print("DONE")
	quit(0)
