extends SceneTree
# Scratch: the same assertions as test_ui_dock_state_cycle, runnable in seconds
# instead of at the end of a 193-suite run.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_dock_states.gd --path .
const UIDockScript = preload("res://scripts/ui_dock.gd")

func _init():
	# One frame before touching anything. Inside a SceneTree script's _init() the
	# tree is not pumping yet, so add_child() does NOT run _ready() synchronously
	# and dock.body() comes back null. run_tests.gd never hits this because its
	# suites run from a coroutine well after the first frame.
	await process_frame
	root.size = Vector2i(1280, 720)
	var host = Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)

	var dock = UIDockScript.new()
	dock.dock_title = "CATALOG"
	dock.side = UIDockScript.Side.LEFT
	dock.expanded_size = 320.0
	dock.auto_reveal = false
	dock.persist_key = ""
	host.add_child(dock)
	await process_frame

	var wide = Label.new()
	wide.text = "A PART NAME LONG ENOUGH TO NEED ROOM"
	dock.body().add_child(wide)
	await process_frame
	await process_frame

	for pair in [
		["EXPANDED", UIDockScript.State.EXPANDED, 320.0],
		["RAILED", UIDockScript.State.RAILED, UIDockScript.RAIL_SIZE],
		["HIDDEN", UIDockScript.State.HIDDEN, UIDockScript.TAB_SIZE],
		["EXPANDED again", UIDockScript.State.EXPANDED, 320.0],
	]:
		dock.set_dock_state(pair[1], false)
		await process_frame
		var got: float = dock.get_combined_minimum_size().x
		var want: float = pair[2]
		print("  %-15s min=%6.1f want<=%6.1f outer_extent=%6.1f  %s" % [
			pair[0], got, want, dock.outer_extent(),
			"ok" if got <= want + 1.0 else "FAIL"])

	dock.set_dock_state(UIDockScript.State.EXPANDED, false)
	dock.toggle()
	await process_frame
	var s1 = dock.get_dock_state()
	dock.toggle()
	await process_frame
	var s2 = dock.get_dock_state()
	print("  toggle cycle: %d -> %d  %s" % [s1, s2,
		"ok" if s1 != UIDockScript.State.HIDDEN and s2 == UIDockScript.State.EXPANDED else "FAIL"])
	print("DONE")
	quit(0)
