extends SceneTree
# Scratch: does the threaded load actually keep the main thread free?
#
# The claim being tested is not "the scene loads" - it did before. It is
# "the main thread keeps ticking while it loads", which is the difference
# between a loading screen and a frozen window. So this measures the LONGEST
# GAP between main-thread iterations during the load. A synchronous load
# produces one gap the length of the whole load; a threaded one produces
# many short gaps.

func _init():
	var path := "res://scenes/Skirmish.tscn"

	# ResourceLoader caches, so running both measurements in one process
	# makes the second one a warm hit and reports a meaninglessly good
	# number. Each mode therefore runs in its OWN process, selected by a
	# user arg after `--`:
	#   ...--script scratch/probe_async_load.gd -- sync
	#   ...--script scratch/probe_async_load.gd -- threaded
	var mode := "sync"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]

	if mode == "sync":
		var t0 := Time.get_ticks_msec()
		var packed = load(path)
		var sync_block := Time.get_ticks_msec() - t0
		print("SYNCHRONOUS load(): main thread blocked for %d ms in ONE go" % sync_block)
		print("main-thread iterations during that block: 1")
		quit(0)
		return

	# --- Threaded ------------------------------------------------------
	ResourceLoader.load_threaded_request(path, "", true)
	var progress := []
	var last_tick := Time.get_ticks_msec()
	var longest_gap := 0
	var iterations := 0
	var started := Time.get_ticks_msec()

	while true:
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		iterations += 1
		var now := Time.get_ticks_msec()
		longest_gap = maxi(longest_gap, now - last_tick)
		last_tick = now
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			print("THREADED load FAILED")
			quit(1)
			return
		if now - started > 30000:
			print("THREADED load timed out")
			quit(1)
			return
		await process_frame

	var total := Time.get_ticks_msec() - started
	print("THREADED load: %d ms total, %d main-thread iterations" % [total, iterations])
	print("longest single main-thread gap: %d ms" % longest_gap)
	print("")
	print("A gap near the total means the main thread still stalled.")
	print("A small gap means the window stayed responsive and could animate.")
	quit(0)
