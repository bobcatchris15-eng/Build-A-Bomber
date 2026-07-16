extends SceneTree
# Scratch: reusable capture of MainLab.tscn's startup state, for verifying
# the playtest-readiness UI fixes (drag hint, tooltips, sliders, etc).
# Must run WITHOUT --headless (dummy renderer doesn't rasterize).
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_mainlab_ui.gd

func _init():
	var out_dir = "res://progress_captures/2026-07-13/design_lab_ux_fixes"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 720)
	for i in range(3): await process_frame
	root.size = Vector2i(1280, 720)
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png("%s/mainlab_startup.png" % out_dir)
	print("[CAPTURE] saved mainlab_startup.png")
	quit(0)
