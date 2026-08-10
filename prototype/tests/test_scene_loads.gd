extends "res://tests/suite_base.gd"
# Screen smoke tests: every scene must survive instantiation and a few frames.
#
# WHY THIS IS WORTH A SUITE. Promoted from tools/probe_scene_loads.gd, which was
# written after a crash on the Design Lab's PRIMARY LOAD PATH went completely
# unnoticed by an otherwise-green 211-suite run - because no suite instantiated
# MainLab.tscn. DesignStats.analyze() was returning a keyless drivetrain
# dictionary and _update_drivetrain_readout crashed on it, and the only way to
# find out was to open the screen by hand.
#
# The lesson generalises: a test suite that never loads a screen cannot tell you
# the game is broken, only that its arithmetic is right.
#
# Battle.tscn is DELIBERATELY EXCLUDED. match_director._ready() awaits a terrain
# bake and declares world_ready, so it finishes many frames later - a fixed frame
# count either races it or has to be large enough to slow the whole suite. The
# battle scene already has extensive dedicated coverage in tests/battle/; this
# suite exists for the screens that have none.

const SCENES := [
	"res://scenes/MainMenu.tscn",
	"res://scenes/MainLab.tscn",
	"res://scenes/MatchSetup.tscn",
	"res://scenes/BlueprintLibrary.tscn",
	"res://scenes/OperationsSetup.tscn",
	"res://scenes/OperationsDraft.tscn",
	"res://scenes/HullBuilder.tscn",
	"res://scenes/Loading.tscn",
]

const SETTLE_FRAMES := 4


func test_every_screen_survives_ready() -> bool:
	print("Running Test Suite: Screens - Every Scene Survives _ready()...")
	var failed: Array = []
	var checked := 0

	for path in SCENES:
		if not ResourceLoader.exists(path):
			print("  [FAIL] ", path, " does not exist - a screen was renamed without updating this list")
			failed.append(path)
			continue
		var packed = load(path)
		if packed == null:
			print("  [FAIL] ", path, " did not load")
			failed.append(path)
			continue
		var inst = packed.instantiate()
		if inst == null:
			print("  [FAIL] ", path, " did not instantiate")
			failed.append(path)
			continue

		root.add_child(inst)
		# Several frames, so deferred calls and one-shot timers actually fire.
		# call_deferred is where a lot of UI assembly happens in this codebase
		# (stat_calculator's toolbar height check, for one), and a single frame
		# would miss all of it.
		for _i in range(SETTLE_FRAMES):
			await tree.process_frame
		if not is_instance_valid(inst):
			print("  [FAIL] ", path, " freed itself during startup")
			failed.append(path)
			continue
		inst.queue_free()
		await tree.process_frame
		checked += 1

	if not failed.is_empty():
		print("  [FAIL] ", failed.size(), " screen(s) failed to start: ", failed)
		return false

	print("  [PASS] All ", checked, " screens instantiated and survived ", SETTLE_FRAMES, " frames.")
	return true
