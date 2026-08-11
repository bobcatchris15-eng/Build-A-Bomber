extends SceneTree
# Manifest-integrity check for run_tests.gd's SUITE_ORDER / SUITE_FILES.
#
#   ./Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script tools/check_suite_manifest.gd
#
# Exits 1 if any SUITE_ORDER row names a function that is not declared in the
# suite file its key maps to. Runs in well under a second.
#
# WHY THIS EXISTS. SUITE_ORDER is a hand-maintained manifest of
# ["<suite key>", "<function name>"] pairs, deliberately explicit rather than
# derived, because execution order is load-bearing (several navmesh/Recast
# suites flake depending on what ran before them). The cost of that choice is
# that a rename on either side goes unnoticed: the runner calls the missing
# method, Godot prints "SCRIPT ERROR: Invalid call. Nonexistent function ..."
# into a 260,000-line log, and the suite is counted as a plain failure
# indistinguishable from a real regression. Three rows had rotted that way by
# 2026-08-11, one of them for a test that had been rewritten to match current
# behaviour and simply never renamed here - so it had never run once.
#
# WHY IT PARSES TEXT INSTEAD OF LOADING ANYTHING. Nothing here calls load() or
# .new(). The manifest and the suite files are read as plain text and matched
# with a regex. That is deliberate on two counts:
#
#   1. Loading run_tests.gd pulls in every suite file via its preloads, which
#      pulls in Battle.tscn and most of scripts/ - minutes of work to answer a
#      question about two literal arrays, and it makes this check fail for
#      unrelated reasons whenever anything anywhere in the tree is mid-edit.
#      A manifest check that only works when the codebase already compiles is
#      useless exactly when you want it.
#   2. run_tests.gd extends SceneTree. Constructing a SceneTree-derived script
#      from inside another SceneTree runs its _init() immediately and hangs the
#      process at 100% CPU with no output - the same trap documented in
#      SUITE_FILES' comment about tests/test_lab_instructions.gd.
#
# It follows each suite file's `extends "res://..."` chain so a row naming a
# helper inherited from tests/suite_base.gd still resolves.
#
# NOTE: this reads .gd files off res:// at runtime. That works from source (how
# the test harness is ever run) but not from an exported .pck, where scripts are
# compiled binaries. This is a dev tool; it is not shipped.

const RUNNER_PATH := "res://run_tests.gd"

# Guards against this script erroring before it reaches quit(). A SceneTree
# script that aborts in _init() leaves the main loop spinning forever with no
# way to tell it to stop - the tree keeps iterating, so a timer created up
# front still fires and can pull the exit for us.
const WATCHDOG_SECONDS := 60.0


func _init() -> void:
	var watchdog := create_timer(WATCHDOG_SECONDS)
	watchdog.timeout.connect(_on_watchdog)

	print("\n=== SUITE MANIFEST CHECK ===\n")

	var manifest := _parse_runner()
	var suite_files: Dictionary = manifest["files"]
	var suite_order: Array = manifest["order"]
	if suite_files.is_empty() or suite_order.is_empty():
		print("[ERROR] Could not parse SUITE_FILES / SUITE_ORDER out of %s." % RUNNER_PATH)
		print("        Parsed %d file entries and %d order rows - the const block" % [
			suite_files.size(), suite_order.size()])
		print("        format has probably changed. Fix the parser, do not ignore this.")
		quit(1)
		return

	print("Parsed %d suite files and %d manifest rows." % [suite_files.size(), suite_order.size()])

	# Function tables, one per suite key, resolved once and reused. `all` is the
	# file plus everything up its extends chain (what a row is allowed to name);
	# `own` is only what the file itself declares (what the orphan scan below
	# reasons about, so shared helpers in suite_base.gd are not reported once
	# per suite that inherits them).
	var all_funcs := {}
	var own_funcs := {}
	var unreadable: Array = []
	for key in suite_files:
		var path: String = suite_files[key]
		var own := _declared_funcs(path)
		if own.is_empty():
			unreadable.append("%s -> %s" % [key, path])
		own_funcs[key] = own
		all_funcs[key] = _declared_funcs_with_bases(path, {})

	var errors: Array = []
	for entry in unreadable:
		errors.append("Suite file could not be read or declares no functions: %s" % entry)

	# THE CHECK. Every row must resolve to a real function.
	var referenced := {}
	for row in suite_order:
		var key: String = row[0]
		var func_name: String = row[1]
		if not suite_files.has(key):
			errors.append("Row [\"%s\", \"%s\"] names suite key '%s', which is not in SUITE_FILES." % [
				key, func_name, key])
			continue
		referenced[key] = referenced.get(key, PackedStringArray())
		var seen_here: PackedStringArray = referenced[key]
		seen_here.append(func_name)
		referenced[key] = seen_here
		if not all_funcs[key].has(func_name):
			errors.append("Row [\"%s\", \"%s\"] -> %s declares no such function." % [
				key, func_name, suite_files[key]])

	# ADVISORY 1: a suite file registered in SUITE_FILES that no row points at.
	# Preloaded and instantiated on every run, contributing nothing. Sometimes
	# intentional (an area mid-rewrite, with a note in run_tests.gd saying so),
	# which is why it warns rather than fails.
	var unused_keys: Array = []
	for key in suite_files:
		if not referenced.has(key):
			unused_keys.append(key)

	# ADVISORY 2: the mirror image, and the more expensive mistake. A test_*
	# function that exists, presumably passes, and is never called because no
	# row names it. This is how a rewritten-and-renamed suite goes quietly dark.
	var orphans: Array = []
	for key in suite_files:
		var named: PackedStringArray = referenced.get(key, PackedStringArray())
		for func_name in own_funcs[key]:
			if not func_name.begins_with("test_"):
				continue
			if not (func_name in named):
				orphans.append("%s: %s" % [key, func_name])

	if not unused_keys.is_empty():
		print("\n[WARN] %d suite file(s) in SUITE_FILES have no SUITE_ORDER rows:" % unused_keys.size())
		for key in unused_keys:
			print("  - %s (%s)" % [key, suite_files[key]])

	if not orphans.is_empty():
		print("\n[WARN] %d test_* function(s) exist but are never registered in SUITE_ORDER" % orphans.size())
		print("       (they do not run - either add a row or delete the function):")
		for o in orphans:
			print("  - %s" % o)

	print("")
	if errors.is_empty():
		print("[OK] Every SUITE_ORDER row resolves to a declared function.")
		quit(0)
		return
	print("[FAIL] %d manifest problem(s):" % errors.size())
	for e in errors:
		print("  - %s" % e)
	print("")
	quit(1)


func _on_watchdog() -> void:
	print("\n[ERROR] Watchdog fired after %ds - the check aborted before finishing." % int(WATCHDOG_SECONDS))
	print("        Scroll up for the SCRIPT ERROR that caused it.")
	quit(2)


# --- parsing ----------------------------------------------------------------

# Pulls the two const blocks out of run_tests.gd. A tiny state machine rather
# than one big regex, because both blocks are multi-line and interleaved with
# long comment blocks that contain example rows in prose.
func _parse_runner() -> Dictionary:
	var files := {}
	var order: Array = []
	var lines := _read_lines(RUNNER_PATH)
	var re_file := RegEx.create_from_string('^"([A-Za-z0-9_]+)"\\s*:\\s*preload\\("([^"]+)"\\)')
	var re_row := RegEx.create_from_string('^\\[\\s*"([A-Za-z0-9_]+)"\\s*,\\s*"([A-Za-z0-9_]+)"\\s*\\]')
	var in_files := false
	var in_order := false
	for raw in lines:
		var line := raw.strip_edges()
		# Commented-out rows are documentation, not registrations - notably the
		# test_lab_instructions.gd block, which is a comment precisely because
		# registering it hung the runner.
		if line.begins_with("#"):
			continue
		if line.begins_with("const SUITE_FILES"):
			in_files = true
			continue
		if line.begins_with("const SUITE_ORDER"):
			in_order = true
			continue
		if in_files:
			if line.begins_with("}"):
				in_files = false
				continue
			var m := re_file.search(line)
			if m != null:
				files[m.get_string(1)] = m.get_string(2)
		elif in_order:
			if line.begins_with("]"):
				in_order = false
				continue
			var m2 := re_row.search(line)
			if m2 != null:
				order.append([m2.get_string(1), m2.get_string(2)])
	return {"files": files, "order": order}


# Function names declared directly in one .gd file.
func _declared_funcs(path: String) -> Dictionary:
	var out := {}
	var re_func := RegEx.create_from_string('^(?:static\\s+)?func\\s+([A-Za-z0-9_]+)\\s*\\(')
	for raw in _read_lines(path):
		var m := re_func.search(raw.strip_edges())
		if m != null:
			out[m.get_string(1)] = true
	return out


# The same, plus everything up the `extends "res://..."` chain. `seen` breaks a
# cycle if one is ever authored; GDScript would reject it, but this parser runs
# on files that may be mid-edit and must not spin.
func _declared_funcs_with_bases(path: String, seen: Dictionary) -> Dictionary:
	var out := {}
	if path == "" or seen.has(path):
		return out
	seen[path] = true
	var re_ext := RegEx.create_from_string('^extends\\s+"([^"]+)"')
	for raw in _read_lines(path):
		var line := raw.strip_edges()
		var me := re_ext.search(line)
		if me != null:
			for k in _declared_funcs_with_bases(me.get_string(1), seen):
				out[k] = true
	for k in _declared_funcs(path):
		out[k] = true
	return out


func _read_lines(path: String) -> PackedStringArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedStringArray()
	var text := f.get_as_text()
	f.close()
	return text.replace("\r\n", "\n").split("\n")
