extends SceneTree
# Scratch: validates the blueprint-selection cap counter in MatchSetup -
# should read "N / 12 selected", turn orange and disable remaining
# checkboxes once 12 are checked. Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_match_setup_cap.gd

func _init():
	var out_dir = "res://progress_captures/2026-07-13/match_setup_cap"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene = load("res://scenes/MatchSetup.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 720)
	for i in range(6): await process_frame

	print("Total blueprint checkboxes found: ", scene.blueprint_checks.size())

	# Check a handful (well under the cap) - counter should read green/plain.
	var to_check_first = min(4, scene.blueprint_checks.size())
	for i in range(to_check_first):
		scene.blueprint_checks[i].check.button_pressed = true
		scene._update_selection_counter()
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/under_cap.png" % out_dir)
	print("[CAPTURE] saved under_cap.png, counter text: '", scene.selection_counter_label.text, "'")

	# Check enough to exceed the cap (if there are enough saved designs).
	var to_check_all = min(scene.blueprint_checks.size(), 16)
	for i in range(to_check_all):
		scene.blueprint_checks[i].check.button_pressed = true
	scene._update_selection_counter()
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/at_or_over_cap.png" % out_dir)
	print("[CAPTURE] saved at_or_over_cap.png, counter text: '", scene.selection_counter_label.text, "'")

	var disabled_count = 0
	for entry in scene.blueprint_checks:
		if entry.check.disabled:
			disabled_count += 1
	print("Checkboxes now disabled (should be >0 if more than 12 designs exist): ", disabled_count)

	quit(0)
