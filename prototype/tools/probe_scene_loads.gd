extends SceneTree
# Instantiates each main scene and ticks it a few frames, so a runtime error in
# _ready() shows up here rather than only when a human opens the screen.
#
# The Design Lab load failure this was written for
# (DesignStats.analyze() returning a keyless drivetrain dict, crashing
# _update_drivetrain_readout) was invisible to the whole 211-suite run, because
# no suite instantiates MainLab.tscn and drives its stat rail.

const SCENES := [
	"res://scenes/MainMenu.tscn",
	"res://scenes/MainLab.tscn",
	"res://scenes/MatchSetup.tscn",
	"res://scenes/BlueprintLibrary.tscn",
	"res://scenes/OperationsSetup.tscn",
	"res://scenes/Loading.tscn",
	"res://scenes/Battle.tscn",
]

func _init():
	var failed: Array = []
	for path in SCENES:
		if not ResourceLoader.exists(path):
			print("  [skip] %s (missing)" % path)
			continue
		var packed = load(path)
		if packed == null:
			print("  [FAIL] %s did not load" % path)
			failed.append(path)
			continue
		var inst = packed.instantiate()
		if inst == null:
			print("  [FAIL] %s did not instantiate" % path)
			failed.append(path)
			continue
		root.add_child(inst)
		# A few frames so deferred calls and one-shot timers actually fire.
		for _i in range(4):
			await process_frame
		print("  [ok]   %s" % path)
		inst.queue_free()
		await process_frame

	if failed.is_empty():
		print("[PASS] every scene instantiated. Check output above for SCRIPT ERROR lines.")
		quit(0)
	else:
		print("[FAIL] %d scene(s) failed." % failed.size())
		quit(1)
