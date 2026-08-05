extends SceneTree
# Targeted parse check: pass script paths as trailing args and each is loaded
# with the resource cache bypassed, exactly as compile_check_all.gd does.
#
# Exists because compile_check_all.gd walks scripts/, tools/ AND tests/ - 200+
# interdependent scripts, each pulling its whole preload graph fresh - and has
# been observed running past 20 minutes without finishing. That makes it useless
# as the fast feedback loop its own docstring claims it is. This checks only what
# you just edited.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/parse_check_some.gd -- res://scripts/foo.gd ...

func _init():
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("[parse_check_some] no script paths given after `--`")
		quit(2)
		return

	var failed: Array = []
	for path in args:
		var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		# A null return is NOT the only failure mode, and assuming it was made the
		# first version of this tool report [PASS] while the engine printed parse
		# errors directly above the result. A script that fails to parse still
		# comes back as a GDScript object; what it cannot do is instantiate. So the
		# validity check has to be can_instantiate(), not a null test.
		var ok := res != null
		if ok and res is GDScript:
			ok = (res as GDScript).can_instantiate()
		if ok:
			print("  [ok]   ", path)
		else:
			failed.append(path)
			print("  [FAIL] ", path)

	if failed.is_empty():
		print("[PASS] %d script(s) parsed." % args.size())
		quit(0)
	else:
		print("[FAIL] %d of %d script(s) failed to parse." % [failed.size(), args.size()])
		quit(1)
