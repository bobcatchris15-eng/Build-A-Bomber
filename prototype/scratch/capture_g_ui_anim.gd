extends SceneTree
# Chunk G verification: custom tooltip card + status toast + resource
# counter roll-up. Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64.exe --script scratch/capture_g_ui_anim.gd --path .

func _init():
	var out_dir = "res://progress_captures/2026-07-27_g_ui_anim"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene = load("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 800)
	for i in range(10): await process_frame

	# Trigger a big resource jump (mid-roll-up) and a status flash (mid
	# slide+fade) at the same time, then capture while both are animating.
	scene.add_resources(scene.PLAYER_TEAM, 500, 200)
	scene._flash_status("Constructing...")
	await process_frame
	await process_frame

	root.get_texture().get_image().save_png("%s/g_toast_and_counter.png" % out_dir)
	print("[CAPTURE] status toast + resource roll-up saved")

	# Tooltip: manufacture one directly (Control tooltips don't reliably
	# trigger via a synthetic mouse hover in a script-driven capture) and
	# add it to the tree so it actually renders for the screenshot.
	var PartButtonScript = load("res://scripts/part_button.gd")
	var btn = Button.new()
	btn.set_script(PartButtonScript)
	var tooltip = btn._make_custom_tooltip("Rotary Gatling\nHP: 120 | Weight: 40\nCost: 200 Metal, 10 Crystal\nDPS: 85")
	tooltip.position = Vector2(500, 400)
	scene.get_node("UI").add_child(tooltip)
	await process_frame

	root.get_texture().get_image().save_png("%s/g_tooltip_card.png" % out_dir)
	print("[CAPTURE] tooltip card saved")
	quit(0)
