extends SceneTree
# Scratch: is skirmish.gd's ~978 ms its own compile, or its preload graph?
#
# GDScript resolves top-level `const X = preload(...)` when the script loads,
# synchronously and transitively. Those are invisible to
# ResourceLoader.get_dependencies(), which is why the dependency probe only
# found 3 entries for a scene that takes over a second.
#
# This times each preload target on its own, in a fresh process, so the
# heaviest branch is identifiable. If one or two dominate, warming those is
# enough; if the cost is spread flat, the script itself is the problem.

func _init():
	var src := FileAccess.get_file_as_string("res://scripts/skirmish.gd")
	var re := RegEx.new()
	re.compile('preload\\("(res://[^"]+)"\\)')

	var paths := []
	for m in re.search_all(src):
		var p := m.get_string(1)
		if p not in paths:
			paths.append(p)

	print("top-level preload targets in skirmish.gd: %d" % paths.size())

	var timings := []
	for p in paths:
		var t0 := Time.get_ticks_usec()
		if ResourceLoader.exists(p):
			ResourceLoader.load(p)
		timings.append({"path": p, "ms": (Time.get_ticks_usec() - t0) / 1000.0})

	timings.sort_custom(func(a, b): return a["ms"] > b["ms"])
	var total := 0.0
	for t in timings:
		total += t["ms"]
	print("sum of preload targets: %.0f ms" % total)
	print("")
	for t in timings.slice(0, 18):
		print("  %8.1f ms  %s" % [t["ms"], t["path"]])
	quit(0)
