extends SceneTree
# Load EVERY .gd under scripts/ and tools/ and report any that fail to
# compile. A targeted safety net for bulk edits - removing a top-level
# declaration can silently orphan the closing bracket of a multi-line literal,
# which only surfaces as a "Could not preload resource script" error from some
# unrelated consumer much later in a test run.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script tools/compile_check_all.gd

func _walk(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			_walk(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()

func _init():
	var files: Array = []
	for root in ["res://scripts", "res://tools"]:
		_walk(root, files)
	files.sort()

	var failed: Array = []
	for f in files:
		var res = load(f)
		if res == null:
			failed.append(f)
		elif res is GDScript and not res.can_instantiate() and res.get_base_script() == null:
			# Static-only utility scripts legitimately report this; not a failure.
			pass

	print("checked %d scripts under scripts/ and tools/" % files.size())
	if failed.is_empty():
		print("[PASS] every script compiled.")
		quit(0)
	else:
		print("[FAIL] %d script(s) failed to compile:" % failed.size())
		for f in failed:
			print("    " + f)
		quit(1)
