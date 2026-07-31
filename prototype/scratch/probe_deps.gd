extends SceneTree
# Scratch: what is the 1.2 s of "loading Skirmish.tscn" actually made of?
#
# Skirmish.tscn is 57 lines. The cost is almost certainly its dependency
# graph - skirmish.gd is ~2900 lines with a large block of top-level
# const preload(), and GDScript resolves those SYNCHRONOUSLY when the script
# itself loads, pulling in the whole transitive graph in one uninterruptible
# go. That is why no threading API helped: by the time the scene load starts,
# the work is one atomic blocking call.
#
# If that's right, the fix is to warm the graph incrementally - a few
# resources per frame, yielding in between - so the main thread keeps
# ticking and the loading screen animates. The final scene load is then a
# cache hit.

func _init():
	var root_path := "res://scenes/Skirmish.tscn"
	var seen := {}
	var order := []
	_collect(root_path, seen, order, 0)

	print("transitive dependencies of %s: %d" % [root_path, order.size()])

	# Time each one cold-ish, largest first, to see where the mass is.
	var timings := []
	for p in order:
		var t0 := Time.get_ticks_usec()
		if ResourceLoader.exists(p):
			ResourceLoader.load(p)
		timings.append({"path": p, "ms": (Time.get_ticks_usec() - t0) / 1000.0})

	timings.sort_custom(func(a, b): return a["ms"] > b["ms"])
	var total := 0.0
	for t in timings:
		total += t["ms"]
	print("total to load all deps individually: %.0f ms" % total)
	print("")
	print("heaviest 15:")
	for t in timings.slice(0, 15):
		print("  %8.1f ms  %s" % [t["ms"], t["path"]])
	quit(0)

func _collect(path: String, seen: Dictionary, order: Array, depth: int) -> void:
	if seen.has(path) or depth > 8:
		return
	seen[path] = true
	var deps := ResourceLoader.get_dependencies(path)
	for d in deps:
		# Format is "uid::type::path" or just a path, depending on how the
		# reference was authored.
		var parts := d.split("::")
		var dep_path: String = parts[parts.size() - 1]
		if dep_path == "" or seen.has(dep_path):
			continue
		_collect(dep_path, seen, order, depth + 1)
	order.append(path)
