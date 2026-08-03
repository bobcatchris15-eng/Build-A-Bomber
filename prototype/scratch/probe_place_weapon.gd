extends SceneTree
# Scratch: reproduce Chris's "immediate failure when i place a weapon in the
# design lab" by booting MainLab headless and placing a weapon for real.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_place_weapon.gd --path .

func _init():
	var lab = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	await process_frame
	await process_frame

	# Guard the user's saved dock layout - any headless MainLab boot otherwise
	# rewrites user://ui_layout.cfg (documented in the weight work).
	for dock_name in ["StatsDock", "PartsDock"]:
		var dock = lab.find_child(dock_name, true, false)
		if dock and "persist_key" in dock:
			dock.persist_key = ""

	var placer = lab.find_child("ModulePlacer", true, false)
	if placer == null:
		placer = lab
	print("placer node: ", placer.name, " has _place_weapon=", placer.has_method("_place_weapon"))

	placer._place_hull_from_ui("medium_hull")
	await process_frame
	print("hull placed ok")

	print("--- placing basic_cannon ---")
	# The REAL UI entry point a click goes through, not the lower-level helper.
	placer._place_weapon_from_ui("basic_cannon", Vector3(0, 1.0, 0), Vector3.UP)
	await process_frame
	await process_frame
	var w = "(via _place_weapon_from_ui)"
	await process_frame
	print("placed: ", w)

	print("--- forcing a stat recalc ---")
	var sc = null
	for n in [lab.find_child("UI_StatBlock", true, false)]:
		if n and n.has_method("update_stats"):
			sc = n
	if sc == null:
		# walk everything looking for the script that owns update_stats
		var stack: Array = [lab]
		while not stack.is_empty():
			var n = stack.pop_back()
			if n.has_method("update_stats") and "weapon_range" in n:
				sc = n
				break
			for c in n.get_children():
				stack.append(c)
	if sc == null:
		for c in lab.get_children():
			print("   lab child: ", c.name)
	else:
		print("stat calc: ", sc.name)
		sc.update_stats(lab.find_child("Hull", true, false))
		await process_frame
		print("range label: ", sc._range_label.text if sc._range_label else "<null>")
		print("vision label: ", sc._vision_label.text if sc._vision_label else "<null>")
		print("weapon_range: ", sc.weapon_range)

	print("DONE")
	quit(0)
