extends SceneTree
# Scratch: does the match load still block the main thread?
#
# Total load cost is deliberately UNCHANGED by the deferred bake - the four
# navmesh surfaces still take ~4s all told. What was supposed to change is
# that no single frame swallows all of it, because Windows reports a process
# as Not Responding after ~5s without pumping its message loop.
#
# So the metric is not total time, it is the LONGEST SINGLE GAP between
# frames. Anything under ~2s is comfortably safe; the old behaviour was one
# unbroken ~4s gap inside Skirmish._ready().
#
# Must run WITHOUT --headless (the deferred path is gated on a real
# DisplayServer, and headless deliberately keeps the blocking call).
# Usage: ./godot.exe --script scratch/probe_load_responsiveness.gd --path .

var _gaps: Array = []
var _last_usec: int = 0
var _done := false

func _init():
	_last_usec = Time.get_ticks_usec()
	_watch()
	var t0 := Time.get_ticks_msec()
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	# _ready() is now a coroutine in the real game, so the scene is not
	# finished when add_child() returns - wait until the nav maps exist.
	var waited := 0
	while waited < 1800 and (skirmish.ground_nav_map == RID() or not skirmish.roster):
		await process_frame
		waited += 1
	# A few more frames so the tail of _ready() lands too.
	for i in range(30):
		await process_frame
	_done = true

	var total := Time.get_ticks_msec() - t0
	_gaps.sort()
	var worst: float = _gaps[_gaps.size() - 1] if not _gaps.is_empty() else 0.0
	var p95: float = _gaps[int(_gaps.size() * 0.95)] if not _gaps.is_empty() else 0.0
	print("=== match load responsiveness ===")
	print("  total load wall time    : %6d ms" % total)
	print("  frames pumped during it : %6d" % _gaps.size())
	print("  WORST single frame gap  : %8.1f ms   <-- the Not Responding metric" % worst)
	print("  p95 frame gap           : %8.1f ms" % p95)
	print("")
	print("  gaps over 500ms:")
	var n := 0
	for g in _gaps:
		if g > 500.0:
			n += 1
	print("    %d" % n)
	quit(0)

# Samples every frame independently of the load coroutine above, so it keeps
# measuring even while _ready() is suspended mid-bake.
func _watch() -> void:
	while not _done:
		await process_frame
		var now := Time.get_ticks_usec()
		_gaps.append((now - _last_usec) / 1000.0)
		_last_usec = now
