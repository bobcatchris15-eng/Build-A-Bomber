extends SceneTree
# Scratch: loads every script the UI/materials pass touched and reports parse
# failures. GDScript compile errors only surface when a script is loaded, and a
# scene that fails to load reports it as a cascade from whatever preloaded it -
# which is how a `sidebar_panel` removal in stat_calculator.gd showed up as a
# compile error in gizmo_3d.gd. This names the real file.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_compile.gd --path .

const PATHS := [
	"res://scripts/skirmish.gd",
	"res://scripts/stat_calculator.gd",
	"res://scripts/tweak_callout.gd",
	"res://scripts/ui_dock.gd",
	"res://scripts/ui_flyout.gd",
	"res://scripts/ui_icons.gd",
	"res://scripts/ui_theme.gd",
	"res://scripts/ui_tokens.gd",
	"res://scripts/parts_menu.gd",
	"res://scripts/hull_builder.gd",
	"res://scripts/gizmo_3d.gd",
	"res://scripts/main_menu.gd",
	"res://scripts/after_action_report.gd",
	"res://scripts/fleet_comparison_panel.gd",
	"res://scripts/blueprint_library_panel.gd",
	"res://scripts/debug_tuning_panel.gd",
	"res://scripts/battlefield.gd",
]

const SCENES := [
	"res://scenes/MainLab.tscn",
	"res://scenes/UI_StatBlock.tscn",
	"res://scenes/UI_PartsMenu.tscn",
	"res://scenes/Skirmish.tscn",
	"res://scenes/HullBuilder.tscn",
	"res://scenes/MainMenu.tscn",
]

func _init():
	var bad := 0
	for p in PATHS:
		var s = load(p)
		if s == null:
			print("  [FAIL] script did not load: ", p)
			bad += 1
		else:
			print("  [ok]   ", p)
	for p in SCENES:
		var s = load(p)
		if s == null:
			print("  [FAIL] scene did not load: ", p)
			bad += 1
		else:
			print("  [ok]   ", p)
	print("RESULT bad=", bad)
	quit(1 if bad > 0 else 0)
