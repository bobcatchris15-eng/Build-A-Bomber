extends SceneTree
# Scratch: validates the new save-feedback toast (replacing the old
# title-label hijack). Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_save_toast.gd

func _init():
	var out_dir = "res://progress_captures/2026-07-13/save_toast"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 720)
	for i in range(6): await process_frame

	# Calling _show_toast() directly (not the full save_blueprint()) so this
	# scratch test never writes a real file into the user's actual
	# user://blueprints/ save directory.
	var bp_manager = scene.get_node("BlueprintManager")
	bp_manager._show_toast("Saved 'Test Design'!")
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/save_success_toast.png" % out_dir)
	print("[CAPTURE] saved save_success_toast.png")

	bp_manager._show_toast("SAVE FAILED: Clipping!", true)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/save_failed_toast.png" % out_dir)
	print("[CAPTURE] saved save_failed_toast.png")

	quit(0)
