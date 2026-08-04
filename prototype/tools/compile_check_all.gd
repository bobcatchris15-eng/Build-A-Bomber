extends SceneTree
# Load EVERY .gd under scripts/, tools/ and tests/ and report any that fail to
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
	for root in ["res://scripts", "res://tools", "res://tests"]:
		_walk(root, files)
	files.sort()

	var failed: Array = []
	for f in files:
		# CACHE_MODE_IGNORE matters: a plain load() will happily hand back an
		# already-cached script object for a file that no longer parses, which
		# made an earlier version of this tool report PASS while Godot was
		# printing parse errors right next to it.
		# Deliberately NOT res.reload() as a second check - reloading 100+
		# interdependent scripts cascades and effectively hangs. The cache-miss
		# load is enough: a file that does not parse comes back null.
		var res = ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res == null:
			failed.append(f)

	print("checked %d scripts under scripts/, tools/ and tests/" % files.size())
	if failed.is_empty():
		print("[PASS] every script compiled.")
		quit(0)
	else:
		print("[FAIL] %d script(s) failed to compile:" % failed.size())
		for f in failed:
			print("    " + f)
		quit(1)
