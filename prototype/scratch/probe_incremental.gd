extends SceneTree
# Scratch: does walking the preload graph one-per-frame actually keep the
# main thread ticking?
#
# The previous attempt (threaded ResourceLoader) produced ONE ~1.2 s gap
# with 2 main-loop iterations - the lamps froze. The metric that matters is
# therefore not total time, which is expected to be about the same, but the
# LONGEST SINGLE GAP between main-thread iterations. That is exactly how
# long the throbber stops moving for.

const SceneRouterScript = preload("res://scripts/scene_router.gd")

func _init():
	var router = Node.new()
	router.set_script(SceneRouterScript)
	root.add_child(router)

	var warm_list: Array = router._warm_list_for("res://scenes/Skirmish.tscn")
	print("warm steps derived: %d" % warm_list.size())
	for p in warm_list:
		print("   ", p)
	print("")

	var gaps := []
	var last := Time.get_ticks_msec()
	for path in warm_list:
		await process_frame
		var now := Time.get_ticks_msec()
		gaps.append({"ms": now - last, "path": path})
		last = now
		if ResourceLoader.exists(path):
			ResourceLoader.load(path)

	await process_frame
	var now2 := Time.get_ticks_msec()
	gaps.append({"ms": now2 - last, "path": "<scene>"})
	last = now2
	load("res://scenes/Skirmish.tscn")
	await process_frame
	gaps.append({"ms": Time.get_ticks_msec() - last, "path": "<scene load>"})

	var longest := 0
	var total := 0
	for g in gaps:
		longest = maxi(longest, g["ms"])
		total += g["ms"]
	print("total: %d ms across %d yielded steps" % [total, gaps.size()])
	print("LONGEST single main-thread gap: %d ms  <-- how long the throbber freezes" % longest)
	print("")
	gaps.sort_custom(func(a, b): return a["ms"] > b["ms"])
	print("worst steps:")
	for g in gaps.slice(0, 6):
		print("  %6d ms  %s" % [g["ms"], g["path"]])
	quit(0)
