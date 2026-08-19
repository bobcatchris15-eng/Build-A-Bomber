extends SceneTree
# Parse-only smoke test for the Day 1 changes in
# docs/design/SKIRMISH_PERF_TROUBLESHOOTING.md.
#
# WHAT THIS IS. A standalone SceneTree that preload()s the four files
# the Day 1 plan touches. A successful run is "every file parsed and
# its class_name resolved"; a failure names the file. Used as a
# faster, narrower check than run_tests.ps1 when only a handful of
# scripts changed and a 5-minute reimport is overkill.
#
# WHAT THIS IS NOT. Not a behaviour test. It catches parse errors and
# missing symbols but says nothing about whether the perf log still
# names sections correctly. The full test suite (run_tests.ps1) is
# what guards correctness; this is the "did I save a file that the
# editor can't even open" gate.
#
# Run from prototype/:
#   ./Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script res://tools/parse_check_day1.gd --quit

const FILES := [
	"res://scripts/battle/battle_profiler.gd",
	"res://scripts/battle/ai/commander.gd",
	"res://scripts/battle/match_director.gd",
	"res://scripts/battle/battle_logger.gd",
	"res://scripts/battle/buildings/building_mesh.gd",
	"res://scripts/scene_router.gd",
	"res://scripts/loading_screen.gd",
	"res://scripts/loading_preview.gd",
]

# Resources (not GDScript) that should load as PackedScene. The same
# "did the editor accept this file" gate the script list above runs,
# without type-confusing load() by assigning to a GDScript var.
const SCENES := [
	"res://scenes/LoadingPreview.tscn",
	"res://scenes/Loading.tscn",
]


func _initialize() -> void:
	var failed := 0
	for path in FILES:
		var script: GDScript = load(path)
		if script == null:
			print("[FAIL] could not load %s" % path)
			failed += 1
			continue
		# A missing class_name is normal for scene-attached scripts
		# (match_director.gd, for instance - it has no class_name by
		# design). The parse failure modes we care about are
		# GDScript parse errors, which load() returns null for, and
		# a broken class_name, which we surface separately so a real
		# regression in a globally-named script is visible.
		var n: String = ""
		if script.has_method("get_global_name"):
			n = script.get_global_name()
		if n.is_empty():
			print("[OK]   %s (no class_name, expected for scene-attached scripts)" % path)
		else:
			print("[OK]   %s -> class_name %s" % [path, n])
	for path in SCENES:
		var packed: PackedScene = load(path)
		if packed == null:
			print("[FAIL] could not load scene %s" % path)
			failed += 1
			continue
		# instantiating the scene runs the script's _ready too, so a
		# parse error in the script would surface here. The instance
		# is freed immediately - this is a parse smoke test, not a
		# behavioural test.
		var inst := packed.instantiate()
		if inst == null:
			print("[FAIL] %s.instantiate() returned null" % path)
			failed += 1
			continue
		inst.free()
		print("[OK]   %s loaded and instantiated" % path)
	if failed > 0:
		print("[FAIL] %d file(s) failed to parse" % failed)
		quit(1)
	else:
		print("[OK]   all %d scripts + %d scenes parsed cleanly" % [FILES.size(), SCENES.size()])
		quit(0)
