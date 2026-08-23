extends SceneTree
# Targeted compile check: load only the files we changed and report
# parse / load status. Loads from disk (CACHE_MODE_IGNORE) so a cached
# good copy cannot mask a broken file.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --quit --path prototype --script tools/_compile_check_targeted.gd

const TARGETS := [
	"res://scripts/battle/units/unit.gd",
	"res://scripts/battle/ai/squad.gd",
	"res://scripts/battle/ai/micro.gd",
	"res://scripts/battle/ai/squad_manager.gd",
	"res://scripts/battle/ai/threat_analyzer.gd",
	"res://scripts/battle/ai/commander.gd",
	"res://scripts/battle/ai/counter_draft.gd",
	"res://scripts/battle/orders/stance.gd",
	"res://scripts/battle/orders/order.gd",
	"res://scripts/battle/orders/order_service.gd",
	"res://scripts/battle/orders/command_registry.gd",
	"res://scripts/auto_weapon.gd",
	"res://scripts/battle/match_director.gd",
	"res://scripts/battle/units/unit_assembly.gd",
	"res://scripts/module_catalog.gd",
	"res://scripts/match_rule_set.gd",
	"res://scripts/core/input_service.gd",
]


func _init():
	var failed: Array = []
	for path in TARGETS:
		var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res == null:
			failed.append(path)
			print("  [FAIL] %s" % path)
		else:
			print("  [OK]   %s" % path)
	if failed.is_empty():
		print("[PASS] %d scripts compiled" % TARGETS.size())
		quit(0)
	else:
		print("[FAIL] %d script(s) failed:" % failed.size())
		for f in failed:
			print("    " + f)
		quit(1)
