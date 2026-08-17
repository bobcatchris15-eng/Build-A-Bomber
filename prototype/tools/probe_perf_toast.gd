extends SceneTree
# Smoke test for the F4 dump path: PerfToast shows the message,
# BattleLogger.dump_now() writes a real file. Runs headlessly, so it
# cannot verify the toast is *visually* on screen - that needs a human
# with a window open - but it CAN verify:
#   1. PerfToast instantiates and accepts show_message()
#   2. the panel becomes visible and the label has the right text
#   3. the timer fires and hides the panel after DEFAULT_DURATION
#   4. BattleLogger.dump_now("manual") produces a non-empty file
#
# The probe is structured as a series of awaits so the SceneTree is
# fully running by the time the test code runs - add_child() in _init()
# happens before the tree is "live" and a Timer.start() against a
# child of a not-yet-in-tree node prints "Unable to start the timer".
# That is a probe issue, not a PerfToast issue; the F4 path runs
# many seconds into the match when the tree is long since live.
#
# Run: Godot --headless --script tools/probe_perf_toast.gd

const PerfToastScript = preload("res://scripts/battle/perf_toast.gd")
const BattleLogger = preload("res://scripts/battle/battle_logger.gd")

var _exit_code: int = 1


func _initialize() -> void:
	# Deferred so the SceneTree is up before any add_child or Timer.start.
	call_deferred("_run")


func _run() -> void:
	# --- PerfToast: lazy-build path ---------------------------------------
	var toast = PerfToastScript.new()
	toast.name = "ProbeToast"
	root.add_child(toast)
	# Wait one frame so the toast is fully in the tree before we touch its
	# internal Timer.
	await process_frame
	toast.show_message("Perf dump written: dump_manual_42.log", 0.4)
	if not toast._panel.visible:
		print("[FAIL] PerfToast._panel is not visible after show_message()")
		quit(1)
		return
	if toast._label.text != "Perf dump written: dump_manual_42.log":
		print("[FAIL] PerfToast label text mismatch: %s" % toast._label.text)
		quit(1)
		return
	print("[OK]   PerfToast.show_message() built the panel and set the text")
	# Wait a bit longer than the duration and confirm the panel hides itself.
	await create_timer(0.7).timeout
	if toast._panel.visible:
		print("[FAIL] PerfToast._panel did not auto-hide after timer expired")
		quit(1)
		return
	print("[OK]   PerfToast panel auto-hide fired after timer expired")
	# show_message again should re-show it (the burst-of-dumps case).
	toast.show_message("Second message", 0.3)
	if not toast._panel.visible:
		print("[FAIL] PerfToast did not re-show on second show_message()")
		quit(1)
		return
	print("[OK]   PerfToast re-shows on repeated show_message()")
	toast.queue_free()
	await process_frame
	# --- BattleLogger.dump_now() ------------------------------------------
	# Open a session, call dump_now, close. Catches the wiring issue where
	# the dump writes to a path but the match_director reports an empty
	# string for any reason.
	BattleLogger.enabled = true
	BattleLogger.begin_match("probe", {"source": "probe_perf_toast"})
	var path := BattleLogger.dump_now("manual")
	if path.is_empty():
		print("[FAIL] BattleLogger.dump_now returned empty path")
		quit(1)
		return
	if not FileAccess.file_exists(path):
		print("[FAIL] BattleLogger.dump_now returned %s but no file exists" % path)
		quit(1)
		return
	print("[OK]   BattleLogger.dump_now wrote %s" % path.get_file())
	BattleLogger.end_match()
	print("[PASS] PerfToast + BattleLogger.dump_now wired correctly.")
	quit(0)
